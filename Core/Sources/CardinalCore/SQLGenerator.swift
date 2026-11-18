import Foundation

enum SQLDialect: String, CaseIterable, Identifiable, Codable, Sendable {
    case mysql = "MySQL"
    case mariadb = "MariaDB"
    case postgresql = "PostgreSQL"
    case sqlite = "SQLite"
    case sqlserver = "SQL Server"
    case oracle = "Oracle"

    var id: String { rawValue }
}

/// SGBD personnalisé, comme dans Looping : un SGBD de base, dont on remplace le type SQL
/// de certains types Cardinal par un texte libre. {n} = longueur, {p} = précision, {s} = échelle.
struct CustomDialect: Codable, Hashable, Sendable {
    var name = "Mon SGBD"
    var base: SQLDialect = .postgresql
    /// Type SQL par type Cardinal (clé : identifiant du type). Absent ou vide : celui du SGBD de base.
    var types: [String: String] = [:]

    /// Texte du type, paramètres remplacés ; nil si ce type n'est pas personnalisé.
    func render(_ spec: TypeSpec) -> String? {
        guard let template = types[spec.kind.rawValue].map(Self.clean), !template.isEmpty else { return nil }
        let spec = spec.normalized
        return template
            .replacingOccurrences(of: "{n}", with: "\(spec.length)")
            .replacingOccurrences(of: "{p}", with: "\(spec.precision)")
            .replacingOccurrences(of: "{s}", with: "\(spec.scale)")
    }

    /// Un type sur une ligne, sans point-virgule ni virgule finale : il ne peut pas casser le script.
    static func clean(_ text: String) -> String {
        var cleaned = text.replacingOccurrences(of: "\n", with: " ").replacingOccurrences(of: ";", with: "")
            .trimmingCharacters(in: .whitespaces)
        while cleaned.hasSuffix(",") { cleaned.removeLast() }
        return cleaned.trimmingCharacters(in: .whitespaces)
    }

    var label: String { "\(name) (personnalisé, basé sur \(base.rawValue))" }
}

/// Génère le script LDD (CREATE TABLE) à partir du MLD, pour le SGBD choisi.
enum SQLGenerator {
    /// SGBD personnalisé en cours de génération (voir `script(for:custom:)`).
    @TaskLocal static var custom: CustomDialect?

    /// Script pour un SGBD personnalisé : celui de son SGBD de base, types remplacés.
    static func script(for model: MCDModel, custom: CustomDialect) -> String {
        $custom.withValue(custom) { script(for: model, dialect: custom.base) }
    }

