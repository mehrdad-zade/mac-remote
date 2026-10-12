import Combine
import Foundation
import Network

// MARK: - Discovered server (live Bonjour result)

struct DiscoveredServer: Identifiable, Sendable {
    let id: UUID
    let endpoint: NWEndpoint
    let name: String

    init(result: NWBrowser.Result) {
        self.id = UUID()
        self.endpoint = result.endpoint
        if case .service(let name, _, _, _) = result.endpoint {
            self.name = name
        } else {
            self.name = "Mac"
        }
    }
}

// MARK: - Saved server (persisted across launches; PIN lives in the Keychain)

struct SavedServer: Codable, Identifiable, Sendable {
    var id: UUID = UUID()
    var name: String
    var lastConnected: Date
}

// MARK: - Connection manager

/// Owns the connection to the Mac.
///
/// Once the user signs in, the session (`activeSession`) persists until they tap
/// Disconnect. iOS closes sockets when the app is backgrounded or the phone locks,
/// so the manager reconnects and re-authenticates by itself whenever the app is
/// active again, instead of sending the user back to the sign-in screen.
@MainActor
final class ConnectionManager: ObservableObject {
    @Published var discoveredServers: [DiscoveredServer] = []
    /// The Mac the user is signed in to. Non-nil from sign-in until Disconnect.
    @Published private(set) var activeSession: SavedServer?
    /// True while an authenticated socket to the Mac is open.
    @Published private(set) var isOnline = false
    /// True while the sign-in screen waits for the first connection.
    @Published private(set) var isConnecting = false
    @Published var connectionError: String? = nil
    @Published var isLocalNetworkPermissionDenied = false
    /// Features the Mac reported. Empty for servers older than protocol v2.
    @Published private(set) var capabilities: Set<String> = []
    @Published private(set) var savedServers: [SavedServer] = []

    var isAuthenticated: Bool { activeSession != nil }
    var connectedServerName: String { activeSession?.name ?? "" }

    func supports(_ capability: String) -> Bool { capabilities.contains(capability) }

    private var browser: NWBrowser?
    private var connection: NWConnection?
    private var receiveBuffer = Data()
    private var lastMoveSent = Date.distantPast

    /// Credentials of the attempt in flight (sign-in or reconnect).
    private var pending: (name: String, pin: String, isSignIn: Bool)?
    private var isAppActive = true
    private var reconnectAttempt = 0
    private var reconnectWork: DispatchWorkItem?
    private var heartbeat: Timer?
    private var lastPong = Date()
    private let pathMonitor = NWPathMonitor(requiredInterfaceType: .wifi)

    private static let serviceType = "_macremote._tcp"
    private static let sessionKey = "activeSessionName"
    private static let savedServersKey = "savedServers"

    init() {
        migrateLegacyStorage()
        savedServers = Self.loadSavedServers()
        if let name = UserDefaults.standard.string(forKey: Self.sessionKey),
           let saved = savedServers.first(where: { $0.name == name }),
           KeychainStore.pin(for: name) != nil {
            activeSession = saved
        }

        pathMonitor.pathUpdateHandler = { [weak self] path in
            guard path.status == .satisfied else { return }
            MainActor.assumeIsolated {
                // Wi-Fi came back: retry now instead of waiting for the backoff timer.
                guard let self, self.activeSession != nil, !self.isOnline, self.connection == nil else { return }
                self.reconnect(resetBackoff: true)
            }
        }
        pathMonitor.start(queue: .main)

        if activeSession != nil {
            reconnect(resetBackoff: true)
        }
    }

    // MARK: - Saved servers

    private static func loadSavedServers() -> [SavedServer] {
        guard let data = UserDefaults.standard.data(forKey: savedServersKey),
              let decoded = try? JSONDecoder().decode([SavedServer].self, from: data)
        else { return [] }
        return decoded.sorted { $0.lastConnected > $1.lastConnected }
    }

    private func storeSavedServers(_ list: [SavedServer]) {
        savedServers = list.sorted { $0.lastConnected > $1.lastConnected }
        if let data = try? JSONEncoder().encode(savedServers) {
            UserDefaults.standard.set(data, forKey: Self.savedServersKey)
        }
    }

