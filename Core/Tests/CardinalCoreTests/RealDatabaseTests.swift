import Testing
import Foundation
#if SWIFT_PACKAGE
@testable import CardinalCore
#else
@testable import Cardinal
#endif

// MARK: - Vrais SGBD

/// Exécute un script dans un vrai PostgreSQL ou MariaDB lancé sur la machine.
/// Le dossier des serveurs est donné par la variable CARDINAL_DB_DIR ; sans elle, ces tests
/// sont ignorés (ils le disent dans leur nom de cas plutôt que de passer en silence).
enum RealDatabase {
    static let directory = ProcessInfo.processInfo.environment["CARDINAL_DB_DIR"]
    static var isAvailable: Bool { directory != nil }

    static func binary(_ name: String) -> String? {
        ["/opt/homebrew/opt/postgresql@17/bin/\(name)", "/opt/homebrew/opt/mariadb/bin/\(name)"]
            .first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    /// Renvoie le message d'erreur du SGBD, ou nil si tout le script s'est exécuté.
    static func run(_ script: String, in dialect: SQLDialect, then extra: String = "") -> String? {
        guard let directory else { return "base indisponible" }
        let space = "t" + UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(12).lowercased()
        switch dialect {
        case .postgresql:
            guard let psql = binary("psql") else { return "psql introuvable" }
            let sql = "CREATE SCHEMA \(space); SET search_path TO \(space);\n\(script)\n\(extra)\nRESET search_path; DROP SCHEMA \(space) CASCADE;"
            return execute(psql, ["-h", directory, "-p", "54329", "-U", "cardinal", "-d", "postgres", "-v", "ON_ERROR_STOP=1", "-q", "-X"],
                           input: sql, cleanup: nil)
        case .mariadb, .mysql:
            guard let client = binary("mariadb") else { return "mariadb introuvable" }
            let sql = "CREATE DATABASE \(space); USE \(space);\n\(script)\n\(extra)\nDROP DATABASE \(space);"
            return execute(client, ["--socket=\(directory)/maria.sock", "-u", NSUserName()], input: sql,
                           cleanup: (client, "DROP DATABASE IF EXISTS \(space);"))
        default:
            return "SGBD non installé"
        }
    }

    private static func execute(_ path: String, _ arguments: [String], input: String, cleanup: (String, String)?) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        process.environment = ["LC_ALL": "C", "PATH": "/usr/bin:/bin"]
        let stdin = Pipe(), stderr = Pipe()
        process.standardInput = stdin
        process.standardError = stderr
        process.standardOutput = FileHandle.nullDevice
        do { try process.run() } catch { return "lancement impossible : \(error)" }
        stdin.fileHandleForWriting.write(Data(input.utf8))
        try? stdin.fileHandleForWriting.close()
        let errors = String(decoding: stderr.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        process.waitUntilExit()
        if process.terminationStatus != 0, let (client, sql) = cleanup {
            _ = execute(client, Array(arguments), input: sql, cleanup: nil)
        }
        let meaningful = errors.split(separator: "\n").filter { !$0.contains("NOTICE") && !$0.isEmpty }
        return process.terminationStatus == 0 ? nil : (meaningful.joined(separator: " ").isEmpty ? "code \(process.terminationStatus)" : meaningful.joined(separator: " "))
    }
}

// MARK: - Générateur de MCD aléatoires

/// Générateur pseudo-aléatoire reproductible : un même numéro donne toujours le même MCD.
struct SeededRandom: RandomNumberGenerator {
    var state: UInt64
    init(_ seed: UInt64) { state = seed &+ 0x9E37_79B9_7F4A_7C15 }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

enum ModelFuzzer {
    /// Noms piégeux : mots réservés, accents, espaces, chiffres en tête, très longs.
    static let trickyNames = [
        "Order", "User", "Group", "Select", "Table", "Index", "Key", "Rank", "Window", "Column", "Check", "Session",
        "Élève", "Année scolaire", "2eme_cycle", "Désignation du produit", "Commande client très longue avec un nom qui ne tient pas dans trente caractères",
    ]
    static let trickyAttributes = [
        "date", "desc", "order", "user", "value", "level", "size", "number", "comment", "from", "to", "limit", "key",
        "prénom", "code postal", "1er_contact", "libelle_extremement_long_qui_depasse_largement_les_limites_de_certains_sgbd_x",
    ]

