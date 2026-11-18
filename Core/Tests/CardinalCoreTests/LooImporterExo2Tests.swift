import Testing
import Foundation
#if SWIFT_PACKAGE
@testable import CardinalCore
#else
@testable import Cardinal
#endif

/// Second fichier Looping réel (exercice de cours), organisé autrement que le premier :
/// numéros de textes des liaisons rangés en ordre décroissant, multiplicités UML stockées
/// à la place des rôles, indicateur de propriété à 1 sur des propriétés qui ne sont pas des identifiants.
/// Le fichier n'est pas publié avec le code : le test ne s'exécute que s'il est présent.
@Suite("Lecture d'un second fichier Looping (exo2)")
struct LooImporterExo2Tests {
    static let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/exo2.loo")

    func legs(_ model: MCDModel, _ name: String) -> [String] {
        (model.associations.first { $0.name == name }?.legs ?? []).map { "\(model.entity($0.entityID)?.name ?? "?") \($0.cardinality.rawValue)" }
    }

    @Test("Les 16 pattes, avec les cardinalités de Looping", .enabled(if: FileManager.default.fileExists(atPath: url.path)))
    func pattes() throws {
        let model = try LooImporter.model(from: Data(contentsOf: Self.url))
        #expect(legs(model, "commande") == ["clients 1,N", "projets 0,N"])
        #expect(legs(model, "composer") == ["projets 0,N", "taches 0,N"])
        #expect(legs(model, "realiser") == ["taches 1,N", "salarie 1,N"])
        #expect(legs(model, "utiliser") == ["salarie 0,N", "materiels 0,N"])
        #expect(legs(model, "rattacher") == ["salarie 0,N", "division 0,N"])
        #expect(legs(model, "regrouper") == ["salarie 0,N", "equipe 0,N"])
        #expect(legs(model, "coordonner") == ["projets 1,1", "salarie 0,N"])
        #expect(legs(model, "estcompose") == ["materiels 0,N", "materiels 0,N"])
        #expect(model.associations.flatMap(\.legs).allSatisfy { $0.role.isEmpty })
    }

    @Test("Seuls les identifiants de Looping sont des identifiants", .enabled(if: FileManager.default.fileExists(atPath: url.path)))
    func identifiants() throws {
        let model = try LooImporter.model(from: Data(contentsOf: Self.url))
        let clients = try #require(model.entities.first { $0.name == "clients" })
        #expect(clients.attributes.map(\.name) == ["id_client", "prenom", "adresse", "nom", "matricule"])
        #expect(clients.attributes.map(\.isIdentifier) == [true, false, false, false, false])
        #expect(model.entities.allSatisfy { $0.name == $0.name.trimmingCharacters(in: .whitespaces) })
    }

    @Test("Multiplicités UML : jamais prises pour des rôles")
    func multiplicites() {
        for texte in ["*", "1", "0..1", "1..*", "2..5", " 1..* "] { #expect(LooImporter.isMultiplicity(texte), "\(texte)") }
        for texte in ["EtreCompose", "Etrecompose", "chef", "", "1..", "..*", "a..b"] { #expect(!LooImporter.isMultiplicity(texte), "\(texte)") }
    }
}
