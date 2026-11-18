import Foundation
#if canImport(CoreGraphics)
import CoreGraphics // CGRect et ses fonctions ; sous Windows et Linux, Foundation les fournit
#endif

/// Lecture des fichiers Looping (.loo) pour les ouvrir dans Cardinal (interopérabilité).
///
/// Le format a été décodé par analyse de fichiers réels, sans le code de Looping :
/// - c'est une sauvegarde MFC (CArchive) : une liste d'objets, chacun avec un en-tête commun
///   (type sur 4 octets puis six mots à 1, trois blocs de style, puis un identifiant) ;
/// - types : 1 = association, 4 = entité, 32 = segment de patte, 64 = texte ;
/// - une entité porte son rectangle ; une association son centre et ses demi-dimensions ;
///   les textes qui suivent un objet sont son nom et ses propriétés ;
/// - une table finale relie chaque patte (texte « Lien N ») à son entité et à son association ;
///   la cardinalité est codée dans le texte suivant (0 = 0,1 ; 1 = 1,1 ; 2 = 0,N ; 3 = 1,N).
enum LooImporter {
    enum Failure: Error, LocalizedError {
        case notLooping
        var errorDescription: String? { "Ce fichier ne ressemble pas à un modèle Looping (.loo)." }
    }

    private enum Kind: UInt32 {
        case association = 1, entity = 4, arc = 32, text = 64
    }

    private struct Object {
        var kind: Kind
        var id: Int32
        var marker: Int
        var end: Int
    }

