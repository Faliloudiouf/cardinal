import SwiftUI

/// Gestes transmis par le canevas interactif (absents lors d'un export en image).
struct DiagramInteraction {
    var onTap: (NodeRef) -> Void
    var onDragChanged: (NodeRef, CGSize) -> Void
    var onDragEnded: (NodeRef, CGSize) -> Void
    /// Déplacement du point de cassure d'une patte (association, identifiant de la patte, nouveau point).
    /// L'identifiant, pas le rang : dans une vue, une association peut montrer moins de pattes.
    var onBendMoved: (UUID, UUID, CGPoint) -> Void = { _, _, _ in }
    /// Figure redimensionnée ou extrémité de trait déplacée.
    var onFigureEdited: (Figure) -> Void = { _ in }
}

/// Dessin complet d'un MCD : liens puis nœuds, positionnés en coordonnées absolues.
/// Utilisé à la fois par le canevas et par les exports (PNG, PDF, impression).
struct DiagramLayer: View {
    let model: MCDModel
    var selection: Set<NodeRef> = []
    var pending: NodeRef?
    var dragging: Set<NodeRef> = []
    var dragOffset: CGSize = .zero
    var interaction: DiagramInteraction?

    static let coordinateSpace = "canvas"

    /// Modèle tel qu'affiché pendant un glisser : les cassures suivent leur association.
    private var shown: MCDModel {
        guard !dragging.isEmpty, dragOffset != .zero else { return model }
        var copy = model
        for index in copy.associations.indices where dragging.contains(.association(copy.associations[index].id)) {
            for leg in copy.associations[index].legs.indices {
                copy.associations[index].legs[leg].bend = copy.associations[index].legs[leg].bend?.offset(by: dragOffset)
            }
        }
        return copy
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Illustrations derrière le diagramme.
            ForEach(model.figures) { figure in
                node(.figure(figure.id)) { FigureNode(figure: figure, state: $0) }
            }
            LinksLayer(model: shown, position: livePosition)
            ForEach(model.notes) { note in
                node(.note(note.id)) { NoteNode(note: note, state: $0) }
            }
            ForEach(model.associations) { association in
                node(.association(association.id)) { AssociationNode(association: association, settings: model.settings, state: $0) }
            }
            ForEach(model.inheritances) { inheritance in
                node(.inheritance(inheritance.id)) { InheritanceNode(inheritance: inheritance, state: $0) }
            }
            ForEach(model.constraints) { constraint in
                node(.constraint(constraint.id)) { ConstraintNode(constraint: constraint, state: $0) }
            }
            ForEach(model.rules) { rule in
                node(.rule(rule.id)) { RuleNode(rule: rule, state: $0) }
            }
            ForEach(model.entities) { entity in
                node(.entity(entity.id)) { EntityNode(entity: entity, settings: model.settings, state: $0) }
            }
            // Poignées des figures sélectionnées : coin pour redimensionner, extrémités pour un trait.
            if let interaction {
                ForEach(model.figures.filter { selection.contains(.figure($0.id)) && !dragging.contains(.figure($0.id)) }) { figure in
                    if figure.kind.isStroke {
                        BendHandle(point: figure.start) { point in
                            var edited = figure; edited.setEnds(point, figure.end); interaction.onFigureEdited(edited)
                        }
                        BendHandle(point: figure.end) { point in
                            var edited = figure; edited.setEnds(figure.start, point); interaction.onFigureEdited(edited)
                        }
                    } else {
                        BendHandle(point: CGPoint(x: figure.frame.maxX, y: figure.frame.maxY)) { point in
                            var edited = figure; edited.resize(toCorner: point); interaction.onFigureEdited(edited)
                        }
                    }
                }
            }
            // Poignées des cassures, sur les associations sélectionnées.
            if let interaction {
                ForEach(model.associations.filter { selection.contains(.association($0.id)) }) { association in
                    ForEach(association.legs) { leg in
                        if let bend = leg.bend {
                            BendHandle(point: bend) { interaction.onBendMoved(association.id, leg.id, $0) }
                        }
                    }
                }
            }
        }
    }

    func livePosition(_ ref: NodeRef) -> CGPoint {
        let base = model.position(of: ref) ?? .zero
        return dragging.contains(ref) ? base.offset(by: dragOffset) : base
    }

    @ViewBuilder
    private func node<Content: View>(_ ref: NodeRef, @ViewBuilder content: (NodeState) -> Content) -> some View {
        let state = NodeState(
            isSelected: selection.contains(ref),
            isPending: pending == ref,
            isLifted: dragging.contains(ref)
        )
        if let interaction {
            content(state)
                .position(livePosition(ref))
                .onTapGesture { interaction.onTap(ref) }
                .gesture(
                    DragGesture(minimumDistance: 3, coordinateSpace: .named(Self.coordinateSpace))
                        .onChanged { interaction.onDragChanged(ref, $0.translation) }
                        .onEnded { interaction.onDragEnded(ref, $0.translation) }
                )
        } else {
            content(state).position(livePosition(ref))
        }
    }
}

/// Trace pattes, liens d'héritage, de contraintes et de règles, avec leurs étiquettes.
struct LinksLayer: View {
    let model: MCDModel
    let position: (NodeRef) -> CGPoint

