import SwiftUI
import AppKit

/// Le canevas interactif du MCD : sélection multiple, déplacement, liens, copier-coller, zoom.
struct DiagramView: View {
    @Binding var model: MCDModel
    @Binding var selection: Set<NodeRef>
    @Binding var tool: Tool
    @Binding var zoom: CGFloat
    /// Incrémenté par la barre d'état pour demander « Ajuster à la fenêtre ».
    var fitRequest: Int
    /// Vue active (sous-modèle) ; nil : le modèle complet.
    var activeView: ModelView.ID? = nil

    /// Ce que montre le canevas : la vue active, ou tout le modèle.
    private var shown: MCDModel { model.visible(in: activeView) }

    @State private var dragging: Set<NodeRef> = []
    @State private var dragOffset: CGSize = .zero
    @State private var pendingLink: NodeRef?
    @State private var marquee: CGRect?
    @State private var zoomAtGestureStart: CGFloat?
    @State private var scrollPosition = ScrollPosition(edge: .top)

    static let canvasSize = CGSize(width: 4000, height: 2800)

    var body: some View {
        GeometryReader { viewport in
            ScrollView([.horizontal, .vertical]) {
                ZStack(alignment: .topLeading) {
                    if model.settings.showGrid { DotGrid() }
                    DiagramLayer(
                        model: shown,
                        selection: selection,
                        pending: pendingLink,
                        dragging: dragging,
                        dragOffset: dragOffset,
                        interaction: DiagramInteraction(onTap: nodeTapped, onDragChanged: dragChanged, onDragEnded: dragEnded,
                                                        onBendMoved: { association, legID, point in
                                                            guard let a = model.associations.firstIndex(where: { $0.id == association }),
                                                                  let l = model.associations[a].legs.firstIndex(where: { $0.id == legID }) else { return }
                                                            model.associations[a].legs[l].bend = clamped(point)
                                                        },
                                                        onFigureEdited: { figure in
                                                            if let index = model.figures.firstIndex(where: { $0.id == figure.id }) { model.figures[index] = figure }
                                                        })
                    )
                    if let marquee {
                        Rectangle()
                            .fill(Color.accentColor.opacity(0.08))
                            .overlay(Rectangle().strokeBorder(Color.accentColor.opacity(0.7), lineWidth: 1))
                            .frame(width: marquee.width, height: marquee.height)
                            .offset(x: marquee.minX, y: marquee.minY)
                            .allowsHitTesting(false)
                    }
                }
                .frame(width: Self.canvasSize.width, height: Self.canvasSize.height, alignment: .topLeading)
                .contentShape(Rectangle())
                .onTapGesture { location in backgroundTapped(at: location) }
                .gesture(marqueeGesture)
                .coordinateSpace(.named(DiagramLayer.coordinateSpace))
                .scaleEffect(zoom, anchor: .topLeading)
                .frame(width: Self.canvasSize.width * zoom, height: Self.canvasSize.height * zoom, alignment: .topLeading)
            }
            .scrollPosition($scrollPosition)
            .onChange(of: fitRequest) { fit(in: viewport.size) }
        }
        .background(Color(nsColor: .underPageBackgroundColor))
        .simultaneousGesture(
            MagnifyGesture()
                .onChanged { value in
                    let start = zoomAtGestureStart ?? zoom
                    zoomAtGestureStart = start
                    zoom = min(max(start * value.magnification, 0.3), 2.5)
                }
                .onEnded { _ in zoomAtGestureStart = nil }
        )
        .focusable()
        .focusEffectDisabled()
        .onDeleteCommand {
            for ref in selection { model.remove(ref) }
            selection = []
        }
        .onExitCommand {
            pendingLink = nil
            tool = .select
            selection = []
        }
        .onCopyCommand { copySelection() }
        .onCutCommand {
            let providers = copySelection()
            for ref in selection { model.remove(ref) }
            selection = []
            return providers
        }
        .onPasteCommand(of: [.utf8PlainText, .plainText]) { _ in paste() }
        .onCommand(#selector(NSResponder.selectAll(_:))) { selection = Set(shown.allRefs) }
        .overlay(alignment: .top) {
            if let hint = tool.hint {
                Label(hint, systemImage: tool.symbol)
                    .font(.system(size: 12, weight: .medium))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.regularMaterial, in: Capsule())
                    .overlay(Capsule().strokeBorder(.white.opacity(0.18)))
                    .shadow(color: .black.opacity(0.12), radius: 8, y: 3)
                    .padding(.top, 12)
                    .transition(.opacity.combined(with: .offset(y: -6)))
            }
        }
        .animation(.easeOut(duration: 0.18), value: tool)
        .onChange(of: tool) { _, newTool in
            if newTool != .link { pendingLink = nil }
        }
    }

