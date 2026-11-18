import Foundation
#if canImport(CoreGraphics)
import CoreGraphics // CGRect et ses fonctions ; sous Windows et Linux, Foundation les fournit
#endif
#if canImport(AppKit) && !CARDINAL_PORTABLE
import AppKit
#endif

// Lisibilité des diagrammes : aucun texte ni élément collé ou superposé.
// Tout est calculé ici, sans interface, pour pouvoir être vérifié par les tests
// et réutilisé tel quel par les versions Windows et Linux.

/// Graisse d'une police, indépendante de toute bibliothèque d'interface.
enum FontWeight: Sendable { case regular, medium, semibold, bold }

/// Mesure du texte. Sur macOS : polices système réelles. Ailleurs : estimation volontairement
/// un peu large (une étiquette mesurée plus grande que nature ne peut pas en chevaucher une autre).
enum TextMetrics {
    static func size(_ text: String, size: CGFloat, weight: FontWeight = .regular, monospaced: Bool = false) -> CGSize {
        // CARDINAL_PORTABLE : force le chemin Windows / Linux, pour le tester depuis un Mac.
        #if canImport(AppKit) && !CARDINAL_PORTABLE
        let nsWeight: NSFont.Weight = switch weight {
        case .regular: .regular
        case .medium: .medium
        case .semibold: .semibold
        case .bold: .bold
        }
        let font = monospaced ? NSFont.monospacedSystemFont(ofSize: size, weight: nsWeight) : NSFont.systemFont(ofSize: size, weight: nsWeight)
        let measured = (text as NSString).size(withAttributes: [.font: font])
        return CGSize(width: ceil(measured.width) + 2, height: ceil(measured.height))
        #else
        return estimated(text, size: size, weight: weight, monospaced: monospaced)
        #endif
    }

    /// Estimation sans police : largeurs des caractères ASCII de la police système, relevées à
    /// 12 points (forme « texte » de la police, plus large) et ramenées à 100, pour chaque graisse, plus 4 % de marge. Un caractère accentué prend la largeur
    /// de sa lettre de base, tout autre caractère celle d'un « M » (prudent).
    static func estimated(_ text: String, size: CGFloat, weight: FontWeight = .regular, monospaced: Bool = false) -> CGSize {
        let height = ceil(size * 1.18)
        if monospaced { return CGSize(width: ceil(CGFloat(text.count) * size * 0.62 * 1.04) + 2, height: height) }
        let table = widths[weight] ?? widths[.regular]!
        let wide = CGFloat(table[Int(UInt8(ascii: "M")) - 32])
        var total: CGFloat = 0
        for character in text {
            let base = String(character).folding(options: .diacriticInsensitive, locale: nil).unicodeScalars.first?.value ?? 0
            total += (32...126).contains(base) ? CGFloat(table[Int(base) - 32]) : wide
        }
        return CGSize(width: ceil(total * size / 100 * 1.04) + 2, height: height)
    }

