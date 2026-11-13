import SwiftUI

/// Sélection de la barre latérale de la fenêtre active, exposée au menu de l'app
/// (⌘, ouvre l'entrée Paramètres de la barre latérale : Navloom n'a pas de fenêtre de réglages séparée).
nonisolated struct SelectedFeatureKey: FocusedValueKey {
    typealias Value = Binding<Feature?>
}

extension FocusedValues {
    var selectedFeature: Binding<Feature?>? {
        get { self[SelectedFeatureKey.self] }
        set { self[SelectedFeatureKey.self] = newValue }
    }
}

/// Entrée demandée par le menu alors qu'aucune fenêtre n'était ouverte :
/// la prochaine fenêtre l'affiche dès son ouverture.
enum PendingNavigation {
    static var feature: Feature?
}

/// Remplace l'entrée « Réglages… » du menu de l'app (⌘,).
struct SettingsMenuItem: View {
    @FocusedValue(\.selectedFeature) private var selection
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Settings…") {
            if let selection {
                selection.wrappedValue = .settings
            } else {
                PendingNavigation.feature = .settings
                openWindow(id: NavloomApp.mainWindowID)
            }
        }
        .keyboardShortcut(",", modifiers: .command)
    }
}
