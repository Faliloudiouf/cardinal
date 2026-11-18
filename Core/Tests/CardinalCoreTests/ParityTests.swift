import Testing
import Foundation
#if SWIFT_PACKAGE
@testable import CardinalCore
#else
@testable import Cardinal
#endif

@Suite("Parité Looping : héritage, CIF, identifiant relatif, rétroconception")
struct ParityTests {
    let model = MCDModel.exempleScolarite
    var tables: [MLDTable] { MLDBuilder.build(model) }

    func table(_ name: String) throws -> MLDTable {
        try #require(tables.first { $0.name == name }, "table \(name) absente")
    }

    @Test("Héritage : la clé du sous-type est la clé du surtype")
    func heritageTableParType() throws {
        let etudiant = try table("Etudiant")
        #expect(etudiant.primaryKey.map(\.name) == ["id_personne"])
        #expect(etudiant.primaryKey.first?.reference?.table == "Personne")
        #expect(etudiant.columns.contains { $0.name == "matricule" && $0.isUnique && !$0.isNullable })
    }

    @Test("Héritage : surtype seul avec discriminant")
    func heritageSurtypeSeul() throws {
        var model = model
        model.inheritances[0].strategy = .surtypeSeul
        let tables = MLDBuilder.build(model)
        #expect(!tables.contains { $0.name == "Etudiant" })
        let personne = try #require(tables.first { $0.name == "Personne" })
        #expect(personne.columns.contains { $0.name == "matricule" && $0.isNullable })
        #expect(personne.columns.contains { $0.name == "type_Personne" && !$0.isNullable })
    }

    @Test("Héritage : sous-types seuls, propriétés migrées")
    func heritageSousTypesSeuls() throws {
        var model = model
        model.inheritances[0].strategy = .sousTypesSeuls
        let tables = MLDBuilder.build(model)
        #expect(!tables.contains { $0.name == "Personne" })
        let enseignant = try #require(tables.first { $0.name == "Enseignant" })
        #expect(enseignant.columns.map(\.name).starts(with: ["id_personne", "nom", "email"]))
    }

    @Test("Identifiant relatif : la clé du bâtiment entre dans la clé de la salle")
    func identifiantRelatif() throws {
        let salle = try table("Salle")
        #expect(Set(salle.primaryKey.map(\.name)) == ["num_salle", "id_batiment"])
        #expect(salle.columns.first { $0.name == "id_batiment" }?.reference?.table == "Batiment")
    }

    @Test("CIF : l'entité cible sort de la clé primaire de l'association")
    func cif() throws {
        let enseigner = try table("Enseigner")
        #expect(Set(enseigner.primaryKey.map(\.name)) == ["code_classe", "code_matiere"])
        let fk = try #require(enseigner.columns.first { $0.name == "id_personne" })
        #expect(!fk.isPrimaryKey && !fk.isNullable)
    }

    @Test("Entité fictive : pas de table, mais sa clé migre")
    func entiteFictive() throws {
        var model = MCDModel()
        let date = Entity(name: "Date", attributes: [Attribute(name: "jour", type: .date, isIdentifier: true)], position: .zero, isFictive: true)
        let medecin = Entity(name: "Medecin", attributes: [Attribute(name: "id_medecin", type: .entier, isIdentifier: true)], position: .zero)
        let patient = Entity(name: "Patient", attributes: [Attribute(name: "id_patient", type: .entier, isIdentifier: true)], position: .zero)
        model.entities = [date, medecin, patient]
        model.associations = [Association(name: "Consulter", legs: [Leg(entityID: date.id), Leg(entityID: medecin.id), Leg(entityID: patient.id)], position: .zero)]
        let tables = MLDBuilder.build(model)
        #expect(!tables.contains { $0.name == "Date" })
        let consulter = try #require(tables.first { $0.name == "Consulter" })
        let jour = try #require(consulter.columns.first { $0.name == "jour" })
        #expect(jour.isPrimaryKey && jour.reference == nil)
    }

    @Test("Conventions de nommage")
    func nommage() {
        #expect(NamingConvention.snake.apply("Numéro Commande") == "numero_commande")
        #expect(NamingConvention.camel.apply("numero_de_commande") == "numeroDeCommande")
        #expect(NamingConvention.pascal.apply("ligne commande") == "LigneCommande")
        #expect(NamingConvention.majuscules.apply("Client") == "CLIENT")
    }

    @Test("Clés étrangères en ALTER TABLE et code SQL des règles")
    func alterTableEtRegles() {
        var model = model
        model.settings.foreignKeysAtEnd = true
        let sql = SQLGenerator.script(for: model, dialect: .postgresql)
        #expect(sql.contains("ALTER TABLE Etudiant ADD CONSTRAINT fk_Etudiant_id_personne FOREIGN KEY (id_personne) REFERENCES Personne (id_personne);"))
        #expect(sql.contains("CHECK (volume_horaire > 0)"))
        #expect(sql.contains("CONSTRAINT uq_Personne_email UNIQUE (email)"))
    }