    // MARK: - Déplacement

    private func dragChanged(_ ref: NodeRef, _ translation: CGSize) {
        guard tool == .select || tool == .link else { return }
        if dragging.isEmpty {
            if !selection.contains(ref) { selection = [ref] }
            dragging = selection
        }
        dragOffset = translation
    }

    private func dragEnded(_ ref: NodeRef, _ translation: CGSize) {
        guard !dragging.isEmpty else { return }
        // Les cassures des pattes suivent leur association.
        model.move(dragging, by: translation)
        for moved in dragging {
            guard let point = model.position(of: moved) else { continue }
            model.setPosition(clamped(point), of: moved)
        }
        dragging = []
        dragOffset = .zero
    }

    private func clamped(_ point: CGPoint) -> CGPoint {
        CGPoint(x: min(max(point.x, 40), Self.canvasSize.width - 40), y: min(max(point.y, 30), Self.canvasSize.height - 30))
    }

    // MARK: - Sélection au lasso

    private var marqueeGesture: some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                guard tool == .select else { return }
                marquee = CGRect(
                    x: min(value.startLocation.x, value.location.x), y: min(value.startLocation.y, value.location.y),
                    width: abs(value.location.x - value.startLocation.x), height: abs(value.location.y - value.startLocation.y)
                )
            }
            .onEnded { _ in
                guard let rect = marquee else { return }
                let visible = shown
                let hits = Set(visible.allRefs.filter { NodeMetrics.frame(of: $0, in: visible)?.intersects(rect) == true })
                selection = NSEvent.modifierFlags.contains(.shift) ? selection.union(hits) : hits
                marquee = nil
            }
    }

    // MARK: - Clics

    private func backgroundTapped(at location: CGPoint) {
        switch tool {
        case .entity:
            let entity = Entity(
                name: model.uniqueName(base: "Entité"),
                attributes: [Attribute(name: "id", type: .entier, isIdentifier: true)],
                position: location
            )
            model.entities.append(entity)
            finishCreation(.entity(entity.id))
        case .association:
            let association = Association(name: model.uniqueName(base: "Association"), position: location)
            model.associations.append(association)
            finishCreation(.association(association.id))
        case .inheritance:
            let inheritance = Inheritance(position: location)
            model.inheritances.append(inheritance)
            startLinking(from: .inheritance(inheritance.id))
        case .constraint, .cif:
            let constraint = Constraint(kind: tool == .cif ? .cif : .exclusion, position: location)
            model.constraints.append(constraint)
            startLinking(from: .constraint(constraint.id))
        case .rule:
            let rule = Rule(name: model.uniqueName(base: "Règle"), position: location)
            model.rules.append(rule)
            startLinking(from: .rule(rule.id))
        case .note:
            let note = Note(text: "Texte", position: location)
            model.notes.append(note)
            finishCreation(.note(note.id))
        case .rectangle, .ellipse, .line, .arrow:
            var figure = Figure(kind: tool.figureKind!, position: location)
            if tool == .ellipse { figure.size = CGSize(width: 140, height: 100) }
            model.figures.append(figure)
            finishCreation(.figure(figure.id))
        case .image:
            guard let image = FigureImage.choose() else { tool = .select; return }
            var figure = Figure(kind: .image, position: location)
            figure.imageData = image.data
            figure.size = image.size
            model.figures.append(figure)
            finishCreation(.figure(figure.id))
        case .select, .link:
            if !NSEvent.modifierFlags.contains(.shift) { selection = [] }
            pendingLink = nil
        }
    }

    private func finishCreation(_ ref: NodeRef) {
        addToActiveView([ref])
        selection = [ref]
        tool = .select
    }

    /// Un élément créé ou collé dans une vue en fait partie.
    private func addToActiveView(_ refs: Set<NodeRef>) {
        guard let activeView, let index = model.views.firstIndex(where: { $0.id == activeView }) else { return }
        model.views[index].add(refs.sorted { "\($0)" < "\($1)" })
    }

    /// Après avoir posé un héritage, une contrainte ou une règle, on enchaîne directement sur les liens.
    private func startLinking(from ref: NodeRef) {
        addToActiveView([ref])
        selection = [ref]
        tool = .link
        pendingLink = ref
    }

    private func nodeTapped(_ ref: NodeRef) {
        guard tool == .link else {
            let flags = NSEvent.modifierFlags
            if flags.contains(.shift) || flags.contains(.command) {
                if selection.contains(ref) { selection.remove(ref) } else { selection.insert(ref) }
            } else {
                selection = [ref]
            }
            return
        }
        if case .figure = ref { return } // une illustration ne se relie à rien
        guard let first = pendingLink, first != ref else {
            pendingLink = ref
            return
        }
        if Linker.link(first, ref, in: &model) {
            selection = [Linker.hub(first, ref)]
            // On garde le « pivot » (association, héritage, contrainte, règle) pour enchaîner les liens.
            pendingLink = Linker.isHub(first) ? first : nil
        } else {
            pendingLink = ref
        }
    }

    // MARK: - Presse-papiers

    private static let pasteboardPrefix = "CARDINAL-FRAGMENT\n"

    @discardableResult
    private func copySelection() -> [NSItemProvider] {
        guard !selection.isEmpty, let data = try? CardinalDocument.encode(model.subset(selection)) else { return [] }
        let text = Self.pasteboardPrefix + String(decoding: data, as: UTF8.self)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        return [NSItemProvider(object: text as NSString)]
    }

    private func paste() {
        guard let text = NSPasteboard.general.string(forType: .string), text.hasPrefix(Self.pasteboardPrefix),
              let fragment = try? JSONDecoder().decode(MCDModel.self, from: Data(text.dropFirst(Self.pasteboardPrefix.count).utf8))
        else { return }
        selection = model.paste(fragment)
        addToActiveView(selection)
    }

    // MARK: - Zoom

    private func fit(in viewport: CGSize) {
        guard let bounds = NodeMetrics.bounds(of: shown), bounds.width > 0, bounds.height > 0 else { return }
        zoom = min(max(min(viewport.width / bounds.width, viewport.height / bounds.height), 0.3), 1.5)
        let target = CGPoint(x: max(bounds.minX * zoom, 0), y: max(bounds.minY * zoom, 0))
        DispatchQueue.main.async { scrollPosition.scrollTo(point: target) }
    }
}

