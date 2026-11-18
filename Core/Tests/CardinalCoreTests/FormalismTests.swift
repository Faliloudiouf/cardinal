import Testing
import Foundation
#if canImport(SQLite3)
import SQLite3
#endif
#if SWIFT_PACKAGE
@testable import CardinalCore
#else
@testable import Cardinal
#endif

// MARK: - Outils de test

/// Construit un MCD en une ligne par élément.
struct MCDBuilder {
    var model = MCDModel()

    @discardableResult
    mutating func entity(_ name: String, ids: [String]? = nil, attrs: [String] = [], fictive: Bool = false) -> UUID {
        let identifiers = (ids ?? ["id_\(name.lowercased())"]).map { Attribute(name: $0, type: .entier, isIdentifier: true) }
        let entity = Entity(name: name, attributes: identifiers + attrs.map { Attribute(name: $0, type: .varchar) },
                            position: .zero, isFictive: fictive)
        model.entities.append(entity)
        return entity.id
    }

    @discardableResult
    mutating func association(_ name: String, _ legs: [(UUID, Cardinality)], attrs: [String] = [],
                              relative: UUID? = nil, roles: [String] = []) -> UUID {
        let association = Association(
            name: name,
            attributes: attrs.map { Attribute(name: $0, type: .entier) },
            legs: legs.enumerated().map { index, leg in
                Leg(entityID: leg.0, cardinality: leg.1, isRelative: leg.0 == relative && leg.1.isMaxOne,
                    role: index < roles.count ? roles[index] : "")
            },
            position: .zero
        )
        model.associations.append(association)
        return association.id
    }

    var tables: [MLDTable] { MLDBuilder.build(model) }

    func table(_ name: String) throws -> MLDTable {
        try #require(tables.first { $0.name == name }, "table \(name) absente : \(tables.map(\.name))")
    }
}

/// Exécute un script dans une vraie base SQLite en mémoire, clés étrangères activées.
/// Renvoie le message d'erreur de SQLite, ou nil si tout s'est exécuté.
func runSQLite(_ script: String, then extra: String? = nil) -> String? {
    #if canImport(SQLite3)
    var database: OpaquePointer?
    guard sqlite3_open(":memory:", &database) == SQLITE_OK else { return "ouverture impossible" }
    defer { sqlite3_close(database) }
    sqlite3_exec(database, "PRAGMA foreign_keys = ON;", nil, nil, nil)
    for sql in [script] + (extra.map { [$0] } ?? []) {
        var error: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(database, sql, nil, nil, &error) != SQLITE_OK {
            let message = error.map { String(cString: $0) } ?? "erreur inconnue"
            sqlite3_free(error)
            return message
        }
    }
    return nil
    #else
    return "SQLite indisponible sur ce système"
    #endif
}

/// Colonnes d'une table sous forme lisible : _pk, #fk, ?nullable.
func shape(_ table: MLDTable) -> [String] {
    table.columns.map { column in
        (column.isPrimaryKey ? "_" : "") + (column.reference != nil ? "#" : "") + column.name + (column.isNullable ? "?" : "")
    }
}

// MARK: - Comparaison avec Looping

@Suite("Mêmes résultats que Looping (fichier réel)")
struct LoopingComparisonTests {
    /// MLD affiché par Looping 4.1 pour LoopingEntrepriseServices2.loo (capture d'écran),
    /// recopié tel quel : clé primaire soulignée = « _ », clé étrangère = « # ».
    static let loopingMLD: [String: [String]] = [
        "Client": ["_Identifiant du client", "Nom du client", "Prenom du client"],
        "Materiel": ["_identifiant du matériel", "Nom du matériel", "groupe matériel appartenant", "#identifiant du matériel_Etrecompose"],
        "Equipe": ["_identifiant de l'équipe", "nom de l'équipe"],
        "Division": ["_identifiant de la division", "nom de la division"],
        "Salarie": ["_identifiant salarié", "nom du salarié", "etre_chefprojet", "prenom du salarié", "#identifiant de la division"],
        "Projet": ["_identifiant du projet", "Nom du projet", "#identifiant salarié", "#Identifiant du client"],
        "Tache": ["_identifiant de la tache", "cout de la tache", "nom de la tache", "#identifiant du projet"],
        "Utiliser": ["_#identifiant du matériel", "_#identifiant salarié"],
        "Realiser": ["_#identifiant de la tache", "_#identifiant salarié", "Date de début de la tache", "Date de fin de la tâche"],
        "EtreRegroupe": ["_#identifiant de l'équipe", "_#identifiant salarié"],
    ]