    @Test("Export XML du MLD")
    func xml() {
        let xml = MLDXMLExporter.xml(tables)
        #expect(xml.hasPrefix("<?xml"))
        #expect(xml.contains("<table nom=\"Salle\""))
        #expect(xml.contains("reference=\"Batiment.id_batiment\""))
    }

    @Test("Rétroconception : le SQL généré redonne le même MCD")
    func allerRetourSQL() throws {
        let sql = SQLGenerator.script(for: .exemple, dialect: .mysql)
        let rebuilt = try ReverseEngineer.model(from: sql)
        #expect(Set(rebuilt.entities.map(\.name)) == ["Client", "Commande", "Produit"])
        let contenir = try #require(rebuilt.associations.first { $0.name == "Contenir" })
        #expect(contenir.legs.count == 2)
        #expect(contenir.attributes.map(\.name) == ["quantite"])
        let passer = try #require(rebuilt.associations.first { $0.legs.contains { $0.cardinality == .oneOne } })
        #expect(rebuilt.entity(passer.legs[0].entityID)?.name == "Commande")
        // Le MLD reconstruit est identique à l'original.
        #expect(MLDBuilder.build(rebuilt).map(\.name).sorted() == MLDBuilder.build(.exemple).map(\.name).sorted())
    }

    @Test("Rétroconception : héritage, identifiant relatif et CIF reconnus")
    func retroconceptionAvancee() throws {
        let rebuilt = try ReverseEngineer.model(from: SQLGenerator.script(for: model, dialect: .postgresql))
        #expect(rebuilt.inheritances.count == 1)
        #expect(rebuilt.associations.contains { $0.legs.contains(where: \.isRelative) })
        #expect(rebuilt.constraints.contains { $0.kind == .cif })
        #expect(Set(MLDBuilder.build(rebuilt).map(\.name)) == Set(tables.map(\.name)))
    }

    @Test("Rétroconception : syntaxes variées (backticks, REFERENCES en ligne, commentaires)")
    func syntaxesVariees() throws {
        let sql = """
        -- commentaire
        CREATE TABLE IF NOT EXISTS `auteur` (
          `id` INT NOT NULL AUTO_INCREMENT PRIMARY KEY,
          `nom` VARCHAR(80) NOT NULL /* bloc */
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
        CREATE TABLE livre (
          isbn CHAR(13) PRIMARY KEY,
          titre TEXT,
          prix NUMERIC(8,2),
          auteur_id INT REFERENCES auteur(id)
        );
        """
        let rebuilt = try ReverseEngineer.model(from: sql)
        let livre = try #require(rebuilt.entities.first { $0.name == "livre" })
        #expect(livre.attributes.first { $0.name == "isbn" }?.isIdentifier == true)
        #expect(livre.attributes.first { $0.name == "prix" }?.type == .decimal)
        #expect(livre.attributes.first { $0.name == "isbn" }?.length == 13)
        let lien = try #require(rebuilt.associations.first)
        #expect(lien.legs.map(\.cardinality) == [.zeroOne, .zeroMany])
    }

    @Test("Copier-coller : nouveaux identifiants, liens internes conservés")
    func copierColler() {
        var model = MCDModel.exemple
        let refs: Set<NodeRef> = [.entity(model.entities[0].id), .entity(model.entities[1].id), .association(model.associations[0].id)]
        let added = model.paste(model.subset(refs))
        #expect(added.count == 3)
        #expect(model.entities.count == 5)
        let copy = model.associations.last!
        #expect(copy.legs.count == 2)
        #expect(copy.legs.allSatisfy { leg in added.contains(.entity(leg.entityID)) })
    }

    @Test("Les anciens fichiers .mcd (version 1) restent lisibles")
    func compatibilite() throws {
        let legacy = """
        {"version":1,"entities":[{"id":"6F1E2B3C-0000-4000-8000-000000000001","name":"Client","position":[100,100],
        "attributes":[{"id":"6F1E2B3C-0000-4000-8000-000000000002","name":"id","type":"entier","length":50,"isIdentifier":true}]}],
        "associations":[]}
        """
        let model = try JSONDecoder().decode(MCDModel.self, from: Data(legacy.utf8))
        #expect(model.entities.first?.isFictive == false)
        #expect(model.inheritances.isEmpty)
        #expect(model.settings.showTypes)
    }

    @Test("Le validateur accepte l'exemple Scolarité")
    func validation() {
        #expect(Validator.check(model).isEmpty, "\(Validator.check(model).map(\.message))")
    }
}
