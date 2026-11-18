import Foundation
#if canImport(CoreGraphics)
import CoreGraphics // CGRect et ses fonctions ; sous Windows et Linux, Foundation les fournit
#endif

/// Diagramme de classes UML calculé à partir du MCD : boîtes, traits et étiquettes,
/// placés pour que rien ne se touche (boîtes écartées, étiquettes hors des traits).
struct UMLLayout {
    enum LabelKind: Equatable { case multiplicity, role, name }

    struct Line: Equatable {
        let text: String
        let isIdentifier: Bool
    }

    struct ClassBox: Identifiable {
        let id: UUID
        let name: String
        let lines: [Line]
        var frame: CGRect
        let isAssociationClass: Bool
    }

    struct Label {
        let text: String
        let kind: LabelKind
        let associationID: UUID
        /// Entité au bout de laquelle l'étiquette est posée (multiplicités et rôles).
        let entityID: UUID?
        /// Point du trait auquel l'étiquette se rapporte.
        let anchor: CGPoint
        var frame: CGRect
    }

    enum EdgeStyle: Equatable { case solid, dashed, generalization }

    struct Edge {
        var points: [CGPoint]
        let style: EdgeStyle
        var segments: [Segment] { zip(points, points.dropFirst()).map { Segment(a: $0, b: $1) } }
    }

    struct Diamond {
        let associationID: UUID
        var center: CGPoint
        var frame: CGRect { Geometry.rect(center: center, size: UMLLayout.diamondSize) }
    }

    private(set) var classes: [ClassBox] = []
    private(set) var edges: [Edge] = []
    private(set) var labels: [Label] = []
    private(set) var diamonds: [Diamond] = []
    private(set) var size: CGSize = .zero

    static let gap: CGFloat = 70
    static let diamondSize = CGSize(width: 30, height: 30)
    static let loopSize: CGFloat = 44
    static let header: CGFloat = 32
    static let row: CGFloat = 20
    static let operations: CGFloat = 12

    static let labelFont: (size: CGFloat, weight: FontWeight) = (11, .semibold)
    static let roleFont: (size: CGFloat, weight: FontWeight) = (10.5, .regular)
    static let nameFont: (size: CGFloat, weight: FontWeight) = (11.5, .medium)

    fileprivate struct EndRequest {
        let text: String
        let kind: LabelKind
        let association: UUID
        let entity: UUID
        let end: CGPoint
        let direction: CGPoint
    }

    // MARK: Conventions UML

    /// Multiplicités d'une association binaire : en UML, on lit à l'autre bout.
    /// La cardinalité Merise de A (combien de B pour un A) s'écrit donc près de B.
    static func binaryEnds(_ first: Cardinality, _ second: Cardinality) -> (nearFirst: String, nearSecond: String) {
        (multiplicity(second), multiplicity(first))
    }

    /// (0,1) → 0..1, (1,1) → 1, (0,N) → *, (1,N) → 1..*
    static func multiplicity(_ cardinality: Cardinality) -> String {
        switch cardinality {
        case .zeroOne: "0..1"
        case .oneOne: "1"
        case .zeroMany: "*"
        case .oneMany: "1..*"
        }
    }

    /// Lignes d'attributs, comme Looping : visibilité publique « + », type si demandé.
    static func lines(for attributes: [Attribute], showTypes: Bool) -> [Line] {
        attributes.map { attribute in
            let type = showTypes ? " : \(attribute.spec.display)" : ""
            return Line(text: "+ \(attribute.name)\(type)", isIdentifier: attribute.isIdentifier)
        }
    }

    static func boxSize(name: String, lines: [Line], simplified: Bool) -> CGSize {
        let title = TextMetrics.size("+ \(name)", size: 13, weight: .semibold).width + 36
        guard !simplified else { return CGSize(width: max(130, title), height: 36) }
        let widest = lines.map { TextMetrics.size($0.text + ($0.isIdentifier ? " {id}" : ""), size: 11.5, monospaced: true).width }.max() ?? 0
        let width = max(140, title, widest + 24)
        let height = header + 1 + 8 + CGFloat(max(lines.count, 1)) * row + 1 + operations
        return CGSize(width: ceil(width), height: height)
    }