/// Règles de liaison entre deux éléments cliqués avec l'outil Lien.
enum Linker {
    static func isHub(_ ref: NodeRef) -> Bool {
        if case .entity = ref { return false }
        if case .note = ref { return false }
        if case .figure = ref { return false }
        return true
    }

    static func hub(_ a: NodeRef, _ b: NodeRef) -> NodeRef { isHub(a) ? a : b }

    @discardableResult
    static func link(_ a: NodeRef, _ b: NodeRef, in model: inout MCDModel) -> Bool {
        connect(a, b, &model) || connect(b, a, &model)
    }

    private static func connect(_ a: NodeRef, _ b: NodeRef, _ model: inout MCDModel) -> Bool {
        switch (a, b) {
        case let (.entity(entityID), .association(associationID)):
            guard let index = model.associations.firstIndex(where: { $0.id == associationID }) else { return false }
            model.associations[index].legs.append(Leg(entityID: entityID))
            return true
        case let (.entity(entityID), .inheritance(inheritanceID)):
            guard let index = model.inheritances.firstIndex(where: { $0.id == inheritanceID }) else { return false }
            var inheritance = model.inheritances[index]
            if inheritance.parentID == nil, !inheritance.childIDs.contains(entityID) {
                inheritance.parentID = entityID
            } else if inheritance.parentID != entityID, !inheritance.childIDs.contains(entityID) {
                inheritance.childIDs.append(entityID)
            } else {
                return false
            }
            model.inheritances[index] = inheritance
            return true
        case let (.constraint(constraintID), target):
            guard let index = model.constraints.firstIndex(where: { $0.id == constraintID }) else { return false }
            switch target {
            case .entity, .association, .inheritance: break
            default: return false
            }
            guard !model.constraints[index].links.contains(where: { $0.target == target }) else { return false }
            var link = ConstraintLink(target: target)
            // Pour une CIF, la première entité reliée est proposée comme cible.
            if case .entity = target, model.constraints[index].kind == .cif,
               !model.constraints[index].links.contains(where: \.isTarget) {
                link.isTarget = true
            }
            model.constraints[index].links.append(link)
            return true
        case let (.rule(ruleID), target):
            guard let index = model.rules.firstIndex(where: { $0.id == ruleID }) else { return false }
            if case .rule = target { return false }
            guard !model.rules[index].links.contains(target) else { return false }
            model.rules[index].links.append(target)
            return true
        default:
            return false
        }
    }
}

/// Alignement et ordre d'affichage des éléments sélectionnés.
enum Arranger {
    enum Alignment: String, CaseIterable, Identifiable {
        case left, centerX, right, top, centerY, bottom
        var id: String { rawValue }

