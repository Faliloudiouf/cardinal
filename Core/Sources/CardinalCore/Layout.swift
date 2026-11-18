import Foundation
#if canImport(CoreGraphics)
import CoreGraphics // CGRect et ses fonctions ; sous Windows et Linux, Foundation les fournit
#endif

// Mise en page partagée par toutes les interfaces (macOS aujourd'hui, Windows et Linux ensuite).

/// Dimensions des nœuds : le canevas en a besoin pour tracer les liens au bon endroit.
enum NodeMetrics {
    static let entityWidth: CGFloat = 200
    static let associationWidth: CGFloat = 176
    static let header: CGFloat = 34
    static let row: CGFloat = 21
    static let padding: CGFloat = 8
    static let bareAssociationHeight: CGFloat = 44
    static let inheritanceSize = CGSize(width: 58, height: 48)
    static let constraintSize = CGSize(width: 46, height: 46)
    static let ruleSize = CGSize(width: 220, height: 40)
    static let noteWidth: CGFloat = 240

    static func size(of entity: Entity, settings: ModelSettings = ModelSettings()) -> CGSize {
        guard settings.showAttributes else { return CGSize(width: entityWidth, height: header + 6) }
        return CGSize(width: entityWidth, height: header + CGFloat(max(entity.attributes.count, 1)) * row + padding * 2)
    }

    static func size(of association: Association, settings: ModelSettings = ModelSettings()) -> CGSize {
        if association.attributes.isEmpty || !settings.showAttributes {
            return CGSize(width: associationWidth, height: bareAssociationHeight)
        }
        return CGSize(width: associationWidth, height: header + CGFloat(association.attributes.count) * row + padding * 2)
    }

    static func size(of note: Note) -> CGSize {
        switch note.style {
        case .titre:
            let width = min(560, max(120, CGFloat(note.text.count) * 12.5 + 28))
            return CGSize(width: width, height: 40)
        case .texte:
            let lines = note.text.split(separator: "\n", omittingEmptySubsequences: false)
                .map { max(1, Int((Double($0.count) / 34).rounded(.up))) }
                .reduce(0, +)
            return CGSize(width: noteWidth, height: CGFloat(max(lines, 1)) * 17 + 20)
        }
    }

    static func size(of ref: NodeRef, in model: MCDModel) -> CGSize {
        switch ref {
        case .entity(let id): model.entity(id).map { size(of: $0, settings: model.settings) } ?? .zero
        case .association(let id): model.association(id).map { size(of: $0, settings: model.settings) } ?? .zero
        case .inheritance: inheritanceSize
        case .constraint: constraintSize
        case .rule: ruleSize
        case .note(let id): model.notes.first { $0.id == id }.map(size(of:)) ?? .zero
        case .figure(let id): model.figures.first { $0.id == id }?.frame.size ?? .zero
        }
    }

    static func frame(of ref: NodeRef, in model: MCDModel) -> CGRect? {
        guard let center = model.position(of: ref) else { return nil }
        let size = size(of: ref, in: model)
        return CGRect(x: center.x - size.width / 2, y: center.y - size.height / 2, width: size.width, height: size.height)
    }

    /// Rectangle englobant tout le diagramme (pour l'export et « Ajuster à la fenêtre »).
    static func bounds(of model: MCDModel, margin: CGFloat = 40) -> CGRect? {
        let frames = model.allRefs.compactMap { frame(of: $0, in: model) }
        guard let first = frames.first else { return nil }
        return frames.dropFirst().reduce(first) { $0.union($1) }.insetBy(dx: -margin, dy: -margin)
    }
}

extension CGPoint {
    static func + (lhs: CGPoint, rhs: CGPoint) -> CGPoint { CGPoint(x: lhs.x + rhs.x, y: lhs.y + rhs.y) }
    static func - (lhs: CGPoint, rhs: CGPoint) -> CGPoint { CGPoint(x: lhs.x - rhs.x, y: lhs.y - rhs.y) }
    static func * (lhs: CGPoint, rhs: CGFloat) -> CGPoint { CGPoint(x: lhs.x * rhs, y: lhs.y * rhs) }

    var normalized: CGPoint {
        let length = (x * x + y * y).squareRoot()
        return length > 0 ? CGPoint(x: x / length, y: y / length) : .zero
    }

