import SwiftUI

/// Miniatures dessinées pour le ruban : chaque outil montre la forme réelle qu'il crée sur le canevas,
/// dans les couleurs de Cardinal. Aucune bibliothèque d'icônes ne propose de symboles Merise :
/// ces dessins sont originaux et suivent le même poids visuel (cadre 30 × 24, traits de 1,4 pt).
enum Glyph: Hashable {
    case entity, association, inheritance, constraint, cif, rule, link, text
    case formalismMCD, formalismMLD, formalismUML, formalismSQL
    case mldText, crowsFoot, umlSimple
}

struct GlyphView: View {
    let glyph: Glyph
    static let size = CGSize(width: 30, height: 24)

    var body: some View {
        Group {
            switch glyph {
            case .entity: EntityGlyph()
            case .association: AssociationGlyph()
            case .inheritance: InheritanceGlyph()
            case .constraint: CircleGlyph(text: "X", tint: Theme.constraint)
            case .cif: CircleGlyph(text: "CIF", tint: Theme.cif, filled: true)
            case .rule: RuleGlyph()
            case .link: LinkGlyph()
            case .text: TextGlyph()
            case .formalismMCD: MCDGlyph()
            case .formalismMLD: MLDGlyph()
            case .formalismUML: UMLGlyph()
            case .formalismSQL: SQLGlyph()
            case .mldText: MLDTextGlyph()
            case .crowsFoot: CrowsFootGlyph()
            case .umlSimple: UMLSimpleGlyph()
            }
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .accessibilityHidden(true)
    }
}

extension Theme {
    /// Rouge de la CIF : contrainte forte, distincte des autres contraintes (violet).
    static let cif = adaptive(light: (0.75, 0.16, 0.16), dark: (0.95, 0.42, 0.40))
    static let paper = Color(nsColor: .textBackgroundColor)
}

// MARK: - Éléments du MCD

/// Entité : bandeau bleu avec le nom, deux lignes de propriétés dont l'identifiant souligné.
private struct EntityGlyph: View {
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 3, style: .continuous)
        VStack(alignment: .leading, spacing: 0) {
            Rectangle().fill(Theme.entityFill).frame(height: 7)
            VStack(alignment: .leading, spacing: 3) {
                Capsule().fill(Theme.entity).frame(width: 12, height: 1.6)
                Capsule().fill(Color.secondary.opacity(0.7)).frame(width: 15, height: 1.6)
                Capsule().fill(Color.secondary.opacity(0.7)).frame(width: 10, height: 1.6)
            }
            .padding(.leading, 4)
            .padding(.top, 3)
            Spacer(minLength: 0)
        }
        .frame(width: 24, height: 21)
        .background(Theme.paper)
        .clipShape(shape)
        .overlay(shape.strokeBorder(Theme.entity, lineWidth: 1.2))
    }
}

/// Association : capsule ambrée avec son nom.
private struct AssociationGlyph: View {
    var body: some View {
        ZStack {
            Capsule().fill(Theme.paper)
            Capsule().fill(Theme.association.opacity(0.16))
            Capsule().strokeBorder(Theme.association, lineWidth: 1.4)
            Capsule().fill(Theme.association).frame(width: 13, height: 1.8)
        }
        .frame(width: 28, height: 15)
    }
}

/// Héritage : surtype en haut, triangle, deux sous-types en bas.
private struct InheritanceGlyph: View {
    var body: some View {
        Canvas { context, size in
            let ink = GraphicsContext.Shading.color(Theme.entity)
            let box = { (x: CGFloat, y: CGFloat, w: CGFloat) in
                Path(roundedRect: CGRect(x: x, y: y, width: w, height: 6), cornerRadius: 1.5)
            }
            context.fill(box(size.width / 2 - 6, 0.5, 12), with: .color(Theme.entityFill))
            var triangle = Path()
            triangle.move(to: CGPoint(x: size.width / 2, y: 8))
            triangle.addLine(to: CGPoint(x: size.width / 2 + 6, y: 15))
            triangle.addLine(to: CGPoint(x: size.width / 2 - 6, y: 15))
            triangle.closeSubpath()
            context.fill(triangle, with: .color(Theme.paper))
            context.stroke(triangle, with: ink, lineWidth: 1.3)
            var legs = Path()
            legs.move(to: CGPoint(x: size.width / 2, y: 6.5)); legs.addLine(to: CGPoint(x: size.width / 2, y: 8))
            legs.move(to: CGPoint(x: size.width / 2 - 3, y: 15)); legs.addLine(to: CGPoint(x: 7, y: 17.5))
            legs.move(to: CGPoint(x: size.width / 2 + 3, y: 15)); legs.addLine(to: CGPoint(x: size.width - 7, y: 17.5))
            context.stroke(legs, with: ink, lineWidth: 1.1)
            context.fill(box(2, 17.5, 10), with: .color(Theme.entityFill))
            context.fill(box(size.width - 12, 17.5, 10), with: .color(Theme.entityFill))
        }
    }
}