        var label: String {
            switch self {
            case .left: "Aligner à gauche"
            case .centerX: "Centrer horizontalement"
            case .right: "Aligner à droite"
            case .top: "Aligner en haut"
            case .centerY: "Centrer verticalement"
            case .bottom: "Aligner en bas"
            }
        }

        var symbol: String {
            switch self {
            case .left: "align.horizontal.left.fill"
            case .centerX: "align.horizontal.center.fill"
            case .right: "align.horizontal.right.fill"
            case .top: "align.vertical.top.fill"
            case .centerY: "align.vertical.center.fill"
            case .bottom: "align.vertical.bottom.fill"
            }
        }
    }

    static func align(_ refs: Set<NodeRef>, _ alignment: Alignment, in model: inout MCDModel) {
        let frames = refs.compactMap { ref in NodeMetrics.frame(of: ref, in: model).map { (ref, $0) } }
        guard frames.count >= 2 else { return }
        let all = frames.map(\.1)
        for (ref, frame) in frames {
            var center = CGPoint(x: frame.midX, y: frame.midY)
            switch alignment {
            case .left: center.x = all.map(\.minX).min()! + frame.width / 2
            case .right: center.x = all.map(\.maxX).max()! - frame.width / 2
            case .centerX: center.x = all.map(\.midX).reduce(0, +) / CGFloat(all.count)
            case .top: center.y = all.map(\.minY).min()! + frame.height / 2
            case .bottom: center.y = all.map(\.maxY).max()! - frame.height / 2
            case .centerY: center.y = all.map(\.midY).reduce(0, +) / CGFloat(all.count)
            }
            model.setPosition(center, of: ref)
        }
    }

    /// Premier plan (`front = true`) ou arrière-plan, au sein de chaque type d'élément.
    static func reorder(_ refs: Set<NodeRef>, front: Bool, in model: inout MCDModel) {
        func move<T: Identifiable>(_ items: inout [T], matching ids: Set<UUID>) where T.ID == UUID {
            let picked = items.filter { ids.contains($0.id) }
            items.removeAll { ids.contains($0.id) }
            items = front ? items + picked : picked + items
        }
        let ids = Set(refs.map(\.id))
        move(&model.entities, matching: ids)
        move(&model.associations, matching: ids)
        move(&model.inheritances, matching: ids)
        move(&model.constraints, matching: ids)
        move(&model.rules, matching: ids)
        move(&model.notes, matching: ids)
        move(&model.figures, matching: ids)
    }
}

/// Fond pointillé discret qui aide à aligner sans distraire.
private struct DotGrid: View {
    var body: some View {
        Canvas { context, size in
            let spacing: CGFloat = 20
            let dot = Path(ellipseIn: CGRect(x: -0.9, y: -0.9, width: 1.8, height: 1.8))
            var y: CGFloat = spacing
            while y < size.height {
                var x: CGFloat = spacing
                while x < size.width {
                    context.fill(dot.offsetBy(dx: x, dy: y), with: .color(.primary.opacity(0.13)))
                    x += spacing
                }
                y += spacing
            }
        }
        .frame(width: DiagramView.canvasSize.width, height: DiagramView.canvasSize.height)
        .allowsHitTesting(false)
    }
}

/// Import d'une image d'illustration : réduite à 1024 points au plus et enregistrée en PNG,
/// pour que le fichier .mcd reste léger ; affichée au départ à 240 points au plus.
enum FigureImage {
    static func choose() -> (data: Data, size: CGSize)? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        guard let result = load(url) else {
            let alert = NSAlert()
            alert.messageText = "Image illisible"
            alert.informativeText = "« \(url.lastPathComponent) » n'est pas une image que Cardinal sait lire."
            alert.runModal()
            return nil
        }
        return result
    }

    static func load(_ url: URL) -> (data: Data, size: CGSize)? {
        guard let image = NSImage(contentsOf: url), let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let original = CGSize(width: cg.width, height: cg.height)
        guard original.width > 0, original.height > 0 else { return nil }
        let scale = min(1, 1024 / max(original.width, original.height))
        let pixels = CGSize(width: max(1, (original.width * scale).rounded()), height: max(1, (original.height * scale).rounded()))
        guard let context = CGContext(data: nil, width: Int(pixels.width), height: Int(pixels.height), bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.interpolationQuality = .high
        context.draw(cg, in: CGRect(origin: .zero, size: pixels))
        guard let resized = context.makeImage(),
              let png = NSBitmapImageRep(cgImage: resized).representation(using: .png, properties: [:]) else { return nil }
        let display = min(1, 240 / max(pixels.width, pixels.height))
        return (png, CGSize(width: (pixels.width * display).rounded(), height: (pixels.height * display).rounded()))
    }
}