    let model: MCDModel

    init() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/LoopingEntrepriseServices2.loo")
        var model = try LooImporter.model(from: Data(contentsOf: url))
        model.settings.useLabels = true // Looping nomme les colonnes avec les libellés
        self.model = model
    }

    /// Noms Looping ramenés à des identifiants SQL valides (espaces et accents), comme le fait Cardinal.
    static func normalized(_ column: String) -> String {
        var prefix = ""
        var name = Substring(column)
        while let first = name.first, first == "_" || first == "#" { prefix.append(first); name = name.dropFirst() }
        return prefix + String(name).sqlIdentifier
    }

    @Test("Mêmes tables que Looping")
    func memesTables() {
        #expect(Set(MLDBuilder.build(model).map(\.name)) == Set(Self.loopingMLD.keys))
    }

    @Test("Mêmes colonnes, clés primaires et clés étrangères que Looping, table par table",
          arguments: Array(loopingMLD.keys).sorted())
    func memesColonnes(table name: String) throws {
        let table = try #require(MLDBuilder.build(model).first { $0.name == name })
        let cardinal = Set(table.columns.map { ($0.isPrimaryKey ? "_" : "") + ($0.reference != nil ? "#" : "") + $0.name })
        let looping = Set(Self.loopingMLD[name]!.map(Self.normalized))
        #expect(cardinal == looping)
    }

    @Test("NOT NULL comme dans le script de Looping")
    func nullabilite() throws {
        let tables = MLDBuilder.build(model)
        // Looping : « identifiant de la division VARCHAR(50) NOT NULL » (Salarie 1,1 EtreRattache).
        let salarie = try #require(tables.first { $0.name == "Salarie" })
        #expect(salarie.columns.first { $0.name == "identifiant_de_la_division" }?.isNullable == false)
        // Looping : « #identifiant du matériel_Etrecompose* » (patte 0,1 : valeur facultative).
        let materiel = try #require(tables.first { $0.name == "Materiel" })
        #expect(materiel.columns.first { $0.reference != nil }?.isNullable == true)
    }

    @Test("Mêmes types que Looping : VARCHAR(50), LOGICAL, DECIMAL(15,2), DATE")
    func types() throws {
        let tables = MLDBuilder.build(model)
        let tache = try #require(tables.first { $0.name == "Tache" })
        #expect(tache.columns.first { $0.name == "cout_de_la_tache" }.map { SQLGenerator.sqlType($0, dialect: .mysql) } == "DECIMAL(15,2)")
        #expect(tache.columns.first { $0.name == "identifiant_de_la_tache" }.map { SQLGenerator.sqlType($0, dialect: .mysql) } == "VARCHAR(50)")
        let realiser = try #require(tables.first { $0.name == "Realiser" })
        #expect(realiser.columns.first { $0.name.hasPrefix("Date_de_debut") }?.type == .date)
        let salarie = try #require(tables.first { $0.name == "Salarie" })
        #expect(salarie.columns.first { $0.name == "etre_chefprojet" }?.type == .booleen)
    }

    @Test("Le script complet s'exécute dans une vraie base SQLite")
    func executionSQLite() {
        let script = SQLGenerator.script(for: model, dialect: .sqlite)
        #expect(runSQLite(script) == nil, "\(runSQLite(script) ?? "")")
    }
}

// MARK: - Règles MCD → MLD, cas par cas

@Suite("MCD → MLD : tous les cas de cardinalités")
struct MLDCasesTests {
    @Test("Binaire : la clé migre côté max 1, NOT NULL si 1,1, facultative si 0,1",
          arguments: [
              (Cardinality.oneOne, Cardinality.zeroMany, false),
              (.oneOne, .oneMany, false),
              (.zeroOne, .zeroMany, true),
              (.zeroOne, .oneMany, true),
          ])
    func binaireUnN(child: Cardinality, parent: Cardinality, nullable: Bool) throws {
        var b = MCDBuilder()
        let a = b.entity("A")
        let p = b.entity("P")
        b.association("Lier", [(a, child), (p, parent)])
        #expect(b.tables.map(\.name) == ["A", "P"])
        #expect(shape(try b.table("A")) == ["_id_a", "#id_p" + (nullable ? "?" : "")])
    }

