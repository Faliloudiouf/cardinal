import Foundation

struct MLDReference: Hashable, Sendable {
    var table: String
    var column: String
    /// Les colonnes d'une même clé étrangère composée partagent le même groupe.
    var group: Int
}

struct MLDColumn: Hashable, Sendable {
    var name: String
    /// Type et paramètres (longueur, précision, valeurs d'énumération…).
    var spec: TypeSpec
    var isPrimaryKey: Bool
    var isNullable: Bool
    var isUnique: Bool = false
    var reference: MLDReference?
    /// Complément SQL et commentaire de la propriété d'origine (pas recopiés sur une clé étrangère).
    var complement: String = ""
    var comment: String = ""

    var type: DataType { spec.kind }
    var length: Int { spec.length }
}

/// Contrainte de table qui ne porte pas sur une seule colonne.
enum MLDCheck: Hashable, Sendable {
    /// Au moins une des colonnes booléennes est vraie (héritage avec totalité).
    case atLeastOneTrue([String])
}

struct MLDTable: Hashable, Sendable, Identifiable {
    var id: String { name }
    var name: String
    var columns: [MLDColumn]
    var comesFromAssociation: Bool
    /// Élément du MCD d'où vient la table (sert à placer la table dans le MLD graphique).
    var origin: NodeRef?
    var checks: [MLDCheck] = []

    var primaryKey: [MLDColumn] { columns.filter(\.isPrimaryKey) }
}

/// Passage du MCD au MLD (règles de transformation Merise).
///
/// 1. Chaque entité devient une table ; ses identifiants forment la clé primaire.
///    Une entité fictive ne produit pas de table, mais son identifiant migre quand même.
/// 2. Association binaire avec une patte de cardinalité max 1 (0,1 ou 1,1) :
///    l'entité de cette patte reçoit une clé étrangère vers l'autre entité.
///    Si la patte est marquée « identifiant relatif », cette clé entre dans sa clé primaire.
/// 3. Toute autre association devient une table dont la clé primaire est la concaténation
///    des clés des entités reliées, sauf l'entité cible d'une CIF (clé étrangère simple).
/// 4. Héritage : une table par type (clé du sous-type = clé du surtype), sous-types seuls,
///    ou surtype seul avec une colonne discriminante.
enum MLDBuilder {
    static func build(_ model: MCDModel) -> [MLDTable] {
        Builder(model: model).run()
    }
}

private final class Builder {
    struct KeyPart {
        var name: String
        var spec: TypeSpec
        var complement = ""
        var comment = ""
        /// Entité dont la table porte réellement cette colonne (nil si elle vient d'une entité fictive).
        var ownerTable: Entity.ID?
    }

    let model: MCDModel
    let naming: NamingConvention
    private var keyCache: [Entity.ID: [KeyPart]] = [:]
    private var visiting: Set<Entity.ID> = []
    private var groupCounter = 0

    init(model: MCDModel) {
        self.model = model
        self.naming = model.settings.naming
    }

    // MARK: Héritage

    func parentInheritance(of id: Entity.ID) -> Inheritance? {
        model.inheritances.first { $0.parentID != nil && $0.parentID != id && $0.childIDs.contains(id) }
    }

    func childInheritances(of id: Entity.ID) -> [Inheritance] {
        model.inheritances.filter { $0.parentID == id && !$0.childIDs.isEmpty }
    }

    /// Entité dont la table contient physiquement les données de `id` (nil = pas de table).
    func host(_ id: Entity.ID) -> Entity.ID? {
        guard let entity = model.entity(id), !entity.isFictive else { return nil }
        if let inheritance = parentInheritance(of: id), inheritance.strategy == .surtypeSeul, let parent = inheritance.parentID {
            return host(parent)
        }
        if childInheritances(of: id).contains(where: { $0.strategy == .sousTypesSeuls }) { return nil }
        return id
    }

    func tableName(_ id: Entity.ID) -> String {
        naming.apply(model.entity(id)?.name ?? "sans_nom")
    }

