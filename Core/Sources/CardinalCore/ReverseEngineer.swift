import Foundation
#if canImport(CoreGraphics)
import CoreGraphics // CGRect et ses fonctions ; sous Windows et Linux, Foundation les fournit
#endif

/// Rétroconception : reconstruit un MCD à partir d'un script DDL (CREATE TABLE / ALTER TABLE).
enum ReverseEngineer {
    struct ParsedColumn: Equatable {
        var name: String
        var rawType: String
        var notNull = false
        var unique = false
        var autoIncrement = false
        var unicode = false
        var collation = ""
        var comment = ""
        var defaultValue = ""
        /// Valeurs d'un CHECK (colonne IN (…)), ou contrôle JSON reconnu.
        var checkValues: [String] = []
        var checksJSON = false
    }

    struct ParsedForeignKey: Equatable {
        var columns: [String]
        var table: String
        var refColumns: [String]
    }

    struct ParsedTable: Equatable {
        var name: String
        var columns: [ParsedColumn] = []
        var primaryKey: [String] = []
        var foreignKeys: [ParsedForeignKey] = []
        var uniques: [[String]] = []
        /// CHECK au niveau de la table : colonne → valeurs autorisées.
        var checks: [String: [String]] = [:]
        var comments: [String: String] = [:]
    }

    enum Failure: Error, LocalizedError {
        case noTable
        var errorDescription: String? { "Aucune instruction CREATE TABLE n'a été trouvée dans ce script." }
    }

    // MARK: - Point d'entrée

    static func model(from sql: String) throws -> MCDModel {
        let tables = parse(sql)
        guard !tables.isEmpty else { throw Failure.noTable }
        return buildModel(tables)
    }

    // MARK: - Analyse du SQL

    static func parse(_ sql: String) -> [ParsedTable] {
        var tables: [ParsedTable] = []
        for statement in statements(tokenize(sql)) {
            let upper = statement.map { $0.uppercased() }
            if let tableIndex = upper.firstIndex(of: "TABLE"), upper.first == "CREATE" {
                var index = tableIndex + 1
                if upper.count > index + 2, upper[index] == "IF", upper[index + 1] == "NOT", upper[index + 2] == "EXISTS" { index += 3 }
                guard index < statement.count else { continue }
                let name = unqualified(statement[index])
                guard let open = statement[index...].firstIndex(of: "("), let close = matchingParen(statement, open) else { continue }
                var table = ParsedTable(name: name)
                for item in splitTopLevel(Array(statement[(open + 1)..<close])) where !item.isEmpty {
                    parseItem(item, into: &table)
                }
                tables.append(table)
            } else if upper.count >= 5, upper[0] == "COMMENT", upper[1] == "ON", upper[2] == "COLUMN",
                      let isIndex = upper.firstIndex(of: "IS"), isIndex + 1 < statement.count {
                // COMMENT ON COLUMN table.colonne IS '…' (PostgreSQL, Oracle).
                let target = statement[3...].prefix(while: { $0.uppercased() != "IS" }).joined().replacingOccurrences(of: quotedMark, with: "")
                let pieces = target.split(separator: ".").map(String.init)
                guard pieces.count >= 2, let tableIndex = tables.firstIndex(where: { $0.name.lowercased() == pieces[pieces.count - 2].lowercased() }) else { continue }
                tables[tableIndex].comments[pieces[pieces.count - 1].lowercased()] = unquoted(statement[isIndex + 1])
            } else if upper.first == "ALTER", upper.count > 3, upper[1] == "TABLE" {
                var index = 2
                if upper[index] == "ONLY" { index += 1 }
                let name = unqualified(statement[index])
                guard let tableIndex = tables.firstIndex(where: { $0.name.lowercased() == name.lowercased() }),
                      let add = upper.firstIndex(of: "ADD") else { continue }
                parseItem(Array(statement[(add + 1)...]), into: &tables[tableIndex])
            }
        }
        return tables
    }