/// Contrainte (violet) ou CIF (rouge plein) : cercle avec son sigle.
private struct CircleGlyph: View {
    let text: String
    let tint: Color
    var filled = false

    var body: some View {
        ZStack {
            Circle().fill(filled ? AnyShapeStyle(tint) : AnyShapeStyle(Theme.paper))
            if !filled { Circle().fill(tint.opacity(0.14)) }
            Circle().strokeBorder(tint, lineWidth: 1.4)
            Text(text)
                .font(.system(size: text.count > 1 ? 7 : 10, weight: .heavy, design: .rounded))
                .foregroundStyle(filled ? Color.white : tint)
        }
        .frame(width: 21, height: 21)
    }
}

/// Règle de gestion : fiche au coin corné, accolades pour le code SQL.
private struct RuleGlyph: View {
    var body: some View {
        Canvas { context, size in
            let rect = CGRect(x: 6, y: 1, width: 18, height: 22)
            var page = Path()
            page.move(to: CGPoint(x: rect.minX, y: rect.minY))
            page.addLine(to: CGPoint(x: rect.maxX - 6, y: rect.minY))
            page.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + 6))
            page.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            page.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            page.closeSubpath()
            context.fill(page, with: .color(Theme.paper))
            context.fill(page, with: .color(Theme.rule.opacity(0.14)))
            context.stroke(page, with: .color(Theme.rule), lineWidth: 1.3)
            var fold = Path()
            fold.move(to: CGPoint(x: rect.maxX - 6, y: rect.minY))
            fold.addLine(to: CGPoint(x: rect.maxX - 6, y: rect.minY + 6))
            fold.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + 6))
            context.stroke(fold, with: .color(Theme.rule), lineWidth: 1)
            let label = context.resolve(Text("R").font(.system(size: 10, weight: .heavy, design: .rounded)).foregroundStyle(Theme.rule))
            context.draw(label, at: CGPoint(x: rect.midX - 1, y: rect.midY + 2))
        }
    }
}

/// Lien (patte) : trait avec une cardinalité au milieu.
private struct LinkGlyph: View {
    var body: some View {
        ZStack {
            Rectangle().fill(Color.primary.opacity(0.75)).frame(width: 28, height: 1.4)
            Text("0,N")
                .font(.system(size: 7.5, weight: .heavy, design: .rounded))
                .foregroundStyle(Theme.association)
                .padding(.horizontal, 2.5)
                .padding(.vertical, 0.5)
                .background(Capsule().fill(Theme.paper))
                .overlay(Capsule().strokeBorder(Theme.association.opacity(0.7), lineWidth: 0.8))
        }
    }
}

/// Texte : grande capitale avec ligne de base.
private struct TextGlyph: View {
    var body: some View {
        VStack(spacing: 1) {
            Text("T")
                .font(.system(size: 18, weight: .bold, design: .serif))
                .foregroundStyle(Color.primary)
            Capsule().fill(Color.secondary).frame(width: 16, height: 1.4)
        }
    }
}

// MARK: - Formalismes

