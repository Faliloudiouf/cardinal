import Foundation

struct Diagnostic: Identifiable, Hashable, Sendable {
    enum Severity: Sendable { case error, warning }

    var id = UUID()
    var severity: Severity
    var message: String
    var target: NodeRef?
}

/// Vérifie le MCD en direct, pendant qu'on dessine.
enum Validator {
    static func check(_ model: MCDModel) -> [Diagnostic] {
        var result: [Diagnostic] = []
        func error(_ message: String, _ ref: NodeRef) { result.append(Diagnostic(severity: .error, message: message, target: ref)) }
        func warning(_ message: String, _ ref: NodeRef) { result.append(Diagnostic(severity: .warning, message: message, target: ref)) }

        var seen: [String: Int] = [:]
        for name in model.entities.map(\.name) + model.associations.map(\.name) {
            seen[name.sqlIdentifier.lowercased(), default: 0] += 1
        }
        var reportedNames = Set<String>()

        let subtypes = Set(model.inheritances.filter { $0.parentID != nil }.flatMap(\.childIDs))
        let relativeEntities = Set(model.associations.filter { $0.legs.count == 2 }.flatMap { association in
            association.legs.filter { $0.isRelative && $0.cardinality.isMaxOne }.map(\.entityID)
        })

        for entity in model.entities {
            let ref = NodeRef.entity(entity.id)
            let hasIdentifier = entity.attributes.contains(where: \.isIdentifier)
            if !hasIdentifier && !subtypes.contains(entity.id) {
                error(relativeEntities.contains(entity.id)
                      ? "« \(entity.name) » a un identifiant relatif mais aucun identifiant propre."
                      : "« \(entity.name) » n'a pas d'identifiant.", ref)
            }
            let key = entity.name.sqlIdentifier.lowercased()
            if seen[key, default: 0] > 1, !reportedNames.contains(key) {
                reportedNames.insert(key)
                error("Le nom « \(entity.name) » est utilisé plusieurs fois.", ref)
            }
            let linked = model.associations.contains { $0.legs.contains { $0.entityID == entity.id } }
                || model.inheritances.contains { $0.parentID == entity.id || $0.childIDs.contains(entity.id) }
            if !linked && model.entities.count > 1 {
                warning("« \(entity.name) » n'est reliée à aucune association.", ref)
            }
            checkAttributes(entity.attributes, owner: entity.name, ref: ref, into: &result)
        }

        for association in model.associations {
            let ref = NodeRef.association(association.id)
            if association.legs.count < 2 {
                error("« \(association.name) » doit relier au moins deux pattes.", ref)
            }
            if association.attributes.contains(where: \.isIdentifier) {
                warning("Une association n'a pas d'identifiant propre (« \(association.name) »).", ref)
            }
            for leg in association.legs where leg.isRelative && !leg.cardinality.isMaxOne {
                let name = model.entity(leg.entityID)?.name ?? "?"
                error("Identifiant relatif sur « \(name) » : la cardinalité doit être 1,1.", ref)
            }
            if association.legs.filter(\.isRelative).count > 0 && association.legs.count != 2 {
                error("Un identifiant relatif n'est possible que sur une association binaire (« \(association.name) »).", ref)
            }
            let key = association.name.sqlIdentifier.lowercased()
            if seen[key, default: 0] > 1, !reportedNames.contains(key) {
                reportedNames.insert(key)
                error("Le nom « \(association.name) » est utilisé plusieurs fois.", ref)
            }
            checkAttributes(association.attributes, owner: association.name, ref: ref, into: &result)

            let legs = association.legs.filter { model.entity($0.entityID) != nil }
            // N-aire avec une patte max 1 : les cours de Merise la ramènent à une CIF ou à des binaires.
            if legs.count > 2 {
                let covered = Set(model.constraints.filter { $0.kind == .cif && $0.links.contains { $0.target == ref } }
                    .flatMap { $0.links.filter(\.isTarget).map(\.target) })
                for leg in legs where leg.cardinality.isMaxOne && !covered.contains(.entity(leg.entityID)) {
                    warning("« \(association.name) » : la patte \(leg.cardinality.rawValue) vers « \(model.entity(leg.entityID)!.name) » dans une association n-aire se modélise par une CIF ou par des associations binaires.", ref)
                }
            }
            if legs.count == 2 {
                let same = legs[0].entityID == legs[1].entityID
                if same, legs.contains(where: { $0.cardinality == .oneOne }) {
                    warning("« \(association.name) » : une réflexive 1,1 oblige chaque occurrence à en référencer une autre ; la première ne pourra jamais être enregistrée. Utilisez 0,1.", ref)
                } else if !same, legs.allSatisfy({ $0.cardinality == .oneOne }) {
                    warning("« \(association.name) » : 1,1 des deux côtés, les deux entités n'en font souvent qu'une.", ref)
                }
            }
        }

        // Références obligatoires en boucle : aucune ligne ne peut être insérée la première.
        let tables = MLDBuilder.build(model)
        var mandatory: [String: Set<String>] = [:]
        for table in tables {
            for column in table.columns where !column.isNullable {
                if let target = column.reference?.table, target != table.name { mandatory[table.name, default: []].insert(target) }
            }
        }
        if let cycle = Self.cycle(in: mandatory) {
            result.append(Diagnostic(severity: .warning, message: "Références obligatoires en boucle (\(cycle.joined(separator: " → "))) : aucune ligne ne pourra être insérée la première. Rendez une des cardinalités 0,1.", target: nil))
        }

        // Mots réservés du SQL : le script les délimite, mais les requêtes devront le faire aussi.
        let reserved = SQLDialect.allCases.reduce(into: Set<String>()) { $0.formUnion(SQLKeywords.reserved(in: $1)) }
        var reservedNames: [String] = []
        for table in tables {
            if reserved.contains(table.name.uppercased()) { reservedNames.append(table.name) }
            for column in table.columns where reserved.contains(column.name.uppercased()) { reservedNames.append("\(table.name).\(column.name)") }
        }
        if !reservedNames.isEmpty {
            result.append(Diagnostic(severity: .warning, message: "Mots réservés du SQL : \(reservedNames.prefix(6).joined(separator: ", ")). Ils seront délimités dans le script, mais un autre nom évitera de devoir le faire dans chaque requête.", target: nil))
        }

        for inheritance in model.inheritances {
            let ref = NodeRef.inheritance(inheritance.id)
            if inheritance.parentID == nil {
                error("Un héritage n'a pas de surtype : reliez-le à l'entité générale.", ref)
            }
            if inheritance.childIDs.isEmpty {
                error("Un héritage n'a aucun sous-type.", ref)
            }
            // Un sous-type hérite de l'identifiant du surtype : en avoir un propre casse le lien
            // (la table du sous-type ne référencerait plus celle du surtype).
            if let parent = inheritance.parentID.flatMap(model.entity) {
                for child in inheritance.childIDs.compactMap(model.entity) where child.attributes.contains(where: \.isIdentifier) {
                    error("« \(child.name) » est un sous-type de « \(parent.name) » : il hérite de son identifiant et ne doit pas en avoir.", ref)
                }
            }
            if inheritance.strategy == .sousTypesSeuls, let parent = inheritance.parentID,
               model.associations.contains(where: { $0.legs.contains { $0.entityID == parent } }) {
                warning("Le surtype est relié à une association mais n'aura pas de table (sous-types seuls).", ref)
            }
        }

        for constraint in model.constraints {
            let ref = NodeRef.constraint(constraint.id)
            if constraint.links.count < (constraint.kind == .cif ? 2 : 2) {
                warning("La contrainte \(constraint.kind.rawValue) doit être reliée à au moins deux éléments.", ref)
            }
            if constraint.kind == .cif && !constraint.links.contains(where: \.isTarget) {
                warning("La CIF n'a pas d'entité cible : cochez « Cible » dans l'inspecteur.", ref)
            }
        }
        return result
    }