    static func model(seed: UInt64) -> MCDModel {
        var random = SeededRandom(seed)
        var model = MCDModel()
        var usedNames = Set<String>()
        func name(_ pool: [String], _ fallback: String) -> String {
            let candidate = Int.random(in: 0..<3, using: &random) == 0 ? pool.randomElement(using: &random)! : fallback
            let key = candidate.sqlIdentifier.lowercased()
            if usedNames.contains(key) { let alt = fallback + "_\(usedNames.count)"; usedNames.insert(alt.sqlIdentifier.lowercased()); return alt }
            usedNames.insert(key)
            return candidate
        }
        func attributes(count: Int, identifier: Bool) -> [Attribute] {
            var result: [Attribute] = []
            var names = Set<String>()
            for index in 0..<count {
                var base = Int.random(in: 0..<3, using: &random) == 0 ? trickyAttributes.randomElement(using: &random)! : "p\(index)"
                if names.contains(base.sqlIdentifier.lowercased()) { base = "p\(index)_b" }
                names.insert(base.sqlIdentifier.lowercased())
                var attribute = Attribute(name: base)
                // Pas de types géographiques : PostGIS n'est pas installé sur le serveur de test.
                let types = DataType.allCases.filter { $0 != .geometrique && $0 != .geographique }
                attribute.setType(types.randomElement(using: &random)!)
                if attribute.type == .libre { attribute.customType = "VARCHAR(12)" }
                if attribute.type == .compteur && !(identifier && index == 0) { attribute.type = .entier }
                if attribute.type.usesLength { attribute.length = [1, 10, 255, 300, 5000, 70_000].randomElement(using: &random)! }
                if attribute.type == .decimal { attribute.precision = Int.random(in: 1...38, using: &random); attribute.scale = Int.random(in: 0...attribute.precision, using: &random) }
                if attribute.type == .enumeration { attribute.enumValues = ["a", "l'été", "très long valeur"].shuffled(using: &random) }
                attribute.isNotNull = Bool.random(using: &random)
                attribute.isUnique = Int.random(in: 0..<5, using: &random) == 0 && attribute.type.category != .autre && attribute.type.storage != .volumineux
                if Int.random(in: 0..<6, using: &random) == 0 { attribute.comment = "Commentaire d'essai" }
                if identifier && index == 0 {
                    attribute.isIdentifier = true
                    attribute.isNotNull = false
                    attribute.isUnique = false
                    // Une clé doit rester indexable partout : pas de texte volumineux, pas de JSON.
                    if [.text, .ntext, .blob, .json, .xml, .reel].contains(attribute.type) || attribute.type.usesLength {
                        attribute.setType(.entier)
                    }
                }
                result.append(attribute)
            }
            return result
        }

        let entityCount = Int.random(in: 2...7, using: &random)
        for index in 0..<entityCount {
            let entity = Entity(name: name(trickyNames, "Ent\(index)"), attributes: attributes(count: Int.random(in: 1...5, using: &random), identifier: true),
                                position: CGPoint(x: index * 300, y: (index % 3) * 250),
                                isFictive: index > 1 && Int.random(in: 0..<10, using: &random) == 0)
            model.entities.append(entity)
        }
        let ids = model.entities.map(\.id)
        let associationCount = Int.random(in: 1...6, using: &random)
        for index in 0..<associationCount {
            let arity = Int.random(in: 0..<6, using: &random) == 0 && ids.count >= 3 ? 3 : 2
            var legEntities = Array(ids.shuffled(using: &random).prefix(arity))
            if arity == 2 && Int.random(in: 0..<6, using: &random) == 0 { legEntities[1] = legEntities[0] } // réflexive
            let legs = legEntities.map { id -> Leg in
                // Pas de max 1 dans les n-aires (règle de Merise, signalée par le validateur).
                let cardinality = arity > 2 ? [Cardinality.zeroMany, .oneMany].randomElement(using: &random)! : Cardinality.allCases.randomElement(using: &random)!
                return Leg(entityID: id, cardinality: cardinality)
            }
            var association = Association(name: name(["Avoir", "Order", "Select"], "Asso\(index)"),
                                          attributes: Bool.random(using: &random) ? attributes(count: Int.random(in: 1...2, using: &random), identifier: false) : [],
                                          legs: legs, position: CGPoint(x: index * 200, y: 600))
            if legs.count == 2, legs[0].entityID == legs[1].entityID {
                association.legs[0].role = "parent"
                association.legs[1].role = "enfant"
                // Réflexive 1,1 : impossible à remplir (signalée par le validateur), on garde 0,1.
                for i in 0..<2 where association.legs[i].cardinality == .oneOne { association.legs[i].cardinality = .zeroOne }
            }
            model.associations.append(association)
        }
        // Un héritage de temps en temps, avec une stratégie et une contrainte au hasard.
        if model.entities.count >= 4, Bool.random(using: &random) {
            let parent = model.entities[0].id
            let children = Array(model.entities[2...].map(\.id).prefix(2))
            for child in children {
                if let index = model.entities.firstIndex(where: { $0.id == child }) {
                    model.entities[index].attributes.removeAll(where: \.isIdentifier)
                    model.entities[index].isFictive = false
                }
            }
            model.inheritances.append(Inheritance(parentID: parent, childIDs: children,
                                                  kind: InheritanceKind.allCases.randomElement(using: &random)!,
                                                  strategy: InheritanceStrategy.allCases.randomElement(using: &random)!,
                                                  position: .zero))
            if let index = model.entities.firstIndex(where: { $0.id == parent }) { model.entities[index].isFictive = false }
        }
        model.settings.naming = NamingConvention.allCases.randomElement(using: &random)!
        model.settings.foreignKeysAtEnd = Int.random(in: 0..<4, using: &random) == 0
        return model
    }