    private static func parseItem(_ tokens: [String], into table: inout ParsedTable) {
        var tokens = tokens
        if tokens.first?.uppercased() == "CONSTRAINT" { tokens.removeFirst(min(2, tokens.count)) }
        guard let first = tokens.first?.uppercased() else { return }
        let upper = tokens.map { $0.uppercased() }

        switch first {
        case "PRIMARY":
            table.primaryKey = names(inParensAfter: 0, in: tokens)
        case "FOREIGN":
            let columns = names(inParensAfter: 0, in: tokens)
            guard let ref = upper.firstIndex(of: "REFERENCES"), ref + 1 < tokens.count else { return }
            let target = unqualified(tokens[ref + 1])
            var refColumns = names(inParensAfter: ref + 1, in: tokens)
            if refColumns.isEmpty { refColumns = columns }
            table.foreignKeys.append(ParsedForeignKey(columns: columns, table: target, refColumns: refColumns))
        case "UNIQUE":
            table.uniques.append(names(inParensAfter: 0, in: tokens))
        case "CHECK":
            if let (column, values) = checkInList(tokens, from: 1) { table.checks[column.lowercased()] = values }
        case "KEY", "INDEX", "FULLTEXT", "SPATIAL", "EXCLUDE":
            // « KEY idx (col) » est un index MySQL ; « key INT » est une colonne nommée key.
            let second = tokens.count > 1 ? tokens[1] : ""
            let isColumn = second != "(" && upper.count > 1 && upper[1] != "USING" && upper[1] != "KEY" && upper[1] != "INDEX"
                && ReverseEngineer.typeSpec(second).kind != .libre
            if isColumn { parseColumn(tokens, into: &table) }
        default:
            parseColumn(tokens, into: &table)
        }
    }

    private static let columnStopWords: Set<String> = [
        "NOT", "NULL", "PRIMARY", "UNIQUE", "REFERENCES", "DEFAULT", "AUTO_INCREMENT", "AUTOINCREMENT",
        "IDENTITY", "CONSTRAINT", "CHECK", "GENERATED", "COLLATE", "COMMENT", "ON", "CHARACTER", "CHARSET",
    ]