    // MARK: Calcul

    init(model: MCDModel, simplified: Bool) {
        guard !model.entities.isEmpty else { return }
        let showTypes = model.settings.showTypes
        let spread: CGFloat = 1.0

        // 1. Boîtes de départ aux positions du MCD (un peu écartées).
        var rects: [CGRect] = []
        var index: [UUID: Int] = [:]
        var boxes: [ClassBox] = []
        for entity in model.entities {
            let lines = Self.lines(for: entity.attributes, showTypes: showTypes)
            let frame = Geometry.rect(center: entity.position * spread, size: Self.boxSize(name: entity.name, lines: lines, simplified: simplified))
            index[entity.id] = rects.count
            rects.append(frame)
            boxes.append(ClassBox(id: entity.id, name: entity.name, lines: lines, frame: frame, isAssociationClass: false))
        }

        let valid = model.associations.map { association in
            (association, association.legs.filter { index[$0.entityID] != nil })
        }
        let binaries = valid.filter { $0.1.count == 2 }
        let naries = valid.filter { $0.1.count > 2 }

        // Associations n-aires : un losange, traité comme une petite boîte.
        var diamondIndex: [UUID: Int] = [:]
        for (association, _) in naries {
            diamondIndex[association.id] = rects.count
            rects.append(Geometry.rect(center: association.position * spread, size: Self.diamondSize))
        }

        // Classes-associations : une boîte de plus, reliée en pointillés.
        var associationClassIndex: [UUID: Int] = [:]
        for (association, legs) in valid where !association.attributes.isEmpty && legs.count >= 2 {
            let lines = Self.lines(for: association.attributes, showTypes: showTypes)
            var center = association.position * spread
            if let diamond = diamondIndex[association.id] { center = CGPoint(x: rects[diamond].midX, y: rects[diamond].maxY + 90) }
            let frame = Geometry.rect(center: center, size: Self.boxSize(name: association.name, lines: lines, simplified: simplified))
            associationClassIndex[association.id] = rects.count
            rects.append(frame)
            boxes.append(ClassBox(id: association.id, name: association.name, lines: lines, frame: frame, isAssociationClass: true))
        }

        // Liens directs à garder dégagés.
        var edgePairs: [(Int, Int)] = []
        var reflexiveCount: [Int: Int] = [:]
        for (_, legs) in binaries {
            let a = index[legs[0].entityID]!, b = index[legs[1].entityID]!
            if a == b { reflexiveCount[a, default: 0] += 1 } else { edgePairs.append((a, b)) }
        }
        for (association, legs) in naries {
            for leg in legs { edgePairs.append((diamondIndex[association.id]!, index[leg.entityID]!)) }
        }
        for inheritance in model.inheritances {
            guard let parent = inheritance.parentID.flatMap({ index[$0] }) else { continue }
            for child in inheritance.childIDs.compactMap({ index[$0] }) { edgePairs.append((child, parent)) }
        }

        // 2. Écartement : les boucles réflexives réservent leur place autour de la boîte.
        let room = Self.loopSize + 6
        var work = rects.enumerated().map { i, rect in reflexiveCount[i] != nil ? rect.insetBy(dx: -room, dy: -room) : rect }
        Untangler.untangle(&work, edges: edgePairs, gap: Self.gap)
        rects = work.enumerated().map { i, rect in reflexiveCount[i] != nil ? rect.insetBy(dx: room, dy: room) : rect }

        struct NameRequest { let text: String; let association: UUID; let candidates: [CGPoint]; let anchor: CGPoint }
        struct Built { var edges: [Edge]; var ends: [EndRequest]; var names: [NameRequest]; var diamonds: [Diamond] }

        // 3. Traits, recalculés à chaque retouche de la mise en page.
        func build(_ rects: [CGRect]) -> Built {
            func center(_ i: Int) -> CGPoint { CGPoint(x: rects[i].midX, y: rects[i].midY) }

            // 3. Traits.
            var edges: [Edge] = []
            var ends: [EndRequest] = []
            var names: [NameRequest] = []
            var connectors: [(association: UUID, from: CGPoint)] = []

            // Associations binaires entre deux classes différentes, traits parallèles si plusieurs.
            let pairs = Dictionary(grouping: binaries.filter { $0.1[0].entityID != $0.1[1].entityID }) { item -> [Int] in
                [index[item.1[0].entityID]!, index[item.1[1].entityID]!].sorted()
            }
            for key in pairs.keys.sorted(by: { $0.lexicographicallyPrecedes($1) }) {
                let group = pairs[key]!
                for (rank, (association, legs)) in group.enumerated() {
                    let a = index[legs[0].entityID]!, b = index[legs[1].entityID]!
                    let u = (center(b) - center(a)).normalized
                    let p = CGPoint(x: -u.y, y: u.x)
                    let limit = min(Geometry.extent(of: rects[a].size, along: p), Geometry.extent(of: rects[b].size, along: p)) - 8
                    // Écart entre traits parallèles : assez pour y loger le nom le plus long.
                    let across = group.map { item -> CGFloat in
                        let size = TextMetrics.size(item.0.name, size: Self.nameFont.size, weight: Self.nameFont.weight)
                        return abs(p.x) * size.width + abs(p.y) * size.height
                    }.max() ?? 0
                    let spacing = max(44, across + 20)
                    let shift = max(-limit, min(limit, (CGFloat(rank) - CGFloat(group.count - 1) / 2) * spacing))
                    let ca = center(a) + p * shift, cb = center(b) + p * shift
                    let start = Geometry.exit(from: ca, toward: cb, rect: rects[a])
                    let end = Geometry.exit(from: cb, toward: ca, rect: rects[b])
                    edges.append(Edge(points: [start, end], style: .solid))
                    Self.addEnds(&ends, association: association, legs: legs, points: [(start, end - start), (end, start - end)])
                    let segment = Segment(a: start, b: end)
                    let middle = start + (end - start) * 0.5
                    if associationClassIndex[association.id] != nil {
                        connectors.append((association.id, middle))
                    } else {
                        let size = TextMetrics.size(association.name, size: Self.nameFont.size, weight: Self.nameFont.weight)
                        names.append(NameRequest(text: association.name, association: association.id,
                                                 candidates: LabelPlacer.middleCandidates(segment, size: size), anchor: middle))
                    }
                }
            }

            // Associations réflexives : une boucle par coin de la boîte.
            var cornerUse: [Int: Int] = [:]
            let corners: [(CGFloat, CGFloat)] = [(1, -1), (1, 1), (-1, 1), (-1, -1)]
            for (association, legs) in binaries where legs[0].entityID == legs[1].entityID {
                let i = index[legs[0].entityID]!
                let r = rects[i]
                let (sx, sy) = corners[cornerUse[i, default: 0] % 4]
                cornerUse[i, default: 0] += 1
                let s = Self.loopSize
                let inset = max(10, min(32, r.height / 2 - 6, r.width / 2 - 6))
                let cx = sx > 0 ? r.maxX : r.minX
                let cy = sy < 0 ? r.minY : r.maxY
                let p0 = CGPoint(x: cx - sx * inset, y: cy)
                let p1 = CGPoint(x: cx - sx * inset, y: cy + sy * s)
                let p2 = CGPoint(x: cx + sx * s, y: cy + sy * s)
                let p3 = CGPoint(x: cx + sx * s, y: cy - sy * inset)
                let p4 = CGPoint(x: cx, y: cy - sy * inset)
                edges.append(Edge(points: [p0, p1, p2, p3, p4], style: .solid))
                Self.addEnds(&ends, association: association, legs: legs,
                             points: [(p0, CGPoint(x: 0, y: sy)), (p4, CGPoint(x: sx, y: 0))])
                if associationClassIndex[association.id] != nil {
                    connectors.append((association.id, p2))
                } else {
                    let size = TextMetrics.size(association.name, size: Self.nameFont.size, weight: Self.nameFont.weight)
                    let outward = CGPoint(x: sx, y: sy).normalized
                    let candidates = [CGFloat(4), 10, 18].flatMap { d in
                        [p2 + outward * (Geometry.extent(of: size, along: outward) + d)]
                    } + LabelPlacer.middleCandidates(Segment(a: p1, b: p2), size: size) + LabelPlacer.middleCandidates(Segment(a: p2, b: p3), size: size)
                    names.append(NameRequest(text: association.name, association: association.id, candidates: candidates, anchor: p2))
                }
            }

            // Associations n-aires : du losange vers chaque classe.
            var diamonds: [Diamond] = []
            for (association, legs) in naries {
                let d = diamondIndex[association.id]!
                let c = center(d)
                diamonds.append(Diamond(associationID: association.id, center: c))
                for leg in legs {
                    let e = index[leg.entityID]!
                    let start = Geometry.exit(from: c, toward: center(e), rect: rects[d])
                    let end = Geometry.exit(from: center(e), toward: c, rect: rects[e])
                    edges.append(Edge(points: [start, end], style: .solid))
                    ends.append(EndRequest(text: Self.multiplicity(leg.cardinality), kind: .multiplicity, association: association.id,
                                           entity: leg.entityID, end: end, direction: start - end))
                    if !leg.role.isEmpty {
                        ends.append(EndRequest(text: leg.role, kind: .role, association: association.id, entity: leg.entityID, end: end, direction: start - end))
                    }
                }
                if associationClassIndex[association.id] != nil { connectors.append((association.id, c)); continue }
                let size = TextMetrics.size(association.name, size: Self.nameFont.size, weight: Self.nameFont.weight)
                let candidates = [CGPoint(x: 0, y: -1), CGPoint(x: 1, y: 0), CGPoint(x: 0, y: 1), CGPoint(x: -1, y: 0)].flatMap { u in
                    [CGFloat(4), 10, 20, 32].map { c + u * (15 + Geometry.extent(of: size, along: u) + $0) }
                }
                names.append(NameRequest(text: association.name, association: association.id, candidates: candidates, anchor: c))
            }

            // Classes-associations : trait pointillé jusqu'à la boîte.
            for (associationID, from) in connectors {
                guard let i = associationClassIndex[associationID] else { continue }
                let target = Geometry.exit(from: center(i), toward: from, rect: rects[i])
                edges.append(Edge(points: [from, target], style: .dashed))
            }

            // Généralisations : de la sous-classe vers la surclasse.
            for inheritance in model.inheritances {
                guard let parent = inheritance.parentID.flatMap({ index[$0] }) else { continue }
                for child in inheritance.childIDs.compactMap({ index[$0] }) where child != parent {
                    let start = Geometry.exit(from: center(child), toward: center(parent), rect: rects[child])
                    let tip = Geometry.exit(from: center(parent), toward: center(child), rect: rects[parent])
                    edges.append(Edge(points: [start, tip], style: .generalization))
                }
            }
            return Built(edges: edges, ends: ends, names: names, diamonds: diamonds)
        }

        // Vérification sur les traits réellement dessinés : aucune boîte traversée par un trait
        // qui ne la relie pas. Les boîtes gênantes sont déplacées jusqu'à disparition des traversées.
        Untangler.repair(&rects, gap: Self.gap, margins: rects.indices.map { reflexiveCount[$0] != nil ? room : 0 }) { trial in
            Self.crossings(build(trial).edges, trial)
        }
        let built = build(rects)
        let edges = built.edges, ends = built.ends, names = built.names, diamonds = built.diamonds


        // 4. Étiquettes : multiplicités d'abord (les plus importantes), puis rôles, puis noms.
        for i in boxes.indices { boxes[i].frame = rects[index[boxes[i].id] ?? associationClassIndex[boxes[i].id]!] }
        var placer = LabelPlacer(obstacles: boxes.map(\.frame) + diamonds.map(\.frame), segments: edges.flatMap(\.segments))
        var labels: [Label] = []
        for kind in [LabelKind.multiplicity, .role] {
            for request in ends where request.kind == kind {
                let font = kind == .multiplicity ? Self.labelFont : Self.roleFont
                let size = TextMetrics.size(request.text, size: font.size, weight: font.weight)
                let frame = placer.place(size: size, candidates: LabelPlacer.endCandidates(end: request.end, direction: request.direction, size: size), anchor: request.end)
                labels.append(Label(text: request.text, kind: kind, associationID: request.association, entityID: request.entity, anchor: request.end, frame: frame))
            }
        }
        for request in names {
            let size = TextMetrics.size(request.text, size: Self.nameFont.size, weight: Self.nameFont.weight)
            let frame = placer.place(size: size, candidates: request.candidates)
            labels.append(Label(text: request.text, kind: .name, associationID: request.association, entityID: nil, anchor: request.anchor, frame: frame))
        }

        // 5. Cadrage : tout le dessin commence à la marge.
        let margin: CGFloat = 40
        var bounds = boxes.map(\.frame).reduce(CGRect.null) { $0.union($1) }
        for diamond in diamonds { bounds = bounds.union(diamond.frame) }
        for label in labels { bounds = bounds.union(label.frame) }
        for point in edges.flatMap(\.points) { bounds = bounds.union(CGRect(origin: point, size: .zero)) }
        let shift = CGPoint(x: margin - bounds.minX, y: margin - bounds.minY)
        self.classes = boxes.map { var box = $0; box.frame = box.frame.offsetBy(dx: shift.x, dy: shift.y); return box }
        self.diamonds = diamonds.map { Diamond(associationID: $0.associationID, center: $0.center + shift) }
        self.edges = edges.map { Edge(points: $0.points.map { $0 + shift }, style: $0.style) }
        self.labels = labels.map { Label(text: $0.text, kind: $0.kind, associationID: $0.associationID, entityID: $0.entityID, anchor: $0.anchor + shift, frame: $0.frame.offsetBy(dx: shift.x, dy: shift.y)) }
        self.size = CGSize(width: bounds.width + margin * 2, height: bounds.height + margin * 2)
    }