    var body: some View {
        Canvas { context, _ in
            let size = { (ref: NodeRef) in NodeMetrics.size(of: ref, in: model) }

            // Pattes : traits d'abord, cardinalités ensuite (placées pour ne rien chevaucher).
            let layout = MCDLabelLayout(model: model, position: position)
            for leg in layout.legPaths {
                var path = Path()
                path.addLines(leg.points)
                context.stroke(path, with: .color(Theme.link), style: StrokeStyle(lineWidth: 1.25, lineCap: .round, lineJoin: .round))
                // Dépendance fonctionnelle : flèche sur la patte 0,1 / 1,1, au bord de l'association.
                if model.settings.showDependencies, leg.isMaxOne, leg.points.count >= 2 {
                    drawArrowHead(at: leg.points[0], from: leg.points[1], color: Theme.link.opacity(1), in: &context)
                }
            }
            for label in layout.labels {
                drawPill(label.text, in: label.frame, tint: Theme.association, in: &context)
            }

            // Héritages : du sommet du triangle vers le surtype, de la base vers les sous-types.
            for inheritance in model.inheritances {
                let ref = NodeRef.inheritance(inheritance.id)
                let center = position(ref)
                let triangle = NodeMetrics.inheritanceSize
                let top = CGPoint(x: center.x, y: center.y - triangle.height / 2)
                let bottom = CGPoint(x: center.x, y: center.y + triangle.height / 2)
                if let parent = inheritance.parentID, model.entity(parent) != nil {
                    let parentRef = NodeRef.entity(parent)
                    let target = layout.linkPorts[MCDLabelLayout.key(ref, parentRef)] ?? edgePoint(center: position(parentRef), toward: top, size: size(parentRef))
                    stroke(from: top, to: target, color: Theme.entity.opacity(0.7), width: 1.5, in: &context)
                }
                for child in inheritance.childIDs where model.entity(child) != nil {
                    let childRef = NodeRef.entity(child)
                    let target = layout.linkPorts[MCDLabelLayout.key(ref, childRef)] ?? edgePoint(center: position(childRef), toward: bottom, size: size(childRef))
                    stroke(from: bottom, to: target, color: Theme.entity.opacity(0.55), width: 1.25, in: &context)
                }
            }

            // Contraintes : traits pointillés, flèche vers l'entité cible d'une CIF.
            for constraint in model.constraints {
                let ref = NodeRef.constraint(constraint.id)
                let center = position(ref)
                for link in constraint.links where model.contains(link.target) {
                    let end = layout.linkPorts[MCDLabelLayout.key(ref, link.target)] ?? edgePoint(center: position(link.target), toward: center, size: size(link.target))
                    let start = edgePoint(center: center, toward: end, size: size(ref))
                    stroke(from: start, to: end, color: Theme.constraint.opacity(0.8), width: 1.2, dash: [5, 4], in: &context)
                    if link.isTarget { drawArrowHead(at: end, from: start, color: Theme.constraint, in: &context) }
                }
            }

            // Règles de gestion : traits pointillés fins.
            for rule in model.rules {
                let ref = NodeRef.rule(rule.id)
                let center = position(ref)
                for target in rule.links where model.contains(target) {
                    let end = layout.linkPorts[MCDLabelLayout.key(ref, target)] ?? edgePoint(center: position(target), toward: center, size: size(target))
                    let start = edgePoint(center: center, toward: end, size: size(ref))
                    stroke(from: start, to: end, color: Theme.rule.opacity(0.75), width: 1, dash: [2, 3], in: &context)
                }
            }
        }
        .frame(width: DiagramView.canvasSize.width, height: DiagramView.canvasSize.height)
        .allowsHitTesting(false)
    }

    private func stroke(from start: CGPoint, to end: CGPoint, color: Color, width: CGFloat, dash: [CGFloat] = [], in context: inout GraphicsContext) {
        var path = Path()
        path.move(to: start)
        path.addLine(to: end)
        context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: width, lineCap: .round, dash: dash))
    }

    private func drawArrowHead(at tip: CGPoint, from start: CGPoint, color: Color, in context: inout GraphicsContext) {
        let direction = (tip - start).normalized
        let perpendicular = CGPoint(x: -direction.y, y: direction.x)
        let base = tip - direction * 10
        var path = Path()
        path.move(to: tip)
        path.addLine(to: base + perpendicular * 5)
        path.addLine(to: base - perpendicular * 5)
        path.closeSubpath()
        context.fill(path, with: .color(color))
    }

    private func drawPill(_ text: String, in pill: CGRect, tint: Color, in context: inout GraphicsContext) {
        let label = context.resolve(
            Text(text).font(.system(size: MCDLabelLayout.fontSize, weight: .bold, design: .rounded)).foregroundStyle(tint)
        )
        let shape = Path(roundedRect: pill, cornerRadius: pill.height / 2)
        context.fill(shape, with: .color(Color(nsColor: .textBackgroundColor)))
        context.stroke(shape, with: .color(tint.opacity(0.35)), lineWidth: 0.75)
        context.draw(label, at: CGPoint(x: pill.midX, y: pill.midY))
    }
}


/// Poignée d'une cassure : un point que l'on fait glisser ; la patte suit en direct.
private struct BendHandle: View {
    let point: CGPoint
    let onMoved: (CGPoint) -> Void
    /// Position au début du glisser : le déplacement se compte à partir d'elle, une seule fois.
    @State private var origin: CGPoint?
    @State private var isHovered = false

    var body: some View {
        Circle()
            .fill(Color(nsColor: .textBackgroundColor))
            .overlay(Circle().strokeBorder(Theme.association, lineWidth: 2))
            .frame(width: isHovered || origin != nil ? 14 : 12, height: isHovered || origin != nil ? 14 : 12)
            .contentShape(Circle().inset(by: -6))
            .position(point)
            .onHover { isHovered = $0 }
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .named(DiagramLayer.coordinateSpace))
                    .onChanged { value in
                        let start = origin ?? point
                        origin = start
                        onMoved(start.offset(by: value.translation))
                    }
                    .onEnded { _ in origin = nil }
            )
            .help("Glissez pour déplacer ce point")
    }
}