    private static func parseColumn(_ tokens: [String], into table: inout ParsedTable) {
        let name = unqualified(tokens[0])
        let upper = tokens.map { $0.uppercased() }
        var index = 1
        var typeTokens: [String] = []
        // « CHARACTER VARYING » est un type ; « CHARACTER SET » ouvre une option.
        func isStop(_ i: Int) -> Bool {
            if upper[i] == "CHARACTER" { return i + 1 < upper.count && upper[i + 1] == "SET" }
            return columnStopWords.contains(upper[i])
        }
        while index < tokens.count, !isStop(index) {
            if tokens[index] == "(", let close = matchingParen(tokens, index) {
                typeTokens.append("(" + tokens[(index + 1)..<close].joined() + ")")
                index = close + 1
            } else {
                typeTokens.append(upper[index])
                index += 1
            }
        }
        var column = ParsedColumn(name: name, rawType: typeTokens.joined(separator: " ").replacingOccurrences(of: " (", with: "("))
        while index < tokens.count {
            switch upper[index] {
            case "NOT" where index + 1 < tokens.count && upper[index + 1] == "NULL":
                column.notNull = true
                index += 2
            case "PRIMARY":
                if !table.primaryKey.contains(name) { table.primaryKey.append(name) }
                column.notNull = true
                index += 2
            case "UNIQUE":
                column.unique = true
                index += 1
            case "AUTO_INCREMENT", "AUTOINCREMENT", "IDENTITY":
                column.autoIncrement = true
                index += 1
                if index < tokens.count, tokens[index] == "(", let close = matchingParen(tokens, index) { index = close + 1 }
            case "GENERATED":
                // GENERATED { ALWAYS | BY DEFAULT } AS IDENTITY
                if let identity = upper[index...].prefix(6).firstIndex(of: "IDENTITY") {
                    column.autoIncrement = true
                    index = identity + 1
                } else {
                    index += 1
                }
            case "CHARACTER", "CHARSET":
                var next = index + 1
                if upper[index] == "CHARACTER", next < tokens.count, upper[next] == "SET" { next += 1 }
                if next < tokens.count, upper[next].hasPrefix("UTF8") || upper[next].hasPrefix("UTF16") || upper[next] == "UCS2" { column.unicode = true }
                index = next + 1
            case "COLLATE" where index + 1 < tokens.count:
                column.collation = unqualified(tokens[index + 1])
                index += 2
            case "COMMENT" where index + 1 < tokens.count:
                column.comment = unquoted(tokens[index + 1])
                index += 2
            case "DEFAULT" where index + 1 < tokens.count:
                var end = index + 2
                if tokens[index + 1] == "(", let close = matchingParen(tokens, index + 1) { end = close + 1 }
                else if end < tokens.count, tokens[end] == "(", let close = matchingParen(tokens, end) { end = close + 1 }
                column.defaultValue = "DEFAULT " + tokens[(index + 1)..<end].joined(separator: " ")
                    .replacingOccurrences(of: "( ", with: "(").replacingOccurrences(of: " )", with: ")")
                    .replacingOccurrences(of: " (", with: "(")
                index = end
            case "CHECK":
                let rest = upper[index...].joined(separator: " ")
                if rest.contains("JSON_VALID") || rest.contains("ISJSON") || rest.contains("IS JSON") { column.checksJSON = true }
                if let (_, values) = checkInList(tokens, from: index + 1) { column.checkValues = values }
                if index + 1 < tokens.count, tokens[index + 1] == "(", let close = matchingParen(tokens, index + 1) { index = close + 1 } else { index += 1 }
            case "REFERENCES" where index + 1 < tokens.count:
                let target = unqualified(tokens[index + 1])
                var refColumns = names(inParensAfter: index + 1, in: tokens)
                if refColumns.isEmpty { refColumns = [name] }
                table.foreignKeys.append(ParsedForeignKey(columns: [name], table: target, refColumns: refColumns))
                index += 2
            default:
                index += 1
            }
        }
        table.columns.append(column)
    }

    // MARK: - Reconstruction du MCD

