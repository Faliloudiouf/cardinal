import Testing
import Foundation
#if SWIFT_PACKAGE
@testable import CardinalCore
#else
@testable import Cardinal
#endif

// MARK: - Modèle d'essai : une propriété de chaque type

enum TypeFixtures {
    /// Une entité avec un compteur pour identifiant et une propriété de chaque autre type.
    static func allTypesModel() -> MCDModel {
        var attributes = [Attribute(name: "id", type: .compteur, isIdentifier: true)]
        for type in DataType.allCases where type != .compteur {
            var attribute = Attribute(name: "c_" + type.rawValue)
            attribute.setType(type)
            if type == .enumeration { attribute.enumValues = ["actif", "suspendu", "l'été"] }
            if type == .libre { attribute.customType = "CITEXT" }
            if type == .decimal { attribute.precision = 12; attribute.scale = 3 }
            attributes.append(attribute)
        }
        var model = MCDModel()
        model.entities = [Entity(name: "Tout", attributes: attributes, position: .zero)]
        return model
    }

    static func table(_ model: MCDModel = allTypesModel()) -> MLDTable { MLDBuilder.build(model)[0] }
}

// MARK: - Catalogue des types

@Suite("Types : catalogue comme Looping, plus les types modernes")
struct TypeCatalogTests {
    @Test("Les quatre familles de Looping et leurs types")
    func familles() {
        #expect(TypeCategory.texte.types.count == 9) // 3 jeux de caractères × 3 stockages
        #expect(Set(TypeCategory.numerique.types) == [.petitEntier, .entier, .grandEntier, .decimal, .reel, .monetaire, .compteur])
        #expect(Set(TypeCategory.dateHeure.types) == [.date, .heure, .dateHeure, .horodatage])
        #expect(Set(TypeCategory.autre.types) == [.booleen, .uuid, .json, .xml, .enumeration, .geometrique, .geographique, .libre])
        #expect(DataType.allCases.allSatisfy { !$0.label.isEmpty && !$0.help.isEmpty })
    }

    @Test("Texte : jeu de caractères × stockage donne le bon type, et inversement",
          arguments: TextEncoding.allCases)
    func texte(encoding: TextEncoding) {
        for storage in TextStorage.allCases {
            let type = DataType.text(encoding, storage)
            #expect(type.encoding == encoding)
            #expect(type.storage == storage)
            #expect(type.usesLength == (storage != .volumineux))
        }
    }

    @Test("Notation affichée sur les diagrammes", arguments: [
        (TypeSpec(kind: .varchar, length: 50), "VARCHAR(50)"),
        (TypeSpec(kind: .nchar, length: 2), "NCHAR(2)"),
        (TypeSpec(kind: .decimal, precision: 15, scale: 2), "DECIMAL(15,2)"),
        (TypeSpec(kind: .booleen), "LOGICAL"),
        (TypeSpec(kind: .compteur), "COUNTER"),
        (TypeSpec(kind: .enumeration, enumValues: ["a", "b"]), "ENUM(a,b)"),
        (TypeSpec(kind: .enumeration, enumValues: ["premiere_valeur", "deuxieme_valeur", "troisieme"]), "ENUM(3 valeurs)"),
        (TypeSpec(kind: .libre, custom: "citext"), "CITEXT"),
        (TypeSpec(kind: .libre), "LIBRE"),
    ])
    func affichage(spec: TypeSpec, expected: String) {
        #expect(spec.display == expected)
    }

    @Test("Changer de type garde des paramètres sensés")
    func changerDeType() {
        var attribute = Attribute(name: "nom", type: .varchar, length: 80, collation: "utf8mb4_bin")
        attribute.setType(.nvarchar)
        #expect(attribute.length == 80) // même stockage variable : la longueur est gardée
        attribute.setType(.nchar)
        #expect(attribute.length == 10) // stockage fixe : longueur par défaut
        attribute.setType(.entier)
        #expect(attribute.collation.isEmpty) // pas de collation sur un nombre
        attribute.setType(.enumeration)
        #expect(attribute.enumValues.count == 2) // jamais une énumération vide
    }