    /// Largeur (pour 100 points, mesurée à 12) des caractères 32 à 126, par graisse : police système de macOS.
    private static let widths: [FontWeight: [UInt8]] = [
        .regular: [29, 32, 48, 63, 63, 93, 72, 30, 39, 39, 48, 63, 30, 48, 30, 31, 63, 47, 61, 63, 65, 62, 64, 57, 64, 64, 30, 30, 63, 63, 63, 52, 92, 68, 66, 72, 73, 60, 58, 75, 75, 27, 54, 66, 57, 88, 75, 78, 64, 78, 66, 64, 64, 74, 68, 97, 68, 66, 67, 39, 31, 39, 63, 59, 50, 56, 62, 56, 62, 58, 37, 61, 59, 25, 25, 55, 26, 88, 59, 60, 62, 61, 39, 53, 37, 59, 55, 78, 53, 55, 54, 39, 26, 39, 63],
        .medium: [28, 33, 52, 65, 65, 97, 73, 32, 40, 40, 48, 65, 32, 48, 32, 32, 65, 49, 62, 65, 66, 64, 66, 59, 66, 66, 32, 32, 65, 65, 65, 53, 93, 70, 68, 73, 74, 61, 59, 76, 76, 29, 57, 68, 58, 89, 76, 78, 65, 78, 67, 66, 65, 75, 70, 99, 70, 68, 67, 40, 32, 40, 65, 60, 50, 57, 63, 57, 63, 59, 38, 63, 61, 27, 27, 57, 27, 90, 60, 61, 63, 63, 41, 54, 39, 60, 56, 81, 55, 57, 55, 40, 28, 40, 65],
        .semibold: [27, 34, 54, 66, 66, 100, 74, 33, 42, 42, 48, 66, 33, 48, 33, 33, 67, 50, 63, 66, 68, 65, 67, 60, 68, 67, 33, 33, 66, 66, 66, 55, 93, 72, 69, 74, 74, 62, 59, 76, 77, 30, 58, 70, 59, 90, 76, 79, 66, 79, 68, 67, 66, 76, 71, 100, 72, 69, 68, 42, 33, 42, 66, 62, 50, 58, 64, 58, 64, 59, 40, 64, 62, 28, 28, 58, 28, 91, 62, 61, 64, 64, 42, 56, 40, 62, 57, 83, 56, 58, 56, 42, 29, 42, 66],
        .bold: [26, 36, 57, 68, 68, 104, 75, 35, 43, 43, 49, 68, 35, 49, 35, 34, 69, 52, 65, 67, 69, 67, 69, 61, 70, 69, 35, 35, 68, 68, 68, 56, 93, 74, 70, 75, 75, 63, 60, 77, 79, 32, 61, 71, 60, 91, 77, 79, 68, 79, 70, 68, 67, 77, 73, 101, 73, 71, 68, 43, 34, 43, 68, 63, 50, 59, 66, 59, 66, 61, 41, 65, 64, 29, 29, 61, 30, 94, 63, 62, 65, 65, 44, 57, 42, 63, 59, 85, 59, 60, 57, 43, 30, 43, 68],
    ]
}

struct Segment: Equatable {
    var a: CGPoint
    var b: CGPoint
}

extension CGPoint {
    func isNear(_ other: CGPoint, tolerance: CGFloat = 1) -> Bool {
        abs(x - other.x) <= tolerance && abs(y - other.y) <= tolerance
    }
}

enum Geometry {
    /// Le segment traverse-t-il le rectangle (ou y est-il contenu) ? Méthode de Liang-Barsky.
    static func intersects(_ segment: Segment, _ rect: CGRect) -> Bool {
        var t0: CGFloat = 0
        var t1: CGFloat = 1
        let dx = segment.b.x - segment.a.x
        let dy = segment.b.y - segment.a.y
        let checks: [(CGFloat, CGFloat)] = [
            (-dx, segment.a.x - rect.minX), (dx, rect.maxX - segment.a.x),
            (-dy, segment.a.y - rect.minY), (dy, rect.maxY - segment.a.y),
        ]
        for (p, q) in checks {
            if p == 0 {
                if q < 0 { return false }
            } else {
                let r = q / p
                if p < 0 { if r > t1 { return false }; if r > t0 { t0 = r } }
                else { if r < t0 { return false }; if r < t1 { t1 = r } }
            }
        }
        return t0 <= t1
    }

    /// Point où le segment p → q sort du rectangle (p à l'intérieur).
    static func exit(from p: CGPoint, toward q: CGPoint, rect: CGRect) -> CGPoint {
        let dx = q.x - p.x
        let dy = q.y - p.y
        var t: CGFloat = 1
        if dx > 0 { t = min(t, (rect.maxX - p.x) / dx) }
        if dx < 0 { t = min(t, (rect.minX - p.x) / dx) }
        if dy > 0 { t = min(t, (rect.maxY - p.y) / dy) }
        if dy < 0 { t = min(t, (rect.minY - p.y) / dy) }
        t = max(0, t)
        return CGPoint(x: p.x + dx * t, y: p.y + dy * t)
    }

