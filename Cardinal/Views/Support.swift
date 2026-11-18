import SwiftUI
import AppKit

enum Tool: String, CaseIterable, Identifiable {
    case select, entity, association, link, inheritance, constraint, cif, rule, note
    case rectangle, ellipse, line, arrow, image

    var id: String { rawValue }

    var label: String {
        switch self {
        case .select: "Sélection"
        case .entity: "Entité"
        case .association: "Association"
        case .link: "Lien"
        case .inheritance: "Héritage"
        case .constraint: "Contrainte"
        case .cif: "CIF"
        case .rule: "Règle de gestion"
        case .note: "Texte"
        case .rectangle: "Rectangle"
        case .ellipse: "Ellipse"
        case .line: "Trait"
        case .arrow: "Flèche"
        case .image: "Image"
        }
    }

    /// Figure d'illustration créée par l'outil (nil pour les autres outils).
    var figureKind: FigureKind? {
        switch self {
        case .rectangle: .rectangle
        case .ellipse: .ellipse
        case .line: .line
        case .arrow: .arrow
        case .image: .image
        default: nil
        }
    }

    var symbol: String {
        switch self {
        case .select: "cursorarrow"
        case .entity: "rectangle.fill"
        case .association: "capsule.fill"
        case .link: "point.topleft.down.to.point.bottomright.curvepath.fill"
        case .inheritance: "triangle.fill"
        case .constraint: "c.circle.fill"
        case .cif: "exclamationmark.circle.fill"
        case .rule: "r.square.fill"
        case .note: "textformat"
        case .rectangle: "rectangle.fill"
        case .ellipse: "oval.fill"
        case .line: "line.diagonal"
        case .arrow: "arrow.up.right"
        case .image: "photo.fill"
        }
    }

    /// Miniature affichée dans le ruban (nil : symbole système, pour le pointeur).
    var glyph: Glyph? {
        switch self {
        case .select: nil
        case .entity: .entity
        case .association: .association
        case .link: .link
        case .inheritance: .inheritance
        case .constraint: .constraint
        case .cif: .cif
        case .rule: .rule
        case .note: .text
        case .rectangle, .ellipse, .line, .arrow, .image: nil
        }
    }

    var hint: String? {
        switch self {
        case .select: nil
        case .entity: "Cliquez sur le canevas pour placer une entité"
        case .association: "Cliquez sur le canevas pour placer une association"
        case .link: "Cliquez sur deux éléments à relier (entité ↔ association, héritage, contrainte, règle)"
        case .inheritance: "Cliquez pour placer un héritage, puis reliez le surtype et les sous-types"
        case .constraint: "Cliquez pour placer une contrainte, puis reliez-la aux associations et entités"
        case .cif: "Cliquez pour placer une CIF, puis reliez l'association et l'entité cible"
        case .rule: "Cliquez pour placer une règle de gestion"
        case .note: "Cliquez pour placer un texte"
        case .rectangle, .ellipse: "Cliquez pour placer la forme, puis tirez sa poignée pour la redimensionner"
        case .line, .arrow: "Cliquez pour placer le trait, puis tirez ses extrémités"
        case .image: "Cliquez à l'endroit où placer l'image, puis choisissez le fichier"
        }
    }
}

enum ViewMode: String, CaseIterable, Identifiable {
    case mcd = "MCD"
    case mld = "MLD"
    case uml = "UML"
    case sql = "SQL"

    var id: String { rawValue }
}

/// Palette « académique » : un bleu institutionnel dominant pour les entités,
/// un ambre en accent pour les associations et les cardinalités.
/// Chaque couleur a deux variantes (clair / sombre) pour garder un contraste WCAG AA.
enum Theme {
    /// Fond des en-têtes, avec texte blanc par-dessus.
    static let entityFill = adaptive(light: (0.14, 0.29, 0.52), dark: (0.18, 0.35, 0.63))
    static let associationFill = adaptive(light: (0.60, 0.36, 0.06), dark: (0.62, 0.38, 0.09))
    /// Texte et icônes posés sur le fond de la fenêtre.
    static let entity = adaptive(light: (0.14, 0.29, 0.52), dark: (0.56, 0.70, 0.95))
    static let association = adaptive(light: (0.62, 0.36, 0.04), dark: (0.93, 0.66, 0.31))
    static let constraint = adaptive(light: (0.45, 0.25, 0.62), dark: (0.74, 0.60, 0.92))
    static let rule = adaptive(light: (0.10, 0.45, 0.42), dark: (0.45, 0.80, 0.76))

    static let link = Color.primary.opacity(0.42)
    static let cornerRadius: CGFloat = 9

    static func adaptive(light: (CGFloat, CGFloat, CGFloat), dark: (CGFloat, CGFloat, CGFloat)) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            let c = isDark ? dark : light
            return NSColor(srgbRed: c.0, green: c.1, blue: c.2, alpha: 1)
        })
    }
}

extension NodeColor {
    var label: String {
        switch self {
        case .auto: "Automatique"
        case .bleu: "Bleu"
        case .sarcelle: "Sarcelle"
        case .vert: "Vert"
        case .violet: "Violet"
        case .rouge: "Rouge"
        case .ardoise: "Ardoise"
        }
    }

    private var rgb: (CGFloat, CGFloat, CGFloat)? {
        switch self {
        case .auto: nil
        case .bleu: (0.16, 0.38, 0.70)
        case .sarcelle: (0.05, 0.45, 0.47)
        case .vert: (0.17, 0.47, 0.22)
        case .violet: (0.42, 0.26, 0.64)
        case .rouge: (0.66, 0.20, 0.20)
        case .ardoise: (0.29, 0.33, 0.40)
        }
    }

    /// Couleur de fond (texte blanc par-dessus).
    func fill(default fallback: Color) -> Color {
        guard let c = rgb else { return fallback }
        return Color(red: c.0, green: c.1, blue: c.2)
    }

    /// Couleur d'encre (texte et traits sur le fond de la fenêtre), éclaircie en mode sombre.
    func ink(default fallback: Color) -> Color {
        guard let c = rgb else { return fallback }
        return Theme.adaptive(light: c, dark: (c.0 + (1 - c.0) * 0.5, c.1 + (1 - c.1) * 0.5, c.2 + (1 - c.2) * 0.5))
    }
}