    func offset(by size: CGSize) -> CGPoint { CGPoint(x: x + size.width, y: y + size.height) }
}

/// Point où la droite centre → cible sort du rectangle d'un nœud.
func edgePoint(center: CGPoint, toward target: CGPoint, size: CGSize) -> CGPoint {
    let dx = target.x - center.x
    let dy = target.y - center.y
    guard dx != 0 || dy != 0 else { return center }
    let scaleX = dx == 0 ? CGFloat.infinity : (size.width / 2) / abs(dx)
    let scaleY = dy == 0 ? CGFloat.infinity : (size.height / 2) / abs(dy)
    let t = min(scaleX, scaleY, 1)
    return CGPoint(x: center.x + dx * t, y: center.y + dy * t)
}

/// Mise en page du MLD graphique : taille des tables et positions sans chevauchement.
enum MLDLayout {
    static let cardWidth: CGFloat = 230
    static let header: CGFloat = 34
    static let row: CGFloat = 25

    static func size(of table: MLDTable) -> CGSize {
        CGSize(width: cardWidth, height: header + CGFloat(table.columns.count) * row + 8)
    }

    /// Positions des tables (centres) : celles du MCD, puis écartées pour qu'aucune table
    /// ne touche une autre et qu'aucune flèche ne traverse une table qui ne la concerne pas.
    static func layout(model: MCDModel, tables: [MLDTable]) -> (positions: [String: CGPoint], size: CGSize) {
        var rects: [CGRect] = []
        for (index, table) in tables.enumerated() {
            let fallback = CGPoint(x: 200 + CGFloat(index % 4) * 300, y: 200 + CGFloat(index / 4) * 300)
            let base = table.origin.flatMap(model.position(of:)) ?? fallback
            // Un peu plus d'espace qu'en MCD : les tables sont plus grandes que les entités.
            rects.append(Geometry.rect(center: CGPoint(x: base.x * 1.25, y: base.y * 1.3), size: size(of: table)))
        }
        let pairs = references(tables)
        Untangler.untangle(&rects, edges: pairs, gap: 60)
        Untangler.repair(&rects, gap: 60, margins: rects.map { _ in 0 }) { trial in
            var result: [Untangler.Crossing] = []
            for (a, b) in pairs {
                let ca = CGPoint(x: trial[a].midX, y: trial[a].midY), cb = CGPoint(x: trial[b].midX, y: trial[b].midY)
                let segment = Segment(a: Geometry.exit(from: ca, toward: cb, rect: trial[a]), b: Geometry.exit(from: cb, toward: ca, rect: trial[b]))
                for k in trial.indices where k != a && k != b && Geometry.intersects(segment, trial[k].insetBy(dx: -8, dy: -8)) {
                    result.append(Untangler.Crossing(box: k, owners: [a, b]))
                }
            }
            return result
        }
        guard let first = rects.first else { return ([:], .zero) }
        let bounds = rects.dropFirst().reduce(first) { $0.union($1) }
        let margin: CGFloat = 60
        var positions: [String: CGPoint] = [:]
        for (table, rect) in zip(tables, rects) {
            positions[table.name] = CGPoint(x: rect.midX - bounds.minX + margin, y: rect.midY - bounds.minY + margin)
        }
        return (positions, CGSize(width: bounds.width + margin * 2, height: bounds.height + margin * 2))
    }

    /// Une flèche du MLD : de la table qui porte la clé étrangère vers la table référencée.
    struct Link {
        let child: String
        let parent: String
        let columns: [MLDColumn]
        /// Tracé : deux points pour une flèche droite, plus pour une boucle (référence à soi-même).
        let points: [CGPoint]
        var isLoop: Bool { child == parent }
    }