    // MARK: Clés

    /// Clé primaire logique d'une entité (identifiants propres, hérités ou relatifs).
    func key(of id: Entity.ID) -> [KeyPart] {
        if let cached = keyCache[id] { return cached }
        guard let entity = model.entity(id), !visiting.contains(id) else { return [] }
        visiting.insert(id)
        defer { visiting.remove(id) }

        var parts: [KeyPart] = []
        if let inheritance = parentInheritance(of: id), let parent = inheritance.parentID,
           !entity.attributes.contains(where: \.isIdentifier) {
            // La clé héritée référence toujours la table du surtype direct.
            parts = key(of: parent).map { part in
                var part = part
                part.ownerTable = nil
                return part
            }
        }
        for attribute in entity.attributes where attribute.isIdentifier {
            parts.append(KeyPart(name: columnName(attribute), spec: attribute.spec,
                                 complement: attribute.complement, comment: attribute.comment, ownerTable: nil))
        }
        for (other, _) in relativeParents(of: id) {
            parts += key(of: other).map { part in
                var part = part
                part.ownerTable = host(other)
                return part
            }
        }
        keyCache[id] = parts
        return parts
    }

    /// Entités dont `id` dépend par un identifiant relatif (association binaire, patte (R) 1,1).
    func relativeParents(of id: Entity.ID) -> [(Entity.ID, Association)] {
        model.associations.compactMap { association in
            let legs = association.legs.filter { model.entity($0.entityID) != nil }
            guard legs.count == 2,
                  let mine = legs.firstIndex(where: { $0.entityID == id && $0.isRelative && $0.cardinality.isMaxOne }) else { return nil }
            let other = legs[1 - mine].entityID
            return other == id ? nil : (other, association)
        }
    }

    // MARK: Construction

    func run() -> [MLDTable] {
        var tables: [Entity.ID: MLDTable] = [:]
        var order: [Entity.ID] = []

        for entity in model.entities where host(entity.id) == entity.id {
            var table = MLDTable(name: tableName(entity.id), columns: [], comesFromAssociation: false, origin: .entity(entity.id))
            appendKey(of: entity.id, into: &table)

            // Sous-types seuls : les propriétés du surtype descendent dans le sous-type.
            if let inheritance = parentInheritance(of: entity.id), inheritance.strategy == .sousTypesSeuls,
               let parent = inheritance.parentID, let parentEntity = model.entity(parent) {
                appendAttributes(parentEntity.attributes.filter { !$0.isIdentifier }, into: &table, nullable: false)
            }
            appendAttributes(entity.attributes.filter { !$0.isIdentifier }, into: &table, nullable: false)

            // Surtype seul : les propriétés des sous-types remontent, plus une colonne discriminante.
            for inheritance in childInheritances(of: entity.id) where inheritance.strategy == .surtypeSeul {
                for child in inheritance.childIDs.compactMap(model.entity) {
                    appendAttributes(child.attributes.filter { !$0.isIdentifier }, into: &table, nullable: true)
                }
                let children = inheritance.childIDs.compactMap(model.entity)
                switch inheritance.kind {
                case .exclusion, .partition:
                    // Un seul sous-type possible : une colonne discriminante limitée aux noms des sous-types,
                    // obligatoire si la partition impose d'en avoir un.
                    table.columns.append(MLDColumn(
                        name: unique(naming.apply("type_\(entity.name)"), in: table.columns),
                        spec: TypeSpec(kind: .enumeration, enumValues: children.map { naming.apply($0.name.sqlIdentifier) }),
                        isPrimaryKey: false, isNullable: inheritance.kind == .exclusion
                    ))
                case .libre, .totalite:
                    // Plusieurs sous-types possibles en même temps : une colonne oui/non par sous-type ;
                    // la totalité impose qu'au moins une soit vraie.
                    var flags: [String] = []
                    for child in children {
                        let name = unique(naming.apply("est_\(child.name.sqlIdentifier)"), in: table.columns)
                        flags.append(name)
                        table.columns.append(MLDColumn(name: name, spec: TypeSpec(kind: .booleen), isPrimaryKey: false, isNullable: true))
                    }
                    if inheritance.kind == .totalite && !flags.isEmpty {
                        table.checks.append(.atLeastOneTrue(flags))
                    }
                }
            }
            tables[entity.id] = table
            order.append(entity.id)
        }

        var associationTables: [MLDTable] = []
        for association in model.associations {
            let legs = association.legs.filter { model.entity($0.entityID) != nil }
            guard legs.count >= 2 else { continue }

            if legs.count == 2, let childIndex = childLegIndex(legs) {
                let childLeg = legs[childIndex]
                let parentLeg = legs[1 - childIndex]
                guard let childHost = host(childLeg.entityID), var child = tables[childHost] else { continue }
                let isRelative = childLeg.isRelative && childLeg.cardinality.isMaxOne
                if !isRelative {
                    let absorbed = childHost != childLeg.entityID
                    appendForeignKey(to: parentLeg.entityID, into: &child, primary: false,
                                     nullable: childLeg.cardinality != .oneOne || absorbed, role: parentLeg.role)
                    if childLeg.cardinality == .zeroOne || childLeg.cardinality == .oneOne,
                       parentLeg.cardinality.isMaxOne {
                        // Association 1-1 : la clé étrangère est unique.
                        markLastGroupUnique(in: &child)
                    }
                }
                appendAttributes(association.attributes, into: &child, nullable: true)
                tables[childHost] = child
            } else {
                var table = MLDTable(name: naming.apply(association.name), columns: [], comesFromAssociation: true, origin: .association(association.id))
                let cifTargets = cifTargets(of: association)
                for leg in legs {
                    appendForeignKey(to: leg.entityID, into: &table, primary: !cifTargets.contains(leg.entityID), nullable: false, role: leg.role)
                }
                appendAttributes(association.attributes, into: &table, nullable: false)
                associationTables.append(table)
            }
        }

        return order.compactMap { tables[$0] } + associationTables
    }