/// E/A : entité – association – entité.
private struct MCDGlyph: View {
    var body: some View {
        Canvas { context, size in
            let y = size.height / 2
            var line = Path()
            line.move(to: CGPoint(x: 6, y: y)); line.addLine(to: CGPoint(x: size.width - 6, y: y))
            context.stroke(line, with: .color(.primary.opacity(0.6)), lineWidth: 1)
            for x in [CGFloat(1), size.width - 10] {
                let rect = CGRect(x: x, y: y - 6, width: 9, height: 12)
                context.fill(Path(roundedRect: rect, cornerRadius: 1.5), with: .color(Theme.paper))
                context.fill(Path(CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: 4)), with: .color(Theme.entityFill))
                context.stroke(Path(roundedRect: rect, cornerRadius: 1.5), with: .color(Theme.entity), lineWidth: 1)
            }
            let capsule = Path(roundedRect: CGRect(x: size.width / 2 - 5.5, y: y - 3.5, width: 11, height: 7), cornerRadius: 3.5)
            context.fill(capsule, with: .color(Theme.paper))
            context.stroke(capsule, with: .color(Theme.association), lineWidth: 1.2)
        }
    }
}

/// MLD : deux tables reliées par une clé étrangère.
private struct MLDGlyph: View {
    var body: some View {
        Canvas { context, size in
            func table(_ x: CGFloat, _ y: CGFloat) {
                let rect = CGRect(x: x, y: y, width: 11, height: 13)
                context.fill(Path(roundedRect: rect, cornerRadius: 1.5), with: .color(Theme.paper))
                context.fill(Path(CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: 4)), with: .color(Theme.entityFill))
                for row in 0..<2 {
                    context.fill(Path(CGRect(x: rect.minX + 2, y: rect.minY + 6.5 + CGFloat(row) * 3, width: 7, height: 1.1)), with: .color(.secondary))
                }
                context.stroke(Path(roundedRect: rect, cornerRadius: 1.5), with: .color(Theme.entity), lineWidth: 1)
            }
            table(1, 1)
            table(size.width - 12, size.height - 14)
            var link = Path()
            link.move(to: CGPoint(x: 12, y: 7)); link.addLine(to: CGPoint(x: 15, y: 7))
            link.addLine(to: CGPoint(x: 15, y: size.height - 7)); link.addLine(to: CGPoint(x: size.width - 12, y: size.height - 7))
            context.stroke(link, with: .color(Theme.association), lineWidth: 1.2)
        }
    }
}

/// UML : la classe UML classique, trois compartiments (nom, attributs, opérations).
private struct UMLGlyph: View {
    var body: some View {
        Canvas { context, size in
            let rect = CGRect(x: size.width / 2 - 10, y: 1, width: 20, height: 22)
            context.fill(Path(rect), with: .color(Theme.paper))
            context.fill(Path(CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: 6)), with: .color(Theme.entity.opacity(0.22)))
            context.stroke(Path(rect), with: .color(Theme.entity), lineWidth: 1.3)
            var bars = Path()
            for y in [rect.minY + 6, rect.minY + 15] {
                bars.move(to: CGPoint(x: rect.minX, y: y)); bars.addLine(to: CGPoint(x: rect.maxX, y: y))
            }
            context.stroke(bars, with: .color(Theme.entity), lineWidth: 1)
            for (index, y) in [rect.minY + 9, rect.minY + 12, rect.minY + 18.5].enumerated() {
                context.fill(Path(CGRect(x: rect.minX + 3, y: y - 0.6, width: index == 2 ? 9 : 12, height: 1.3)), with: .color(.secondary))
            }
        }
    }
}