    static func buildModel(_ tables: [ParsedTable]) -> MCDModel {
        var model = MCDModel()
        let known = Set(tables.map { $0.name.lowercased() })
        func validForeignKeys(_ table: ParsedTable) -> [ParsedForeignKey] {
            table.foreignKeys.filter { known.contains($0.table.lowercased()) }
        }

        // 1. Classement : table d'association (clé = uniquement des clés étrangères) ou entité.
        var associationTables: [ParsedTable] = []
        var entityTables: [ParsedTable] = []
        var subtypeOf: [String: String] = [:]
        for table in tables {
            let fks = validForeignKeys(table)
            let pk = Set(table.primaryKey.map { $0.lowercased() })
            let fkColumns = Set(fks.flatMap { $0.columns.map { $0.lowercased() } })
            let fksInKey = fks.filter { !Set($0.columns.map { $0.lowercased() }).isDisjoint(with: pk) }
            if !pk.isEmpty, pk.isSubset(of: fkColumns), fksInKey.count >= 2 {
                associationTables.append(table)
            } else {
                entityTables.append(table)
                if !pk.isEmpty, fksInKey.count == 1, Set(fksInKey[0].columns.map { $0.lowercased() }) == pk,
                   fksInKey[0].table.lowercased() != table.name.lowercased() {
                    subtypeOf[table.name.lowercased()] = fksInKey[0].table.lowercased()
                }
            }
        }

        // 2. Entités.
        var entityIDs: [String: UUID] = [:]
        for table in entityTables {
            let fkColumns = Set(validForeignKeys(table).flatMap { $0.columns.map { $0.lowercased() } })
            let pk = Set(table.primaryKey.map { $0.lowercased() })
            let attributes = table.columns.filter { !fkColumns.contains($0.name.lowercased()) }.map { column in
                attribute(from: column, isIdentifier: pk.contains(column.name.lowercased()), uniques: table.uniques, tableChecks: table.checks, tableComments: table.comments)
            }
            let entity = Entity(name: table.name, attributes: attributes, position: .zero)
            entityIDs[table.name.lowercased()] = entity.id
            model.entities.append(entity)
        }

        // 3. Héritages : les sous-types d'un même surtype sont regroupés.
        let groupedSubtypes = Dictionary(grouping: subtypeOf.keys.sorted()) { subtypeOf[$0]! }
        for (parentName, childNames) in groupedSubtypes.sorted(by: { $0.key < $1.key }) {
            guard let parent = entityIDs[parentName] else { continue }
            model.inheritances.append(Inheritance(
                parentID: parent,
                childIDs: childNames.compactMap { entityIDs[$0] },
                position: .zero
            ))
        }

        // 4. Clés étrangères des entités → associations binaires.
        for table in entityTables {
            guard let childID = entityIDs[table.name.lowercased()] else { continue }
            let pk = Set(table.primaryKey.map { $0.lowercased() })
            for fk in validForeignKeys(table) {
                if subtypeOf[table.name.lowercased()] == fk.table.lowercased(),
                   Set(fk.columns.map { $0.lowercased() }) == pk { continue }
                guard let parentID = entityIDs[fk.table.lowercased()] else { continue }
                let columns = fk.columns.compactMap { name in table.columns.first { $0.name.lowercased() == name.lowercased() } }
                let isRelative = !Set(fk.columns.map { $0.lowercased() }).isDisjoint(with: pk)
                let notNull = isRelative || (!columns.isEmpty && columns.allSatisfy(\.notNull))
                let isUnique = (columns.count == 1 && columns[0].unique)
                    || table.uniques.contains { Set($0.map { $0.lowercased() }) == Set(fk.columns.map { $0.lowercased() }) }
                model.associations.append(Association(
                    name: "\(table.name)_\(fk.table)",
                    legs: [
                        Leg(entityID: childID, cardinality: notNull ? .oneOne : .zeroOne, isRelative: isRelative),
                        Leg(entityID: parentID, cardinality: isUnique ? .zeroOne : .zeroMany, role: role(of: fk)),
                    ],
                    position: .zero
                ))
            }
        }

        // 5. Tables d'association → associations N,N (ou n-aires), avec CIF si une clé étrangère est hors clé primaire.
        for table in associationTables {
            let fks = validForeignKeys(table)
            let pk = Set(table.primaryKey.map { $0.lowercased() })
            let fkColumns = Set(fks.flatMap { $0.columns.map { $0.lowercased() } })
            var association = Association(
                name: table.name,
                attributes: table.columns.filter { !fkColumns.contains($0.name.lowercased()) }
                    .map { attribute(from: $0, isIdentifier: false, uniques: table.uniques, tableChecks: table.checks, tableComments: table.comments) },
                position: .zero
            )
            var cifTarget: UUID?
            for fk in fks {
                guard let entityID = entityIDs[fk.table.lowercased()] else { continue }
                association.legs.append(Leg(entityID: entityID, cardinality: .zeroMany, role: role(of: fk)))
                if Set(fk.columns.map { $0.lowercased() }).isDisjoint(with: pk) { cifTarget = entityID }
            }
            model.associations.append(association)
            if let target = cifTarget {
                model.constraints.append(Constraint(
                    kind: .cif,
                    links: [ConstraintLink(target: .association(association.id)), ConstraintLink(target: .entity(target), isTarget: true)],
                    position: .zero
                ))
            }
        }

        layout(&model)
        return model
    }