    // MARK: Aides

    private func appendKey(of id: Entity.ID, into table: inout MLDTable) {
        var groups: [Entity.ID: Int] = [:]
        for part in key(of: id) {
            var reference: MLDReference?
            if let owner = part.ownerTable ?? inheritedOwner(of: id), owner != id {
                let group = groups[owner] ?? nextGroup()
                groups[owner] = group
                reference = MLDReference(table: tableName(owner), column: part.name, group: group)
            }
            // Une clé reçue d'une autre table n'est jamais un compteur : elle recopie une valeur.
            table.columns.append(MLDColumn(
                name: unique(part.name, in: table.columns), spec: reference == nil ? part.spec : part.spec.asForeignKey,
                isPrimaryKey: true, isNullable: false, reference: reference,
                complement: reference == nil ? part.complement : "", comment: reference == nil ? part.comment : ""
            ))
        }
    }

    /// Pour un sous-type « une table par type », la clé héritée référence la table du surtype.
    private func inheritedOwner(of id: Entity.ID) -> Entity.ID? {
        guard let entity = model.entity(id), !entity.attributes.contains(where: \.isIdentifier),
              let inheritance = parentInheritance(of: id), inheritance.strategy == .tablesSousTypes,
              let parent = inheritance.parentID else { return nil }
        return host(parent)
    }

    private func appendForeignKey(to entityID: Entity.ID, into table: inout MLDTable, primary: Bool, nullable: Bool, role: String = "") {
        let owner = host(entityID)
        let group = nextGroup()
        let suffix = role.trimmingCharacters(in: .whitespaces).isEmpty ? "" : "_" + role.sqlIdentifier
        for part in key(of: entityID) {
            table.columns.append(MLDColumn(
                name: unique(part.name + suffix, in: table.columns), spec: part.spec.asForeignKey,
                isPrimaryKey: primary, isNullable: primary ? false : nullable,
                reference: owner.map { MLDReference(table: tableName($0), column: part.name, group: group) }
            ))
        }
    }

