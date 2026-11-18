import SwiftUI

/// État d'une fenêtre (outil, vue, zoom, sélection), partagé avec la barre de menus.
@MainActor
final class WindowState: ObservableObject {
    @Published var tool: Tool = .select
    @Published var mode: ViewMode = .mcd
    @Published var zoom: CGFloat = 1
    @Published var selection: Set<NodeRef> = []
    @Published var fitRequest = 0
    @Published var showInspector = true
    /// Vue (sous-modèle) affichée dans le canevas ; nil : le modèle complet.
    @Published var activeView: ModelView.ID?

    init(mode: ViewMode = .mcd, selection: Set<NodeRef> = []) {
        self.mode = mode
        self.selection = selection
    }

    func zoomIn() { zoom = min((zoom * 10).rounded() / 10 + 0.1, 2.5) }
    func zoomOut() { zoom = max((zoom * 10).rounded() / 10 - 0.1, 0.3) }
    func actualSize() { zoom = 1 }
    func fit() { fitRequest += 1 }
}

struct CardinalDocumentKey: FocusedValueKey { typealias Value = Binding<CardinalDocument> }

extension FocusedValues {
    var cardinalDocument: Binding<CardinalDocument>? {
        get { self[CardinalDocumentKey.self] }
        set { self[CardinalDocumentKey.self] = newValue }
    }
}

/// Préférences par défaut des nouveaux modèles (fenêtre Réglages).
enum Defaults {
    static let dialect = "dialecteSQL"
    static let naming = "nommageParDefaut"
    static let foreignKeysAtEnd = "clesEnFinParDefaut"
    static let useLabels = "libellesParDefaut"
    static let showTypes = "typesParDefaut"
    static let showGrid = "grilleParDefaut"

    /// Réglages appliqués à un nouveau document.
    static var newModelSettings: ModelSettings {
        let store = UserDefaults.standard
        var settings = ModelSettings()
        if let raw = store.string(forKey: naming), let naming = NamingConvention(rawValue: raw) { settings.naming = naming }
        settings.foreignKeysAtEnd = store.bool(forKey: foreignKeysAtEnd)
        settings.useLabels = store.bool(forKey: useLabels)
        if store.object(forKey: showTypes) != nil { settings.showTypes = store.bool(forKey: showTypes) }
        if store.object(forKey: showGrid) != nil { settings.showGrid = store.bool(forKey: showGrid) }
        return settings
    }
}