    /// Traits qui traversent une boîte qu'ils ne relient pas (avec une marge pour respirer).
    static func crossings(_ edges: [Edge], _ rects: [CGRect]) -> [Untangler.Crossing] {
        var result: [Untangler.Crossing] = []
        for segment in edges.flatMap(\.segments) {
            let owners = rects.indices.filter { Geometry.distance(segment.a, rects[$0]) < 1.5 || Geometry.distance(segment.b, rects[$0]) < 1.5 }
            for k in rects.indices where !owners.contains(k) && Geometry.intersects(segment, rects[k].insetBy(dx: -8, dy: -8)) {
                result.append(Untangler.Crossing(box: k, owners: owners))
            }
        }
        return result
    }

    /// Aux deux bouts d'une binaire : la multiplicité se lit à l'autre bout (cardinalités croisées),
    /// le rôle de chaque patte reste de son côté, comme dans Looping.
    private static func addEnds(_ ends: inout [EndRequest], association: Association, legs: [Leg], points: [(CGPoint, CGPoint)]) {
        for side in 0..<2 {
            let other = legs[1 - side]
            ends.append(EndRequest(text: multiplicity(other.cardinality), kind: .multiplicity, association: association.id,
                                        entity: legs[side].entityID, end: points[side].0, direction: points[side].1))
            if !legs[side].role.isEmpty {
                ends.append(EndRequest(text: legs[side].role, kind: .role, association: association.id,
                                            entity: legs[side].entityID, end: points[side].0, direction: points[side].1))
            }
        }
    }
}