    @Test("Binaire N,N : nouvelle table, clé composée des deux clés",
          arguments: [(Cardinality.zeroMany, Cardinality.zeroMany), (.oneMany, .zeroMany), (.oneMany, .oneMany)])
    func binaireNN(left: Cardinality, right: Cardinality) throws {
        var b = MCDBuilder()
        let a = b.entity("A")
        let c = b.entity("C")
        b.association("Lier", [(a, left), (c, right)], attrs: ["qte"])
        #expect(shape(try b.table("Lier")) == ["_#id_a", "_#id_c", "qte?"])
    }

    @Test("Binaire 1-1 : clé étrangère unique, du côté de la première patte max 1",
          arguments: [(Cardinality.oneOne, Cardinality.oneOne), (.oneOne, .zeroOne), (.zeroOne, .zeroOne)])
    func unUn(left: Cardinality, right: Cardinality) throws {
        var b = MCDBuilder()
        let a = b.entity("A")
        let c = b.entity("C")
        b.association("Lier", [(a, left), (c, right)])
        let fk = try #require(try b.table("A").columns.first { $0.reference != nil })
        #expect(fk.isUnique)
        #expect(fk.isNullable == (left != .oneOne))
        #expect(try b.table("C").columns.allSatisfy { $0.reference == nil })
    }

    @Test("Attribut d'une association 1,N : il migre avec la clé")
    func attributMigre() throws {
        var b = MCDBuilder()
        let a = b.entity("Commande")
        let c = b.entity("Client")
        b.association("Passer", [(a, .oneOne), (c, .zeroMany)], attrs: ["date_passage"])
        #expect(shape(try b.table("Commande")) == ["_id_commande", "#id_client", "date_passage?"])
    }

    @Test("Ternaire : table à clé composée des trois clés")
    func ternaire() throws {
        var b = MCDBuilder()
        let x = b.entity("X")
        let y = b.entity("Y")
        let z = b.entity("Z")
        b.association("Relier", [(x, .zeroMany), (y, .oneMany), (z, .zeroMany)])
        #expect(shape(try b.table("Relier")) == ["_#id_x", "_#id_y", "_#id_z"])
    }

    @Test("Ternaire avec CIF : l'entité cible sort de la clé primaire")
    func ternaireCIF() throws {
        var b = MCDBuilder()
        let classe = b.entity("Classe")
        let matiere = b.entity("Matiere")
        let prof = b.entity("Prof")
        let enseigner = b.association("Enseigner", [(classe, .oneMany), (matiere, .oneMany), (prof, .zeroMany)])
        b.model.constraints = [Constraint(kind: .cif, links: [
            ConstraintLink(target: .association(enseigner)), ConstraintLink(target: .entity(prof), isTarget: true),
        ], position: .zero)]
        #expect(shape(try b.table("Enseigner")) == ["_#id_classe", "_#id_matiere", "#id_prof"])
    }

    @Test("Réflexive N,N : deux colonnes distinctes, les rôles servent de suffixe")
    func reflexiveNN() throws {
        var b = MCDBuilder()
        let p = b.entity("Personne")
        b.association("Connaitre", [(p, .zeroMany), (p, .zeroMany)])
        #expect(shape(try b.table("Connaitre")) == ["_#id_personne", "_#id_personne_2"])

        var r = MCDBuilder()
        let q = r.entity("Personne")
        r.association("Encadrer", [(q, .zeroMany), (q, .zeroMany)], roles: ["chef", "membre"])
        #expect(shape(try r.table("Encadrer")) == ["_#id_personne_chef", "_#id_personne_membre"])
    }

    @Test("Réflexive 0,1 / 0,N : clé étrangère vers la même table, suffixée par le rôle")
    func reflexiveUnN() throws {
        var b = MCDBuilder()
        let m = b.entity("Materiel")
        b.association("Composer", [(m, .zeroMany), (m, .zeroOne)], roles: ["compose", "composant"])
        let table = try b.table("Materiel")
        #expect(shape(table) == ["_id_materiel", "#id_materiel_compose?"])
        #expect(table.columns.last?.reference?.table == "Materiel")
    }