    /// Script complet d'un MCD : tables, puis code SQL des règles et contraintes.
    static func script(for model: MCDModel, dialect: SQLDialect) -> String {
        var appendix: [(String, String)] = []
        for rule in model.rules where !rule.sql.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            appendix.append(("Règle « \(rule.name) »", rule.sql))
        }
        for constraint in model.constraints where !constraint.sql.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            appendix.append(("Contrainte \(constraint.kind.rawValue)", constraint.sql))
        }
        return script(
            for: MLDBuilder.build(model),
            dialect: dialect,
            foreignKeysAtEnd: model.settings.foreignKeysAtEnd,
            appendix: appendix
        )
    }

    static func script(
        for tables: [MLDTable],
        dialect: SQLDialect,
        foreignKeysAtEnd: Bool = false,
        appendix: [(title: String, sql: String)] = []
    ) -> String {
        guard !tables.isEmpty else {
            return "-- Le modèle est vide : ajoutez des entités dans l'onglet MCD."
        }
        // SQLite ne sait pas ajouter une clé étrangère après coup.
        let deferForeignKeys = foreignKeysAtEnd && dialect != .sqlite
        var lines = ["-- Script généré par Cardinal", "-- SGBD : \(custom?.label ?? dialect.rawValue)", ""]
        let spatial = tables.contains { $0.columns.contains { $0.type == .geometrique || $0.type == .geographique } }
        if spatial && dialect == .postgresql {
            lines += ["-- Types géométriques et géographiques : extension PostGIS", "CREATE EXTENSION IF NOT EXISTS postgis;", ""]
        }
        let ordered = deferForeignKeys ? tables : creationOrder(tables)
        var created = Set<String>()
        var alters: [String] = []
        for table in ordered {
            created.insert(table.name)
            var inline: [String] = []
            for clause in foreignKeyClauses(of: table, dialect: dialect) {
                // Une clé vers une table pas encore créée (références croisées) est ajoutée après coup,
                // sauf en SQLite qui accepte les références en avant et ne sait pas ajouter une contrainte.
                if !deferForeignKeys && (created.contains(clause.target) || dialect == .sqlite) {
                    inline.append(clause.sql)
                } else {
                    alters.append("ALTER TABLE \(ident(table.name, dialect)) ADD \(clause.sql);")
                }
            }
            lines.append(createTable(table, dialect: dialect, foreignKeyClauses: inline))
            lines.append("")
        }
        if !alters.isEmpty {
            lines.append(deferForeignKeys ? "-- Clés étrangères" : "-- Clés étrangères entre tables qui se référencent mutuellement")
            lines += alters
            lines.append("")
        }
        for (title, sql) in appendix {
            lines.append("-- \(title)")
            lines.append(sql.trimmingCharacters(in: .whitespacesAndNewlines))
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }

    static func createTable(_ table: MLDTable, dialect: SQLDialect, includeForeignKeys: Bool = true) -> String {
        createTable(table, dialect: dialect, foreignKeyClauses: includeForeignKeys ? foreignKeys(of: table, dialect: dialect) : [])
    }

    static func createTable(_ table: MLDTable, dialect: SQLDialect, foreignKeyClauses: [String]) -> String {
        let primaryKey = table.primaryKey.map(\.name)
        // SQLite : un compteur seul en clé primaire s'écrit INTEGER PRIMARY KEY AUTOINCREMENT.
        let sqliteCounter = dialect == .sqlite && table.primaryKey.count == 1 && table.primaryKey[0].type == .compteur
            && table.primaryKey[0].reference == nil
        var parts: [String] = table.columns.map { column in
            var pieces = ["\(ident(column.name, dialect)) \(sqlType(column, dialect: dialect))"]
            if let collate = collation(column.spec, dialect: dialect) { pieces.append(collate) }
            if sqliteCounter && column.isPrimaryKey {
                pieces.append("PRIMARY KEY AUTOINCREMENT")
            } else if let identity = identityClause(column, in: table, dialect: dialect) {
                pieces.append(identity)
            }
            if !column.isNullable { pieces.append("NOT NULL") }
            if let extra = complement(column.complement) { pieces.append(extra) }
            // MySQL / MariaDB : COMMENT doit précéder CHECK dans la définition d'une colonne.
            if (dialect == .mysql || dialect == .mariadb), !column.comment.isEmpty {
                pieces.append("COMMENT " + quoted(column.comment.replacingOccurrences(of: "\n", with: " ")))
            }
            if let check = check(column, dialect: dialect) { pieces.append(check) }
            return "    " + pieces.joined(separator: " ")
        }
        if !primaryKey.isEmpty && !sqliteCounter {
            parts.append("    CONSTRAINT \(ident("pk_" + table.name, dialect)) PRIMARY KEY (\(primaryKey.map { ident($0, dialect) }.joined(separator: ", ")))")
        }
        for column in table.columns where column.isUnique && !column.isPrimaryKey {
            parts.append("    CONSTRAINT \(ident("uq_\(table.name)_\(column.name)", dialect)) UNIQUE (\(ident(column.name, dialect)))")
        }
        for (index, check) in table.checks.enumerated() {
            switch check {
            case .atLeastOneTrue(let columns):
                // COALESCE : une colonne vide (NULL) compte comme « non », sinon le CHECK laisserait passer.
                let boolean = dialect == .postgresql ? ("FALSE", "TRUE") : ("0", "1")
                let condition = columns.map { "COALESCE(\(ident($0, dialect)), \(boolean.0)) = \(boolean.1)" }.joined(separator: " OR ")
                parts.append("    CONSTRAINT \(ident("ck_\(table.name)_\(index + 1)", dialect)) CHECK (\(condition))")
            }
        }
        parts += foreignKeyClauses.map { "    " + $0 }
        let suffix = (dialect == .mysql || dialect == .mariadb) ? " ENGINE=InnoDB" : ""
        var lines: [String] = []
        let commented = table.columns.filter { !$0.comment.isEmpty }
        if dialect == .sqlserver || dialect == .sqlite {
            // Pas de commentaire de colonne simple : on l'écrit en commentaire SQL.
            lines += commented.map { "-- \(table.name).\($0.name) : \($0.comment.replacingOccurrences(of: "\n", with: " "))" }
        }
        lines.append("CREATE TABLE \(ident(table.name, dialect)) (\n\(parts.joined(separator: ",\n"))\n)\(suffix);")
        if dialect == .postgresql || dialect == .oracle {
            lines += commented.map {
                "COMMENT ON COLUMN \(ident(table.name, dialect)).\(ident($0.name, dialect)) IS \(quoted($0.comment.replacingOccurrences(of: "\n", with: " ")));"
            }
        }
        return lines.joined(separator: "\n")
    }

    /// « CONSTRAINT fk_… FOREIGN KEY (…) REFERENCES … (…) » pour chaque clé étrangère.
    static func foreignKeys(of table: MLDTable, dialect: SQLDialect = .postgresql) -> [String] {
        foreignKeyClauses(of: table, dialect: dialect).map(\.sql)
    }

    static func foreignKeyClauses(of table: MLDTable, dialect: SQLDialect) -> [(target: String, sql: String)] {
        let groups = Dictionary(grouping: table.columns.filter { $0.reference != nil }) { $0.reference!.group }
        return groups.keys.sorted().compactMap { group in
            guard let columns = groups[group], let target = columns.first?.reference?.table else { return nil }
            let local = columns.map { ident($0.name, dialect) }.joined(separator: ", ")
            let remote = columns.compactMap { $0.reference.map { ident($0.column, dialect) } }.joined(separator: ", ")
            let name = ident("fk_\(table.name)_\(columns[0].name)", dialect)
            return (target, "CONSTRAINT \(name) FOREIGN KEY (\(local)) REFERENCES \(ident(target, dialect)) (\(remote))")
        }
    }

    // MARK: Noms

    /// Longueur maximale d'un nom (table, colonne, contrainte). Oracle : 30, limite des versions
    /// antérieures à 12.2 encore répandues, valable aussi pour les récentes.
    static func maxIdentifierLength(_ dialect: SQLDialect) -> Int {
        switch dialect {
        case .postgresql: 63
        case .mysql, .mariadb: 64
        case .sqlserver: 128
        case .oracle: 30
        case .sqlite: 1000
        }
    }

    /// Nom prêt pour le script : raccourci s'il dépasse la limite du SGBD (avec un code
    /// pour que deux noms longs restent distincts), délimité s'il est un mot réservé.
    static func ident(_ raw: String, _ dialect: SQLDialect) -> String {
        var name = raw
        let limit = maxIdentifierLength(dialect)
        if name.utf8.count > limit {
            let code = String(fnv1a(raw), radix: 16).suffix(6)
            // On coupe entre deux caractères, jamais au milieu d'un caractère accentué.
            var cut = ""
            for character in name {
                guard cut.utf8.count + String(character).utf8.count <= limit - 7 else { break }
                cut.append(character)
            }
            name = cut + "_" + code
        }
        guard SQLKeywords.reserved(in: dialect).contains(name.uppercased()) else { return name }
        switch dialect {
        case .mysql, .mariadb: return "`\(name)`"
        case .sqlserver: return "[\(name)]"
        default: return "\"\(name)\""
        }
    }

    private static func fnv1a(_ text: String) -> UInt32 {
        var hash: UInt32 = 2_166_136_261
        for byte in text.utf8 { hash = (hash ^ UInt32(byte)) &* 16_777_619 }
        return hash
    }

    /// Les tables référencées sont créées avant celles qui les référencent.
    static func creationOrder(_ tables: [MLDTable]) -> [MLDTable] {
        var remaining = tables
        var created = Set<String>()
        var ordered: [MLDTable] = []
        while !remaining.isEmpty {
            let readyIndex = remaining.firstIndex { table in
                table.columns.compactMap(\.reference?.table).allSatisfy { $0 == table.name || created.contains($0) }
            }
            // En cas de cycle, on garde l'ordre d'origine plutôt que de bloquer.
            let table = remaining.remove(at: readyIndex ?? 0)
            created.insert(table.name)
            ordered.append(table)
        }
        return ordered
    }

    static func sqlType(_ column: MLDColumn, dialect: SQLDialect) -> String {
        sqlType(column.spec, dialect: dialect)
    }

    /// Traduction d'un type pour un SGBD. Toujours une syntaxe valide : une longueur au-delà
    /// de la limite du SGBD bascule sur son type volumineux, une précision est ramenée dans ses bornes.
    static func sqlType(_ input: TypeSpec, dialect: SQLDialect) -> String {
        if let custom, let type = custom.render(input) { return type }
        let spec = input.normalized
        let n = spec.length
        let isMySQL = dialect == .mysql || dialect == .mariadb
        switch spec.kind {
        // Texte ASCII
        case .varchar:
            switch dialect {
            case .mysql, .mariadb: return n <= 16_383 ? "VARCHAR(\(n))" : "LONGTEXT"
            case .postgresql: return "VARCHAR(\(n))"
            case .sqlserver: return n <= 8000 ? "VARCHAR(\(n))" : "VARCHAR(MAX)"
            case .oracle: return n <= 4000 ? "VARCHAR2(\(n))" : "CLOB"
            case .sqlite: return "TEXT"
            }
        case .char:
            switch dialect {
            case .mysql, .mariadb: return n <= 255 ? "CHAR(\(n))" : sqlType(TypeSpec(kind: .varchar, length: n), dialect: dialect)
            case .postgresql: return "CHAR(\(n))"
            case .sqlserver: return n <= 8000 ? "CHAR(\(n))" : "VARCHAR(MAX)"
            case .oracle: return n <= 2000 ? "CHAR(\(n))" : sqlType(TypeSpec(kind: .varchar, length: n), dialect: dialect)
            case .sqlite: return "TEXT"
            }
        case .text:
            switch dialect {
            case .mysql, .mariadb: return "LONGTEXT"
            case .postgresql, .sqlite: return "TEXT"
            case .sqlserver: return "VARCHAR(MAX)"
            case .oracle: return "CLOB"
            }
        // Texte Unicode
        case .nvarchar:
            switch dialect {
            case .mysql, .mariadb: return n <= 16_383 ? "VARCHAR(\(n)) CHARACTER SET utf8mb4" : "LONGTEXT CHARACTER SET utf8mb4"
            case .postgresql: return "VARCHAR(\(n))"
            case .sqlserver: return n <= 4000 ? "NVARCHAR(\(n))" : "NVARCHAR(MAX)"
            case .oracle: return n <= 2000 ? "NVARCHAR2(\(n))" : "NCLOB"
            case .sqlite: return "TEXT"
            }
        case .nchar:
            switch dialect {
            case .mysql, .mariadb: return n <= 255 ? "CHAR(\(n)) CHARACTER SET utf8mb4" : sqlType(TypeSpec(kind: .nvarchar, length: n), dialect: dialect)
            case .postgresql: return "CHAR(\(n))"
            case .sqlserver: return n <= 4000 ? "NCHAR(\(n))" : "NVARCHAR(MAX)"
            case .oracle: return n <= 1000 ? "NCHAR(\(n))" : sqlType(TypeSpec(kind: .nvarchar, length: n), dialect: dialect)
            case .sqlite: return "TEXT"
            }
        case .ntext:
            switch dialect {
            case .mysql, .mariadb: return "LONGTEXT CHARACTER SET utf8mb4"
            case .postgresql, .sqlite: return "TEXT"
            case .sqlserver: return "NVARCHAR(MAX)"
            case .oracle: return "NCLOB"
            }
        // Binaire
        case .varbinary:
            switch dialect {
            case .mysql, .mariadb: return n <= 65_535 ? "VARBINARY(\(n))" : "LONGBLOB"
            case .postgresql: return "BYTEA"
            case .sqlserver: return n <= 8000 ? "VARBINARY(\(n))" : "VARBINARY(MAX)"
            case .oracle: return n <= 2000 ? "RAW(\(n))" : "BLOB"
            case .sqlite: return "BLOB"
            }
        case .binary:
            switch dialect {
            case .mysql, .mariadb: return n <= 255 ? "BINARY(\(n))" : sqlType(TypeSpec(kind: .varbinary, length: n), dialect: dialect)
            case .postgresql: return "BYTEA"
            case .sqlserver: return n <= 8000 ? "BINARY(\(n))" : "VARBINARY(MAX)"
            case .oracle: return n <= 2000 ? "RAW(\(n))" : "BLOB"
            case .sqlite: return "BLOB"
            }
        case .blob:
            switch dialect {
            case .mysql, .mariadb: return "LONGBLOB"
            case .postgresql: return "BYTEA"
            case .sqlserver: return "VARBINARY(MAX)"
            case .oracle, .sqlite: return "BLOB"
            }
        // Numérique
        case .petitEntier:
            return dialect == .oracle ? "NUMBER(5)" : dialect == .sqlite ? "INTEGER" : "SMALLINT"
        case .entier, .compteur:
            switch dialect {
            case .oracle: return "NUMBER(10)"
            case .sqlite, .postgresql: return "INTEGER"
            default: return "INT"
            }
        case .grandEntier:
            return dialect == .oracle ? "NUMBER(19)" : dialect == .sqlite ? "INTEGER" : "BIGINT"
        case .decimal:
            let p = isMySQL ? min(spec.precision, 65) : spec.precision
            let scale = isMySQL ? min(spec.scale, 30, p) : spec.scale
            switch dialect {
            case .oracle: return "NUMBER(\(p),\(scale))"
            case .postgresql, .sqlite: return "NUMERIC(\(p),\(scale))"
            default: return "DECIMAL(\(p),\(scale))"
            }
        case .reel:
            switch dialect {
            case .mysql, .mariadb: return "DOUBLE"
            case .postgresql: return "DOUBLE PRECISION"
            case .sqlserver: return "FLOAT"
            case .oracle: return "BINARY_DOUBLE"
            case .sqlite: return "REAL"
            }
        case .monetaire:
            switch dialect {
            case .sqlserver: return "MONEY"
            case .oracle: return "NUMBER(19,4)"
            case .postgresql, .sqlite: return "NUMERIC(19,4)"
            default: return "DECIMAL(19,4)"
            }
        // Date et heure
        case .date:
            return dialect == .sqlite ? "TEXT" : "DATE"
        case .heure:
            switch dialect {
            case .oracle: return "INTERVAL DAY(0) TO SECOND(0)"
            case .sqlite: return "TEXT"
            default: return "TIME"
            }
        case .dateHeure:
            switch dialect {
            case .mysql, .mariadb: return "DATETIME"
            case .sqlserver: return "DATETIME2"
            case .sqlite: return "TEXT"
            default: return "TIMESTAMP"
            }
        case .horodatage:
            switch dialect {
            case .mysql, .mariadb: return "TIMESTAMP"
            case .postgresql: return "TIMESTAMPTZ"
            case .sqlserver: return "DATETIMEOFFSET"
            case .oracle: return "TIMESTAMP WITH TIME ZONE"
            case .sqlite: return "TEXT"
            }
        // Autre
        case .booleen:
            switch dialect {
            case .sqlserver: return "BIT"
            case .oracle: return "NUMBER(1)"
            case .sqlite: return "INTEGER"
            default: return "BOOLEAN"
            }
        case .uuid:
            switch dialect {
            case .mysql: return "CHAR(36)"
            case .mariadb, .postgresql: return "UUID"
            case .sqlserver: return "UNIQUEIDENTIFIER"
            case .oracle: return "RAW(16)"
            case .sqlite: return "TEXT"
            }
        case .json:
            switch dialect {
            case .mysql, .mariadb: return "JSON"
            case .postgresql: return "JSONB"
            case .sqlserver: return "NVARCHAR(MAX)"
            case .oracle: return "CLOB"
            case .sqlite: return "TEXT"
            }
        case .xml:
            switch dialect {
            case .mysql, .mariadb: return "LONGTEXT"
            case .postgresql, .sqlserver: return "XML"
            case .oracle: return "XMLTYPE"
            case .sqlite: return "TEXT"
            }
        case .enumeration:
            // Pas d'ENUM en MySQL : obligatoire et sans valeur, il prend en silence la première valeur
            // de la liste (vérifié sur MariaDB). Un texte contrôlé par CHECK refuse vraiment l'oubli.
            let values = spec.enumValues
            let width = max(values.map(\.count).max() ?? 0, 1)
            switch dialect {
            case .oracle: return "VARCHAR2(\(width))"
            case .sqlite: return "TEXT"
            case .sqlserver: return "NVARCHAR(\(width))"
            default: return "VARCHAR(\(width))"
            }
        case .geometrique:
            switch dialect {
            case .oracle: return "SDO_GEOMETRY"
            case .sqlite: return "BLOB"
            default: return "GEOMETRY"
            }
        case .geographique:
            switch dialect {
            case .mysql: return "GEOMETRY SRID 4326"
            case .mariadb: return "GEOMETRY"
            case .postgresql, .sqlserver: return "GEOGRAPHY"
            case .oracle: return "SDO_GEOMETRY"
            case .sqlite: return "BLOB"
            }
        case .libre:
            let custom = spec.custom.filter { $0.isLetter || $0.isNumber || " (),_".contains($0) }
            return custom.isEmpty ? sqlType(TypeSpec(kind: .varchar), dialect: dialect) : custom.uppercased()
        }
    }

    /// Chaîne SQL entre apostrophes, apostrophes internes doublées.
    static func quoted(_ text: String) -> String {
        "'" + text.replacingOccurrences(of: "'", with: "''") + "'"
    }

    /// Clause de collation, seulement pour un texte et si le SGBD la comprend.
    static func collation(_ spec: TypeSpec, dialect: SQLDialect) -> String? {
        let spec = spec.normalized
        guard spec.kind.usesCollation, !spec.collation.isEmpty else { return nil }
        return dialect == .postgresql ? "COLLATE \"\(spec.collation)\"" : "COLLATE \(spec.collation)"
    }

    /// Contrôle de valeurs ajouté à la colonne : énumération (hors MySQL qui a ENUM),
    /// booléen sans vrai type, JSON valide quand le SGBD sait le vérifier.
    static func check(_ column: MLDColumn, dialect: SQLDialect) -> String? {
        let spec = column.spec.normalized
        switch spec.kind {
        case .enumeration where !spec.enumValues.isEmpty:
            return "CHECK (\(ident(column.name, dialect)) IN (" + spec.enumValues.map(quoted).joined(separator: ", ") + "))"
        case .booleen where dialect == .oracle || dialect == .sqlite:
            return "CHECK (\(ident(column.name, dialect)) IN (0, 1))"
        case .json where dialect == .sqlserver:
            return "CHECK (ISJSON(\(ident(column.name, dialect))) = 1)"
        case .json where dialect == .oracle:
            return "CHECK (\(ident(column.name, dialect)) IS JSON)"
        case .json where dialect == .sqlite:
            return "CHECK (json_valid(\(ident(column.name, dialect))))"
        default:
            return nil
        }
    }

    /// Complément SQL saisi par l'utilisateur, nettoyé pour ne pas casser le script.
    static func complement(_ text: String) -> String? {
        var cleaned = text.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespaces)
        while cleaned.hasSuffix(";") || cleaned.hasSuffix(",") { cleaned.removeLast(); cleaned = cleaned.trimmingCharacters(in: .whitespaces) }
        return cleaned.isEmpty ? nil : cleaned
    }

    /// Génération automatique de valeurs pour un compteur. Un seul par table ; il doit être
    /// la clé primaire (ou unique) pour que tous les SGBD l'acceptent.
    static func identityClause(_ column: MLDColumn, in table: MLDTable, dialect: SQLDialect) -> String? {
        guard column.type == .compteur, column.reference == nil,
              table.columns.first(where: { $0.type == .compteur && $0.reference == nil })?.name == column.name,
              column.isPrimaryKey || column.isUnique else { return nil }
        switch dialect {
        case .mysql, .mariadb: return "AUTO_INCREMENT"
        case .postgresql, .oracle: return "GENERATED BY DEFAULT AS IDENTITY"
        case .sqlserver: return "IDENTITY(1,1)"
        case .sqlite: return nil // géré par « INTEGER PRIMARY KEY AUTOINCREMENT »
        }
    }
}