    /// Modèles sans erreur bloquante (ceux que l'utilisateur peut légitimement générer).
    static func validModels(count: Int) -> [(UInt64, MCDModel)] {
        var result: [(UInt64, MCDModel)] = []
        var seed: UInt64 = 1
        while result.count < count && seed < UInt64(count * 20) {
            let model = model(seed: seed)
            if !Validator.check(model).contains(where: { $0.severity == .error }) { result.append((seed, model)) }
            seed += 1
        }
        return result
    }
}

// MARK: - Tests

@Suite("Fiabilité : centaines de MCD aléatoires")
struct FuzzTests {
    static let models = ModelFuzzer.validModels(count: 300)

    @Test("Le générateur produit bien des cas variés")
    func variete() {
        let models = Self.models.map(\.1)
        #expect(models.count == 300)
        #expect(models.contains { !$0.inheritances.isEmpty })
        #expect(models.contains { $0.associations.contains { $0.legs.count == 3 } })
        #expect(models.contains { $0.associations.contains { $0.legs.count == 2 && $0.legs[0].entityID == $0.legs[1].entityID } })
        #expect(models.contains { $0.entities.contains { $0.name == "Order" } })
    }

    @Test("Le MLD est toujours cohérent : clés étrangères vers des colonnes de clé existantes, noms uniques")
    func mldCoherent() {
        for (seed, model) in Self.models {
            let tables = MLDBuilder.build(model)
            #expect(Set(tables.map { $0.name.lowercased() }).count == tables.count, "graine \(seed) : deux tables du même nom")
            for table in tables {
                #expect(!table.columns.isEmpty, "graine \(seed) : \(table.name) sans colonne")
                #expect(Set(table.columns.map { $0.name.lowercased() }).count == table.columns.count, "graine \(seed) : colonnes en double dans \(table.name)")
                for column in table.columns {
                    guard let reference = column.reference else { continue }
                    let target = tables.first { $0.name == reference.table }
                    #expect(target != nil, "graine \(seed) : \(table.name).\(column.name) vise une table absente")
                    #expect(target?.columns.contains { $0.name == reference.column && $0.isPrimaryKey } == true,
                            "graine \(seed) : \(table.name).\(column.name) vise une colonne qui n'est pas une clé")
                    if column.isPrimaryKey { #expect(!column.isNullable) }
                }
            }
        }
    }

    @Test("Le script s'exécute dans SQLite, pour chaque MCD")
    func sqlite() {
        for (seed, model) in Self.models {
            let error = runSQLite(SQLGenerator.script(for: model, dialect: .sqlite))
            #expect(error == nil, "graine \(seed) : \(error ?? "")")
        }
    }

    @Test("Le script s'exécute dans un vrai PostgreSQL et un vrai MariaDB, pour chaque MCD",
          .enabled(if: RealDatabase.isAvailable), arguments: [SQLDialect.postgresql, .mariadb, .mysql])
    func vraisSGBD(dialect: SQLDialect) {
        for (seed, model) in Self.models {
            let error = RealDatabase.run(SQLGenerator.script(for: model, dialect: dialect), in: dialect)
            if let error { debugLog("graine \(seed), \(dialect.rawValue) : \(error)") }
            #expect(error == nil, "graine \(seed), \(dialect.rawValue) : \(error ?? "")")
        }
    }

