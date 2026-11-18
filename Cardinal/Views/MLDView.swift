import SwiftUI

enum MLDDisplay: String, CaseIterable, Identifiable {
    case textuel = "Textuel"
    case standard = "Diagramme"
    case crowsFoot = "Pattes de corbeau"
    var id: String { rawValue }
}

struct MLDView: View {
    let model: MCDModel
    let tables: [MLDTable]
    @Binding var zoom: CGFloat
    @AppStorage("affichageMLD") private var display: MLDDisplay = .textuel
    @State private var zoomAtGestureStart: CGFloat?

    var body: some View {
        Group {
            if tables.isEmpty {
                ContentUnavailableView(
                    "Aucune table",
                    systemImage: "tablecells.fill",
                    description: Text("Ajoutez des entités dans l'onglet E/A pour générer le modèle logique.")
                )
            } else if display == .textuel {
                MLDTextView(tables: tables, zoom: zoom)
            } else {
                ScrollView([.horizontal, .vertical]) {
                    ZoomedContent(zoom: zoom) { MLDDiagram(model: model, tables: tables, crowsFoot: display == .crowsFoot) }
                }
                .background(Color(nsColor: .underPageBackgroundColor))
            }
        }
        .simultaneousGesture(PinchZoom(zoom: $zoom, start: $zoomAtGestureStart).gesture)
    }

    /// Notation textuelle Merise : Commande(num_commande, date, #id_client)
    static func textual(_ table: MLDTable, size: CGFloat = 13.5) -> AttributedString {
        var result = AttributedString(table.name)
        result.font = .system(size: size, weight: .bold, design: .monospaced)
        result.foregroundColor = table.comesFromAssociation ? Theme.association : Theme.entity
        result += AttributedString(" (")
        for (index, column) in table.columns.enumerated() {
            var part = AttributedString((column.reference != nil ? "#" : "") + column.name)
            if column.isPrimaryKey {
                part.underlineStyle = .single
                part.font = .system(size: size, weight: .semibold, design: .monospaced)
            }
            result += part
            if index < table.columns.count - 1 { result += AttributedString(", ") }
        }
        result += AttributedString(")")
        return result
    }
}

private struct MLDTextView: View {
    let tables: [MLDTable]
    let zoom: CGFloat

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Modèle logique de données")
                        .font(.system(size: 26 * zoom, weight: .bold))
                        .tracking(-0.4)
                    Text("Clé primaire soulignée · clé étrangère précédée de #")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 8) {
                    ForEach(tables) { table in
                        Text(MLDView.textual(table, size: 13.5 * zoom))
                            .font(.system(size: 13.5 * zoom, design: .monospaced))
                            .textSelection(.enabled)
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color(nsColor: .separatorColor)))

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 250 * zoom), spacing: 16, alignment: .top)], alignment: .leading, spacing: 16) {
                    ForEach(tables) { TableCard(table: $0, showsReferences: true, scale: zoom) }
                }
            }
            .padding(28)
            .frame(maxWidth: 1100 * zoom, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(nsColor: .underPageBackgroundColor))
    }
}

// MARK: - MLD graphique

/// Les tables sont placées comme les éléments du MCD d'origine ; les liens vont de la clé étrangère à la table référencée.
struct MLDDiagram: View {
    let model: MCDModel
    let tables: [MLDTable]
    let crowsFoot: Bool

    static let cardWidth = MLDLayout.cardWidth
    static func size(of table: MLDTable) -> CGSize { MLDLayout.size(of: table) }

    private var layout: (positions: [String: CGPoint], size: CGSize) { MLDLayout.layout(model: model, tables: tables) }

    var body: some View {
        let layout = layout
        ZStack(alignment: .topLeading) {
            Canvas { context, _ in
                for link in MLDLayout.links(tables: tables, positions: layout.positions) {
                    guard let start = link.points.first, let end = link.points.last,
                          let child = tables.first(where: { $0.name == link.child }) else { continue }
                    var path = Path()
                    path.addLines(link.points)
                    context.stroke(path, with: .color(Theme.link), style: StrokeStyle(lineWidth: 1.3, lineJoin: .round))
                    // Les extrémités s'orientent sur le premier et le dernier segment du tracé.
                    let afterStart = link.points[1]
                    let beforeEnd = link.points[link.points.count - 2]
                    if crowsFoot {
                        let columns = link.columns
                        let unique = columns.count == 1 && (columns[0].isUnique || columns[0].isPrimaryKey && child.primaryKey.count == 1)
                        drawChildEnd(at: start, toward: afterStart, many: !unique, optional: true, in: &context)
                        drawParentEnd(at: end, toward: beforeEnd, optional: columns.contains(where: \.isNullable), in: &context)
                    } else {
                        drawArrow(at: end, from: beforeEnd, in: &context)
                    }
                }
            }
            .frame(width: layout.size.width, height: layout.size.height)

            ForEach(tables) { table in
                TableCard(table: table, showsReferences: false)
                    .frame(width: Self.cardWidth, height: Self.size(of: table).height)
                    .position(layout.positions[table.name] ?? .zero)
            }
        }
        .frame(width: max(layout.size.width, 400), height: max(layout.size.height, 300), alignment: .topLeading)
    }

