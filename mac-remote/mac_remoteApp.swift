import SwiftUI

@main
struct mac_remoteApp: App {
    @State private var connectionManager = ConnectionManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(connectionManager)
                .preferredColorScheme(.dark)
                .task { triggerLocalNetworkPermission() }
        }
    }

    // Sends a single UDP byte to the mDNS multicast address via a raw BSD
    // socket. The sendto() call is synchronous so iOS intercepts it immediately
    // and shows the Local Network permission dialog — before the user has to
    // interact with anything. The NWConnection-based approach is async and
    // frequently misses the prompt window on first launch.
    private func triggerLocalNetworkPermission() {
        DispatchQueue.global().async {
            let sock = socket(AF_INET, SOCK_DGRAM, 0)
            guard sock >= 0 else { return }
            defer { close(sock) }
            var addr = sockaddr_in()
            addr.sin_family = sa_family_t(AF_INET)
            addr.sin_port = UInt16(5353).bigEndian
            addr.sin_addr.s_addr = inet_addr("224.0.0.251")
            let byte: [UInt8] = [0]
            withUnsafePointer(to: &addr) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockAddr in
                    _ = sendto(sock, byte, 1, 0, sockAddr, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        }
    }
}
