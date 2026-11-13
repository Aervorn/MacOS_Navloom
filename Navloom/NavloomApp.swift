import SwiftUI

@main
struct NavloomApp: App {
    static let mainWindowID = "main"

    init() {
        _ = AppUpdater.shared   // démarre Sparkle (recherche planifiée des mises à jour)
    }

    var body: some Scene {
        WindowGroup(id: Self.mainWindowID) {
            MainView()
        }
        .defaultSize(width: 960, height: 640)
        .commands {
            CommandGroup(after: .appInfo) {
                CheckForUpdatesMenuItem()
            }
            CommandGroup(replacing: .appSettings) {
                SettingsMenuItem()
            }
        }
    }
}