    func pin(for serverName: String) -> String {
        KeychainStore.pin(for: serverName) ?? ""
    }

    /// PIN of the most recently used Mac, to pre-fill the sign-in screen.
    var lastUsedPIN: String {
        savedServers.first.map { pin(for: $0.name) } ?? ""
    }

    private func upsertSavedServer(name: String, pin: String) {
        KeychainStore.setPIN(pin, for: name)
        var list = savedServers
        if let idx = list.firstIndex(where: { $0.name == name }) {
            list[idx].lastConnected = Date()
        } else {
            list.append(SavedServer(name: name, lastConnected: Date()))
        }
        storeSavedServers(list)
    }

    func removeSavedServer(id: UUID) {
        guard let server = savedServers.first(where: { $0.id == id }) else { return }
        KeychainStore.removePIN(for: server.name)
        storeSavedServers(savedServers.filter { $0.id != id })
    }

    /// Earlier versions kept PINs in UserDefaults. Move them to the Keychain once.
    private func migrateLegacyStorage() {
        struct LegacySavedServer: Decodable { var name: String; var pin: String? }
        let defaults = UserDefaults.standard
        if let data = defaults.data(forKey: Self.savedServersKey),
           let legacy = try? JSONDecoder().decode([LegacySavedServer].self, from: data),
           legacy.contains(where: { $0.pin != nil }) {
            for server in legacy {
                if let pin = server.pin { KeychainStore.setPIN(pin, for: server.name) }
            }
            // Re-encode without the PINs.
            if let servers = try? JSONDecoder().decode([SavedServer].self, from: data),
               let clean = try? JSONEncoder().encode(servers) {
                defaults.set(clean, forKey: Self.savedServersKey)
            }
        }
        defaults.removeObject(forKey: "savedPIN")
    }

    // MARK: - Bonjour discovery

    private static func isPermissionError(_ error: Error) -> Bool {
        let desc = error.localizedDescription
        return desc.contains("noauth") || desc.contains("-65555")
    }

    func startBrowsing() {
        browser?.cancel()
        discoveredServers = []
        isLocalNetworkPermissionDenied = false

        let params = NWParameters()
        params.includePeerToPeer = true
        let b = NWBrowser(for: .bonjour(type: Self.serviceType, domain: nil), using: params)
        self.browser = b

        b.stateUpdateHandler = { [weak self] state in
            MainActor.assumeIsolated {
                switch state {
                case .ready:
                    // Permission confirmed — clear any stale denial flag
                    self?.isLocalNetworkPermissionDenied = false
                case .failed(let error):
                    // Only .failed is terminal; .waiting is transient and clears itself
                    if Self.isPermissionError(error) {
                        self?.isLocalNetworkPermissionDenied = true
                    } else {
                        self?.connectionError = error.localizedDescription
                    }
                default:
                    break
                }
            }
        }

        b.browseResultsChangedHandler = { [weak self] results, _ in
            MainActor.assumeIsolated {
                self?.discoveredServers = results
                    .map { DiscoveredServer(result: $0) }
                    .sorted { $0.name < $1.name }
            }
        }

        b.start(queue: .main)
    }

    func stopBrowsing() {
        browser?.cancel()
        browser = nil
    }

    // MARK: - Sign in / out

    /// Sign in from the login screen.
    func connect(to server: DiscoveredServer, pin: String) {
        connectionError = nil
        isConnecting = true
        open(server.endpoint, name: server.name, pin: pin, isSignIn: true)
    }

    /// Ends the session. The app will not reconnect until the user signs in again.
    func logout() {
        sendMessage(["type": "disconnect"])
        activeSession = nil
        UserDefaults.standard.removeObject(forKey: Self.sessionKey)
        closeConnection()
        startBrowsing()
    }

    // MARK: - App lifecycle

    /// Call from the scene phase. Sockets don't survive suspension, so close
    /// cleanly in the background and reconnect as soon as the app is back.
    func setAppActive(_ active: Bool) {
        isAppActive = active
        if active {
            if activeSession != nil { reconnect(resetBackoff: true) }
        } else {
            closeConnection()
            isConnecting = false
        }
    }

