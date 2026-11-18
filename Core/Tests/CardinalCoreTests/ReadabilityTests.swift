import Testing
import Foundation
#if SWIFT_PACKAGE
@testable import CardinalCore
#else
@testable import Cardinal
#endif

// MARK: - Modèles d'essai

enum ReadabilityModels {
    static func loo() throws -> MCDModel {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/LoopingEntrepriseServices2.loo")
        return try LooImporter.model(from: Data(contentsOf: url))
    }

    /// Cas extrêmes : trois associations entre les deux mêmes entités, deux réflexives sur la même,
    /// une ternaire porteuse d'attributs, un héritage, des noms très longs.
    static func charge(spacing: CGFloat) -> MCDModel {
        var b = MCDBuilder()
        let salarie = b.entity("Salarie", attrs: ["nom_salarie", "prenom_salarie", "date_embauche_dans_la_societe"])
        let societe = b.entity("Societe", attrs: ["raison_sociale"])
        let personne = b.entity("PersonneAvecUnNomTresLongPourLeTest", attrs: ["nom"])
        let projet = b.entity("Projet", attrs: ["libelle"])
        let date = b.entity("Date", ids: ["jour"])
        let cadre = b.entity("Cadre", ids: [], attrs: ["prime"]) // sous-type : identifiant hérité
        b.association("Employer", [(salarie, .oneOne), (societe, .zeroMany)])
        b.association("Diriger", [(salarie, .zeroOne), (societe, .oneOne)])
        b.association("AvoirTravaillePour", [(salarie, .zeroMany), (societe, .zeroMany)], attrs: ["date_debut", "date_fin"])
        b.association("EtreParent", [(personne, .zeroMany), (personne, .zeroMany)], roles: ["parent", "enfant"])
        b.association("EtreConjoint", [(personne, .zeroOne), (personne, .zeroOne)], roles: ["epoux", "epouse"])
        b.association("Affecter", [(salarie, .zeroMany), (projet, .oneMany), (date, .zeroMany)], attrs: ["role_dans_le_projet"])
        b.association("Connaitre", [(salarie, .zeroMany), (personne, .zeroMany)])
        b.model.inheritances.append(Inheritance(parentID: salarie, childIDs: [cadre], position: .zero))
        // Disposition réaliste, réduite d'autant que `spacing` est petit (0 : tout empilé au même point).
        let scale = spacing / 520
        let places: [CGPoint] = [CGPoint(x: 0, y: 0), CGPoint(x: 700, y: 0), CGPoint(x: 700, y: 650),
                                 CGPoint(x: -150, y: 700), CGPoint(x: 300, y: 900), CGPoint(x: -400, y: 420)]
        for (id, place) in zip(b.model.entities.map(\.id), places) {
            b.model.setPosition(CGPoint(x: 500 + place.x * scale, y: 200 + place.y * scale), of: .entity(id))
        }
        // Comme un utilisateur : chaque association au milieu de ses entités, les parallèles décalées,
        // les réflexives à côté de leur entité.
        var seen: [[UUID]: Int] = [:]
        var reflexive = 0
        for association in b.model.associations {
            let points = association.legs.compactMap { b.model.entity($0.entityID)?.position }
            var center = CGPoint(x: points.map(\.x).reduce(0, +) / CGFloat(points.count), y: points.map(\.y).reduce(0, +) / CGFloat(points.count))
            let key = Array(Set(association.legs.map(\.entityID))).sorted { $0.uuidString < $1.uuidString }
            if key.count == 1 {
                center = center + CGPoint(x: 280, y: reflexive == 0 ? -70 : 70)
                reflexive += 1
            } else {
                let rank = seen[key, default: 0]
                seen[key] = rank + 1
                center = center + CGPoint(x: 0, y: CGFloat(rank) * 70 - 30)
            }
            b.model.setPosition(spacing == 0 ? .zero : center, of: .association(association.id))
        }
        if let id = b.model.inheritances.first?.id, let cadre = b.model.entity(cadre) {
            let salarie = b.model.entities[0].position
            b.model.setPosition(CGPoint(x: (salarie.x + cadre.position.x) / 2, y: (salarie.y + cadre.position.y) / 2), of: .inheritance(id))
        }
        return b.model
    }

    static func all() throws -> [(String, MCDModel)] {
        [("commandes", .exemple), ("scolarité", .exempleScolarite), ("fichier Looping", try loo()),
         ("chargé espacé", charge(spacing: 520)), ("chargé serré", charge(spacing: 120)), ("tout empilé", charge(spacing: 0))]
    }
}