    /// Flèches du MLD. Plusieurs clés entre les deux mêmes tables : flèches parallèles écartées.
    /// Clé vers sa propre table : boucle sur le côté droit (une par clé, emboîtées).
    static func links(tables: [MLDTable], positions: [String: CGPoint]) -> [Link] {
        struct Raw { let child: MLDTable; let parent: MLDTable; let columns: [MLDColumn] }
        var raws: [Raw] = []
        for table in tables {
            let groups = Dictionary(grouping: table.columns.filter { $0.reference != nil }) { $0.reference!.group }
            for (_, columns) in groups.sorted(by: { $0.key < $1.key }) {
                guard let parent = tables.first(where: { $0.name == columns.first?.reference?.table }) else { continue }
                raws.append(Raw(child: table, parent: parent, columns: columns))
            }
        }
        func frame(_ table: MLDTable) -> CGRect? {
            positions[table.name].map { Geometry.rect(center: $0, size: size(of: table)) }
        }
        var result: [Link] = []
        var loops: [(Raw, Int)] = []
        let pairs = Dictionary(grouping: raws.indices) { [raws[$0].child.name, raws[$0].parent.name].sorted().joined(separator: "\u{0}") }
        for key in pairs.keys.sorted() {
            let members = pairs[key]!
            for (rank, index) in members.enumerated() {
                let raw = raws[index]
                guard let a = frame(raw.child), let b = frame(raw.parent) else { continue }
                if raw.child.name == raw.parent.name {
                    loops.append((raw, rank)) // placées après les autres flèches, côté le moins chargé
                    continue
                }
                // Sens de référence commun à la paire, pour que les décalages ne se croisent pas.
                let (first, second) = raw.child.name < raw.parent.name ? (a, b) : (b, a)
                let u = (CGPoint(x: second.midX, y: second.midY) - CGPoint(x: first.midX, y: first.midY)).normalized
                let p = CGPoint(x: -u.y, y: u.x)
                let limit = min(Geometry.extent(of: a.size, along: p), Geometry.extent(of: b.size, along: p)) - 10
                let shift = max(-limit, min(limit, (CGFloat(rank) - CGFloat(members.count - 1) / 2) * 22))
                let ca = CGPoint(x: a.midX, y: a.midY) + p * shift
                let cb = CGPoint(x: b.midX, y: b.midY) + p * shift
                result.append(Link(child: raw.child.name, parent: raw.parent.name, columns: raw.columns,
                                   points: [Geometry.exit(from: ca, toward: cb, rect: a), Geometry.exit(from: cb, toward: ca, rect: b)]))
            }
        }
        for (raw, rank) in loops {
            guard let a = frame(raw.child) else { continue }
            // Côté droit ou gauche : celui où arrivent le moins d'autres flèches.
            let ends = result.flatMap { [$0.points.first!, $0.points.last!] }
            let onRight = ends.filter { abs($0.x - a.maxX) < 1.5 && $0.y >= a.minY && $0.y <= a.maxY }.count
            let onLeft = ends.filter { abs($0.x - a.minX) < 1.5 && $0.y >= a.minY && $0.y <= a.maxY }.count
            let side: CGFloat = onRight <= onLeft ? 1 : -1
            let edge = side > 0 ? a.maxX : a.minX
            let step = CGFloat(rank) * 14
            let top = a.minY + header + 6
            let bottom = min(a.maxY - 6, top + 34 + step)
            let out = edge + side * (36 + step)
            result.append(Link(child: raw.child.name, parent: raw.parent.name, columns: raw.columns,
                               points: [CGPoint(x: edge, y: top + step / 3), CGPoint(x: out, y: top + step / 3),
                                        CGPoint(x: out, y: bottom), CGPoint(x: edge, y: bottom)]))
        }
        return result
    }

    /// Paires (table qui référence, table référencée), une par clé étrangère.
    static func references(_ tables: [MLDTable]) -> [(Int, Int)] {
        var result: [(Int, Int)] = []
        for (child, table) in tables.enumerated() {
            let groups = Dictionary(grouping: table.columns.filter { $0.reference != nil }) { $0.reference!.group }
            for (_, columns) in groups.sorted(by: { $0.key < $1.key }) {
                guard let parent = tables.firstIndex(where: { $0.name == columns.first?.reference?.table }), parent != child else { continue }
                result.append((child, parent))
            }
        }
        return result
    }

}

/// Pattes du MCD et emplacement de leurs cardinalités : jamais sur une boîte,
/// une autre cardinalité ou un trait, et toujours au plus près de l'entité concernée.
struct MCDLabelLayout {
    struct Label {
        let text: String
        let associationID: UUID
        let legIndex: Int
        let anchor: CGPoint
        let frame: CGRect
    }

    /// Tracé d'une patte : du bord de l'association (cassure éventuelle) jusqu'au bord de l'entité.
    struct LegPath {
        let associationID: UUID
        let legIndex: Int
        let points: [CGPoint]
        /// Patte 0,1 ou 1,1 : porte la flèche de dépendance fonctionnelle.
        let isMaxOne: Bool
    }