    private static func attribute(from column: ParsedColumn, isIdentifier: Bool, uniques: [[String]],
                                  tableChecks: [String: [String]] = [:], tableComments: [String: String] = [:]) -> Attribute {
        var spec = typeSpec(column.rawType, unicode: column.unicode)
        let checkValues = column.checkValues.isEmpty ? (tableChecks[column.name.lowercased()] ?? []) : column.checkValues
        if column.autoIncrement && spec.kind.isInteger { spec.kind = .compteur }
        if !checkValues.isEmpty {
            if Set(checkValues) == ["0", "1"] && (spec.kind.isInteger || spec.kind == .booleen) {
                spec.kind = .booleen
            } else if spec.kind.category == .texte || spec.kind == .enumeration {
                spec.kind = .enumeration
                spec.enumValues = checkValues
            }
        }
        if column.checksJSON && spec.kind.category == .texte { spec.kind = .json }
        spec.collation = column.collation
        let unique = column.unique || uniques.contains { $0.count == 1 && $0[0].lowercased() == column.name.lowercased() }
        var attribute = Attribute(
            name: column.name, isIdentifier: isIdentifier,
            isNotNull: column.notNull && !isIdentifier, isUnique: unique && !isIdentifier,
            complement: column.defaultValue, comment: column.comment.isEmpty ? (tableComments[column.name.lowercased()] ?? "") : column.comment
        )
        attribute.spec = spec.normalized
        return attribute
    }

