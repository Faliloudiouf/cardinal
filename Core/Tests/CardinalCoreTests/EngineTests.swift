import Testing
import Foundation
#if SWIFT_PACKAGE
@testable import CardinalCore
#else
@testable import Cardinal
#endif

@Suite("Passage MCD → MLD → SQL")
struct EngineTests {
    let tables = MLDBuilder.build(.exemple)

    @Test("Une association 1,1 fait migrer la clé vers l'entité")
    func cleMigreVersLEntite() throws {
        let commande = try #require(tables.first { $0.name == "Commande" })
        let fk = try #require(commande.columns.first { $0.name == "id_client" })
        #expect(fk.reference?.table == "Client")
        #expect(fk.isNullable == false)
        #expect(!tables.contains { $0.name == "Passer" })
    }

    @Test("Une association N,N devient une table à clé composée")
    func associationNNDevientTable() throws {
        let contenir = try #require(tables.first { $0.name == "Contenir" })
        #expect(contenir.primaryKey.map(\.name) == ["num_commande", "ref_produit"])
        #expect(contenir.columns.contains { $0.name == "quantite" && !$0.isPrimaryKey })
    }

    @Test("Les tables référencées sont créées en premier")
    func ordreDeCreation() throws {
        let sql = SQLGenerator.script(for: tables, dialect: .mysql)
        let client = try #require(sql.range(of: "CREATE TABLE Client ("))
        let commande = try #require(sql.range(of: "CREATE TABLE Commande ("))
        let contenir = try #require(sql.range(of: "CREATE TABLE Contenir ("))
        #expect(client.lowerBound < commande.lowerBound)
        #expect(commande.lowerBound < contenir.lowerBound)
        #expect(sql.contains("FOREIGN KEY (id_client) REFERENCES Client (id_client)"))
    }

    @Test("Chaque SGBD reçoit ses propres types", arguments: [
        (SQLDialect.oracle, "VARCHAR2(60)"),
        (SQLDialect.sqlserver, "VARCHAR(60)"),
        (SQLDialect.postgresql, "VARCHAR(60)"),
        (SQLDialect.sqlite, "TEXT"),
    ])
    func typesParSGBD(dialect: SQLDialect, expected: String) {
        let sql = SQLGenerator.script(for: tables, dialect: dialect)
        #expect(sql.contains("nom \(expected)"))
    }

    @Test("Association réflexive : deux colonnes distinctes")
    func associationReflexive() throws {
        var model = MCDModel()
        let personne = Entity(name: "Personne", attributes: [Attribute(name: "id", type: .entier, isIdentifier: true)], position: .zero)
        model.entities = [personne]
        model.associations = [Association(name: "Parent de", legs: [Leg(entityID: personne.id), Leg(entityID: personne.id)], position: .zero)]
        let table = try #require(MLDBuilder.build(model).first { $0.name == "Parent_de" })
        #expect(table.primaryKey.map(\.name) == ["id", "id_2"])
    }

    @Test("Noms SQL sans accents ni espaces")
    func identifiantsSQL() {
        #expect("Numéro de commande".sqlIdentifier == "Numero_de_commande")
        #expect("  Élève  ".sqlIdentifier == "Eleve")
        #expect("2023".sqlIdentifier == "t_2023")
    }

    @Test("Le fichier .mcd se relit à l'identique")
    func allerRetourJSON() throws {
        let data = try ModelFile.encode(.exemple)
        let decoded = try JSONDecoder().decode(MCDModel.self, from: data)
        #expect(decoded.entities.map(\.name) == ["Client", "Commande", "Produit"])
        #expect(decoded.associations.first?.legs.count == 2)
    }

    @Test("Le validateur signale une entité sans identifiant")
    func validation() {
        var model = MCDModel()
        model.entities = [Entity(name: "Livre", attributes: [Attribute(name: "titre")], position: .zero)]
        #expect(Validator.check(model).contains { $0.message.contains("pas d'identifiant") })
        #expect(Validator.check(.exemple).isEmpty)
    }
}