    @Test("Paramètres hors bornes ramenés à des valeurs valides", arguments: [
        (TypeSpec(kind: .varchar, length: 0), 1, 15, 2),
        (TypeSpec(kind: .varchar, length: -5), 1, 15, 2),
        (TypeSpec(kind: .char, length: 99_999), 8000, 15, 2),
        (TypeSpec(kind: .decimal, precision: 0, scale: 5), 50, 1, 1),
        (TypeSpec(kind: .decimal, precision: 80, scale: 60), 50, 38, 38),
        (TypeSpec(kind: .decimal, precision: 10, scale: -3), 50, 10, 0),
    ])
    func bornes(spec: TypeSpec, length: Int, precision: Int, scale: Int) {
        let normalized = spec.normalized
        #expect(normalized.length == length)
        #expect(normalized.precision == precision)
        #expect(normalized.scale == scale)
    }

    @Test("Valeurs d'énumération : blancs retirés, vides et doublons ignorés, ordre gardé")
    func valeursEnumeration() {
        #expect(TypeSpec.cleanValues([" actif ", "", "clos", "actif", "  "]) == ["actif", "clos"])
    }
}

// MARK: - Fichiers

@Suite("Types : lecture des fichiers")
struct TypeFileTests {
    @Test("Les anciens fichiers Cardinal restent lisibles (anciens noms de types)", arguments: [
        ("texteCourt", DataType.varchar), ("texteLong", .text), ("montant", .decimal), ("entier", .entier),
        ("reel", .reel), ("date", .date), ("dateHeure", .dateHeure), ("booleen", .booleen),
        ("type_qui_n_existe_pas", .varchar),
    ])
    func ancienFormat(raw: String, expected: DataType) throws {
        let json = #"{"name":"x","type":"\#(raw)","length":40}"#
        let attribute = try JSONDecoder().decode(Attribute.self, from: Data(json.utf8))
        #expect(attribute.type == expected)
        #expect(attribute.length == 40)
        #expect(attribute.precision == 15 && attribute.scale == 2) // ancien « montant » = DECIMAL(15,2)
    }

    @Test("Le fichier d'exemple enregistré avec l'ancien format s'ouvre, types traduits")
    func ancienFichierReel() throws {
        // Core/Tests/CardinalCoreTests → racine du projet.
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let url = root.appendingPathComponent("Exemples/gestion_commandes.mcd")
        let model = try JSONDecoder().decode(MCDModel.self, from: Data(contentsOf: url))
        #expect(!model.entities.isEmpty)
        let types = Set(model.entities.flatMap(\.attributes).map(\.type))
        #expect(!types.isEmpty)
        #expect(types.isSubset(of: [.entier, .varchar, .text, .decimal, .date, .dateHeure, .booleen, .reel]))
        #expect(runSQLite(SQLGenerator.script(for: model, dialect: .sqlite)) == nil)
    }

    @Test("Toutes les options d'une propriété survivent à l'enregistrement")
    func allerRetour() throws {
        let model = TypeFixtures.allTypesModel()
        var entity = model.entities[0]
        entity.attributes[1].collation = "utf8mb4_bin"
        entity.attributes[1].complement = "DEFAULT 'x'"
        entity.attributes[1].comment = "Commentaire avec « guillemets » et l'apostrophe"
        entity.attributes[1].label = "Nom logique"
        let data = try JSONEncoder().encode(entity)
        let decoded = try JSONDecoder().decode(Entity.self, from: data)
        #expect(decoded == entity)
    }
}

// MARK: - SQL

@Suite("Types : SQL généré pour chaque SGBD")
struct TypeSQLTests {
    @Test("Chaque type donne un script complet et bien formé, dans chaque SGBD", arguments: SQLDialect.allCases)
    func scriptBienForme(dialect: SQLDialect) {
        let sql = SQLGenerator.script(for: TypeFixtures.allTypesModel(), dialect: dialect)
        #expect(sql.filter { $0 == "(" }.count == sql.filter { $0 == ")" }.count)
        #expect(!sql.contains("()"))
        #expect(!sql.contains(",\n)"))
        #expect(!sql.contains(", ,"))
        for type in DataType.allCases {
            #expect(!SQLGenerator.sqlType(TypeSpec(kind: type), dialect: dialect).isEmpty, "\(type) vide en \(dialect.rawValue)")
        }
    }

