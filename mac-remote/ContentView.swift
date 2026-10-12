import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var connectionManager: ConnectionManager
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if connectionManager.isAuthenticated {
                TrackpadView()
            } else {
                LoginView()
            }
        }
        .animation(.easeInOut(duration: 0.35), value: connectionManager.isAuthenticated)
        .onChange(of: scenePhase) { phase in
            switch phase {
            case .active:
                // Signed in: reconnect silently. Otherwise restart discovery so a Local
                // Network permission grant in Settings takes effect without a relaunch.
                connectionManager.setAppActive(true)
                if !connectionManager.isAuthenticated {
                    connectionManager.startBrowsing()
                }
            case .background:
                connectionManager.setAppActive(false)
            default:
                // .inactive (Face ID, Control Center, app switcher) keeps the connection.
                break
            }
        }
    }
}
