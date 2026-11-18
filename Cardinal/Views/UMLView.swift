import SwiftUI

/// Diagramme de classes UML déduit du MCD (mêmes positions que le MCD).
struct UMLView: View {
    let model: MCDModel
    @Binding var zoom: CGFloat
    @AppStorage("umlSimplifie") private var simplified = false
    @State private var zoomAtGestureStart: CGFloat?

    var body: some View {
        if model.entities.isEmpty {
            ContentUnavailableView("Aucune classe", systemImage: "square.stack.3d.up.fill",
                                   description: Text("Ajoutez des entités dans l'onglet E/A."))
        } else {
            ScrollView([.horizontal, .vertical]) {
                ZoomedContent(zoom: zoom) { UMLDiagram(model: model, simplified: simplified) }
            }
            .background(Color(nsColor: .underPageBackgroundColor))
            .simultaneousGesture(PinchZoom(zoom: $zoom, start: $zoomAtGestureStart).gesture)
        }
    }

    /// Multiplicités d'une association binaire : en UML, on lit à l'autre bout.
    /// La cardinalité Merise de A (combien de B pour un A) s'écrit donc près de B.
    static func binaryEnds(_ first: Cardinality, _ second: Cardinality) -> (nearFirst: String, nearSecond: String) {
        UMLLayout.binaryEnds(first, second)
    }

    /// (0,1) → 0..1, (1,1) → 1, (0,N) → *, (1,N) → 1..*
    static func multiplicity(_ cardinality: Cardinality) -> String {
        UMLLayout.multiplicity(cardinality)
    }
}

/// Dessin du diagramme de classes : tout est placé par UMLLayout.
struct UMLDiagram: View {
    let model: MCDModel
    let simplified: Bool

    var body: some View {
        let layout = UMLLayout(model: model, simplified: simplified)
        ZStack(alignment: .topLeading) {
            Canvas { context, _ in draw(layout, in: &context) }
                .frame(width: layout.size.width, height: layout.size.height)
            ForEach(layout.classes) { box in
                UMLClassBox(box: box, simplified: simplified)
                    .frame(width: box.frame.width, height: box.frame.height)
                    .position(x: box.frame.midX, y: box.frame.midY)
            }
        }
        .frame(width: layout.size.width, height: layout.size.height, alignment: .topLeading)
    }

    private func draw(_ layout: UMLLayout, in context: inout GraphicsContext) {
        for edge in layout.edges {
            var path = Path()
            path.addLines(edge.points)
            let dash: [CGFloat] = edge.style == .dashed ? [5, 4] : []
            context.stroke(path, with: .color(Theme.link), style: StrokeStyle(lineWidth: 1.3, lineCap: .round, lineJoin: .round, dash: dash))
            if edge.style == .generalization, let tip = edge.points.last, let before = edge.points.dropLast().last {
                // Flèche à triangle creux vers la surclasse.
                let u = (tip - before).normalized
                let p = CGPoint(x: -u.y, y: u.x)
                let base = tip - u * 14
                var triangle = Path()
                triangle.move(to: tip)
                triangle.addLine(to: base + p * 8)
                triangle.addLine(to: base - p * 8)
                triangle.closeSubpath()
                context.fill(triangle, with: .color(Color(nsColor: .textBackgroundColor)))
                context.stroke(triangle, with: .color(Theme.link), lineWidth: 1.3)
            }
        }
        for diamond in layout.diamonds {
            let c = diamond.center
            var shape = Path()
            shape.move(to: c + CGPoint(x: 0, y: -15))
            shape.addLine(to: c + CGPoint(x: 15, y: 0))
            shape.addLine(to: c + CGPoint(x: 0, y: 15))
            shape.addLine(to: c + CGPoint(x: -15, y: 0))
            shape.closeSubpath()
            context.fill(shape, with: .color(Color(nsColor: .textBackgroundColor)))
            context.stroke(shape, with: .color(Theme.link), lineWidth: 1.3)
        }
        for label in layout.labels {
            let text: Text
            switch label.kind {
            case .multiplicity:
                text = Text(label.text).font(.system(size: UMLLayout.labelFont.size, weight: .semibold)).foregroundStyle(Theme.association)
            case .role:
                text = Text(label.text).font(.system(size: UMLLayout.roleFont.size)).italic().foregroundStyle(.secondary)
            case .name:
                text = Text(label.text).font(.system(size: UMLLayout.nameFont.size, weight: .medium)).italic().foregroundStyle(.secondary)
            }
            context.draw(context.resolve(text), at: CGPoint(x: label.frame.midX, y: label.frame.midY))
        }
    }
}

/// Boîte de classe UML à trois compartiments : nom, attributs, opérations (vide), comme Looping.
private struct UMLClassBox: View {
    let box: UMLLayout.ClassBox
    let simplified: Bool

    var body: some View {
        let tint = box.isAssociationClass ? Theme.association : Theme.entity
        VStack(alignment: .leading, spacing: 0) {
            Text("+ \(box.name)")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tint)
                .lineLimit(1)
                .frame(maxWidth: .infinity)
                .frame(height: simplified ? nil : UMLLayout.header)
                .frame(maxHeight: simplified ? .infinity : nil)
            if !simplified {
                Rectangle().fill(tint.opacity(0.5)).frame(height: 1)
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(box.lines.enumerated()), id: \.offset) { _, line in
                        HStack(spacing: 0) {
                            Text(line.text)
                            if line.isIdentifier { Text(" {id}").foregroundStyle(tint) }
                        }
                        .font(.system(size: 11.5, design: .monospaced))
                        .lineLimit(1)
                        .frame(height: UMLLayout.row)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
                Spacer(minLength: 0)
                Rectangle().fill(tint.opacity(0.5)).frame(height: 1)
                Color.clear.frame(height: UMLLayout.operations)
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 3))
        .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(tint.opacity(0.7), style: StrokeStyle(lineWidth: 1.2, dash: box.isAssociationClass ? [5, 3] : [])))
        .shadow(color: .black.opacity(0.06), radius: 4, y: 2)
    }
}

/// Applique le zoom à un diagramme en gardant une zone de défilement à la bonne taille.
struct ZoomedContent<Content: View>: View {
    let zoom: CGFloat
    @ViewBuilder let content: Content

    var body: some View {
        content
            .fixedSize()
            .scaleEffect(zoom, anchor: .topLeading)
            .background(GeometryReader { proxy in Color.clear.preference(key: SizeKey.self, value: proxy.size) })
            .modifier(ScaledFrame(zoom: zoom))
    }
}

private struct SizeKey: PreferenceKey {
    static let defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) { value = nextValue() }
}

/// Réserve la place du contenu agrandi (scaleEffect ne change pas la taille de mise en page).
private struct ScaledFrame: ViewModifier {
    let zoom: CGFloat
    @State private var size: CGSize = .zero

    func body(content: Content) -> some View {
        content
            .onPreferenceChange(SizeKey.self) { size = $0 }
            .frame(width: size.width * zoom, height: size.height * zoom, alignment: .topLeading)
    }
}