    @Test("Table de correspondance : un type courant par SGBD", arguments: [
        (DataType.varchar, SQLDialect.mysql, "VARCHAR(50)"), (.varchar, .oracle, "VARCHAR2(50)"), (.varchar, .sqlserver, "VARCHAR(50)"),
        (.nvarchar, .sqlserver, "NVARCHAR(50)"), (.nvarchar, .oracle, "NVARCHAR2(50)"), (.nvarchar, .mysql, "VARCHAR(50) CHARACTER SET utf8mb4"),
        (.text, .sqlserver, "VARCHAR(MAX)"), (.ntext, .oracle, "NCLOB"), (.blob, .postgresql, "BYTEA"),
        (.entier, .oracle, "NUMBER(10)"), (.grandEntier, .postgresql, "BIGINT"), (.reel, .postgresql, "DOUBLE PRECISION"),
        (.monetaire, .sqlserver, "MONEY"), (.heure, .oracle, "INTERVAL DAY(0) TO SECOND(0)"),
        (.dateHeure, .sqlserver, "DATETIME2"), (.horodatage, .postgresql, "TIMESTAMPTZ"), (.horodatage, .sqlserver, "DATETIMEOFFSET"),
        (.booleen, .sqlserver, "BIT"), (.uuid, .sqlserver, "UNIQUEIDENTIFIER"), (.uuid, .postgresql, "UUID"),
        (.json, .postgresql, "JSONB"), (.xml, .oracle, "XMLTYPE"), (.geographique, .mysql, "GEOMETRY SRID 4326"),
    ])
    func correspondance(type: DataType, dialect: SQLDialect, expected: String) {
        #expect(SQLGenerator.sqlType(TypeSpec(kind: type), dialect: dialect) == expected)
    }

    @Test("Une longueur au-delà de la limite du SGBD bascule sur son type volumineux", arguments: [
        (DataType.varchar, 70_000, SQLDialect.mysql, "LONGTEXT"), (.varchar, 9000, .sqlserver, "VARCHAR(MAX)"),
        (.varchar, 5000, .oracle, "CLOB"), (.varchar, 70_000, .postgresql, "VARCHAR(70000)"),
        (.nvarchar, 4001, .sqlserver, "NVARCHAR(MAX)"), (.nvarchar, 2001, .oracle, "NCLOB"),
        (.char, 300, .mysql, "VARCHAR(300)"), (.char, 3000, .oracle, "VARCHAR2(3000)"),
        (.varbinary, 9000, .sqlserver, "VARBINARY(MAX)"), (.binary, 3000, .oracle, "BLOB"),
    ])
    func limites(type: DataType, length: Int, dialect: SQLDialect, expected: String) {
        #expect(SQLGenerator.sqlType(TypeSpec(kind: type, length: length), dialect: dialect) == expected)
    }

    @Test("Décimal : précision ramenée dans les bornes du SGBD")
    func decimal() {
        #expect(SQLGenerator.sqlType(TypeSpec(kind: .decimal, precision: 38, scale: 35), dialect: .mysql) == "DECIMAL(38,30)")
        #expect(SQLGenerator.sqlType(TypeSpec(kind: .decimal, precision: 12, scale: 3), dialect: .oracle) == "NUMBER(12,3)")
        #expect(SQLGenerator.sqlType(TypeSpec(kind: .decimal, precision: 0, scale: 9), dialect: .postgresql) == "NUMERIC(1,1)")
    }

    @Test("Énumération : contrôle CHECK partout (même MySQL), apostrophes doublées", arguments: SQLDialect.allCases)
    func enumeration(dialect: SQLDialect) {
        let sql = SQLGenerator.script(for: TypeFixtures.allTypesModel(), dialect: dialect)
        #expect(sql.contains("CHECK (c_enum IN ('actif', 'suspendu', 'l''été'))"))
        #expect(!sql.contains("ENUM("))
    }