    private func line(_ a: CGPoint, _ b: CGPoint, in context: inout GraphicsContext) {
        var path = Path()
        path.move(to: a)
        path.addLine(to: b)
        context.stroke(path, with: .color(Theme.link), lineWidth: 1.3)
    }

    private func circle(at point: CGPoint, in context: inout GraphicsContext) {
        let rect = CGRect(x: point.x - 4.5, y: point.y - 4.5, width: 9, height: 9)
        context.fill(Path(ellipseIn: rect), with: .color(Color(nsColor: .textBackgroundColor)))
        context.stroke(Path(ellipseIn: rect), with: .color(Theme.link), lineWidth: 1.3)
    }

    /// Côté table qui porte la clé étrangère : patte de corbeau (plusieurs) ou barre (un seul).
    private func drawChildEnd(at edge: CGPoint, toward other: CGPoint, many: Bool, optional: Bool, in context: inout GraphicsContext) {
        let u = (other - edge).normalized
        let p = CGPoint(x: -u.y, y: u.x)
        if many {
            let fork = edge + u * 14
            line(fork, edge + p * 8, in: &context)
            line(fork, edge - p * 8, in: &context)
        } else {
            line(edge + u * 8 + p * 7, edge + u * 8 - p * 7, in: &context)
        }
        if optional { circle(at: edge + u * 22, in: &context) } else { line(edge + u * 20 + p * 7, edge + u * 20 - p * 7, in: &context) }
    }

    /// Côté table référencée : « exactement un » (deux barres) ou « zéro ou un » (barre + cercle).
    private func drawParentEnd(at edge: CGPoint, toward other: CGPoint, optional: Bool, in context: inout GraphicsContext) {
        let u = (other - edge).normalized
        let p = CGPoint(x: -u.y, y: u.x)
        line(edge + u * 8 + p * 7, edge + u * 8 - p * 7, in: &context)
        if optional { circle(at: edge + u * 18, in: &context) } else { line(edge + u * 14 + p * 7, edge + u * 14 - p * 7, in: &context) }
    }

    private func drawArrow(at tip: CGPoint, from start: CGPoint, in context: inout GraphicsContext) {
        let u = (tip - start).normalized
        let p = CGPoint(x: -u.y, y: u.x)
        let base = tip - u * 11
        var path = Path()
        path.move(to: tip)
        path.addLine(to: base + p * 5.5)
        path.addLine(to: base - p * 5.5)
        path.closeSubpath()
        context.fill(path, with: .color(Theme.link))
    }
}

struct TableCard: View {
    let table: MLDTable
    var showsReferences = true
    /// Agrandissement des textes (MLD textuel) ; le diagramme, lui, est zoomé dans son ensemble.
    var scale: CGFloat = 1

    var body: some View {
        let tint = table.comesFromAssociation ? Theme.association : Theme.entity
        let fill = table.comesFromAssociation ? Theme.associationFill : Theme.entityFill
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Image(systemName: "tablecells.fill")
                Text(table.name).tracking(0.2).lineLimit(1)
                Spacer()
                if table.comesFromAssociation {
                    Text("association")
                        .font(.system(size: 10 * scale, weight: .semibold))
                        .textCase(.uppercase)
                        .tracking(0.6)
                        .opacity(0.85)
                }
            }
            .font(.system(size: 13 * scale, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .frame(height: 34 * scale)
            .background(fill)

            VStack(spacing: 0) {
                ForEach(Array(table.columns.enumerated()), id: \.offset) { index, column in
                    if index > 0 { Divider().padding(.leading, 12) }
                    ColumnRow(column: column, tint: tint, showsReference: showsReferences, scale: scale)
                }
            }
            .padding(.vertical, 4)
        }
        .background(Color(nsColor: .textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous).strokeBorder(tint.opacity(0.45)))
        .shadow(color: .black.opacity(0.07), radius: 5, y: 2)
    }
}

private struct ColumnRow: View {
    let column: MLDColumn
    let tint: Color
    let showsReference: Bool
    let scale: CGFloat

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(column.name)
                    .underline(column.isPrimaryKey)
                    .fontWeight(column.isPrimaryKey ? .semibold : .regular)
                    .lineLimit(1)
                if showsReference, let reference = column.reference {
                    Text("→ \(reference.table).\(reference.column)")
                        .font(.system(size: 10.5 * scale))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            if column.isPrimaryKey { Badge(text: "PK", tint: tint, scale: scale) }
            if column.reference != nil { Badge(text: "FK", tint: Theme.association, scale: scale) }
            if column.isUnique && !column.isPrimaryKey { Badge(text: "U", tint: tint, scale: scale) }
            Text(column.spec.display)
                .font(.system(size: 10.5 * scale, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .font(.system(size: 12.5 * scale))
        .padding(.horizontal, 12)
        .padding(.vertical, showsReference ? 6 : 0)
        .frame(minHeight: showsReference ? nil : MLDLayout.row - 1)
    }
}

private struct Badge: View {
    let text: String
    let tint: Color
    let scale: CGFloat

    var body: some View {
        Text(text)
            .font(.system(size: 9.5 * scale, weight: .bold, design: .rounded))
            .foregroundStyle(tint)
            .padding(.horizontal, 5)
            .padding(.vertical, 1.5)
            .background(tint.opacity(0.12), in: Capsule())
    }
}