    static func closestPoint(on segment: Segment, to point: CGPoint) -> CGPoint {
        let d = segment.b - segment.a
        let length2 = d.x * d.x + d.y * d.y
        guard length2 > 0 else { return segment.a }
        let t = max(0, min(1, ((point.x - segment.a.x) * d.x + (point.y - segment.a.y) * d.y) / length2))
        return segment.a + d * t
    }

    static func distance(_ point: CGPoint, _ rect: CGRect) -> CGFloat {
        let dx = max(rect.minX - point.x, 0, point.x - rect.maxX)
        let dy = max(rect.minY - point.y, 0, point.y - rect.maxY)
        return (dx * dx + dy * dy).squareRoot()
    }

    /// Demi-largeur d'un rectangle mesurée le long d'une direction unitaire.
    static func extent(of size: CGSize, along direction: CGPoint) -> CGFloat {
        abs(direction.x) * size.width / 2 + abs(direction.y) * size.height / 2
    }

    static func rect(center: CGPoint, size: CGSize) -> CGRect {
        CGRect(x: center.x - size.width / 2, y: center.y - size.height / 2, width: size.width, height: size.height)
    }
}

/// Place les étiquettes une à une, chacune à l'endroit candidat le moins gênant :
/// jamais sur une autre étiquette ni sur une boîte, et si possible sur aucun trait.
struct LabelPlacer {
    var obstacles: [CGRect]
    var segments: [Segment]
    private(set) var placed: [CGRect] = []
    /// Espace minimal entre une étiquette et ce qui l'entoure.
    var gap: CGFloat = 3
    /// Traits qui portent des étiquettes (les premiers de `segments`) : seuls ceux-là comptent pour
    /// l'ambiguïté. Un lien d'héritage, sans cardinalité, ne peut pas « voler » une étiquette.
    var labelledSegments: Int?

    init(obstacles: [CGRect], segments: [Segment]) {
        self.obstacles = obstacles
        self.segments = segments
    }

    /// `anchor` : bout de trait décrit par l'étiquette. L'étiquette doit alors rester plus proche
    /// de ce trait que de tout autre, pour qu'on ne puisse pas l'attribuer au mauvais lien.
    /// `onOwnLine` : l'étiquette a un fond opaque et peut se poser sur son propre trait (pastille du MCD).
    mutating func place(size: CGSize, candidates: [CGPoint], anchor: CGPoint? = nil, onOwnLine: Bool = false) -> CGRect {
        let own = anchor.map { point in segments.indices.filter { segments[$0].a.isNear(point) || segments[$0].b.isNear(point) } } ?? []
        let skipped = onOwnLine ? own : []
        var best = Geometry.rect(center: candidates.first ?? .zero, size: size)
        var bestCost = CGFloat.infinity
        for (index, center) in candidates.enumerated() {
            let rect = Geometry.rect(center: center, size: size)
            var cost = self.cost(of: rect, skipping: skipped) + CGFloat(index)
            if !own.isEmpty && isAmbiguous(center, own: own) { cost += 50_000 }
            if cost < bestCost {
                bestCost = cost
                best = rect
                if cost == CGFloat(index) { break } // aucune gêne : le premier libre suffit
            }
        }
        placed.append(best)
        return best
    }

    func isAmbiguous(_ center: CGPoint, own: [Int]) -> Bool {
        func gap(_ segment: Segment) -> CGFloat {
            let p = Geometry.closestPoint(on: segment, to: center)
            return ((p.x - center.x) * (p.x - center.x) + (p.y - center.y) * (p.y - center.y)).squareRoot()
        }
        let mine = own.map { gap(segments[$0]) }.min() ?? 0
        let candidates = segments.indices.prefix(labelledSegments ?? segments.count)
        return candidates.contains { !own.contains($0) && gap(segments[$0]) < mine - 1 }
    }

    func cost(of rect: CGRect, skipping: [Int] = []) -> CGFloat {
        let padded = rect.insetBy(dx: -gap, dy: -gap)
        var cost: CGFloat = 0
        for other in placed where padded.intersects(other) { cost += 1_000_000 }
        for box in obstacles where padded.intersects(box) { cost += 1_000_000 }
        for (index, segment) in segments.enumerated() where !skipping.contains(index) && Geometry.intersects(segment, rect.insetBy(dx: -1.5, dy: -1.5)) { cost += 10_000 }
        return cost
    }

