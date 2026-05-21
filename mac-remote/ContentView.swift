import SwiftUI

struct ContentView: View {
    @Environment(ConnectionManager.self) private var connectionManager
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
        .onChange(of: scenePhase) {
            // Restart discovery when returning from background so a Local Network
            // permission grant in Settings takes effect without needing an app relaunch.
            if scenePhase == .active, !connectionManager.isAuthenticated {
                connectionManager.startBrowsing()
            }
        }
    }
}