    /// Premier cycle trouvé dans un graphe orienté (table → tables référencées).
    static func cycle(in graph: [String: Set<String>]) -> [String]? {
        var state: [String: Int] = [:] // 1 en cours, 2 terminé
        var path: [String] = []
        func visit(_ node: String) -> [String]? {
            state[node] = 1
            path.append(node)
            for next in (graph[node] ?? []).sorted() {
                if state[next] == 1, let start = path.firstIndex(of: next) { return Array(path[start...]) + [next] }
                if state[next] == nil, let found = visit(next) { return found }
            }
            path.removeLast()
            state[node] = 2
            return nil
        }
        for node in graph.keys.sorted() where state[node] == nil {
            if let found = visit(node) { return found }
        }
        return nil
    }

    private static func checkAttributes(_ attributes: [Attribute], owner: String, ref: NodeRef, into result: inout [Diagnostic]) {
        if attributes.contains(where: { $0.name.trimmingCharacters(in: .whitespaces).isEmpty }) {
            result.append(Diagnostic(severity: .error, message: "« \(owner) » contient une propriété sans nom.", target: ref))
        }
        let names = attributes.map { $0.name.sqlIdentifier.lowercased() }
        if Set(names).count != names.count {
            result.append(Diagnostic(severity: .error, message: "« \(owner) » contient deux propriétés du même nom.", target: ref))
        }
        for message in typeProblems(attributes) {
            result.append(Diagnostic(severity: message.isError ? .error : .warning, message: "« \(owner) » : \(message.text)", target: ref))
        }
    }

    /// Incohérences de type, signalées avant qu'elles ne donnent un script refusé par le SGBD.
    static func typeProblems(_ attributes: [Attribute]) -> [(text: String, isError: Bool)] {
        var problems: [(String, Bool)] = []
        for attribute in attributes {
            let name = attribute.name.isEmpty ? "propriété sans nom" : attribute.name
            let spec = attribute.spec
            switch attribute.type {
            case .enumeration where TypeSpec.cleanValues(spec.enumValues).isEmpty:
                problems.append(("l'énumération « \(name) » n'a aucune valeur.", true))
            case .enumeration where TypeSpec.cleanValues(spec.enumValues).count != spec.enumValues.count:
                problems.append(("l'énumération « \(name) » contient une valeur vide ou en double (ignorée).", false))
            case .libre where spec.custom.trimmingCharacters(in: .whitespaces).isEmpty:
                problems.append(("le type libre de « \(name) » n'est pas renseigné (VARCHAR(50) sera utilisé).", true))
            case .compteur where !attribute.isIdentifier && !attribute.isUnique:
                problems.append(("le compteur « \(name) » n'est ni identifiant ni unique : il ne sera pas numéroté automatiquement.", false))
            case .decimal where attribute.scale > attribute.precision || !TypeSpec.precisionRange.contains(attribute.precision):
                problems.append(("DECIMAL(\(attribute.precision),\(attribute.scale)) de « \(name) » est invalide (précision 1 à 38, échelle ≤ précision).", true))
            default:
                if attribute.type.usesLength && (attribute.length < 1 || attribute.length > attribute.type.maxLength) {
                    problems.append(("la longueur \(attribute.length) de « \(name) » doit être comprise entre 1 et \(attribute.type.maxLength).", true))
                }
            }
        }
        if attributes.filter({ $0.type == .compteur }).count > 1 {
            problems.append(("plusieurs compteurs : seul le premier sera numéroté automatiquement.", false))
        }
        return problems
    }
}