    @Test("Compteur : numérotation automatique propre à chaque SGBD", arguments: [
        (SQLDialect.mysql, "id INT AUTO_INCREMENT NOT NULL"), (.mariadb, "id INT AUTO_INCREMENT NOT NULL"),
        (.postgresql, "id INTEGER GENERATED BY DEFAULT AS IDENTITY NOT NULL"),
        (.sqlserver, "id INT IDENTITY(1,1) NOT NULL"), (.oracle, "id NUMBER(10) GENERATED BY DEFAULT AS IDENTITY NOT NULL"),
        (.sqlite, "id INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL"),
    ])
    func compteur(dialect: SQLDialect, expected: String) {
        let sql = SQLGenerator.script(for: TypeFixtures.allTypesModel(), dialect: dialect)
        #expect(sql.contains(expected))
        if dialect == .sqlite { #expect(!sql.contains("CONSTRAINT pk_Tout")) } // la clé est déjà déclarée
    }

    @Test("Une clé étrangère vers un compteur est un simple entier", arguments: SQLDialect.allCases)
    func compteurEnCleEtrangere(dialect: SQLDialect) throws {
        var b = MCDBuilder()
        let client = b.entity("Client", ids: [])
        b.model.entities[0].attributes = [Attribute(name: "id_client", type: .compteur, isIdentifier: true)]
        let commande = b.entity("Commande", ids: ["num"])
        b.association("Passer", [(client, .zeroMany), (commande, .oneOne)])
        let commandeTable = try b.table("Commande")
        #expect(commandeTable.columns.first { $0.name == "id_client" }?.type == .entier)
        let sql = SQLGenerator.script(for: b.model, dialect: dialect)
        let marker = ["AUTO_INCREMENT", "IDENTITY", "AUTOINCREMENT"]
        let count = marker.map { sql.components(separatedBy: $0).count - 1 }.reduce(0, +)
        #expect(count == 1, "une seule numérotation automatique, dans Client")
    }

    @Test("Collation : syntaxe du SGBD, jamais sur un nombre, nettoyée", arguments: [
        (SQLDialect.mysql, "COLLATE utf8mb4_bin"), (.postgresql, "COLLATE \"utf8mb4_bin\""), (.sqlserver, "COLLATE utf8mb4_bin"),
    ])
    func collation(dialect: SQLDialect, expected: String) {
        #expect(SQLGenerator.collation(TypeSpec(kind: .varchar, collation: "utf8mb4_bin"), dialect: dialect) == expected)
        #expect(SQLGenerator.collation(TypeSpec(kind: .entier, collation: "utf8mb4_bin"), dialect: dialect) == nil)
        #expect(SQLGenerator.collation(TypeSpec(kind: .varchar, collation: "x; DROP TABLE t"), dialect: .mysql) == "COLLATE xDROPTABLEt")
    }

    @Test("Complément : point-virgule final retiré, rien ne casse le script")
    func complement() {
        #expect(SQLGenerator.complement("DEFAULT 0;") == "DEFAULT 0")
        #expect(SQLGenerator.complement("DEFAULT 1 ,\n") == "DEFAULT 1")
        #expect(SQLGenerator.complement("   ") == nil)
    }

    @Test("Commentaire : COMMENT en MySQL, COMMENT ON en PostgreSQL et Oracle, ligne -- ailleurs", arguments: SQLDialect.allCases)
    func commentaire(dialect: SQLDialect) {
        var model = TypeFixtures.allTypesModel()
        model.entities[0].attributes[1].comment = "Nom d'usage"
        let sql = SQLGenerator.script(for: model, dialect: dialect)
        switch dialect {
        case .mysql, .mariadb: #expect(sql.contains("COMMENT 'Nom d''usage'"))
        case .postgresql, .oracle: #expect(sql.contains("COMMENT ON COLUMN Tout.c_varchar IS 'Nom d''usage';"))
        case .sqlserver, .sqlite: #expect(sql.contains("-- Tout.c_varchar : Nom d'usage"))
        }
    }

    @Test("PostgreSQL : PostGIS activé seulement si un type géométrique est utilisé")
    func postgis() {
        #expect(SQLGenerator.script(for: TypeFixtures.allTypesModel(), dialect: .postgresql).contains("CREATE EXTENSION IF NOT EXISTS postgis;"))
        #expect(!SQLGenerator.script(for: .exemple, dialect: .postgresql).contains("postgis"))
    }
}

// MARK: - Exécution réelle

@Suite("Types : exécution réelle dans SQLite")
struct TypeExecutionTests {
    let script = SQLGenerator.script(for: TypeFixtures.allTypesModel(), dialect: .sqlite)

    @Test("La table avec tous les types est créée")
    func creation() {
        #expect(runSQLite(script) == nil)
    }

    @Test("Le compteur numérote tout seul")
    func compteur() {
        #expect(runSQLite(script, then: "INSERT INTO Tout (c_enum) VALUES ('actif'); INSERT INTO Tout (c_enum) VALUES ('clos');")?.contains("CHECK") == true)
        #expect(runSQLite(script, then: "INSERT INTO Tout (c_enum) VALUES ('actif'); INSERT INTO Tout (c_enum) VALUES ('l''été');") == nil)
    }