    static let fontSize: CGFloat = 11
    private(set) var legs: [Segment] = []
    private(set) var legPaths: [LegPath] = []
    private(set) var labels: [Label] = []
    private(set) var obstacles: [CGRect] = []
    private(set) var segments: [Segment] = []
    /// Point d'arrivée de chaque lien non-patte (héritage, contrainte, règle), clé `key(source, cible)`.
    private(set) var linkPorts: [String: CGPoint] = [:]

    static func key(_ source: NodeRef, _ target: NodeRef) -> String { "\(source)>\(target)" }

    static func text(of leg: Leg) -> String {
        var text = leg.cardinality.rawValue + (leg.isRelative ? " (R)" : "")
        if !leg.role.isEmpty { text += "  " + leg.role }
        return text
    }

    init(model: MCDModel, position: @escaping (NodeRef) -> CGPoint) {
        let size = { (ref: NodeRef) in NodeMetrics.size(of: ref, in: model) }
        let frame = { (ref: NodeRef) in Geometry.rect(center: position(ref), size: size(ref)) }
        // Un trait ou une flèche d'illustration n'est pas une boîte : c'est un segment à éviter.
        obstacles = model.allRefs.filter { ref in
            if case .figure(let id) = ref, model.figures.first(where: { $0.id == id })?.kind.isStroke == true { return false }
            return true
        }.map(frame)

        struct Request { let text: String; let association: UUID; let leg: Int; let edge: CGPoint; let direction: CGPoint }
        struct Pending { let association: UUID; let leg: Int; let text: String; let entity: NodeRef; let start: CGPoint; var port: CGPoint; let side: Int; var link: String? = nil
            var bend: CGPoint? = nil; var isMaxOne = false
            /// Point vers lequel la patte quitte l'entité : la cassure s'il y en a une.
            var toward: CGPoint { bend ?? start } }
        var pending: [Pending] = []
        for association in model.associations {
            let ref = NodeRef.association(association.id)
            let center = position(ref)
            let siblingsByEntity = Dictionary(grouping: association.legs.indices) { association.legs[$0].entityID }
            for (index, leg) in association.legs.enumerated() {
                guard model.entity(leg.entityID) != nil else { continue }
                let entityRef = NodeRef.entity(leg.entityID)
                let entityCenter = position(entityRef)
                let direction = (entityCenter - center).normalized
                let perpendicular = CGPoint(x: -direction.y, y: direction.x)
                // Association réflexive : on écarte les pattes vers la même entité.
                let siblings = siblingsByEntity[leg.entityID] ?? [index]
                let rank = CGFloat(siblings.firstIndex(of: index) ?? 0)
                let shift = perpendicular * ((rank - CGFloat(siblings.count - 1) / 2) * 28)
                let start = center + shift
                let box = frame(entityRef)
                let toward = leg.bend ?? start
                let port = Geometry.exit(from: entityCenter + (leg.bend == nil ? shift : .zero), toward: toward, rect: box.insetBy(dx: -0.5, dy: -0.5))
                // Côté de la boîte où la patte arrive : 0 haut, 1 droite, 2 bas, 3 gauche.
                let side = abs(port.y - box.minY) < 1.5 ? 0 : abs(port.x - box.maxX) < 1.5 ? 1 : abs(port.y - box.maxY) < 1.5 ? 2 : 3
                pending.append(Pending(association: association.id, leg: index, text: Self.text(of: leg), entity: entityRef,
                                       start: start, port: port, side: side, bend: leg.bend, isMaxOne: leg.cardinality.isMaxOne))
            }
        }
        // Les autres liens (héritages, contraintes, règles) prennent aussi leur place sur le côté :
        // ils ne doivent pas arriver au même endroit qu'une patte.
        func addLink(from source: NodeRef, start: CGPoint, to target: NodeRef) {
            let box = frame(target)
            let port = Geometry.exit(from: position(target), toward: start, rect: box.insetBy(dx: -0.5, dy: -0.5))
            let side = abs(port.y - box.minY) < 1.5 ? 0 : abs(port.x - box.maxX) < 1.5 ? 1 : abs(port.y - box.maxY) < 1.5 ? 2 : 3
            pending.append(Pending(association: UUID(), leg: -1, text: "", entity: target, start: start, port: port, side: side,
                                   link: Self.key(source, target)))
        }
        for inheritance in model.inheritances {
            let ref = NodeRef.inheritance(inheritance.id)
            let center = position(ref)
            let half = NodeMetrics.inheritanceSize.height / 2
            if let parent = inheritance.parentID, model.entity(parent) != nil {
                addLink(from: ref, start: CGPoint(x: center.x, y: center.y - half), to: .entity(parent))
            }
            for child in inheritance.childIDs where model.entity(child) != nil {
                addLink(from: ref, start: CGPoint(x: center.x, y: center.y + half), to: .entity(child))
            }
        }
        for constraint in model.constraints {
            let ref = NodeRef.constraint(constraint.id)
            for link in constraint.links where model.contains(link.target) { addLink(from: ref, start: position(ref), to: link.target) }
        }
        for rule in model.rules {
            let ref = NodeRef.rule(rule.id)
            for target in rule.links where model.contains(target) { addLink(from: ref, start: position(ref), to: target) }
        }
        // Plusieurs pattes sur le même côté d'une entité : points d'arrivée répartis le long du côté,
        // dans l'ordre où elles arrivent (aucun croisement ajouté), au lieu de converger vers le centre.
        let groups = Dictionary(grouping: pending.indices) { "\(pending[$0].entity)-\(pending[$0].side)" }
        for key in groups.keys.sorted() {
            let members = groups[key]!
            guard members.count > 1 else { continue }
            let box = frame(pending[members[0]].entity)
            let horizontal = pending[members[0]].side % 2 == 0
            // Ordre des associations vues depuis le côté (pas celui des points d'impact) : aucun croisement.
            let sorted = members.sorted { horizontal ? pending[$0].toward.x < pending[$1].toward.x : pending[$0].toward.y < pending[$1].toward.y }
            let low = horizontal ? box.minX + box.width * 0.18 : box.minY + min(box.height * 0.25, 30)
            let high = horizontal ? box.maxX - box.width * 0.18 : box.maxY - box.height * 0.15
            for (rank, i) in sorted.enumerated() {
                let t = CGFloat(rank) / CGFloat(sorted.count - 1)
                let value = low + (high - low) * t
                pending[i].port = horizontal ? CGPoint(x: value, y: pending[i].port.y) : CGPoint(x: pending[i].port.x, y: value)
            }
        }
        var requests: [Request] = []
        var others: [Segment] = []
        for item in pending where item.link != nil {
            linkPorts[item.link!] = item.port
            others.append(Segment(a: item.start, b: item.port))
        }
        for item in pending where item.link == nil {
            // Bord de l'association, dans la direction du premier point visible (cassure ou entité).
            let from = Geometry.exit(from: item.start, toward: item.bend ?? item.port, rect: frame(NodeRef.association(item.association)).insetBy(dx: -0.5, dy: -0.5))
            legs.append(Segment(a: item.toward, b: item.port))
            legPaths.append(LegPath(associationID: item.association, legIndex: item.leg,
                                    points: item.bend.map { [from, $0, item.port] } ?? [from, item.port], isMaxOne: item.isMaxOne))
            // Le tronçon qui touche l'entité porte la cardinalité ; l'autre tronçon est un simple trait à éviter.
            segments.append(Segment(a: item.bend ?? from, b: item.port))
            if let bend = item.bend { others.append(Segment(a: from, b: bend)) }
            requests.append(Request(text: item.text, association: item.association, leg: item.leg, edge: item.port, direction: item.toward - item.port))
        }
        segments += others
        segments += model.figures.filter(\.kind.isStroke).map { Segment(a: $0.start, b: $0.end) }

        var placer = LabelPlacer(obstacles: obstacles, segments: segments)
        placer.labelledSegments = requests.count
        for request in requests {
            let text = TextMetrics.size(request.text, size: Self.fontSize, weight: .bold)
            let pill = CGSize(width: text.width + 10, height: text.height + 3)
            let frame = placer.place(size: pill, candidates: LabelPlacer.endCandidates(end: request.edge, direction: request.direction, size: pill)
                                        + LabelPlacer.onLineCandidates(end: request.edge, direction: request.direction, size: pill),
                                    anchor: request.edge, onOwnLine: true)
            labels.append(Label(text: request.text, associationID: request.association, legIndex: request.leg, anchor: request.edge, frame: frame))
        }
    }
}