/// Export du MLD au format XML (équivalent de « MLD textuel au format XML » de Looping).
enum MLDXMLExporter {
    static func xml(_ tables: [MLDTable]) -> String {
        func escape(_ text: String) -> String {
            text.replacingOccurrences(of: "&", with: "&amp;")
                .replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;")
                .replacingOccurrences(of: "\"", with: "&quot;")
        }
        var lines = ["<?xml version=\"1.0\" encoding=\"UTF-8\"?>", "<mld generateur=\"Cardinal\">"]
        for table in tables {
            lines.append("  <table nom=\"\(escape(table.name))\" association=\"\(table.comesFromAssociation)\">")
            for column in table.columns {
                var attributes = "nom=\"\(escape(column.name))\" type=\"\(escape(column.spec.display))\""
                if column.type.usesLength { attributes += " longueur=\"\(column.spec.normalized.length)\"" }
                if column.isPrimaryKey { attributes += " clePrimaire=\"true\"" }
                if !column.isNullable { attributes += " nonNul=\"true\"" }
                if column.isUnique { attributes += " unique=\"true\"" }
                if let reference = column.reference {
                    attributes += " reference=\"\(escape(reference.table)).\(escape(reference.column))\""
                }
                lines.append("    <colonne \(attributes)/>")
            }
            lines.append("  </table>")
        }
        lines.append("</mld>")
        return lines.joined(separator: "\n")
    }
}