    @Test("Rétroconception du script : le MLD obtenu est le même", arguments: [SQLDialect.postgresql, .sqlserver])
    func allerRetour(dialect: SQLDialect) throws {
        for (seed, model) in Self.models.prefix(150) {
            var plain = model
            plain.settings.naming = .telQuel
            let tables = MLDBuilder.build(plain)
            // Un nom raccourci par la limite du SGBD ne peut pas retrouver sa forme d'origine (testé à part).
            let limit = SQLGenerator.maxIdentifierLength(dialect)
            if tables.contains(where: { $0.name.utf8.count > limit || $0.columns.contains { $0.name.utf8.count > limit } }) { continue }
            let back = try ReverseEngineer.model(from: SQLGenerator.script(for: tables, dialect: dialect))
            let again = MLDBuilder.build(back)
            // Noms tels que le SGBD les reçoit (raccourcis au besoin), sans délimiteurs.
            func name(_ raw: String) -> String {
                SQLGenerator.ident(raw, dialect).trimmingCharacters(in: CharacterSet(charactersIn: "\"[]`")).lowercased()
            }
            func shape(_ tables: [MLDTable]) -> Set<String> {
                Set(tables.map { table in
                    name(table.name) + "(" + table.columns.map { name($0.name) + ($0.isPrimaryKey ? "*" : "") }.sorted().joined(separator: ",") + ")"
                })
            }
            #expect(shape(again) == shape(tables), "graine \(seed)")
        }
    }
}

@Suite("Fiabilité : noms piégeux et cas limites, dans de vrais SGBD")
struct TrickyCaseTests {
    static let dialects: [SQLDialect] = RealDatabase.isAvailable ? [.sqlite, .postgresql, .mariadb, .mysql] : [.sqlite]

    func execute(_ model: MCDModel, _ dialect: SQLDialect, then extra: String = "") -> String? {
        let script = SQLGenerator.script(for: model, dialect: dialect)
        return dialect == .sqlite ? runSQLite(script, then: extra.isEmpty ? nil : extra) : RealDatabase.run(script, in: dialect, then: extra)
    }

    @Test("Tables et colonnes nommées avec des mots réservés", arguments: dialects)
    func motsReserves(dialect: SQLDialect) {
        var b = MCDBuilder()
        let order = b.entity("Order", ids: ["key"], attrs: ["date", "desc", "user", "group", "value"])
        let user = b.entity("User", ids: ["select"], attrs: ["rank", "window"])
        b.association("Group", [(order, .zeroMany), (user, .zeroMany)], attrs: ["from"])
        #expect(execute(b.model, dialect) == nil, "\(dialect.rawValue) : \(execute(b.model, dialect) ?? "")")
    }

    @Test("Noms très longs : raccourcis, distincts, acceptés", arguments: dialects + [.oracle, .sqlserver])
    func nomsLongs(dialect: SQLDialect) {
        var b = MCDBuilder()
        let long = String(repeating: "tres_long_", count: 9)
        let a = b.entity(long + "a", ids: [long + "id_a"], attrs: [long + "x", long + "y"])
        let c = b.entity(long + "b", ids: [long + "id_b"])
        b.association(long + "lien", [(a, .zeroMany), (c, .zeroMany)])
        let script = SQLGenerator.script(for: b.model, dialect: dialect)
        let limit = SQLGenerator.maxIdentifierLength(dialect)
        let identifiers = script.split(whereSeparator: { !($0.isLetter || $0.isNumber || $0 == "_") }).filter { $0.contains("tres_long") }
        #expect(identifiers.allSatisfy { $0.utf8.count <= limit }, "\(dialect.rawValue) : un nom dépasse \(limit)")
        #expect(Set(identifiers.filter { $0.hasSuffix("_x") || $0.contains("_x_") || $0.hasSuffix("_y") }).count != 1)
        if dialect == .sqlite || RealDatabase.isAvailable && dialect != .oracle && dialect != .sqlserver {
            #expect(execute(b.model, dialect) == nil)
        }
    }

    @Test("Références croisées entre deux tables : le script se crée quand même", arguments: dialects)
    func referencesCroisees(dialect: SQLDialect) {
        var b = MCDBuilder()
        let a = b.entity("Departement")
        let c = b.entity("Employe")
        b.association("Travailler", [(c, .oneOne), (a, .zeroMany)])
        b.association("Diriger", [(a, .zeroOne), (c, .zeroMany)])
        let error = execute(b.model, dialect)
        #expect(error == nil, "\(dialect.rawValue) : \(error ?? "")")
        #expect(Validator.check(b.model).allSatisfy { !$0.message.contains("en boucle") }) // 0,1 : pas obligatoire
    }

    @Test("Références obligatoires en boucle : signalées par le validateur")
    func boucleObligatoire() {
        var b = MCDBuilder()
        let a = b.entity("A")
        let c = b.entity("B")
        b.association("R1", [(c, .oneOne), (a, .zeroMany)])
        b.association("R2", [(a, .oneOne), (c, .zeroMany)])
        #expect(Validator.check(b.model).contains { $0.message.contains("en boucle") })
    }