/// Liste lisible de tout ce qui gêne la lecture : textes qui se touchent, textes posés
/// sur une boîte ou sur un trait, traits qui traversent une boîte, boîtes trop proches.
func readabilityProblems(boxes: [(String, CGRect)], labels: [(String, CGRect)], segments: [Segment], minBoxGap: CGFloat) -> [String] {
    var problems: [String] = []
    for i in boxes.indices {
        for j in boxes.indices where j > i {
            let a = boxes[i].1.insetBy(dx: -minBoxGap / 2, dy: -minBoxGap / 2)
            if a.intersects(boxes[j].1.insetBy(dx: -minBoxGap / 2, dy: -minBoxGap / 2)) {
                problems.append("boîtes trop proches : \(boxes[i].0) / \(boxes[j].0)")
            }
        }
    }
    for i in labels.indices {
        for j in labels.indices where j > i && labels[i].1.insetBy(dx: -1, dy: -1).intersects(labels[j].1) {
            problems.append("textes collés : « \(labels[i].0) » / « \(labels[j].0) »")
        }
        for box in boxes where labels[i].1.intersects(box.1) {
            problems.append("texte « \(labels[i].0) » sur la boîte \(box.0)")
        }
        for segment in segments where Geometry.intersects(segment, labels[i].1.insetBy(dx: 0.5, dy: 0.5)) {
            problems.append("texte « \(labels[i].0) » sur un trait")
        }
    }
    for segment in segments {
        for box in boxes {
            let touches = Geometry.distance(segment.a, box.1) < 1.5 || Geometry.distance(segment.b, box.1) < 1.5
            if !touches && Geometry.intersects(segment, box.1.insetBy(dx: 2, dy: 2)) {
                problems.append("trait à travers la boîte \(box.0)")
            }
        }
    }
    return problems
}

// MARK: - UML

@MainActor
@Suite("Lisibilité : diagramme de classes UML")
struct UMLReadabilityTests {
    @Test("Aucun chevauchement, aucun texte sur un trait, aucune boîte traversée",
          arguments: [false, true])
    func lisible(simplified: Bool) throws {
        for (name, model) in try ReadabilityModels.all() {
            let layout = UMLLayout(model: model, simplified: simplified)
            let problems = readabilityProblems(
                boxes: layout.classes.map { ($0.name, $0.frame) } + layout.diamonds.map { ("losange", $0.frame) },
                labels: layout.labels.map { ($0.text, $0.frame) },
                segments: layout.edges.flatMap(\.segments),
                minBoxGap: 40
            )
            #expect(problems.isEmpty, "\(name) : \(problems)")
        }
    }

    @Test("Chaque multiplicité et chaque rôle restent près du bout de trait qu'ils décrivent")
    func procheDuBout() throws {
        for (name, model) in try ReadabilityModels.all() {
            for label in UMLLayout(model: model, simplified: false).labels where label.kind != .name {
                let distance = Geometry.distance(label.anchor, label.frame)
                #expect(distance <= 70, "\(name) : « \(label.text) » à \(Int(distance)) pt de son bout de trait")
            }
        }
    }

    @Test("Toutes les associations sont dessinées, réflexives comprises, avec leurs deux multiplicités")
    func toutEstDessine() throws {
        for (name, model) in try ReadabilityModels.all() {
            let layout = UMLLayout(model: model, simplified: false)
            for association in model.associations {
                let count = layout.labels.filter { $0.associationID == association.id && $0.kind == .multiplicity }.count
                #expect(count == association.legs.count, "\(name) : \(association.name) a \(count) multiplicités")
            }
            #expect(layout.classes.filter { !$0.isAssociationClass }.count == model.entities.count)
        }
    }
}

@MainActor
@Suite("Mêmes résultats que Looping : UML du fichier réel")
struct UMLParityTests {
    /// Lu sur la capture de l'onglet UML de Looping pour LoopingEntrepriseServices2.loo :
    /// association → (classe, multiplicité écrite près de cette classe, rôle).
    nonisolated static let looping: [String: [(String, String, String)]] = [
        "Commander": [("Client", "1", ""), ("Projet", "1..*", "")],
        "Composer": [("Projet", "1", ""), ("Tache", "1..*", "")],
        "Utiliser": [("Materiel", "1..*", ""), ("Salarie", "*", "")],
        "Realiser": [("Tache", "*", ""), ("Salarie", "1..*", "")],
        "Coordonner": [("Projet", "*", ""), ("Salarie", "1", "")],
        "EtreRattache": [("Salarie", "1..*", ""), ("Division", "1", "")],
        "EtreRegroupe": [("Salarie", "1..*", ""), ("Equipe", "*", "")],
        "EtreCompose": [("Materiel", "0..1", "Etrecompose"), ("Materiel", "*", "EtreComposant")],
    ]