    @Test("Identifiant relatif, y compris en chaîne (Bâtiment ← Salle ← Place)")
    func identifiantRelatifEnChaine() throws {
        var b = MCDBuilder()
        let batiment = b.entity("Batiment", ids: ["num_bat"])
        let salle = b.entity("Salle", ids: ["num_salle"])
        let place = b.entity("Place", ids: ["num_place"])
        b.association("Situer", [(salle, .oneOne), (batiment, .oneMany)], relative: salle)
        b.association("Contenir", [(place, .oneOne), (salle, .oneMany)], relative: place)
        #expect(shape(try b.table("Salle")) == ["_num_salle", "_#num_bat"])
        #expect(shape(try b.table("Place")) == ["_num_place", "_#num_salle", "_#num_bat"])
        // La clé étrangère composée de Place référence les deux colonnes de la clé de Salle.
        let place2 = try b.table("Place")
        #expect(Set(place2.columns.compactMap { $0.reference?.table }) == ["Salle"])
    }

    @Test("Entité fictive : pas de table, sa clé entre dans l'association sans clé étrangère")
    func fictive() throws {
        var b = MCDBuilder()
        let date = b.entity("Date", ids: ["jour"], fictive: true)
        let medecin = b.entity("Medecin")
        let patient = b.entity("Patient")
        b.association("Consulter", [(date, .zeroMany), (medecin, .zeroMany), (patient, .zeroMany)])
        #expect(!b.tables.contains { $0.name == "Date" })
        #expect(shape(try b.table("Consulter")) == ["_jour", "_#id_medecin", "_#id_patient"])
    }

    @Test("Identifiant composé : la clé étrangère reprend toutes les colonnes dans une seule contrainte")
    func identifiantCompose() throws {
        var b = MCDBuilder()
        let vol = b.entity("Vol", ids: ["num_vol", "date_vol"])
        let billet = b.entity("Billet")
        b.association("Concerner", [(billet, .oneOne), (vol, .zeroMany)])
        #expect(shape(try b.table("Billet")) == ["_id_billet", "#num_vol", "#date_vol"])
        let sql = SQLGenerator.script(for: b.model, dialect: .postgresql)
        #expect(sql.contains("FOREIGN KEY (num_vol, date_vol) REFERENCES Vol (num_vol, date_vol)"))
    }

    @Test("Héritage : un sous-type relié à une association reçoit la clé étrangère")
    func heritageEtAssociation() throws {
        var b = MCDBuilder()
        let personne = b.entity("Personne")
        let etudiant = b.entity("Etudiant", ids: [])
        let classe = b.entity("Classe")
        b.model.inheritances = [Inheritance(parentID: personne, childIDs: [etudiant], position: .zero)]
        b.association("Appartenir", [(etudiant, .oneOne), (classe, .zeroMany)])
        #expect(shape(try b.table("Etudiant")) == ["_#id_personne", "#id_classe"])
    }

    @Test("Conventions de nommage : les clés étrangères pointent vers les bons noms",
          arguments: NamingConvention.allCases)
    func nommageCoherent(naming: NamingConvention) throws {
        var b = MCDBuilder()
        let a = b.entity("Ligne Commande", ids: ["num ligne"])
        let p = b.entity("Produit Fini", ids: ["ref produit"])
        b.association("Concerner", [(a, .oneOne), (p, .zeroMany)])
        b.model.settings.naming = naming
        let tables = b.tables
        for table in tables {
            for column in table.columns {
                guard let reference = column.reference else { continue }
                let target = try #require(tables.first { $0.name == reference.table })
                #expect(target.primaryKey.contains { $0.name == reference.column })
            }
        }
        #expect(runSQLite(SQLGenerator.script(for: b.model, dialect: .sqlite)) == nil)
    }
}

// MARK: - Exécution réelle du SQL

@Suite("SQL : exécution réelle dans SQLite")
struct SQLExecutionTests {
    static let models: [(String, MCDModel)] = {
        var list: [(String, MCDModel)] = [("Commandes", .exemple), ("Scolarité", .exempleScolarite)]
        var reflexive = MCDBuilder()
        let m = reflexive.entity("Materiel")
        reflexive.association("Composer", [(m, .zeroMany), (m, .zeroOne)], roles: ["compose", "composant"])
        list.append(("Réflexive", reflexive.model))
        var chain = MCDBuilder()
        let bat = chain.entity("Batiment", ids: ["num_bat"])
        let salle = chain.entity("Salle", ids: ["num_salle"])
        chain.association("Situer", [(salle, .oneOne), (bat, .oneMany)], relative: salle)
        list.append(("Identifiant relatif", chain.model))
        return list
    }()

