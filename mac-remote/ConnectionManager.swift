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

// MARK: - Saved server (persisted across launches)

struct SavedServer: Codable, Identifiable, Sendable {
    var id: UUID = UUID()
    var name: String
    var pin: String
    var lastConnected: Date
}

// MARK: - Connection manager

@Observable
@MainActor
final class ConnectionManager {
    var discoveredServers: [DiscoveredServer] = []
    var isConnected = false
    var isAuthenticated = false
    var isConnecting = false
    var connectionError: String? = nil
    var isLocalNetworkPermissionDenied = false
    var connectedServerName = ""

    private var browser: NWBrowser?
    private var connection: NWConnection?
    private var receiveBuffer = Data()
    private var lastMoveSent = Date.distantPast

    // MARK: - Saved servers (persisted)

    var savedServers: [SavedServer] {
        get {
            guard let data = UserDefaults.standard.data(forKey: "savedServers"),
                  let decoded = try? JSONDecoder().decode([SavedServer].self, from: data)
            else { return [] }
            return decoded.sorted { $0.lastConnected > $1.lastConnected }
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                UserDefaults.standard.set(data, forKey: "savedServers")
            }
        }
    }

    func upsertSavedServer(name: String, pin: String) {
        var list = savedServers
        if let idx = list.firstIndex(where: { $0.name == name }) {
            list[idx].pin = pin
            list[idx].lastConnected = Date()
        } else {
            list.append(SavedServer(name: name, pin: pin, lastConnected: Date()))
        }
        savedServers = list
    }

    func removeSavedServer(id: UUID) {
        var list = savedServers
        list.removeAll { $0.id == id }
        savedServers = list
    }

    // Convenience: saved PIN for the currently-selected server name
    var savedPIN: String {
        get { UserDefaults.standard.string(forKey: "savedPIN") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "savedPIN") }
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
        let b = NWBrowser(for: .bonjour(type: "_macremote._tcp", domain: nil), using: params)
        self.browser = b

        b.stateUpdateHandler = { state in
            Task { @MainActor [weak self] in
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

        b.browseResultsChangedHandler = { results, _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.discoveredServers = results
                    .map { DiscoveredServer(result: $0) }
                    .sorted { $0.name < $1.name }
            }
        }

        b.start(queue: .global(qos: .utility))
    }

    func stopBrowsing() {
        browser?.cancel()
        browser = nil
    }

    // MARK: - Connection

    func connect(to server: DiscoveredServer, pin: String) {
        savedPIN = pin
        isConnecting = true
        connectionError = nil
        connectedServerName = server.name

        let params = NWParameters.tcp
        params.includePeerToPeer = true
        // Force physical WiFi interface so VPN tunnels don't block local TCP connections
        params.requiredInterfaceType = .wifi
        let conn = NWConnection(to: server.endpoint, using: params)
        self.connection = conn

        conn.stateUpdateHandler = { state in
            Task { @MainActor [weak self] in
                guard let self else { return }
                switch state {
                case .ready:
                    self.isConnected = true
                    self.sendMessage(["type": "auth", "pin": pin])
                    self.receiveLoop()
                case .failed(let error):
                    if Self.isPermissionError(error) {
                        self.isLocalNetworkPermissionDenied = true
                    } else {
                        self.connectionError = error.localizedDescription
                    }
                    self.reset()
                case .cancelled:
                    self.reset()
                default:
                    break
                }
            }
        }

        conn.start(queue: .global(qos: .userInteractive))
    }

    func disconnect() {
        sendMessage(["type": "disconnect"])
        connection?.cancel()
        connection = nil
        reset()
        startBrowsing()
    }

    private func reset() {
        isConnected = false
        isAuthenticated = false
        isConnecting = false
        connectedServerName = ""
        receiveBuffer = Data()
        // isLocalNetworkPermissionDenied is intentionally NOT cleared here —
        // it persists until the next startBrowsing() call so the UI can show
        // the "Open Settings" prompt across the connection reset.
    }

    // MARK: - Receive loop

    private func receiveLoop() {
        connection?.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let data, !data.isEmpty {
                    self.receiveBuffer.append(data)
                    self.drainBuffer()
                }
                if isComplete || error != nil {
                    if self.isAuthenticated {
                        self.connectionError = "Connection lost."
                    }
                    self.reset()
                    self.startBrowsing()
                    return
                }
                self.receiveLoop()
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
        }
    }

    private func handleIncoming(_ json: [String: Any]) {
        guard let type = json["type"] as? String else { return }
        switch type {
        case "authResult":
            let success = json["success"] as? Bool ?? false
            isConnecting = false
            if success {
                isAuthenticated = true
                stopBrowsing()
                // Persist this server for quick reconnect
                upsertSavedServer(name: connectedServerName, pin: savedPIN)
            } else {
                connectionError = "Wrong PIN — check the Mac app and try again."
                connection?.cancel()
                connection = nil
                reset()
            }
        case "error":
            connectionError = json["message"] as? String ?? "An error occurred."
        default:
            break
        }
    }

    // MARK: - Sending

    func sendMessage(_ dict: [String: Any]) {
        guard let conn = connection,
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

    func sendKeypress(_ characters: String) {
        sendMessage(["type": "keypress", "characters": characters])
    }

    func sendKeyCode(_ code: Int) {
        sendMessage(["type": "keyCode", "code": code])
    }

    func sendSleep() { sendMessage(["type": "sleep"]) }

    func sendSwitchSpace(left: Bool) {
        sendMessage(["type": "switchSpace", "direction": left ? "left" : "right"])
    }
}