    @Test("Multiplicités et rôles identiques à Looping", arguments: Array(looping.keys).sorted())
    func multiplicites(association name: String) throws {
        let model = try ReadabilityModels.loo()
        let association = try #require(model.associations.first { $0.name == name })
        let labels = UMLLayout(model: model, simplified: false).labels.filter { $0.associationID == association.id }
        let multiplicities = labels.filter { $0.kind == .multiplicity }
        let roles = labels.filter { $0.kind == .role }
        // Chaque bout : (classe, multiplicité, rôle posé au même bout).
        var cardinal: [String] = []
        for label in multiplicities {
            let entity = model.entity(label.entityID!)!.name
            let role = roles.first { $0.anchor == label.anchor }?.text ?? ""
            cardinal.append("\(entity) \(label.text) \(role)")
        }
        let expected = Self.looping[name]!.map { "\($0.0) \($0.1) \($0.2)" }
        #expect(cardinal.sorted() == expected.sorted())
    }

    @Test("Realiser est une classe-association avec date_debut et date_fin, comme dans Looping")
    func classeAssociation() throws {
        let model = try ReadabilityModels.loo()
        let layout = UMLLayout(model: model, simplified: false)
        let realiser = try #require(layout.classes.first { $0.isAssociationClass })
        #expect(realiser.name == "Realiser")
        #expect(realiser.lines.map(\.text).map { $0.components(separatedBy: " : ")[0] } == ["+ date_debut", "+ date_fin"])
        #expect(layout.edges.filter { $0.style == .dashed }.count == 1)
        #expect(layout.classes.count == 8) // 7 classes + Realiser
    }
}

// MARK: - MCD

@MainActor
@Suite("Lisibilité : cardinalités du MCD")
struct MCDReadabilityTests {
    @Test("Les cardinalités ne touchent ni une autre cardinalité, ni une boîte, ni un trait")
    func lisible() throws {
        // « tout empilé » est exclu : les boîtes s'y recouvrent par construction.
        for (name, model) in try ReadabilityModels.all() where name != "tout empilé" && name != "chargé serré" {
            let layout = MCDLabelLayout(model: model) { model.position(of: $0) ?? .zero }
            var problems: [String] = []
            for i in layout.labels.indices {
                let label = layout.labels[i]
                for other in layout.labels[(i + 1)...] where label.frame.insetBy(dx: -1, dy: -1).intersects(other.frame) {
                    problems.append("« \(label.text) » / « \(other.text) »")
                }
                for box in layout.obstacles where label.frame.intersects(box) { problems.append("« \(label.text) » sur une boîte") }
                // Sa propre patte peut passer sous la pastille (fond opaque) ; aucune autre.
                for (k, segment) in layout.segments.enumerated() where k != i && Geometry.intersects(segment, label.frame.insetBy(dx: 0.5, dy: 0.5)) {
                    problems.append("« \(label.text) » sur un autre trait")
                }
                let distance = Geometry.distance(label.anchor, label.frame)
                if distance > 100 { problems.append("« \(label.text) » à \(Int(distance)) pt de son entité") }
                // Sans ambiguïté : la cardinalité est plus proche de sa propre patte que de toute autre patte.
                let center = CGPoint(x: label.frame.midX, y: label.frame.midY)
                let gaps = layout.segments.prefix(layout.labels.count).map { segment -> CGFloat in
                    let p = Geometry.closestPoint(on: segment, to: center)
                    return ((p.x - center.x) * (p.x - center.x) + (p.y - center.y) * (p.y - center.y)).squareRoot()
                }
                if let nearest = gaps.min(), gaps[i] > nearest + 1 {
                    problems.append("« \(label.text) » (\(model.association(label.associationID)?.name ?? "") patte \(label.legIndex) ; \(Int(label.frame.midX)),\(Int(label.frame.midY))) plus proche d’une autre patte que de la sienne")
                }
            }
            #expect(problems.isEmpty, "\(name) : \(problems)")
        }
    }

    @Test("Une cardinalité par patte, avec (R) et rôle")
    func contenu() throws {
        let model = try ReadabilityModels.loo()
        let layout = MCDLabelLayout(model: model) { model.position(of: $0) ?? .zero }
        #expect(layout.labels.count == model.associations.reduce(0) { $0 + $1.legs.count })
        #expect(layout.labels.contains { $0.text == "0,1  EtreComposant" })
        #expect(MCDLabelLayout.text(of: Leg(entityID: UUID(), cardinality: .oneOne, isRelative: true)) == "1,1 (R)")
    }
}

// MARK: - MLD