    @Test("Les contrôles refusent les mauvaises valeurs", arguments: [
        ("INSERT INTO Tout (c_enum) VALUES ('inconnu');", false),
        ("INSERT INTO Tout (c_enum) VALUES ('suspendu');", true),
        ("INSERT INTO Tout (c_boolean) VALUES (2);", false),
        ("INSERT INTO Tout (c_boolean) VALUES (1);", true),
        ("INSERT INTO Tout (c_json) VALUES ('{pas du json');", false),
        ("INSERT INTO Tout (c_json) VALUES ('{\"a\": 1}');", true),
        ("INSERT INTO Tout (c_json) VALUES (NULL);", true),
    ])
    func controles(insert: String, accepted: Bool) {
        let error = runSQLite(script, then: insert)
        #expect((error == nil) == accepted, "\(insert) → \(error ?? "accepté")")
    }

    @Test("Le complément DEFAULT s'applique vraiment")
    func complementDefault() {
        var model = TypeFixtures.allTypesModel()
        if let index = model.entities[0].attributes.firstIndex(where: { $0.type == .entier }) {
            model.entities[0].attributes[index].complement = "DEFAULT 7;"
        }
        let sql = SQLGenerator.script(for: model, dialect: .sqlite)
        // Une table de contrôle qui refuse toute valeur autre que 7.
        let verify = "INSERT INTO Tout (c_enum) VALUES ('actif'); CREATE TABLE verif (v INTEGER CHECK (v IS 7)); INSERT INTO verif SELECT c_int FROM Tout;"
        #expect(runSQLite(sql, then: verify) == nil)
        #expect(runSQLite(SQLGenerator.script(for: TypeFixtures.allTypesModel(), dialect: .sqlite), then: verify) != nil) // sans DEFAULT : NULL
    }

    @Test("Clé étrangère vers un compteur : le script complet s'exécute et la référence est vérifiée")
    func cleVersCompteur() {
        var b = MCDBuilder()
        let client = b.entity("Client", ids: [])
        b.model.entities[0].attributes = [Attribute(name: "id_client", type: .compteur, isIdentifier: true)]
        let commande = b.entity("Commande", ids: ["num"])
        b.association("Passer", [(client, .zeroMany), (commande, .oneOne)])
        let sql = SQLGenerator.script(for: b.model, dialect: .sqlite)
        #expect(runSQLite(sql, then: "INSERT INTO Client DEFAULT VALUES; INSERT INTO Commande (num, id_client) VALUES (1, 1);") == nil)
        #expect(runSQLite(sql, then: "INSERT INTO Commande (num, id_client) VALUES (1, 99);")?.contains("FOREIGN KEY") == true)
    }
}

// MARK: - Rétroconception

@Suite("Types : rétroconception")
struct TypeReverseTests {
    /// SQL Server distingue tous les types de Cardinal : l'aller-retour doit être exact.
    @Test("Aller-retour exact par SQL Server : type, longueur, précision, valeurs")
    func allerRetourSQLServer() throws {
        let model = TypeFixtures.allTypesModel()
        let sql = SQLGenerator.script(for: model, dialect: .sqlserver)
        let back = try ReverseEngineer.model(from: sql)
        let original = Dictionary(uniqueKeysWithValues: model.entities[0].attributes.map { ($0.name, $0.spec.normalized) })
        for attribute in try #require(back.entities.first).attributes {
            let expected = try #require(original[attribute.name])
            var got = attribute.spec.normalized
            // Paramètres sans objet pour le type : on ne compare que ceux qui comptent.
            if !got.kind.usesLength { got.length = expected.length }
            if !got.kind.usesPrecision { got.precision = expected.precision; got.scale = expected.scale }
            #expect(got.kind == expected.kind, "\(attribute.name)")
            #expect(got == expected, "\(attribute.name) : \(got.display) au lieu de \(expected.display)")
        }
    }