    /// Traduit un type SQL (n'importe quel SGBD) en type Cardinal. Un type inconnu est conservé
    /// tel quel comme type « Libre » : rien n'est perdu.
    static func typeSpec(_ raw: String, unicode: Bool = false) -> TypeSpec {
        let upper = raw.uppercased().trimmingCharacters(in: .whitespaces)
        let words = upper.split(whereSeparator: { $0 == "(" || $0 == " " }).map(String.init)
        let base = words.first ?? upper
        let inside: String = {
            guard let open = raw.firstIndex(of: "("), let close = raw.lastIndex(of: ")"), open < close else { return "" }
            return String(raw[raw.index(after: open)..<close])
        }()
        let numbers = inside.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
        let isMax = inside.uppercased().contains("MAX")
        func text(_ kind: DataType) -> TypeSpec {
            var kind = kind
            if unicode { kind = DataType.text(.unicode, kind.storage ?? .variable) }
            if isMax { kind = DataType.text(kind.encoding ?? .ascii, .volumineux) }
            return TypeSpec(kind: kind, length: numbers.first ?? kind.defaultLength)
        }
        switch base {
        case "INT", "INTEGER", "MEDIUMINT", "INT4":
            return TypeSpec(kind: .entier)
        case "SMALLINT", "INT2":
            return TypeSpec(kind: .petitEntier)
        case "TINYINT":
            return TypeSpec(kind: numbers.first == 1 ? .booleen : .petitEntier)
        case "BIGINT", "INT8":
            return TypeSpec(kind: .grandEntier)
        case "SERIAL", "SMALLSERIAL", "BIGSERIAL", "SERIAL4", "SERIAL8", "COUNTER", "AUTOINCREMENT":
            return TypeSpec(kind: .compteur)
        case "NUMBER":
            if numbers.count >= 2, numbers[1] > 0 { return TypeSpec(kind: .decimal, precision: numbers[0], scale: numbers[1]) }
            switch numbers.first {
            case 1: return TypeSpec(kind: .booleen)
            case .some(let p) where p <= 5: return TypeSpec(kind: .petitEntier)
            case .some(let p) where p <= 10: return TypeSpec(kind: .entier)
            case .some(let p) where p <= 19: return TypeSpec(kind: .grandEntier)
            case .some(let p): return TypeSpec(kind: .decimal, precision: p, scale: 0)
            case .none: return TypeSpec(kind: .decimal, precision: 38, scale: 0)
            }
        case "DECIMAL", "NUMERIC", "DEC", "FIXED":
            return TypeSpec(kind: .decimal, precision: numbers.first ?? 10, scale: numbers.count > 1 ? numbers[1] : 0)
        case "MONEY", "SMALLMONEY", "CURRENCY":
            return TypeSpec(kind: .monetaire)
        case "FLOAT", "DOUBLE", "REAL", "BINARY_DOUBLE", "BINARY_FLOAT", "FLOAT4", "FLOAT8":
            return TypeSpec(kind: .reel)
        case "VARCHAR", "VARCHAR2", "VARYING":
            return text(.varchar)
        case "CHARACTER":
            return text(words.dropFirst().first == "VARYING" ? .varchar : .char)
        case "CHAR":
            return text(.char)
        case "NVARCHAR", "NVARCHAR2", "NATIONAL":
            return text(.nvarchar)
        case "NCHAR":
            return text(.nchar)
        case "TEXT", "LONGTEXT", "MEDIUMTEXT", "TINYTEXT", "CLOB", "LONG", "STRING":
            return TypeSpec(kind: unicode ? .ntext : .text)
        case "NTEXT", "NCLOB":
            return TypeSpec(kind: .ntext)
        case "VARBINARY":
            return isMax ? TypeSpec(kind: .blob) : TypeSpec(kind: .varbinary, length: numbers.first ?? 16)
        case "BINARY":
            return TypeSpec(kind: .binary, length: numbers.first ?? 16)
        case "RAW":
            return TypeSpec(kind: .varbinary, length: numbers.first ?? 16)
        case "BLOB", "LONGBLOB", "MEDIUMBLOB", "TINYBLOB", "BYTEA", "IMAGE":
            return TypeSpec(kind: .blob)
        case "DATE":
            return TypeSpec(kind: .date)
        case "TIME", "INTERVAL":
            return TypeSpec(kind: .heure)
        case "DATETIME", "DATETIME2", "SMALLDATETIME":
            return TypeSpec(kind: .dateHeure)
        case "TIMESTAMP":
            return TypeSpec(kind: upper.contains("WITH TIME ZONE") || upper.contains("WITH LOCAL TIME ZONE") ? .horodatage : .dateHeure)
        case "TIMESTAMPTZ", "DATETIMEOFFSET":
            return TypeSpec(kind: .horodatage)
        case "BOOLEAN", "BOOL", "BIT", "LOGICAL":
            return TypeSpec(kind: .booleen)
        case "UUID", "UNIQUEIDENTIFIER":
            return TypeSpec(kind: .uuid)
        case "JSON", "JSONB":
            return TypeSpec(kind: .json)
        case "XML", "XMLTYPE":
            return TypeSpec(kind: .xml)
        case "ENUM":
            let values = inside.split(separator: ",").map { unquoted(String($0).trimmingCharacters(in: .whitespaces)) }
            return TypeSpec(kind: .enumeration, enumValues: values)
        case "GEOGRAPHY":
            return TypeSpec(kind: .geographique)
        case "GEOMETRY", "POINT", "LINESTRING", "POLYGON", "MULTIPOINT", "MULTILINESTRING", "MULTIPOLYGON",
             "GEOMETRYCOLLECTION", "SDO_GEOMETRY":
            return TypeSpec(kind: upper.contains("SRID 4326") ? .geographique : .geometrique)
        default:
            return TypeSpec(kind: .libre, custom: raw.trimmingCharacters(in: .whitespaces))
        }
    }

    /// « (colonne IN ('a', 'b')) » → (colonne, [a, b]). Accepte aussi des nombres.
    private static func checkInList(_ tokens: [String], from start: Int) -> (String, [String])? {
        guard start < tokens.count, tokens[start] == "(", let close = matchingParen(tokens, start) else { return nil }
        let body = Array(tokens[(start + 1)..<close])
        guard body.count >= 4, body[1].uppercased() == "IN", body[2] == "(", let end = matchingParen(body, 2) else { return nil }
        let values = body[3..<end].filter { $0 != "," }.map(unquoted)
        guard !values.isEmpty else { return nil }
        return (unqualified(body[0]), values)
    }