    private func reconnect(resetBackoff: Bool) {
        reconnectWork?.cancel()
        reconnectWork = nil
        if resetBackoff { reconnectAttempt = 0 }
        guard isAppActive, let session = activeSession, connection == nil else { return }
        let pin = pin(for: session.name)
        guard !pin.isEmpty else { logout(); return }
        let endpoint = NWEndpoint.service(name: session.name, type: Self.serviceType, domain: "local.", interface: nil)
        open(endpoint, name: session.name, pin: pin, isSignIn: false)
    }

    private func scheduleReconnect() {
        guard isAppActive, activeSession != nil else { return }
        let delay = min(0.5 * pow(2, Double(reconnectAttempt)), 10)
        reconnectAttempt += 1
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.reconnect(resetBackoff: false) }
        }
        reconnectWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    // MARK: - Connection

    private func open(_ endpoint: NWEndpoint, name: String, pin: String, isSignIn: Bool) {
        closeConnection()
        pending = (name, pin, isSignIn)

        let tcp = NWProtocolTCP.Options()
        tcp.connectionTimeout = 6
        tcp.noDelay = true
        tcp.enableKeepalive = true
        tcp.keepaliveIdle = 5
        tcp.keepaliveInterval = 2
        tcp.keepaliveCount = 3
        let params = NWParameters(tls: nil, tcp: tcp)
        params.includePeerToPeer = true
        // Force physical WiFi interface so VPN tunnels don't block local TCP connections
        params.requiredInterfaceType = .wifi
        let conn = NWConnection(to: endpoint, using: params)
        self.connection = conn

        conn.stateUpdateHandler = { [weak self, weak conn] state in
            MainActor.assumeIsolated {
                guard let self, let conn, conn === self.connection else { return }
                switch state {
                case .ready:
                    self.sendMessage(["type": "auth", "pin": pin], beforeAuth: true)
                    self.receiveLoop(conn)
                case .waiting(let error), .failed(let error):
                    self.connectionFailed(error)
                default:
                    break
                }
            }
        }

        conn.start(queue: .main)
    }

    private func connectionFailed(_ error: NWError?) {
        let wasSignIn = pending?.isSignIn ?? false
        let wasOnline = isOnline
        closeConnection()

        if let error, Self.isPermissionError(error) {
            isLocalNetworkPermissionDenied = true
        }
        if activeSession != nil {
            // Signed in: stay on the trackpad and keep trying.
            if wasOnline { reconnectAttempt = 0 }
            scheduleReconnect()
        } else if wasSignIn {
            isConnecting = false
            if !isLocalNetworkPermissionDenied {
                connectionError = "Couldn't reach the Mac. Make sure MacRemote is running on it and both devices are on the same Wi-Fi."
            }
        }
    }

    /// Closes the socket without ending the session.
    private func closeConnection() {
        heartbeat?.invalidate()
        heartbeat = nil
        reconnectWork?.cancel()
        reconnectWork = nil
        connection?.stateUpdateHandler = nil
        connection?.cancel()
        connection = nil
        pending = nil
        isOnline = false
        receiveBuffer = Data()
    }

    // MARK: - Receive loop

    private func receiveLoop(_ conn: NWConnection) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self, weak conn] data, _, isComplete, error in
            MainActor.assumeIsolated {
                guard let self, let conn, conn === self.connection else { return }
                if let data, !data.isEmpty {
                    self.receiveBuffer.append(data)
                    self.drainBuffer()
                }
                // Handling a message may have closed the connection.
                guard conn === self.connection else { return }
                if isComplete || error != nil {
                    self.connectionFailed(error)
                    return
                }
                self.receiveLoop(conn)
            }
        }
    }

    private func drainBuffer() {
        while let newline = receiveBuffer.firstIndex(of: 0x0A) {
            let lineData = receiveBuffer[receiveBuffer.startIndex..<newline]
            receiveBuffer = receiveBuffer[receiveBuffer.index(after: newline)...]
            if let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any] {
                handleIncoming(json)
            }
            // A handler may have closed the connection and cleared the buffer.
            if connection == nil { return }
        }
    }

    private func handleIncoming(_ json: [String: Any]) {
        guard let type = json["type"] as? String else { return }
        switch type {
        case "authResult":
            guard let pending else { return }
            if json["success"] as? Bool ?? false {
                authenticated(name: pending.name, pin: pending.pin, json: json)
            } else {
                authRejected(isSignIn: pending.isSignIn)
            }
        case "pong":
            lastPong = Date()
        case "error":
            // Wrong-PIN errors are already handled through authResult.
            if isOnline { connectionError = json["message"] as? String ?? "An error occurred." }
        default:
            break
        }
    }

    private func authenticated(name: String, pin: String, json: [String: Any]) {
        isOnline = true
        isConnecting = false
        connectionError = nil
        isLocalNetworkPermissionDenied = false
        reconnectAttempt = 0
        capabilities = Set(json["capabilities"] as? [String] ?? [])

        upsertSavedServer(name: name, pin: pin)
        activeSession = savedServers.first { $0.name == name }
        UserDefaults.standard.set(name, forKey: Self.sessionKey)
        stopBrowsing()
        startHeartbeat()
    }

    private func authRejected(isSignIn: Bool) {
        closeConnection()
        isConnecting = false
        if isSignIn {
            connectionError = "Wrong PIN — check the Mac app and try again."
        } else {
            // The PIN was changed on the Mac: the session can't continue.
            activeSession = nil
            UserDefaults.standard.removeObject(forKey: Self.sessionKey)
            connectionError = "The PIN on your Mac has changed. Enter the new PIN to reconnect."
            startBrowsing()
        }
    }

    /// Detects a dead connection within seconds (e.g. the Mac went to sleep).
    /// Only used with servers that answer pings.
    private func startHeartbeat() {
        heartbeat?.invalidate()
        guard supports("ping") else { return }
        lastPong = Date()
        heartbeat = Timer.scheduledTimer(withTimeInterval: 4, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.isOnline else { return }
                if Date().timeIntervalSince(self.lastPong) > 10 {
                    self.connectionFailed(nil)
                } else {
                    self.sendMessage(["type": "ping"])
                }
            }
        }
    }

    // MARK: - Sending

    /// Commands are dropped while offline; replaying stale moves and keys later
    /// would do surprising things on the Mac.
    func sendMessage(_ dict: [String: Any], beforeAuth: Bool = false) {
        guard let conn = connection, isOnline || beforeAuth,
              var payload = try? JSONSerialization.data(withJSONObject: dict) else { return }
        payload.append(0x0A)
        conn.send(content: payload, completion: .idempotent)
    }

    func sendMove(dx: CGFloat, dy: CGFloat) {
        let now = Date()
        guard now.timeIntervalSince(lastMoveSent) > 0.008 else { return }
        lastMoveSent = now
        sendMessage(["type": "move", "dx": Double(dx), "dy": Double(dy)])
    }

    func sendTap()        { sendMessage(["type": "tap"]) }
    func sendRightClick() { sendMessage(["type": "rightClick"]) }

    func sendScroll(dx: CGFloat, dy: CGFloat) {
        sendMessage(["type": "scroll", "dx": Double(dx), "dy": Double(dy)])
    }

    func sendKeypress(_ characters: String, modifiers: [Int] = []) {
        var msg: [String: Any] = ["type": "keypress", "characters": characters]
        if !modifiers.isEmpty { msg["modifiers"] = modifiers }
        sendMessage(msg)
    }

    func sendKeyCode(_ code: Int, modifiers: [Int] = []) {
        var msg: [String: Any] = ["type": "keyCode", "code": code]
        if !modifiers.isEmpty { msg["modifiers"] = modifiers }
        sendMessage(msg)
    }

    func sendAppSwitcher(reverse: Bool = false) {
        sendMessage(["type": "appSwitcher", "reverse": reverse])
    }

    enum VolumeAction: String { case up, down, mute }
    func sendVolume(_ action: VolumeAction) {
        sendMessage(["type": "volume", "action": action.rawValue])
    }

    enum MediaAction: String { case playPause, next, previous }
    func sendMedia(_ action: MediaAction) {
        sendMessage(["type": "media", "action": action.rawValue])
    }

    func sendSleep() { sendMessage(["type": "sleep"]) }

    func sendSwitchSpace(left: Bool) {
        sendMessage(["type": "switchSpace", "direction": left ? "left" : "right"])
    }
}