    /// Multiplicité UML : « * », « 1 », « 0..1 », « 1..* », « 2..5 »…
    static func isMultiplicity(_ text: String) -> Bool {
        let t = text.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return false }
        let parts = t.components(separatedBy: "..")
        guard parts.count <= 2 else { return false }
        return parts.allSatisfy { $0 == "*" || (!$0.isEmpty && $0.allSatisfy(\.isNumber)) }
    }

    static func model(from data: Data) throws -> MCDModel {
        try Reader(bytes: [UInt8](data)).run()
    }

    private struct Reader {
        let bytes: [UInt8]

        func i32(_ offset: Int) -> Int32? {
            guard offset >= 0, offset + 4 <= bytes.count else { return nil }
            return Int32(bitPattern: UInt32(bytes[offset]) | UInt32(bytes[offset + 1]) << 8
                | UInt32(bytes[offset + 2]) << 16 | UInt32(bytes[offset + 3]) << 24)
        }

        func u16(_ offset: Int) -> Int? {
            guard offset >= 0, offset + 2 <= bytes.count else { return nil }
            return Int(bytes[offset]) | Int(bytes[offset + 1]) << 8
        }

        /// Chaîne MFC Unicode : FF FE FF, longueur (1 octet, ou FF + 2 octets), puis UTF-16.
        func string(at offset: Int) -> (String, Int)? {
            guard offset + 4 <= bytes.count, bytes[offset] == 0xFF, bytes[offset + 1] == 0xFE, bytes[offset + 2] == 0xFF else { return nil }
            var length = Int(bytes[offset + 3])
            var start = offset + 4
            if length == 0xFF {
                guard let long = u16(offset + 4) else { return nil }
                length = long
                start = offset + 6
            }
            let end = start + length * 2
            guard end <= bytes.count else { return nil }
            let text = String(decoding: stride(from: start, to: end, by: 2).map { UInt16(bytes[$0]) | UInt16(bytes[$0 + 1]) << 8 }, as: UTF16.self)
            return (text, end)
        }

        func strings(in range: Range<Int>) -> [String] {
            var result: [String] = []
            var offset = range.lowerBound
            while offset < range.upperBound - 3 {
                if let (text, end) = string(at: offset) {
                    if !text.isEmpty { result.append(text) }
                    offset = max(end, offset + 1)
                } else {
                    offset += 1
                }
            }
            return result
        }

        func find(_ pattern: [UInt8], in range: Range<Int>) -> Int? {
            guard pattern.count <= range.count else { return nil }
            var offset = range.lowerBound
            while offset + pattern.count <= range.upperBound {
                if bytes[offset] == pattern[0], Array(bytes[offset..<offset + pattern.count]) == pattern { return offset }
                offset += 1
            }
            return nil
        }

        // MARK: Objets

        func objects() -> [Object] {
            let signature: [UInt8] = [1, 0, 1, 0, 1, 0, 1, 0, 1, 0, 1, 0]
            var markers: [(Int, Kind)] = []
            var offset = 4
            while offset + signature.count <= bytes.count {
                if bytes[offset] == 1, Array(bytes[offset..<offset + signature.count]) == signature,
                   let raw = i32(offset - 4), let kind = Kind(rawValue: UInt32(bitPattern: raw)) {
                    markers.append((offset, kind))
                    offset += signature.count
                } else {
                    offset += 1
                }
            }
            return markers.enumerated().compactMap { index, item in
                guard let id = i32(item.0 + 96) else { return nil }
                let end = index + 1 < markers.count ? markers[index + 1].0 - 6 : bytes.count
                return Object(kind: item.1, id: id, marker: item.0, end: max(end, item.0))
            }
        }

        // MARK: Propriétés

        /// Enregistrement d'une propriété : code, (type, 1, 0), 3 chaînes, entier, libellé, 2 chaînes, 14 entiers.
        func attributes(in range: Range<Int>) -> [Attribute] {
            var result: [Attribute] = []
            /// Nombre d'identifiants, lu juste avant la première propriété : (65536, nombre de propriétés,
            /// nombre d'identifiants). Les identifiants sont les premières propriétés de la liste.
            var identifierCount: Int?
            var offset = range.lowerBound
            while offset < range.upperBound - 3 {
                guard let (code, afterCode) = string(at: offset) else {
                    offset += 1
                    continue
                }
                guard !code.isEmpty, let typeIndex = i32(afterCode), i32(afterCode + 4) == 1, i32(afterCode + 8) == 0,
                      (0..<64).contains(typeIndex) else {
                    offset = max(afterCode, offset + 1)
                    continue
                }
                var cursor = afterCode + 12
                var valid = true
                for _ in 0..<3 {
                    guard let (_, next) = string(at: cursor) else { valid = false; break }
                    cursor = next
                }
                guard valid else { offset = afterCode; continue }
                cursor += 4
                guard let (label, afterLabel) = string(at: cursor) else { offset = afterCode; continue }
                cursor = afterLabel
                for _ in 0..<2 {
                    guard let (_, next) = string(at: cursor) else { valid = false; break }
                    cursor = next
                }
                guard valid, let identifierFlag = i32(cursor + 36) else { offset = afterCode; continue }

                var length = 50
                if let precision = find([15, 0, 0, 0, 2, 0, 0, 0], in: cursor..<min(cursor + 400, range.upperBound)),
                   let stored = i32(precision - 24), stored > 0, stored < 10_000 {
                    length = Int(stored)
                }
                // Codes de type relevés dans de vrais fichiers Looping ; un code inconnu reste du texte.
                let type: DataType = switch typeIndex {
                case 1: .decimal   // DECIMAL(15,2) par défaut dans Looping
                case 2: .date
                case 3: .booleen
                default: .varchar
                }
                if result.isEmpty, i32(offset - 12) == 65536, let total = i32(offset - 8), let ids = i32(offset - 4),
                   total > 0, ids >= 0, ids <= total {
                    identifierCount = Int(ids)
                }
                result.append(Attribute(
                    name: code.trimmingCharacters(in: .whitespaces), type: type, length: length, precision: 15, scale: 2, isIdentifier: identifierFlag == 1,
                    label: label == code ? "" : label
                ))
                offset = cursor + 56
            }
            // Le compte d'identifiants fait foi ; l'indicateur propre à chaque propriété ne sert qu'à défaut
            // (dans certains fichiers, il est aussi à 1 pour des propriétés qui ne sont pas des identifiants).
            if let identifierCount {
                for index in result.indices { result[index].isIdentifier = index < identifierCount }
            }
            return result
        }

        // MARK: Construction du MCD

        func run() throws -> MCDModel {
            let objects = objects()
            guard objects.contains(where: { $0.kind == .entity }) else { throw Failure.notLooping }
            let byID = Dictionary(objects.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

            var model = MCDModel()
            var entityIDs: [Int32: UUID] = [:]
            var associationIDs: [Int32: UUID] = [:]
            var rawPositions: [UUID: CGPoint] = [:]

            for (index, object) in objects.enumerated() where object.kind == .entity || object.kind == .association {
                // Les textes qui suivent l'objet : son nom et ses propriétés.
                var name = ""
                var attributes: [Attribute] = []
                var next = index + 1
                while next < objects.count, objects[next].kind == .text {
                    let range = objects[next].marker..<objects[next].end
                    let found = self.attributes(in: range)
                    if !found.isEmpty {
                        attributes = found
                    } else if name.isEmpty, let text = strings(in: range).first {
                        name = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                    next += 1
                }

                if object.kind == .entity {
                    guard let left = i32(object.marker + 168), let top = i32(object.marker + 172),
                          let right = i32(object.marker + 176), let bottom = i32(object.marker + 180) else { continue }
                    let entity = Entity(name: name.isEmpty ? "Entité \(object.id)" : name, attributes: attributes, position: .zero)
                    entityIDs[object.id] = entity.id
                    rawPositions[entity.id] = CGPoint(x: CGFloat(left + right) / 2, y: CGFloat(top + bottom) / 2)
                    model.entities.append(entity)
                } else {
                    guard let x = i32(object.marker + 166), let y = i32(object.marker + 170) else { continue }
                    let association = Association(
                        name: name.isEmpty ? "Association \(object.id)" : name,
                        attributes: attributes.map { var attribute = $0; attribute.isIdentifier = false; return attribute },
                        position: .zero
                    )
                    associationIDs[object.id] = association.id
                    rawPositions[association.id] = CGPoint(x: CGFloat(x), y: CGFloat(y))
                    model.associations.append(association)
                }
            }

            // Pattes. Chaque liaison laisse deux enregistrements voisins dans le fichier :
            // (trois numéros de textes consécutifs, dans un ordre quelconque, segment de départ ou 0,
            // segment d'arrivée ou 0, nœud relié, 1). L'un rattache la liaison à l'entité, l'autre à
            // l'association. Le texte du milieu de l'enregistrement « d'arrivée » (segment de départ
            // à 0) porte la cardinalité et le rôle.
            struct Record { let offset: Int; let texts: [Int32]; let node: Int32; let arrival: Bool }
            let arcs = Set(objects.filter { $0.kind == .arc }.map(\.id))
            var records: [Record] = []
            var offset = 12
            while offset + 16 <= bytes.count {
                if i32(offset + 12) == 1, let a = i32(offset), let b = i32(offset + 4), let node = i32(offset + 8),
                   (arcs.contains(a) && b == 0) || (a == 0 && arcs.contains(b)),
                   entityIDs[node] != nil || associationIDs[node] != nil,
                   let t1 = i32(offset - 12), let t2 = i32(offset - 8), let t3 = i32(offset - 4) {
                    let texts = [t1, t2, t3].sorted()
                    if texts[0] > 0, texts[1] == texts[0] + 1, texts[2] == texts[0] + 2 {
                        records.append(Record(offset: offset, texts: texts, node: node, arrival: a == 0))
                        offset += 16
                        continue
                    }
                }
                offset += 1
            }
            var index = 0
            while index + 1 < records.count {
                let pair = [records[index], records[index + 1]]
                // Deux enregistrements d'une même liaison : voisins, l'un vers une entité, l'autre vers une association.
                guard pair[1].offset - pair[0].offset < 160,
                      let entityRaw = pair.map(\.node).first(where: { entityIDs[$0] != nil }),
                      let associationRaw = pair.map(\.node).first(where: { associationIDs[$0] != nil }),
                      let entityID = entityIDs[entityRaw], let associationID = associationIDs[associationRaw],
                      let associationIndex = model.associations.firstIndex(where: { $0.id == associationID }) else {
                    index += 1
                    continue
                }
                index += 2

                var leg = Leg(entityID: entityID)
                let labelRecord = pair.first(where: \.arrival) ?? pair[0]
                if let cardinalityText = byID[labelRecord.texts[1]] {
                    let range = cardinalityText.marker..<cardinalityText.end
                    if let code = find([15, 0, 0, 0, 2, 0, 0, 0, 1, 0, 0, 0], in: range), let value = i32(code + 12) {
                        leg.cardinality = switch value {
                        case 0: .zeroOne
                        case 1: .oneOne
                        case 3: .oneMany
                        default: .zeroMany
                        }
                    }
                    // Le second texte est le rôle… sauf quand Looping y range la multiplicité UML
                    // de la patte (« * », « 1 », « 0..1 », « 1..* ») : ce n'est pas un rôle.
                    let texts = strings(in: range)
                    if texts.count >= 2, !LooImporter.isMultiplicity(texts[1]) { leg.role = texts[1].trimmingCharacters(in: .whitespaces) }
                }
                model.associations[associationIndex].legs.append(leg)
            }

            // Mise à l'échelle : les nœuds de Cardinal sont plus grands que ceux de Looping.
            let points = Array(rawPositions.values)
            let minX = points.map(\.x).min() ?? 0
            let minY = points.map(\.y).min() ?? 0
            let scale: CGFloat = 1.7
            func place(_ id: UUID) -> CGPoint {
                let raw = rawPositions[id] ?? .zero
                return CGPoint(x: 180 + (raw.x - minX) * scale, y: 140 + (raw.y - minY) * scale)
            }
            for i in model.entities.indices { model.entities[i].position = place(model.entities[i].id) }
            for i in model.associations.indices { model.associations[i].position = place(model.associations[i].id) }
            return model
        }
    }
}