    /// Positions candidates près de l'extrémité d'un lien, du plus proche au plus éloigné,
    /// de part et d'autre du trait. `direction` part de la boîte vers l'autre bout du lien.
    static func endCandidates(end: CGPoint, direction: CGPoint, size: CGSize) -> [CGPoint] {
        let u = direction.normalized
        let p = CGPoint(x: -u.y, y: u.x)
        let along = Geometry.extent(of: size, along: u)
        let across = Geometry.extent(of: size, along: p)
        var result: [CGPoint] = []
        for distance: CGFloat in [6, 14, 24, 36, 50, 66, 84] {
            for offset: CGFloat in [5, 12, 22, 34] {
                for side: CGFloat in [1, -1] {
                    result.append(end + u * (along + distance) + p * (side * (across + offset)))
                }
            }
        }
        return result
    }

    /// Positions centrées sur le trait lui-même, près de son extrémité (étiquettes à fond opaque).
    static func onLineCandidates(end: CGPoint, direction: CGPoint, size: CGSize) -> [CGPoint] {
        let u = direction.normalized
        let along = Geometry.extent(of: size, along: u)
        return [CGFloat(6), 14, 24, 36, 50].map { end + u * (along + $0) }
    }

    /// Positions candidates le long d'un trait, en partant du milieu.
    static func middleCandidates(_ segment: Segment, size: CGSize) -> [CGPoint] {
        let u = (segment.b - segment.a).normalized
        let p = CGPoint(x: -u.y, y: u.x)
        let across = Geometry.extent(of: size, along: p)
        var result: [CGPoint] = []
        for t: CGFloat in [0.5, 0.42, 0.58, 0.34, 0.66, 0.26, 0.74, 0.18, 0.82] {
            for offset: CGFloat in [4, 10, 18, 28, 40] {
                for side: CGFloat in [-1, 1] {
                    let point = segment.a + (segment.b - segment.a) * t
                    result.append(point + p * (side * (across + offset)))
                }
            }
        }
        return result
    }
}

/// Écarte des boîtes qui se touchent, puis écarte les boîtes traversées par un trait
/// qui ne les concerne pas. Les positions de départ (celles du MCD) sont respectées au mieux.
enum Untangler {
    static func separate(_ rects: inout [CGRect], gap: CGFloat, iterations: Int = 800) {
        guard rects.count > 1 else { return }
        for _ in 0..<iterations {
            var moved = false
            for i in rects.indices {
                for j in rects.indices where j > i {
                    let a = rects[i].insetBy(dx: -gap / 2, dy: -gap / 2)
                    let b = rects[j].insetBy(dx: -gap / 2, dy: -gap / 2)
                    guard a.intersects(b) else { continue }
                    let overlapX = min(a.maxX - b.minX, b.maxX - a.minX)
                    let overlapY = min(a.maxY - b.minY, b.maxY - a.minY)
                    if overlapX < overlapY {
                        let sign: CGFloat = a.midX <= b.midX ? -1 : 1
                        rects[i] = rects[i].offsetBy(dx: sign * (overlapX / 2 + 0.5), dy: 0)
                        rects[j] = rects[j].offsetBy(dx: -sign * (overlapX / 2 + 0.5), dy: 0)
                    } else {
                        let sign: CGFloat = a.midY <= b.midY ? -1 : 1
                        rects[i] = rects[i].offsetBy(dx: 0, dy: sign * (overlapY / 2 + 0.5))
                        rects[j] = rects[j].offsetBy(dx: 0, dy: -sign * (overlapY / 2 + 0.5))
                    }
                    moved = true
                }
            }
            if !moved { return }
        }
    }