    @Test("Aller-retour par MySQL : les types que MySQL distingue reviennent à l'identique")
    func allerRetourMySQL() throws {
        let model = TypeFixtures.allTypesModel()
        let back = try ReverseEngineer.model(from: SQLGenerator.script(for: model, dialect: .mysql))
        let kinds = Dictionary(uniqueKeysWithValues: try #require(back.entities.first).attributes.map { ($0.name, $0.type) })
        // Pertes inhérentes à MySQL : MONEY, TIMESTAMPTZ, UUID et XML n'y existent pas.
        let lossy: [DataType: DataType] = [.monetaire: .decimal, .horodatage: .dateHeure, .uuid: .char, .xml: .text]
        for attribute in model.entities[0].attributes {
            #expect(kinds[attribute.name] == (lossy[attribute.type] ?? attribute.type), "\(attribute.name)")
        }
    }

    @Test("Types écrits à la main, de tous les SGBD", arguments: [
        ("CHARACTER VARYING(30)", DataType.varchar), ("DOUBLE PRECISION", .reel), ("TIMESTAMP WITH TIME ZONE", .horodatage),
        ("TIMESTAMP", .dateHeure), ("NVARCHAR(MAX)", .ntext), ("VARCHAR(MAX)", .text), ("TINYINT(1)", .booleen),
        ("BIGSERIAL", .compteur), ("NUMBER(5)", .petitEntier), ("NUMBER(12,2)", .decimal), ("BYTEA", .blob),
        ("UNIQUEIDENTIFIER", .uuid), ("JSONB", .json), ("POINT", .geometrique), ("INET", .libre),
    ])
    func typesManuscrits(raw: String, expected: DataType) {
        #expect(ReverseEngineer.typeSpec(raw).kind == expected)
    }

    @Test("Options de colonne : AUTO_INCREMENT, CHARACTER SET, COLLATE, DEFAULT, COMMENT, CHECK de table")
    func options() throws {
        let sql = """
        CREATE TABLE Membre (
            id INT NOT NULL AUTO_INCREMENT,
            nom VARCHAR(40) CHARACTER SET utf8mb4 COLLATE utf8mb4_bin NOT NULL COMMENT 'Nom d''usage',
            statut VARCHAR(10) DEFAULT 'actif',
            note SMALLINT DEFAULT (0),
            PRIMARY KEY (id),
            CONSTRAINT ck_statut CHECK (statut IN ('actif', 'clos'))
        );
        COMMENT ON COLUMN Membre.note IS 'Sur 20';
        """
        let attributes = try #require(try ReverseEngineer.model(from: sql).entities.first).attributes
        let byName = Dictionary(uniqueKeysWithValues: attributes.map { ($0.name, $0) })
        #expect(byName["id"]?.type == .compteur)
        #expect(byName["nom"]?.type == .nvarchar)
        #expect(byName["nom"]?.length == 40)
        #expect(byName["nom"]?.collation == "utf8mb4_bin")
        #expect(byName["nom"]?.comment == "Nom d'usage")
        #expect(byName["nom"]?.isNotNull == true)
        #expect(byName["statut"]?.type == .enumeration)
        #expect(byName["statut"]?.enumValues == ["actif", "clos"])
        #expect(byName["statut"]?.complement == "DEFAULT 'actif'")
        #expect(byName["note"]?.complement == "DEFAULT (0)")
        #expect(byName["note"]?.comment == "Sur 20")
    }
}

// MARK: - Vérification

@Suite("Types : le validateur prévient avant le SGBD")
struct TypeValidatorTests {
    @Test("Chaque incohérence est signalée", arguments: [
        (Attribute(name: "e", type: .enumeration), true),
        (Attribute(name: "e", type: .enumeration, enumValues: ["a", "a"]), false),
        (Attribute(name: "l", type: .libre), true),
        (Attribute(name: "c", type: .compteur), false),
        (Attribute(name: "d", type: .decimal, precision: 5, scale: 9), true),
        (Attribute(name: "v", type: .varchar, length: 0), true),
    ])
    func incoherences(attribute: Attribute, isError: Bool) {
        let problems = Validator.typeProblems([attribute])
        #expect(problems.count == 1)
        #expect(problems.first?.isError == isError)
    }

    @Test("Aucun faux positif sur une propriété correcte de chaque type")
    func pasDeFauxPositif() {
        #expect(Validator.typeProblems(TypeFixtures.allTypesModel().entities[0].attributes).isEmpty)
    }

    @Test("Deux compteurs dans la même entité : avertissement")
    func deuxCompteurs() {
        let problems = Validator.typeProblems([Attribute(name: "a", type: .compteur, isIdentifier: true),
                                               Attribute(name: "b", type: .compteur, isUnique: true)])
        #expect(problems.contains { $0.text.contains("plusieurs compteurs") })
    }
}
