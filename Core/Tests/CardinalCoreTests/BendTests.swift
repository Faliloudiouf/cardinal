import Testing
import Foundation
#if SWIFT_PACKAGE
@testable import CardinalCore
#else
@testable import Cardinal
#endif

@Suite("Cassures de pattes et dépendances fonctionnelles")
struct BendTests {
    /// Client (0,N) — Passer — (1,1) Commande, posés en ligne.
    func model() -> MCDModel {
        var b = MCDBuilder()
        let client = b.entity("Client")
        let commande = b.entity("Commande")
        b.association("Passer", [(client, .zeroMany), (commande, .oneOne)])
        b.model.setPosition(CGPoint(x: 200, y: 300), of: .entity(client))
        b.model.setPosition(CGPoint(x: 900, y: 300), of: .entity(commande))
        b.model.setPosition(CGPoint(x: 550, y: 300), of: .association(b.model.associations[0].id))
        return b.model
    }

    @Test("Ajouter puis retirer une cassure ; elle est décalée de la ligne droite")
    func ajouterRetirer() {
        var model = model()
        let association = model.associations[0]
        model.toggleBend(association: association.id, leg: association.legs[0].id)
        let bend = try! #require(model.associations[0].legs[0].bend)
        #expect(abs(bend.y - 300) >= 50) // visible : pas sur la droite qui joint les deux nœuds
        model.toggleBend(association: association.id, leg: association.legs[0].id)
        #expect(model.associations[0].legs[0].bend == nil)
    }

    @Test("Déplacer une association emmène ses cassures ; déplacer une entité ne les touche pas")
    func deplacement() {
        var model = model()
        model.associations[0].legs[0].bend = CGPoint(x: 400, y: 150)
        model.move([.entity(model.entities[0].id)], by: CGSize(width: 30, height: 30))
        #expect(model.associations[0].legs[0].bend == CGPoint(x: 400, y: 150))
        model.move([.association(model.associations[0].id)], by: CGSize(width: 10, height: -20))
        #expect(model.associations[0].legs[0].bend == CGPoint(x: 410, y: 130))
        #expect(model.associations[0].position == CGPoint(x: 560, y: 280))
    }

    @Test("Tracé : la patte passe par la cassure et arrive sur le côté de l'entité tourné vers elle")
    func trace() {
        var model = model()
        model.associations[0].legs[0].bend = CGPoint(x: 200, y: 120) // au-dessus de Client
        let layout = MCDLabelLayout(model: model) { model.position(of: $0) ?? .zero }
        let leg = try! #require(layout.legPaths.first { $0.legIndex == 0 })
        #expect(leg.points.count == 3)
        #expect(leg.points[1] == CGPoint(x: 200, y: 120))
        let client = NodeMetrics.frame(of: .entity(model.entities[0].id), in: model)!
        #expect(abs(leg.points[2].y - client.minY) < 1) // arrive par le haut de la boîte
        // La cardinalité reste près de son entité, sur le tronçon final.
        let label = try! #require(layout.labels.first { $0.legIndex == 0 })
        #expect(Geometry.distance(label.anchor, label.frame) < 60)
        #expect(!layout.obstacles.contains { $0.intersects(label.frame) })
    }

    @Test("Dépendances : seules les pattes 0,1 et 1,1 portent la flèche")
    func dependances() {
        let model = model()
        let layout = MCDLabelLayout(model: model) { model.position(of: $0) ?? .zero }
        #expect(layout.legPaths.map(\.isMaxOne).sorted { !$0 && $1 } == [false, true])
    }

    @Test("Une patte commence au bord de l'association, jamais sous elle (avec ou sans cassure)",
          arguments: [false, true])
    func departAuBord(withBend: Bool) {
        var model = model()
        if withBend { model.associations[0].legs[0].bend = CGPoint(x: 400, y: 120) }
        let layout = MCDLabelLayout(model: model) { model.position(of: $0) ?? .zero }
        let capsule = NodeMetrics.frame(of: .association(model.associations[0].id), in: model)!
        for leg in layout.legPaths {
            #expect(Geometry.distance(leg.points[0], capsule) < 1, "départ hors du bord")
            #expect(!capsule.insetBy(dx: 2, dy: 2).contains(leg.points[0]), "départ caché sous l'association")
        }
    }

    @Test("Cassure et option enregistrées ; un ancien fichier sans elles reste lisible")
    func fichier() throws {
        var model = model()
        model.associations[0].legs[1].bend = CGPoint(x: 700, y: 450)
        model.settings.showDependencies = true
        let back = try ModelFile.read(try ModelFile.encode(model))
        #expect(back.associations[0].legs[1].bend == CGPoint(x: 700, y: 450))
        #expect(back.settings.showDependencies)
        let old = #"{"associations":[{"name":"A","legs":[{"entityID":"\#(UUID().uuidString)","cardinality":"1,1"}],"position":[0,0]}]}"#
        let decoded = try ModelFile.read(Data(old.utf8))
        #expect(decoded.associations[0].legs[0].bend == nil)
        #expect(!decoded.settings.showDependencies)
    }

    @Test("Lisibilité conservée avec des cassures sur un modèle chargé")
    func lisibilite() {
        var model = ReadabilityModels.charge(spacing: 520)
        for a in model.associations.indices {
            let legs = model.associations[a].legs
            for leg in legs.prefix(1) { model.toggleBend(association: model.associations[a].id, leg: leg.id) }
        }
        let layout = MCDLabelLayout(model: model) { model.position(of: $0) ?? .zero }
        for (i, label) in layout.labels.enumerated() {
            for other in layout.labels[(i + 1)...] { #expect(!label.frame.insetBy(dx: -1, dy: -1).intersects(other.frame), "« \(label.text) » / « \(other.text) »") }
            #expect(!layout.obstacles.contains { $0.intersects(label.frame) }, "« \(label.text) » sur une boîte")
        }
    }
}