@MainActor
@Suite("Lisibilité : MLD graphique")
struct MLDReadabilityTests {
    @Test("Tables écartées, aucune flèche à travers une autre table")
    func lisible() throws {
        for (name, model) in try ReadabilityModels.all() {
            let tables = MLDBuilder.build(model)
            let layout = MLDLayout.layout(model: model, tables: tables)
            let frames = tables.map { Geometry.rect(center: layout.positions[$0.name]!, size: MLDLayout.size(of: $0)) }
            let links = MLDLayout.links(tables: tables, positions: layout.positions)
            let segments = links.flatMap { link in zip(link.points, link.points.dropFirst()).map { Segment(a: $0, b: $1) } }
            // Une flèche par clé étrangère, boucles comprises.
            let expected = tables.reduce(0) { $0 + Set($1.columns.compactMap { $0.reference?.group }).count }
            #expect(links.count == expected, "\(name) : \(links.count) flèches pour \(expected) clés étrangères")
            // Une boucle (clé vers sa propre table) ne frôle aucune autre flèche.
            for loop in links where loop.isLoop {
                let loopSegments = zip(loop.points, loop.points.dropFirst()).map { Segment(a: $0, b: $1) }
                for other in links where !other.isLoop {
                    for point in [other.points.first!, other.points.last!] {
                        let near = loopSegments.contains { segment in
                            let c = Geometry.closestPoint(on: segment, to: point)
                            return ((c.x - point.x) * (c.x - point.x) + (c.y - point.y) * (c.y - point.y)).squareRoot() < 10
                        }
                        #expect(!near, "\(name) : la boucle de \(loop.child) frôle la flèche \(other.child)→\(other.parent)")
                    }
                }
            }
            // Deux flèches ne se confondent jamais : leurs milieux restent écartés.
            for i in links.indices where !links[i].isLoop {
                for j in links.indices where j > i && !links[j].isLoop {
                    let m1 = (links[i].points[0] + links[i].points[1]) * 0.5, m2 = (links[j].points[0] + links[j].points[1]) * 0.5
                    let gap = ((m1.x - m2.x) * (m1.x - m2.x) + (m1.y - m2.y) * (m1.y - m2.y)).squareRoot()
                    #expect(gap >= 12, "\(name) : flèches \(links[i].child)→\(links[i].parent) et \(links[j].child)→\(links[j].parent) confondues")
                }
            }
            let problems = readabilityProblems(boxes: zip(tables, frames).map { ($0.name, $1) }, labels: [], segments: segments, minBoxGap: 40)
            #expect(problems.isEmpty, "\(name) : \(problems)")
        }
    }
}

// MARK: - Moteur

@MainActor
@Suite("Moteur de placement")
struct PlacementEngineTests {
    @Test("Segment et rectangle : traversée, contact, à côté, contenu")
    func intersection() {
        let rect = CGRect(x: 0, y: 0, width: 10, height: 10)
        #expect(Geometry.intersects(Segment(a: CGPoint(x: -5, y: 5), b: CGPoint(x: 15, y: 5)), rect))
        #expect(Geometry.intersects(Segment(a: CGPoint(x: 2, y: 2), b: CGPoint(x: 3, y: 3)), rect))
        #expect(!Geometry.intersects(Segment(a: CGPoint(x: -5, y: -1), b: CGPoint(x: 15, y: -1)), rect))
        #expect(!Geometry.intersects(Segment(a: CGPoint(x: 11, y: -5), b: CGPoint(x: 20, y: 20)), rect))
    }

    @Test("Le placeur évite une étiquette déjà posée et un trait")
    func placeur() {
        var placer = LabelPlacer(obstacles: [], segments: [Segment(a: CGPoint(x: 0, y: 0), b: CGPoint(x: 100, y: 0))])
        let first = placer.place(size: CGSize(width: 20, height: 10), candidates: [CGPoint(x: 50, y: 0), CGPoint(x: 50, y: 12)])
        #expect(first.midY == 12) // le premier candidat est sur le trait
        let second = placer.place(size: CGSize(width: 20, height: 10), candidates: [CGPoint(x: 50, y: 12), CGPoint(x: 50, y: -12)])
        #expect(second.midY == -12) // le premier candidat est pris
    }

    @Test("Écartement : boîtes empilées au même point séparées d'au moins l'écart demandé")
    func ecartement() {
        var rects = Array(repeating: CGRect(x: 0, y: 0, width: 100, height: 60), count: 6)
        Untangler.separate(&rects, gap: 50)
        for i in rects.indices {
            for j in rects.indices where j > i {
                #expect(!rects[i].insetBy(dx: -24, dy: -24).intersects(rects[j].insetBy(dx: -24, dy: -24)))
            }
        }
    }
}