    /// Indices des liens (paires de boîtes) dont le trait direct traverse une troisième boîte.
    static func crossings(_ rects: [CGRect], edges: [(Int, Int)], clearance: CGFloat) -> [(edge: Int, box: Int)] {
        var result: [(Int, Int)] = []
        for (index, edge) in edges.enumerated() where edge.0 != edge.1 {
            let segment = Segment(a: CGPoint(x: rects[edge.0].midX, y: rects[edge.0].midY),
                                  b: CGPoint(x: rects[edge.1].midX, y: rects[edge.1].midY))
            for k in rects.indices where k != edge.0 && k != edge.1 {
                if Geometry.intersects(segment, rects[k].insetBy(dx: -clearance, dy: -clearance)) {
                    result.append((index, k))
                }
            }
        }
        return result
    }

    static func untangle(_ rects: inout [CGRect], edges: [(Int, Int)], gap: CGFloat, clearance: CGFloat = 16) {
        separate(&rects, gap: gap)
        for _ in 0..<200 {
            let found = crossings(rects, edges: edges, clearance: clearance)
            guard let (edgeIndex, k) = found.first else { return }
            let edge = edges[edgeIndex]
            let segment = Segment(a: CGPoint(x: rects[edge.0].midX, y: rects[edge.0].midY),
                                  b: CGPoint(x: rects[edge.1].midX, y: rects[edge.1].midY))
            let center = CGPoint(x: rects[k].midX, y: rects[k].midY)
            let closest = Geometry.closestPoint(on: segment, to: center)
            var direction = (center - closest).normalized
            if direction == .zero {
                let u = (segment.b - segment.a).normalized
                direction = CGPoint(x: -u.y, y: u.x)
            }
            let distance = ((center - closest).x * (center - closest).x + (center - closest).y * (center - closest).y).squareRoot()
            let needed = Geometry.extent(of: rects[k].size, along: direction) + clearance + 6 - distance
            rects[k] = rects[k].offsetBy(dx: direction.x * needed, dy: direction.y * needed)
            separate(&rects, gap: gap)
        }
    }

    /// Un trait qui traverse une boîte : la boîte gênante et les boîtes que le trait relie.
    struct Crossing {
        let box: Int
        let owners: [Int]
    }

    /// Recherche locale : pour chaque traversée, essaie de déplacer la boîte gênante ou l'une des
    /// boîtes reliées, dans 16 directions et 4 distances, et garde le déplacement qui réduit le plus
    /// le nombre de traversées (à égalité, le plus court, pour rester proche de la mise en page d'origine).
    /// `margins` agrandit certaines boîtes pendant l'écartement (place réservée aux boucles réflexives).
    static func repair(_ rects: inout [CGRect], gap: CGFloat, margins: [CGFloat], crossings: ([CGRect]) -> [Crossing]) {
        func separated(_ input: [CGRect]) -> [CGRect] {
            var work = input.enumerated().map { $1.insetBy(dx: -margins[$0], dy: -margins[$0]) }
            separate(&work, gap: gap)
            return work.enumerated().map { $1.insetBy(dx: margins[$0], dy: margins[$0]) }
        }
        rects = separated(rects)
        var current = crossings(rects)
        let directions = (0..<16).map { CGPoint(x: cos(CGFloat($0) * .pi / 8), y: sin(CGFloat($0) * .pi / 8)) }
        for _ in 0..<100 where !current.isEmpty {
            var best: (rects: [CGRect], count: Int, cost: CGFloat)?
            for crossing in current {
                for mover in Set([crossing.box] + crossing.owners).sorted() {
                    for direction in directions {
                        for distance: CGFloat in [50, 110, 190, 300, 440, 620] {
                            var trial = rects
                            trial[mover] = trial[mover].offsetBy(dx: direction.x * distance, dy: direction.y * distance)
                            trial = separated(trial)
                            let count = crossings(trial).count
                            if count < current.count && (best == nil || count < best!.count || (count == best!.count && distance < best!.cost)) {
                                best = (trial, count, distance)
                            }
                        }
                    }
                }
                if best != nil { break }
            }
            guard let found = best else { return }
            rects = found.rects
            current = crossings(rects)
        }
    }
}