    @Test("Le script s'exécute sans erreur", arguments: models.indices, [false, true])
    func execution(index: Int, alterAtEnd: Bool) {
        var model = Self.models[index].1
        model.settings.foreignKeysAtEnd = alterAtEnd
        let script = SQLGenerator.script(for: model, dialect: .sqlite)
        #expect(runSQLite(script) == nil, "\(Self.models[index].0) : \(runSQLite(script) ?? "")")
    }

    @Test("Les clés étrangères sont réellement appliquées par la base")
    func clesAppliquees() {
        let script = SQLGenerator.script(for: .exemple, dialect: .sqlite)
        // Une commande pour un client inexistant doit être refusée…
        let refus = runSQLite(script, then: "INSERT INTO Commande (num_commande, date_commande, id_client) VALUES (1, '2026-11-16', 99);")
        #expect(refus?.contains("FOREIGN KEY") == true)
        // … et acceptée quand le client existe.
        let accord = runSQLite(script, then: """
            INSERT INTO Client (id_client, nom) VALUES (99, 'Diop');
            INSERT INTO Commande (num_commande, date_commande, id_client) VALUES (1, '2026-11-16', 99);
            """)
        #expect(accord == nil)
    }

    @Test("NOT NULL et clé primaire sont appliqués")
    func contraintesAppliquees() {
        let script = SQLGenerator.script(for: .exemple, dialect: .sqlite)
        let sansClient = runSQLite(script, then: "INSERT INTO Commande (num_commande, date_commande) VALUES (1, '2026-11-16');")
        #expect(sansClient?.contains("NOT NULL") == true)
        let doublon = runSQLite(script, then: "INSERT INTO Client (id_client) VALUES (1); INSERT INTO Client (id_client) VALUES (1);")
        #expect(doublon?.contains("UNIQUE") == true)
    }

    @Test("Chaque SGBD reçoit une syntaxe qui lui est propre", arguments: SQLDialect.allCases)
    func syntaxeParSGBD(dialect: SQLDialect) {
        let sql = SQLGenerator.script(for: .exempleScolarite, dialect: dialect)
        #expect(sql.components(separatedBy: "CREATE TABLE").count - 1 == MLDBuilder.build(.exempleScolarite).count)
        #expect(sql.contains("ENGINE=InnoDB") == (dialect == .mysql || dialect == .mariadb))
        #expect(sql.contains("VARCHAR2") == (dialect == .oracle))
        // Textes ASCII : jamais de NVARCHAR (réservé aux textes Unicode, comme dans Looping).
        #expect(!sql.contains("NVARCHAR"))
        // Parenthèses équilibrées : pas d'instruction tronquée.
        #expect(sql.filter { $0 == "(" }.count == sql.filter { $0 == ")" }.count)
    }
}

// MARK: - Aller-retour SQL → MCD

@Suite("Rétroconception : aller-retour sur tous les cas")
struct RoundTripTests {
    @Test("SQL généré → MCD → même MLD", arguments: SQLExecutionTests.models.indices)
    func allerRetour(index: Int) throws {
        let model = SQLExecutionTests.models[index].1
        let original = MLDBuilder.build(model)
        let rebuilt = MLDBuilder.build(try ReverseEngineer.model(from: SQLGenerator.script(for: model, dialect: .postgresql)))
        #expect(Set(rebuilt.map(\.name)) == Set(original.map(\.name)))
        for table in original {
            let twin = try #require(rebuilt.first { $0.name == table.name })
            #expect(Set(twin.primaryKey.map(\.name)) == Set(table.primaryKey.map(\.name)), "clé de \(table.name)")
            #expect(Set(twin.columns.compactMap { $0.reference?.table }) == Set(table.columns.compactMap { $0.reference?.table }), "liens de \(table.name)")
        }
    }
}

// MARK: - UML

@Suite("UML : multiplicités")
struct UMLTests {
    @Test("Conversion Merise → UML", arguments: [
        (Cardinality.zeroOne, "0..1"), (.oneOne, "1"), (.zeroMany, "*"), (.oneMany, "1..*"),
    ])
    func conversion(cardinality: Cardinality, expected: String) {
        #expect(UMLLayout.multiplicity(cardinality) == expected)
    }

    @Test("Lecture croisée : Client (1,N) Commander (1,1) Projet")
    func lectureCroisee() {
        // Un client commande 1..* projets ; un projet est commandé par exactement 1 client.
        let ends = UMLLayout.binaryEnds(.oneMany, .oneOne)
        #expect(ends.nearFirst == "1")      // près de Client
        #expect(ends.nearSecond == "1..*")  // près de Projet
    }
}
