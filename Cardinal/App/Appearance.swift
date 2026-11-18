import AppKit
import SwiftUI

/// Apparence de Cardinal : celle de macOS (automatique), ou toujours claire, ou toujours sombre.
/// Les exports (PNG, PDF, impression) restent toujours en clair, quel que soit ce choix.
enum AppAppearance: String, CaseIterable, Identifiable {
    case automatique, clair, sombre

    static let storageKey = "apparence"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .automatique: "Automatique"
        case .clair: "Clair"
        case .sombre: "Sombre"
        }
    }

    var symbol: String {
        switch self {
        case .automatique: "circle.lefthalf.filled"
        case .clair: "sun.max.fill"
        case .sombre: "moon.fill"
        }
    }

    var detail: String {
        switch self {
        case .automatique: "Suit l'apparence de macOS, y compris ses changements automatiques jour / nuit."
        case .clair: "Toujours clair, même si macOS est en sombre."
        case .sombre: "Toujours sombre, même si macOS est en clair."
        }
    }

    private var nsAppearance: NSAppearance? {
        switch self {
        case .automatique: nil
        case .clair: NSAppearance(named: .aqua)
        case .sombre: NSAppearance(named: .darkAqua)
        }
    }

    static var stored: AppAppearance {
        UserDefaults.standard.string(forKey: storageKey).flatMap(AppAppearance.init(rawValue:)) ?? .automatique
    }

    /// Mémorise le choix et l'applique tout de suite à toutes les fenêtres.
    @MainActor
    static func choose(_ appearance: AppAppearance) {
        UserDefaults.standard.set(appearance.rawValue, forKey: storageKey)
        apply(appearance)
    }

    @MainActor
    static func apply(_ appearance: AppAppearance = stored) {
        NSApp.appearance = appearance.nsAppearance
    }
}

/// Choix de l'apparence : trois boutons avec leur icône (Réglages).
struct AppearancePicker: View {
    @AppStorage(AppAppearance.storageKey) private var appearance: AppAppearance = .automatique

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Picker("Apparence", selection: Binding(get: { appearance }, set: { AppAppearance.choose($0) })) {
                ForEach(AppAppearance.allCases) { option in
                    Label(option.label, systemImage: option.symbol).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden() // le titre de la section suffit
            Text(appearance.detail)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

/// Sous-menu « Apparence » du menu Présentation, avec la coche sur le choix actuel.
struct AppearanceMenu: View {
    @AppStorage(AppAppearance.storageKey) private var appearance: AppAppearance = .automatique

    var body: some View {
        Picker("Apparence", selection: Binding(get: { appearance }, set: { AppAppearance.choose($0) })) {
            ForEach(AppAppearance.allCases) { option in
                Label(option.label, systemImage: option.symbol).tag(option)
            }
        }
    }
}

/// Raccourci visible (barre d'état, accueil) : l'icône de l'apparence actuelle, et le menu des trois choix.
struct AppearanceQuickMenu: View {
    @AppStorage(AppAppearance.storageKey) private var appearance: AppAppearance = .automatique

    var body: some View {
        Menu {
            ForEach(AppAppearance.allCases) { option in
                Button {
                    AppAppearance.choose(option)
                } label: {
                    if option == appearance {
                        Label(option.label, systemImage: "checkmark")
                    } else {
                        Text(option.label)
                    }
                }
            }
            Divider()
            SettingsLink { Text("Tous les réglages…") }
        } label: {
            Label("Apparence : \(appearance.label)", systemImage: appearance.symbol)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Apparence de Cardinal : automatique (comme macOS), claire ou sombre")
    }
}