    private func appendAttributes(_ attributes: [Attribute], into table: inout MLDTable, nullable: Bool) {
        for attribute in attributes {
            table.columns.append(MLDColumn(
                name: unique(columnName(attribute), in: table.columns),
                spec: attribute.spec, isPrimaryKey: false,
                isNullable: nullable || !attribute.isNotNull,
                isUnique: attribute.isUnique,
                complement: attribute.complement, comment: attribute.comment
            ))
        }
    }

    /// Nom de colonne : code de la propriété, ou son libellé si l'option est activée.
    private func columnName(_ attribute: Attribute) -> String {
        let useLabel = model.settings.useLabels && !attribute.label.trimmingCharacters(in: .whitespaces).isEmpty
        return naming.apply(useLabel ? attribute.label : attribute.name)
    }

    private func markLastGroupUnique(in table: inout MLDTable) {
        guard let last = table.columns.last?.reference?.group, table.columns.filter({ $0.reference?.group == last }).count == 1,
              let index = table.columns.lastIndex(where: { $0.reference?.group == last }) else { return }
        table.columns[index].isUnique = true
    }

    private func cifTargets(of association: Association) -> Set<Entity.ID> {
        var result = Set<Entity.ID>()
        for constraint in model.constraints where constraint.kind == .cif
            && constraint.links.contains(where: { $0.target == .association(association.id) }) {
            for link in constraint.links where link.isTarget {
                if case .entity(let id) = link.target { result.insert(id) }
            }
        }
        // On garde au moins une colonne dans la clé primaire.
        if result.count >= association.legs.count { return [] }
        return result
    }

    private func nextGroup() -> Int {
        groupCounter += 1
        return groupCounter
    }

    /// Indice de la patte qui « reçoit » la clé étrangère : 1,1 en priorité, sinon 0,1.
    private func childLegIndex(_ legs: [Leg]) -> Int? {
        legs.firstIndex { $0.cardinality == .oneOne } ?? legs.firstIndex { $0.cardinality == .zeroOne }
    }

    /// Évite deux colonnes du même nom (cas des associations réflexives).
    private func unique(_ base: String, in columns: [MLDColumn]) -> String {
        let used = Set(columns.map(\.name))
        guard used.contains(base) else { return base }
        var counter = 2
        while used.contains("\(base)_\(counter)") { counter += 1 }
        return "\(base)_\(counter)"
    }
}

extension NamingConvention {
    /// Applique la convention de nommage à un nom saisi dans le MCD.
    func apply(_ raw: String) -> String {
        let base = raw.sqlIdentifier
        let words = base.split(separator: "_").map(String.init)
        func capitalized(_ word: String) -> String { word.prefix(1).uppercased() + word.dropFirst().lowercased() }
        switch self {
        case .telQuel: return base
        case .snake: return words.map { $0.lowercased() }.joined(separator: "_")
        case .camel:
            guard let first = words.first else { return base }
            return first.lowercased() + words.dropFirst().map(capitalized).joined()
        case .pascal: return words.map(capitalized).joined()
        case .majuscules: return words.map { $0.uppercased() }.joined(separator: "_")
        }
    }
}

extension String {
    /// « Numéro de commande » → « Numero_de_commande » : sans accents ni espaces, utilisable en SQL.
    var sqlIdentifier: String {
        let folded = folding(options: .diacriticInsensitive, locale: Locale(identifier: "fr_FR"))
        var result = ""
        for character in folded {
            if character.isASCII && (character.isLetter || character.isNumber) {
                result.append(character)
            } else if !result.isEmpty && !result.hasSuffix("_") {
                result.append("_")
            }
        }
        while result.hasSuffix("_") { result.removeLast() }
        if result.isEmpty { return "sans_nom" }
        if let first = result.first, first.isNumber { result = "t_" + result }
        return result
    }
}
