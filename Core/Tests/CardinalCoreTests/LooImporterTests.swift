import Testing
import Foundation
#if SWIFT_PACKAGE
@testable import CardinalCore
#else
@testable import Cardinal
#endif

/// Le fichier de référence vient d'un vrai projet Looping 4.1 (L3 GLSI).
@Suite("Lecture des fichiers Looping (.loo)")
struct LooImporterTests {
    let model: MCDModel

    init() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/LoopingEntrepriseServices2.loo")
        model = try LooImporter.model(from: Data(contentsOf: url))
    }

    func legs(_ name: String) -> [String] {
        (model.associations.first { $0.name == name }?.legs ?? []).map { leg in
            "\(model.entity(leg.entityID)?.name ?? "?") \(leg.cardinality.rawValue)"
        }
    }

    @Test("Entités, propriétés, libellés et types")
    func entites() throws {
        #expect(model.entities.map(\.name) == ["Client", "Projet", "Materiel", "Tache", "Equipe", "Salarie", "Division"])
        let tache = try #require(model.entities.first { $0.name == "Tache" })
        #expect(tache.attributes.map(\.name) == ["id_tache", "cout_tache", "nom_tache"])
        #expect(tache.attributes[0].isIdentifier && !tache.attributes[1].isIdentifier)
        #expect(tache.attributes[0].label == "identifiant de la tache")
        #expect(tache.attributes[1].type == .decimal)
        let materiel = try #require(model.entities.first { $0.name == "Materiel" })
        #expect(materiel.attributes.first { $0.name == "groupe_mat" }?.type == .booleen)
    }

    @Test("Associations et cardinalités identiques à Looping")
    func associations() {
        #expect(model.associations.count == 8)
        #expect(legs("Commander") == ["Client 1,N", "Projet 1,1"])
        #expect(legs("Composer") == ["Projet 1,N", "Tache 1,1"])
        #expect(legs("Utiliser") == ["Materiel 0,N", "Salarie 1,N"])
        #expect(legs("Coordonner") == ["Projet 1,1", "Salarie 0,N"])
        #expect(legs("EtreRattache") == ["Salarie 1,1", "Division 1,N"])
        #expect(legs("EtreRegroupe") == ["Equipe 1,N", "Salarie 0,N"])
        let realiser = model.associations.first { $0.name == "Realiser" }
        #expect(realiser?.attributes.map(\.name) == ["date_debut", "date_fin"])
        #expect(realiser?.attributes.first?.type == .date)
    }

    @Test("Association réflexive : rôles conservés")
    func reflexive() {
        let compose = model.associations.first { $0.name == "EtreCompose" }
        #expect(compose?.legs.map(\.role) == ["Etrecompose", "EtreComposant"])
        #expect(compose?.legs.map(\.cardinality) == [.zeroMany, .zeroOne])
    }

    @Test("Le MLD obtenu est celui affiché par Looping")
    func mld() throws {
        let tables = MLDBuilder.build(model)
        #expect(Set(tables.map(\.name)) == ["Client", "Projet", "Materiel", "Tache", "Equipe", "Salarie", "Division", "Utiliser", "Realiser", "EtreRegroupe"])
        let projet = try #require(tables.first { $0.name == "Projet" })
        #expect(Set(projet.columns.compactMap { $0.reference?.table }) == ["Client", "Salarie"])
        let materiel = try #require(tables.first { $0.name == "Materiel" })
        #expect(materiel.columns.contains { $0.name == "id_mat_Etrecompose" && $0.reference?.table == "Materiel" })
        let realiser = try #require(tables.first { $0.name == "Realiser" })
        #expect(realiser.primaryKey.map(\.name) == ["id_tache", "id_salarie"])
    }

    @Test("Option libellés : colonnes nommées comme dans Looping")
    func libelles() throws {
        var model = model
        model.settings.useLabels = true
        let client = try #require(MLDBuilder.build(model).first { $0.name == "Client" })
        #expect(client.columns.map(\.name) == ["Identifiant_du_client", "Nom_du_client", "Prenom_du_client"])
    }

    @Test("Positions : la mise en page de Looping est conservée")
    func positions() throws {
        let client = try #require(model.entities.first { $0.name == "Client" })
        let projet = try #require(model.entities.first { $0.name == "Projet" })
        let salarie = try #require(model.entities.first { $0.name == "Salarie" })
        #expect(client.position.x < projet.position.x)
        #expect(client.position.y < salarie.position.y)
    }

    @Test("Un fichier qui n'est pas un .loo est refusé proprement")
    func refus() {
        #expect(throws: LooImporter.Failure.self) { try LooImporter.model(from: Data("bonjour".utf8)) }
    }
}