    /// Retire les apostrophes d'une chaîne SQL ('l''été' → l'été).
    static func unquoted(_ token: String) -> String {
        guard token.count >= 2, token.hasPrefix("'"), token.hasSuffix("'") else { return token }
        return String(token.dropFirst().dropLast()).replacingOccurrences(of: "''", with: "'")
    }

    // MARK: - Mise en page automatique

    /// Place les entités sur une grille, chaque association au milieu de ses entités.
    static func layout(_ model: inout MCDModel) {
        let columns = max(2, Int(Double(model.entities.count).squareRoot().rounded(.up)))
        let spacingX: CGFloat = 430
        let spacingY: CGFloat = 320
        for index in model.entities.indices {
            let row = index / columns
            let column = index % columns
            model.entities[index].position = CGPoint(
                x: 220 + CGFloat(column) * spacingX + (row.isMultiple(of: 2) ? 0 : spacingX / 2),
                y: 200 + CGFloat(row) * spacingY
            )
        }
        var occupied: [CGPoint] = model.entities.map(\.position)
        func free(_ point: CGPoint) -> CGPoint {
            var candidate = point
            var attempt = 0
            while occupied.contains(where: { abs($0.x - candidate.x) < 190 && abs($0.y - candidate.y) < 70 }) && attempt < 12 {
                attempt += 1
                candidate.y += (attempt.isMultiple(of: 2) ? -1 : 1) * CGFloat(attempt) * 40
            }
            occupied.append(candidate)
            return candidate
        }
        for index in model.associations.indices {
            let points = model.associations[index].legs.compactMap { model.entity($0.entityID)?.position }
            guard !points.isEmpty else { continue }
            var center = CGPoint(x: points.map(\.x).reduce(0, +) / CGFloat(points.count),
                                 y: points.map(\.y).reduce(0, +) / CGFloat(points.count))
            if points.count == 1 || (points.count == 2 && points[0] == points[1]) { center.x += 260 }
            model.associations[index].position = free(center)
        }
        for index in model.inheritances.indices {
            let inheritance = model.inheritances[index]
            guard let parent = inheritance.parentID.flatMap(model.entity)?.position else { continue }
            let children = inheritance.childIDs.compactMap { model.entity($0)?.position }
            let average = children.isEmpty ? parent : CGPoint(
                x: children.map(\.x).reduce(0, +) / CGFloat(children.count),
                y: children.map(\.y).reduce(0, +) / CGFloat(children.count)
            )
            model.inheritances[index].position = free(CGPoint(x: (parent.x + average.x) / 2, y: (parent.y + average.y) / 2))
        }
        for index in model.constraints.indices {
            let points = model.constraints[index].links.compactMap { model.position(of: $0.target) }
            guard !points.isEmpty else { continue }
            let center = CGPoint(x: points.map(\.x).reduce(0, +) / CGFloat(points.count) + 90,
                                 y: points.map(\.y).reduce(0, +) / CGFloat(points.count) - 70)
            model.constraints[index].position = free(center)
        }
    }

    // MARK: - Découpage lexical