/// SQL : base de données (cylindre à deux bandes).
private struct SQLGlyph: View {
    var body: some View {
        Canvas { context, size in
            let rect = CGRect(x: size.width / 2 - 9, y: 1.5, width: 18, height: 21)
            let ring: CGFloat = 6
            var body = Path()
            body.move(to: CGPoint(x: rect.minX, y: rect.minY + ring / 2))
            body.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - ring / 2))
            body.addEllipse(in: CGRect(x: rect.minX, y: rect.maxY - ring, width: rect.width, height: ring))
            context.fill(Path(CGRect(x: rect.minX, y: rect.minY + ring / 2, width: rect.width, height: rect.height - ring)), with: .color(Theme.association.opacity(0.2)))
            context.fill(Path(ellipseIn: CGRect(x: rect.minX, y: rect.maxY - ring, width: rect.width, height: ring)), with: .color(Theme.association.opacity(0.2)))
            var outline = Path()
            outline.move(to: CGPoint(x: rect.minX, y: rect.minY + ring / 2)); outline.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - ring / 2))
            outline.move(to: CGPoint(x: rect.maxX, y: rect.minY + ring / 2)); outline.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - ring / 2))
            outline.addArc(center: CGPoint(x: rect.midX, y: rect.maxY - ring / 2), radius: rect.width / 2, startAngle: .zero, endAngle: .degrees(180), clockwise: false)
            // Bande du milieu : deux disques empilés.
            let middle = rect.midY
            var band = Path()
            band.addArc(center: CGPoint(x: rect.midX, y: middle), radius: rect.width / 2, startAngle: .zero, endAngle: .degrees(180), clockwise: false)
            context.stroke(outline, with: .color(Theme.association), lineWidth: 1.3)
            context.stroke(band.applying(CGAffineTransform(translationX: 0, y: middle).scaledBy(x: 1, y: ring / rect.width).translatedBy(x: 0, y: -middle)), with: .color(Theme.association), lineWidth: 1.1)
            let top = Path(ellipseIn: CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: ring))
            context.fill(top, with: .color(Theme.paper))
            context.fill(top, with: .color(Theme.association.opacity(0.35)))
            context.stroke(top, with: .color(Theme.association), lineWidth: 1.3)
            _ = body
        }
    }
}

/// MLD textuel : Table(clé, …, #clé étrangère) sur trois lignes.
private struct MLDTextGlyph: View {
    var body: some View {
        Canvas { context, size in
            for (index, width) in [CGFloat(22), 18, 20].enumerated() {
                let y = 5 + CGFloat(index) * 6
                context.fill(Path(roundedRect: CGRect(x: 3, y: y, width: 6, height: 2.2), cornerRadius: 1), with: .color(Theme.entity))
                context.fill(Path(roundedRect: CGRect(x: 10.5, y: y, width: width - 8, height: 2.2), cornerRadius: 1), with: .color(.secondary))
            }
            var underline = Path()
            underline.move(to: CGPoint(x: 10.5, y: 8.6)); underline.addLine(to: CGPoint(x: 18, y: 8.6))
            context.stroke(underline, with: .color(.primary), lineWidth: 0.8)
        }
    }
}

/// Pattes de corbeau : deux tables, « plusieurs » d'un côté, « un seul » de l'autre.
private struct CrowsFootGlyph: View {
    var body: some View {
        Canvas { context, size in
            let y = size.height / 2
            for x in [CGFloat(0.5), size.width - 8.5] {
                let rect = CGRect(x: x, y: y - 7, width: 8, height: 14)
                context.fill(Path(roundedRect: rect, cornerRadius: 1.5), with: .color(Theme.paper))
                context.fill(Path(CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: 4)), with: .color(Theme.entityFill))
                context.stroke(Path(roundedRect: rect, cornerRadius: 1.5), with: .color(Theme.entity), lineWidth: 1)
            }
            var path = Path()
            path.move(to: CGPoint(x: 8.5, y: y)); path.addLine(to: CGPoint(x: size.width - 8.5, y: y))
            // « Plusieurs » côté gauche : fourche.
            path.move(to: CGPoint(x: 13, y: y)); path.addLine(to: CGPoint(x: 8.5, y: y - 4))
            path.move(to: CGPoint(x: 13, y: y)); path.addLine(to: CGPoint(x: 8.5, y: y + 4))
            // « Un seul » côté droit : deux barres.
            for x in [size.width - 13, size.width - 11] {
                path.move(to: CGPoint(x: x, y: y - 3.5)); path.addLine(to: CGPoint(x: x, y: y + 3.5))
            }
            context.stroke(path, with: .color(Theme.association), lineWidth: 1.2)
        }
    }
}

/// UML simplifié : classe réduite à son nom.
private struct UMLSimpleGlyph: View {
    var body: some View {
        Canvas { context, size in
            let rect = CGRect(x: size.width / 2 - 11, y: 6, width: 22, height: 12)
            context.fill(Path(rect), with: .color(Theme.paper))
            context.fill(Path(rect), with: .color(Theme.entity.opacity(0.22)))
            context.stroke(Path(rect), with: .color(Theme.entity), lineWidth: 1.3)
            context.fill(Path(roundedRect: CGRect(x: rect.midX - 6, y: rect.midY - 1, width: 12, height: 2.2), cornerRadius: 1), with: .color(Theme.entity))
        }
    }
}
