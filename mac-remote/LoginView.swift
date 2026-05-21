import SwiftUI

struct LoginView: View {
    @Environment(ConnectionManager.self) private var connectionManager

    @State private var selectedServer: DiscoveredServer? = nil
    @State private var pin = ""
    @State private var appeared = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            ambientOrbs

            ScrollView {
                VStack(spacing: 24) {
                    header
                    savedServersCard
                    discoveredServersCard
                    pinCard
                    connectButton
                    if connectionManager.isLocalNetworkPermissionDenied {
                        localNetworkPermissionBanner
                    } else if let error = connectionManager.connectionError {
                        errorBanner(error)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 64)
                .padding(.bottom, 40)
            }
        }
        .onAppear {
            pin = connectionManager.savedPIN
            connectionManager.startBrowsing()
            withAnimation(.easeOut(duration: 0.6)) { appeared = true }
        }
        .onDisappear {
            connectionManager.stopBrowsing()
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 8) {
            Image(systemName: "cursorarrow.rays")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(
                    LinearGradient(colors: [.blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing)
                )
                .padding(.bottom, 4)

            Text("Mac Remote")
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

            Text("Control your Mac from your iPhone")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.5))
        }
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : -20)
    }

    // MARK: - Saved servers card

    @ViewBuilder
    private var savedServersCard: some View {
        let saved = connectionManager.savedServers
        if !saved.isEmpty {
            GlassCard {
                VStack(alignment: .leading, spacing: 12) {
                    Label("Saved Macs", systemImage: "bookmark.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.5))
                        .textCase(.uppercase)

                    ForEach(saved) { server in
                        savedServerRow(server)
                    }
                }
            }
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 16)
            .animation(.easeOut(duration: 0.5).delay(0.08), value: appeared)
        }
    }

    private func savedServerRow(_ server: SavedServer) -> some View {
        let isSelected = selectedServer?.name == server.name

        return HStack(spacing: 14) {
            Button {
                // Auto-fill PIN and select if found in discovered list
                pin = server.pin
                selectedServer = connectionManager.discoveredServers.first { $0.name == server.name }
            } label: {
                HStack(spacing: 14) {
                    Image(systemName: "desktopcomputer")
                        .font(.title3.weight(.medium))
                        .foregroundStyle(isSelected ? Color.blue : .white.opacity(0.7))
                        .frame(width: 28)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(server.name)
                            .font(.body.weight(.medium))
                            .foregroundStyle(.white)
                        Text("Last used: \(server.lastConnected.formatted(.relative(presentation: .named)))")
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.4))
                    }

                    Spacer()

                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title3)
                            .foregroundStyle(.blue)
                    } else {
                        // Online indicator if currently on network
                        let isOnline = connectionManager.discoveredServers.contains { $0.name == server.name }
                        Circle()
                            .fill(isOnline ? Color.green : Color.white.opacity(0.2))
                            .frame(width: 7, height: 7)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(isSelected ? Color.white.opacity(0.12) : Color.white.opacity(0.04))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(isSelected ? Color.blue.opacity(0.5) : Color.white.opacity(0.08), lineWidth: 0.5)
                )
            }
            .buttonStyle(.plain)

            // Delete button
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                    connectionManager.removeSavedServer(id: server.id)
                    if selectedServer?.name == server.name { selectedServer = nil }
                }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(.white.opacity(0.3))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Discovered servers card

    private var discoveredServersCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                Label("Available on Network", systemImage: "wifi")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.5))
                    .textCase(.uppercase)

                if connectionManager.discoveredServers.isEmpty {
                    HStack(spacing: 12) {
                        ProgressView()
                            .tint(.white.opacity(0.5))
                        Text("Searching on local network…")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.5))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
                } else {
                    ForEach(connectionManager.discoveredServers) { server in
                        discoveredServerRow(server)
                    }
                }
            }
        }
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 16)
        .animation(.easeOut(duration: 0.5).delay(0.13), value: appeared)
    }

    private func discoveredServerRow(_ server: DiscoveredServer) -> some View {
        let isSelected = selectedServer?.id == server.id
        let isSaved = connectionManager.savedServers.contains { $0.name == server.name }

        return Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                selectedServer = server
                // Auto-fill saved PIN if we know this server
                if let saved = connectionManager.savedServers.first(where: { $0.name == server.name }) {
                    pin = saved.pin
                }
            }
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "desktopcomputer")
                    .font(.title3.weight(.medium))
                    .foregroundStyle(isSelected ? Color.blue : .white.opacity(0.7))
                    .frame(width: 28)

                Text(server.name)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.white)

                if isSaved {
                    Image(systemName: "bookmark.fill")
                        .font(.caption)
                        .foregroundStyle(.blue.opacity(0.7))
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.blue)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(isSelected ? Color.white.opacity(0.12) : Color.white.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(
                        isSelected ? Color.blue.opacity(0.5) : Color.white.opacity(0.08),
                        lineWidth: 0.5
                    )
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - PIN card

    private var pinCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                Label("PIN Code", systemImage: "lock.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.5))
                    .textCase(.uppercase)

                HStack(spacing: 12) {
                    TextField("Enter PIN from Mac app", text: $pin)
                        .keyboardType(.numberPad)
                        .font(.system(size: 22, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.white)
                        .tint(.blue)
                        .onChange(of: pin) { _, newValue in
                            let filtered = newValue.filter { $0.isNumber }
                            if filtered != newValue || newValue.count > 4 {
                                pin = String(filtered.prefix(4))
                            }
                        }

                    if !pin.isEmpty {
                        Button { pin = "" } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.white.opacity(0.4))
                        }
                        .buttonStyle(.plain)
                    }
                }

                Text("Set the PIN in the Mac app's menu bar icon.")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.35))
            }
        }
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 16)
        .animation(.easeOut(duration: 0.5).delay(0.18), value: appeared)
    }

    // MARK: - Connect button

    private var connectButton: some View {
        let canConnect = selectedServer != nil && pin.count == 4 && !connectionManager.isConnecting

        return Button {
            guard let server = selectedServer else { return }
            connectionManager.connect(to: server, pin: pin)
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(
                        LinearGradient(
                            colors: canConnect
                                ? [Color.blue, Color.purple]
                                : [Color.white.opacity(0.1), Color.white.opacity(0.08)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(height: 56)

                if connectionManager.isConnecting {
                    HStack(spacing: 10) {
                        ProgressView().tint(.white)
                        Text("Connecting…")
                            .font(.headline)
                            .foregroundStyle(.white)
                    }
                } else {
                    Text("Connect")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(canConnect ? .white : .white.opacity(0.3))
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(!canConnect)
        .opacity(appeared ? 1 : 0)
        .animation(.easeOut(duration: 0.5).delay(0.25), value: appeared)
    }

    // MARK: - Local network permission banner

    private var localNetworkPermissionBanner: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "network.slash")
                    .foregroundStyle(.orange)
                Text("Local Network Access Required")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.white)
            }
            Text("Mac Remote needs local network access to discover your Mac. Open Settings and enable it under Privacy & Security → Local Network.")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.7))
            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            } label: {
                Label("Open Settings", systemImage: "gear")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color.orange.opacity(0.8))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(Color.orange.opacity(0.15))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.orange.opacity(0.3), lineWidth: 0.5))
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    // MARK: - Error banner

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.85))
            Spacer()
        }
        .padding(14)
        .background(Color.orange.opacity(0.15))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.orange.opacity(0.3), lineWidth: 0.5))
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    // MARK: - Background orbs

    private var ambientOrbs: some View {
        ZStack {
            Circle()
                .fill(RadialGradient(colors: [Color.blue.opacity(0.45), .clear],
                                     center: .center, startRadius: 0, endRadius: 200))
                .frame(width: 400, height: 400)
                .blur(radius: 60)
                .offset(x: -120, y: -300)

            Circle()
                .fill(RadialGradient(colors: [Color.purple.opacity(0.4), .clear],
                                     center: .center, startRadius: 0, endRadius: 180))
                .frame(width: 350, height: 350)
                .blur(radius: 50)
                .offset(x: 160, y: 100)

            Circle()
                .fill(RadialGradient(colors: [Color.indigo.opacity(0.3), .clear],
                                     center: .center, startRadius: 0, endRadius: 150))
                .frame(width: 300, height: 300)
                .blur(radius: 70)
                .offset(x: -60, y: 350)
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Reusable glass card

struct GlassCard<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(18)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5)
            )
    }
}