    @Test("Héritage : chaque contrainte X, T, XT est réellement appliquée par le SGBD",
          arguments: InheritanceKind.allCases)
    func heritage(kind: InheritanceKind) {
        for dialect in Self.dialects {
            var b = MCDBuilder()
            let personne = b.entity("Personne")
            let etudiant = b.entity("Etudiant", ids: [], attrs: ["matricule"])
            let prof = b.entity("Enseignant", ids: [], attrs: ["grade"])
            b.model.inheritances = [Inheritance(parentID: personne, childIDs: [etudiant, prof], kind: kind, strategy: .surtypeSeul, position: .zero)]
            #expect(execute(b.model, dialect) == nil, "\(dialect.rawValue)")
            let isTrue = dialect == .sqlite ? "1" : "TRUE"
            let table = dialect == .sqlite || dialect == .mariadb || dialect == .mysql ? "Personne" : "Personne"
            switch kind {
            case .exclusion, .partition:
                // Une seule valeur, parmi les sous-types.
                #expect(execute(b.model, dialect, then: "INSERT INTO \(table) (id_personne, type_Personne) VALUES (1, 'Etudiant');") == nil)
                #expect(execute(b.model, dialect, then: "INSERT INTO \(table) (id_personne, type_Personne) VALUES (1, 'Pirate');") != nil)
                let sansType = execute(b.model, dialect, then: "INSERT INTO \(table) (id_personne) VALUES (1);")
                #expect((sansType == nil) == (kind == .exclusion), "\(dialect.rawValue) : sans sous-type")
            case .libre, .totalite:
                // Plusieurs sous-types à la fois sont permis ; la totalité en exige au moins un.
                #expect(execute(b.model, dialect, then: "INSERT INTO \(table) (id_personne, est_Etudiant, est_Enseignant) VALUES (1, \(isTrue), \(isTrue));") == nil)
                let aucun = execute(b.model, dialect, then: "INSERT INTO \(table) (id_personne) VALUES (1);")
                #expect((aucun == nil) == (kind == .libre), "\(dialect.rawValue) : aucun sous-type")
            }
        }
    }

    @Test("Validateur : un sous-type avec son propre identifiant est refusé")
    func sousTypeAvecIdentifiant() {
        var b = MCDBuilder()
        let salarie = b.entity("Salarie")
        let cadre = b.entity("Cadre") // a son propre identifiant id_cadre
        b.model.inheritances = [Inheritance(parentID: salarie, childIDs: [cadre], position: .zero)]
        #expect(Validator.check(b.model).contains { $0.severity == .error && $0.message.contains("hérite de son identifiant") })
        b.model.entities[1].attributes.removeAll(where: \.isIdentifier)
        #expect(!Validator.check(b.model).contains { $0.message.contains("hérite de son identifiant") })
    }

    @Test("Validateur : pièges de logique Merise signalés", arguments: [
        ("ternaire 1,1", true), ("réflexive 1,1", true), ("1,1 des deux côtés", true), ("modèle correct", false),
    ])
    func piegesMerise(cas: String, warned: Bool) {
        var b = MCDBuilder()
        let a = b.entity("A"), c = b.entity("C"), d = b.entity("D")
        switch cas {
        case "ternaire 1,1": b.association("T", [(a, .oneOne), (c, .zeroMany), (d, .zeroMany)])
        case "réflexive 1,1": b.association("R", [(a, .oneOne), (a, .zeroMany)])
        case "1,1 des deux côtés": b.association("U", [(a, .oneOne), (c, .oneOne)]); b.association("V", [(d, .zeroMany), (c, .zeroMany)])
        default: b.association("V", [(a, .zeroMany), (c, .oneOne)]); b.association("W", [(d, .zeroMany), (c, .zeroMany)])
        }
        let warnings = Validator.check(b.model).filter { $0.severity == .warning && !$0.message.contains("reliée à aucune") }
        #expect(warnings.isEmpty != warned, "\(cas) : \(warnings.map(\.message))")
    }
}

/// Journal de mise au point (seulement si CARDINAL_DEBUG est défini) : les commentaires des
/// attentes ne sont pas toujours affichés par xcodebuild.
func debugLog(_ line: String) {
    guard ProcessInfo.processInfo.environment["CARDINAL_DEBUG"] != nil else { return }
    let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("cardinal-debug.txt")
    let data = Data((line + "\n").utf8)
    if let handle = try? FileHandle(forWritingTo: url) { handle.seekToEndOfFile(); handle.write(data); try? handle.close() }
    else { try? data.write(to: url) }
}