    static func tokenize(_ sql: String) -> [String] {
        var tokens: [String] = []
        let characters = Array(sql)
        var index = 0
        while index < characters.count {
            let character = characters[index]
            if character.isWhitespace {
                index += 1
            } else if character == "-", index + 1 < characters.count, characters[index + 1] == "-" {
                while index < characters.count, characters[index] != "\n" { index += 1 }
            } else if character == "#" {
                while index < characters.count, characters[index] != "\n" { index += 1 }
            } else if character == "/", index + 1 < characters.count, characters[index + 1] == "*" {
                index += 2
                while index + 1 < characters.count, !(characters[index] == "*" && characters[index + 1] == "/") { index += 1 }
                index += 2
            } else if character == "'" {
                var token = "'"
                index += 1
                while index < characters.count {
                    token.append(characters[index])
                    if characters[index] == "'" {
                        if index + 1 < characters.count, characters[index + 1] == "'" { index += 1; token.append("'") } else { break }
                    }
                    index += 1
                }
                index += 1
                tokens.append(token)
            } else if character == "`" || character == "\"" || character == "[" {
                let closing: Character = character == "[" ? "]" : character
                var token = ""
                index += 1
                while index < characters.count, characters[index] != closing {
                    token.append(characters[index])
                    index += 1
                }
                index += 1
                // Marque d'un nom délimité : « "key" » est une colonne, pas le mot-clé KEY.
                tokens.append(quotedMark + token)
            } else if "(),;".contains(character) {
                tokens.append(String(character))
                index += 1
            } else {
                var token = ""
                while index < characters.count, !characters[index].isWhitespace, !"(),;'`\"[".contains(characters[index]) {
                    token.append(characters[index])
                    index += 1
                }
                tokens.append(token)
            }
        }
        return tokens
    }

    private static func statements(_ tokens: [String]) -> [[String]] {
        var result: [[String]] = []
        var current: [String] = []
        for token in tokens {
            if token == ";" {
                if !current.isEmpty { result.append(current) }
                current = []
            } else {
                current.append(token)
            }
        }
        if !current.isEmpty { result.append(current) }
        return result
    }

    private static func matchingParen(_ tokens: [String], _ open: Int) -> Int? {
        var depth = 0
        for index in open..<tokens.count {
            if tokens[index] == "(" { depth += 1 }
            if tokens[index] == ")" {
                depth -= 1
                if depth == 0 { return index }
            }
        }
        return nil
    }

    private static func splitTopLevel(_ tokens: [String]) -> [[String]] {
        var items: [[String]] = []
        var current: [String] = []
        var depth = 0
        for token in tokens {
            if token == "(" { depth += 1 }
            if token == ")" { depth -= 1 }
            if token == ",", depth == 0 {
                items.append(current)
                current = []
            } else {
                current.append(token)
            }
        }
        items.append(current)
        return items
    }

    /// Noms entre parenthèses qui suivent la position donnée : « (a, b) ».
    private static func names(inParensAfter start: Int, in tokens: [String]) -> [String] {
        guard let open = tokens[start...].firstIndex(of: "("), let close = matchingParen(tokens, open) else { return [] }
        return tokens[(open + 1)..<close].filter { $0 != "," }.map(unqualified)
    }

    /// Rôle d'une patte retrouvé dans le nom des colonnes : « id_personne_parent » qui référence
    /// « id_personne » donne le rôle « parent » (c'est ainsi que Cardinal et Looping les nomment).
    private static func role(of fk: ParsedForeignKey) -> String {
        guard fk.columns.count == fk.refColumns.count, !fk.columns.isEmpty else { return "" }
        var suffix: String?
        for (local, remote) in zip(fk.columns, fk.refColumns) {
            let prefix = remote.lowercased() + "_"
            guard local.lowercased().hasPrefix(prefix), local.count > prefix.count else { return "" }
            let tail = String(local.dropFirst(prefix.count))
            // « _2 », « _3 » : simple numérotation pour éviter un doublon, pas un rôle.
            if tail.allSatisfy(\.isNumber) { return "" }
            if let suffix, suffix != tail { return "" }
            suffix = tail
        }
        return suffix ?? ""
    }

    /// Préfixe ajouté par l'analyseur aux noms écrits entre délimiteurs ("…", `…`, […]).
    static let quotedMark = "\u{1}"

    /// « schema.table » → « table », sans marque de délimiteur.
    private static func unqualified(_ name: String) -> String {
        let plain = name.replacingOccurrences(of: quotedMark, with: "")
        return String(plain.split(separator: ".").last ?? Substring(plain))
    }
}
