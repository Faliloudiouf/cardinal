import Foundation
#if canImport(CoreGraphics)
import CoreGraphics // CGRect et ses fonctions ; sous Windows et Linux, Foundation les fournit
#endif

// MARK: - Références

/// Référence vers n'importe quel élément du diagramme.
enum NodeRef: Hashable, Codable, Sendable {
    case entity(UUID)
    case association(UUID)
    case inheritance(UUID)
    case constraint(UUID)
    case rule(UUID)
    case note(UUID)
    case figure(UUID)

    var id: UUID {
        switch self {
        case .entity(let id), .association(let id), .inheritance(let id),
             .constraint(let id), .rule(let id), .note(let id), .figure(let id):
            id
        }
    }
}

// MARK: - Propriétés

struct Attribute: Identifiable, Codable, Hashable, Sendable {
    var id = UUID()
    var name: String
    var type: DataType = .varchar
    /// Longueur des textes (VARCHAR, CHAR…).
    var length: Int = 50
    /// Précision et échelle d'un décimal : DECIMAL(précision, échelle).
    var precision: Int = 15
    var scale: Int = 2
    var isIdentifier = false
    var isNotNull = false
    var isUnique = false
    /// Libellé lisible (« Identifiant du client ») : le « nom logique » de Looping.
    var label: String = ""
    /// Collation d'un texte (ex. utf8mb4_bin, French_CI_AS).
    var collation: String = ""
    /// Complément SQL ajouté tel quel à la colonne (ex. DEFAULT 0).
    var complement: String = ""
    var comment: String = ""
    /// Valeurs d'une énumération.
    var enumValues: [String] = []
    /// Type écrit tel quel pour le type « Libre ».
    var customType: String = ""

    init(name: String, type: DataType = .varchar, length: Int = 50, precision: Int = 15, scale: Int = 2,
         isIdentifier: Bool = false, isNotNull: Bool = false, isUnique: Bool = false, label: String = "",
         collation: String = "", complement: String = "", comment: String = "",
         enumValues: [String] = [], customType: String = "") {
        self.name = name
        self.type = type
        self.length = length
        self.precision = precision
        self.scale = scale
        self.isIdentifier = isIdentifier
        self.isNotNull = isNotNull
        self.isUnique = isUnique
        self.label = label
        self.collation = collation
        self.complement = complement
        self.comment = comment
        self.enumValues = enumValues
        self.customType = customType
    }
}

/// Couleur choisie par l'utilisateur pour un élément (« auto » = couleur du thème).
enum NodeColor: String, Codable, CaseIterable, Identifiable, Sendable {
    case auto, bleu, sarcelle, vert, violet, rouge, ardoise
    var id: String { rawValue }
}

// MARK: - Entités et associations

struct Entity: Identifiable, Codable, Hashable, Sendable {
    var id = UUID()
    var name: String
    var attributes: [Attribute] = []
    var position: CGPoint
    /// Entité fictive : dessinée dans le MCD mais sans table dans le MLD (ex. « Date »).
    var isFictive = false
    var color: NodeColor = .auto
}

/// Cardinalité d'une patte : combien de fois une occurrence de l'entité participe à l'association.
enum Cardinality: String, Codable, CaseIterable, Identifiable, Sendable {
    case zeroOne = "0,1"
    case oneOne = "1,1"
    case zeroMany = "0,N"
    case oneMany = "1,N"

    var id: String { rawValue }
    var isMaxOne: Bool { self == .zeroOne || self == .oneOne }
}

/// Une patte relie une association à une entité.
struct Leg: Identifiable, Codable, Hashable, Sendable {
    var id = UUID()
    var entityID: Entity.ID
    var cardinality: Cardinality = .zeroMany
    /// Identifiant relatif « (R) » : l'entité est identifiée en partie par l'autre entité.
    var isRelative = false
    /// Rôle de la patte (utile dans les associations réflexives : « EtreCompose », « EtreComposant »).
    var role: String = ""
    /// Cassure : point par lequel passe la patte (coordonnées du canevas), nil pour une patte droite.
    var bend: CGPoint?
}

struct Association: Identifiable, Codable, Hashable, Sendable {
    var id = UUID()
    var name: String
    var attributes: [Attribute] = []
    var legs: [Leg] = []
    var position: CGPoint
    var color: NodeColor = .auto
}

// MARK: - Héritage

enum InheritanceKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case libre = ""
    case exclusion = "X"
    case totalite = "T"
    case partition = "XT"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .libre: "Sans contrainte"
        case .exclusion: "Exclusion (X)"
        case .totalite: "Totalité (T)"
        case .partition: "Partition (XT)"
        }
    }
}

/// Comment l'héritage est traduit dans le MLD.
enum InheritanceStrategy: String, Codable, CaseIterable, Identifiable, Sendable {
    case tablesSousTypes, sousTypesSeuls, surtypeSeul

    var id: String { rawValue }

    var label: String {
        switch self {
        case .tablesSousTypes: "Une table par type"
        case .sousTypesSeuls: "Sous-types seuls (propriétés migrées)"
        case .surtypeSeul: "Surtype seul (avec discriminant)"
        }
    }
}

struct Inheritance: Identifiable, Codable, Hashable, Sendable {
    var id = UUID()
    var parentID: Entity.ID?
    var childIDs: [Entity.ID] = []
    var kind: InheritanceKind = .libre
    var strategy: InheritanceStrategy = .tablesSousTypes
    var position: CGPoint
}

// MARK: - Contraintes, règles, textes

enum ConstraintKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case cif = "CIF"
    case inclusion = "I"
    case exclusion = "X"
    case totalite = "T"
    case partition = "XT"
    case simultaneite = "S"
    case egalite = "="

    var id: String { rawValue }

    var label: String {
        switch self {
        case .cif: "Contrainte d'intégrité fonctionnelle (CIF)"
        case .inclusion: "Inclusion (I)"
        case .exclusion: "Exclusion (X)"
        case .totalite: "Totalité (T)"
        case .partition: "Partition (XT)"
        case .simultaneite: "Simultanéité (S)"
        case .egalite: "Égalité (=)"
        }
    }
}

struct ConstraintLink: Identifiable, Codable, Hashable, Sendable {
    var id = UUID()
    var target: NodeRef
    /// Pour une CIF : vrai sur l'entité déterminée (la cible de la flèche).
    var isTarget = false
}

struct Constraint: Identifiable, Codable, Hashable, Sendable {
    var id = UUID()
    var kind: ConstraintKind = .cif
    var links: [ConstraintLink] = []
    var position: CGPoint
    var sql: String = ""
}

/// Règle de gestion, éventuellement accompagnée de code SQL (déclencheur, CHECK…).
struct Rule: Identifiable, Codable, Hashable, Sendable {
    var id = UUID()
    var name: String
    var details: String = ""
    var sql: String = ""
    var links: [NodeRef] = []
    var position: CGPoint
}

enum NoteStyle: String, Codable, CaseIterable, Identifiable, Sendable {
    case titre, texte
    var id: String { rawValue }
}

struct Note: Identifiable, Codable, Hashable, Sendable {
    var id = UUID()
    var text: String
    var style: NoteStyle = .texte
    var position: CGPoint
}

// MARK: - Vues (sous-modèles)

struct ModelView: Identifiable, Codable, Hashable, Sendable {
    var id = UUID()
    var name: String
    var refs: [NodeRef] = []

    init(id: UUID = UUID(), name: String, refs: [NodeRef] = []) {
        self.id = id
        self.name = name
        self.refs = refs
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? "Vue"
        // Une référence illisible (fichier d'une version future) est ignorée, pas bloquante.
        refs = (try? c.decodeIfPresent([NodeRef].self, forKey: .refs)) ?? []
    }

    mutating func add(_ newRefs: some Sequence<NodeRef>) {
        for ref in newRefs where !refs.contains(ref) { refs.append(ref) }
    }
}

// MARK: - Illustrations

enum FigureKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case rectangle, ellipse, line, arrow, image
    var id: String { rawValue }

    var label: String {
        switch self {
        case .rectangle: "Rectangle"
        case .ellipse: "Ellipse"
        case .line: "Trait"
        case .arrow: "Flèche"
        case .image: "Image"
        }
    }

    /// Trait ou flèche : défini par ses deux extrémités, pas par un cadre.
    var isStroke: Bool { self == .line || self == .arrow }
}

/// Élément d'illustration, sans effet sur le MLD ni le SQL (comme le groupe Illustration de Looping).
struct Figure: Identifiable, Codable, Hashable, Sendable {
    var id = UUID()
    var kind: FigureKind
    /// Centre de la figure.
    var position: CGPoint
    /// Taille du cadre (rectangle, ellipse, image).
    var size = CGSize(width: 160, height: 100)
    /// Trait et flèche : de l'extrémité de départ à celle d'arrivée.
    var span = CGPoint(x: 160, y: 0)
    var color: NodeColor = .auto
    var isFilled = false
    /// Image au format PNG (redimensionnée à l'import pour garder des fichiers légers).
    var imageData: Data?

    static let minimumSize: CGFloat = 16

    var start: CGPoint { position - span * 0.5 }
    var end: CGPoint { position + span * 0.5 }

    /// Cadre occupé sur le canevas (au moins 16 points dans chaque sens, pour rester cliquable).
    var frame: CGRect {
        if kind.isStroke {
            let rect = CGRect(x: min(start.x, end.x), y: min(start.y, end.y), width: abs(span.x), height: abs(span.y))
            return rect.insetBy(dx: -max(0, (Self.minimumSize - rect.width) / 2), dy: -max(0, (Self.minimumSize - rect.height) / 2))
        }
        return CGRect(x: position.x - size.width / 2, y: position.y - size.height / 2, width: size.width, height: size.height)
    }

    /// Fixe les deux extrémités d'un trait ou d'une flèche.
    mutating func setEnds(_ start: CGPoint, _ end: CGPoint) {
        position = CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2)
        span = end - start
    }

    /// Redimensionne le cadre en gardant le coin opposé fixe ; jamais plus petit que le minimum.
    mutating func resize(toCorner corner: CGPoint) {
        let origin = CGPoint(x: position.x - size.width / 2, y: position.y - size.height / 2)
        let width = max(Self.minimumSize, corner.x - origin.x)
        let height = max(Self.minimumSize, corner.y - origin.y)
        size = CGSize(width: width, height: height)
        position = CGPoint(x: origin.x + width / 2, y: origin.y + height / 2)
    }
}

extension Figure {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        kind = try c.decodeIfPresent(FigureKind.self, forKey: .kind) ?? .rectangle
        position = try c.decodeIfPresent(CGPoint.self, forKey: .position) ?? .zero
        size = try c.decodeIfPresent(CGSize.self, forKey: .size) ?? CGSize(width: 160, height: 100)
        span = try c.decodeIfPresent(CGPoint.self, forKey: .span) ?? CGPoint(x: 160, y: 0)
        color = try c.decodeIfPresent(NodeColor.self, forKey: .color) ?? .auto
        isFilled = try c.decodeIfPresent(Bool.self, forKey: .isFilled) ?? false
        imageData = try c.decodeIfPresent(Data.self, forKey: .imageData)
    }
}

// MARK: - Réglages

enum NamingConvention: String, Codable, CaseIterable, Identifiable, Sendable {
    case telQuel, snake, camel, pascal, majuscules

    var id: String { rawValue }

    var label: String {
        switch self {
        case .telQuel: "Tel quel"
        case .snake: "snake_case"
        case .camel: "camelCase"
        case .pascal: "PascalCase"
        case .majuscules: "MAJUSCULES"
        }
    }
}

struct ModelSettings: Codable, Hashable, Sendable {
    var naming: NamingConvention = .telQuel
    /// Place les clés étrangères dans des ALTER TABLE en fin de script.
    var foreignKeysAtEnd = false
    var showTypes = true
    var showAttributes = true
    var showGrid = true
    /// Nomme les colonnes du MLD avec les libellés plutôt qu'avec les codes (comportement de Looping).
    var useLabels = false
    /// Flèche de dépendance fonctionnelle sur les pattes 0,1 et 1,1, pointée vers l'association.
    var showDependencies = false
}

// MARK: - Modèle

/// Le MCD complet, tel qu'il est enregistré dans un fichier .mcd (JSON).
struct MCDModel: Codable, Hashable, Sendable {
    var version = 2
    var entities: [Entity] = []
    var associations: [Association] = []
    var inheritances: [Inheritance] = []
    var constraints: [Constraint] = []
    var rules: [Rule] = []
    var notes: [Note] = []
    /// Illustrations : rectangles, ellipses, traits, flèches, images (sans effet sur le MLD).
    var figures: [Figure] = []
    /// Vues (sous-modèles) : chacune montre une partie du modèle, aux mêmes positions.
    var views: [ModelView] = []
    var settings = ModelSettings()

    func entity(_ id: Entity.ID) -> Entity? { entities.first { $0.id == id } }
    func association(_ id: Association.ID) -> Association? { associations.first { $0.id == id } }

    var allRefs: [NodeRef] {
        entities.map { .entity($0.id) } + associations.map { .association($0.id) }
            + inheritances.map { .inheritance($0.id) } + constraints.map { .constraint($0.id) }
            + rules.map { .rule($0.id) } + notes.map { .note($0.id) } + figures.map { .figure($0.id) }
    }

    func contains(_ ref: NodeRef) -> Bool { position(of: ref) != nil }

    func position(of ref: NodeRef) -> CGPoint? {
        switch ref {
        case .entity(let id): entities.first { $0.id == id }?.position
        case .association(let id): associations.first { $0.id == id }?.position
        case .inheritance(let id): inheritances.first { $0.id == id }?.position
        case .constraint(let id): constraints.first { $0.id == id }?.position
        case .rule(let id): rules.first { $0.id == id }?.position
        case .note(let id): notes.first { $0.id == id }?.position
        case .figure(let id): figures.first { $0.id == id }?.position
        }
    }

    mutating func setPosition(_ point: CGPoint, of ref: NodeRef) {
        switch ref {
        case .entity(let id): if let i = entities.firstIndex(where: { $0.id == id }) { entities[i].position = point }
        case .association(let id): if let i = associations.firstIndex(where: { $0.id == id }) { associations[i].position = point }
        case .inheritance(let id): if let i = inheritances.firstIndex(where: { $0.id == id }) { inheritances[i].position = point }
        case .constraint(let id): if let i = constraints.firstIndex(where: { $0.id == id }) { constraints[i].position = point }
        case .rule(let id): if let i = rules.firstIndex(where: { $0.id == id }) { rules[i].position = point }
        case .note(let id): if let i = notes.firstIndex(where: { $0.id == id }) { notes[i].position = point }
        case .figure(let id): if let i = figures.firstIndex(where: { $0.id == id }) { figures[i].position = point }
        }
    }

    /// Déplace des éléments ; les cassures des pattes d'une association déplacée la suivent.
    mutating func move(_ refs: Set<NodeRef>, by offset: CGSize) {
        for ref in refs {
            guard let point = position(of: ref) else { continue }
            setPosition(point.offset(by: offset), of: ref)
        }
        for index in associations.indices where refs.contains(.association(associations[index].id)) {
            for leg in associations[index].legs.indices {
                associations[index].legs[leg].bend = associations[index].legs[leg].bend?.offset(by: offset)
            }
        }
    }

    /// Ajoute une cassure au milieu de la patte (décalée pour qu'on la voie), ou la retire.
    mutating func toggleBend(association id: Association.ID, leg legID: Leg.ID) {
        guard let a = associations.firstIndex(where: { $0.id == id }),
              let l = associations[a].legs.firstIndex(where: { $0.id == legID }) else { return }
        if associations[a].legs[l].bend != nil {
            associations[a].legs[l].bend = nil
            return
        }
        let start = associations[a].position
        guard let end = entity(associations[a].legs[l].entityID)?.position else { return }
        let middle = CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2)
        let u = (end - start).normalized
        associations[a].legs[l].bend = middle + CGPoint(x: -u.y, y: u.x) * 60
    }

    /// Supprime un élément et toutes les références qui pointent vers lui.
    mutating func remove(_ ref: NodeRef) {
        switch ref {
        case .entity(let id):
            entities.removeAll { $0.id == id }
            for i in associations.indices { associations[i].legs.removeAll { $0.entityID == id } }
            for i in inheritances.indices {
                if inheritances[i].parentID == id { inheritances[i].parentID = nil }
                inheritances[i].childIDs.removeAll { $0 == id }
            }
        case .association(let id): associations.removeAll { $0.id == id }
        case .inheritance(let id): inheritances.removeAll { $0.id == id }
        case .constraint(let id): constraints.removeAll { $0.id == id }
        case .rule(let id): rules.removeAll { $0.id == id }
        case .note(let id): notes.removeAll { $0.id == id }
        case .figure(let id): figures.removeAll { $0.id == id }
        }
        for i in constraints.indices { constraints[i].links.removeAll { $0.target == ref } }
        for i in rules.indices { rules[i].links.removeAll { $0 == ref } }
        for i in views.indices { views[i].refs.removeAll { $0 == ref } }
    }

    /// Ce que montre une vue : ses éléments, avec les liens entre eux (pattes, héritages…).
    func visible(in viewID: ModelView.ID?) -> MCDModel {
        guard let viewID, let view = views.first(where: { $0.id == viewID }) else { return self }
        var shown = subset(Set(view.refs).filter(contains))
        shown.views = views
        return shown
    }

    /// Complète une sélection avec ce qui relie ses éléments : associations dont toutes les entités
    /// sont choisies, héritages, contraintes et règles entièrement couverts.
    func completed(_ refs: Set<NodeRef>) -> Set<NodeRef> {
        var result = refs
        for association in associations where !association.legs.isEmpty
            && association.legs.allSatisfy({ result.contains(.entity($0.entityID)) }) {
            result.insert(.association(association.id))
        }
        for inheritance in inheritances {
            let members = [inheritance.parentID].compactMap { $0 } + inheritance.childIDs
            if !members.isEmpty, members.allSatisfy({ result.contains(.entity($0)) }) { result.insert(.inheritance(inheritance.id)) }
        }
        for constraint in constraints where !constraint.links.isEmpty && constraint.links.allSatisfy({ result.contains($0.target) }) {
            result.insert(.constraint(constraint.id))
        }
        for rule in rules where !rule.links.isEmpty && rule.links.allSatisfy(result.contains) {
            result.insert(.rule(rule.id))
        }
        return result
    }

    mutating func removeEntity(_ id: Entity.ID) { remove(.entity(id)) }
    mutating func removeAssociation(_ id: Association.ID) { remove(.association(id)) }

    /// Propose « Entité 3 » si « Entité 1 » et « Entité 2 » existent déjà.
    func uniqueName(base: String) -> String {
        let used = Set(entities.map(\.name) + associations.map(\.name) + rules.map(\.name))
        var counter = 1
        while used.contains("\(base) \(counter)") { counter += 1 }
        return "\(base) \(counter)"
    }

    /// Sous-ensemble du modèle (pour copier-coller) : seuls les éléments demandés,
    /// avec les liens internes à la sélection.
    func subset(_ refs: Set<NodeRef>) -> MCDModel {
        var copy = MCDModel(settings: settings)
        copy.entities = entities.filter { refs.contains(.entity($0.id)) }
        let kept = Set(copy.entities.map(\.id))
        copy.associations = associations.filter { refs.contains(.association($0.id)) }.map { association in
            var association = association
            association.legs.removeAll { !kept.contains($0.entityID) }
            return association
        }
        copy.inheritances = inheritances.filter { refs.contains(.inheritance($0.id)) }.map { inheritance in
            var inheritance = inheritance
            if let parent = inheritance.parentID, !kept.contains(parent) { inheritance.parentID = nil }
            inheritance.childIDs.removeAll { !kept.contains($0) }
            return inheritance
        }
        copy.constraints = constraints.filter { refs.contains(.constraint($0.id)) }.map { constraint in
            var constraint = constraint
            constraint.links.removeAll { !refs.contains($0.target) }
            return constraint
        }
        copy.rules = rules.filter { refs.contains(.rule($0.id)) }.map { rule in
            var rule = rule
            rule.links.removeAll { !refs.contains($0) }
            return rule
        }
        copy.notes = notes.filter { refs.contains(.note($0.id)) }
        copy.figures = figures.filter { refs.contains(.figure($0.id)) }
        return copy
    }

    /// Colle un fragment : nouveaux identifiants, positions décalées. Renvoie les éléments ajoutés.
    mutating func paste(_ fragment: MCDModel, offset: CGFloat = 30) -> Set<NodeRef> {
        var map: [UUID: UUID] = [:]
        func fresh(_ old: UUID) -> UUID {
            if let new = map[old] { return new }
            let new = UUID()
            map[old] = new
            return new
        }
        func shifted(_ point: CGPoint) -> CGPoint { CGPoint(x: point.x + offset, y: point.y + offset) }
        func remap(_ ref: NodeRef) -> NodeRef {
            switch ref {
            case .entity(let id): .entity(fresh(id))
            case .association(let id): .association(fresh(id))
            case .inheritance(let id): .inheritance(fresh(id))
            case .constraint(let id): .constraint(fresh(id))
            case .rule(let id): .rule(fresh(id))
            case .note(let id): .note(fresh(id))
            case .figure(let id): .figure(fresh(id))
            }
        }
        var added = Set<NodeRef>()
        let usedNames = Set(entities.map(\.name) + associations.map(\.name))
        func freshName(_ name: String) -> String {
            guard usedNames.contains(name) else { return name }
            var counter = 2
            while usedNames.contains("\(name) \(counter)") { counter += 1 }
            return "\(name) \(counter)"
        }

        for var entity in fragment.entities {
            entity.id = fresh(entity.id)
            entity.name = freshName(entity.name)
            entity.position = shifted(entity.position)
            entity.attributes = entity.attributes.map { var a = $0; a.id = UUID(); return a }
            entities.append(entity)
            added.insert(.entity(entity.id))
        }
        for var association in fragment.associations {
            association.id = fresh(association.id)
            association.name = freshName(association.name)
            association.position = shifted(association.position)
            // Les cassures suivent la copie, comme le reste de l'association.
            association.legs = association.legs.map { var leg = $0; leg.id = UUID(); leg.entityID = fresh(leg.entityID); leg.bend = leg.bend.map(shifted); return leg }
            association.attributes = association.attributes.map { var a = $0; a.id = UUID(); return a }
            associations.append(association)
            added.insert(.association(association.id))
        }
        for var inheritance in fragment.inheritances {
            inheritance.id = fresh(inheritance.id)
            inheritance.parentID = inheritance.parentID.map(fresh)
            inheritance.childIDs = inheritance.childIDs.map(fresh)
            inheritance.position = shifted(inheritance.position)
            inheritances.append(inheritance)
            added.insert(.inheritance(inheritance.id))
        }
        for var constraint in fragment.constraints {
            constraint.id = fresh(constraint.id)
            constraint.links = constraint.links.map { var link = $0; link.id = UUID(); link.target = remap(link.target); return link }
            constraint.position = shifted(constraint.position)
            constraints.append(constraint)
            added.insert(.constraint(constraint.id))
        }
        for var rule in fragment.rules {
            rule.id = fresh(rule.id)
            rule.links = rule.links.map(remap)
            rule.position = shifted(rule.position)
            rules.append(rule)
            added.insert(.rule(rule.id))
        }
        for var note in fragment.notes {
            note.id = fresh(note.id)
            note.position = shifted(note.position)
            notes.append(note)
            added.insert(.note(note.id))
        }
        for var figure in fragment.figures {
            figure.id = fresh(figure.id)
            figure.position = shifted(figure.position)
            figures.append(figure)
            added.insert(.figure(figure.id))
        }
        return added
    }
}

// MARK: - Lecture tolérante (les anciens fichiers .mcd restent lisibles)

private extension KeyedDecodingContainer {
    func value<T: Decodable>(_ key: Key, _ fallback: @autoclosure () -> T) throws -> T {
        try decodeIfPresent(T.self, forKey: key) ?? fallback()
    }
}

extension Attribute {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.value(.id, UUID())
        name = try c.value(.name, "")
        type = try c.value(.type, .varchar)
        length = try c.value(.length, 50)
        precision = try c.value(.precision, 15)
        scale = try c.value(.scale, 2)
        isIdentifier = try c.value(.isIdentifier, false)
        isNotNull = try c.value(.isNotNull, false)
        isUnique = try c.value(.isUnique, false)
        label = try c.value(.label, "")
        collation = try c.value(.collation, "")
        complement = try c.value(.complement, "")
        comment = try c.value(.comment, "")
        enumValues = try c.value(.enumValues, [])
        customType = try c.value(.customType, "")
    }
}

extension Entity {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.value(.id, UUID())
        name = try c.value(.name, "")
        attributes = try c.value(.attributes, [])
        position = try c.value(.position, .zero)
        isFictive = try c.value(.isFictive, false)
        color = try c.value(.color, .auto)
    }
}

extension Leg {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.value(.id, UUID())
        entityID = try c.decode(UUID.self, forKey: .entityID)
        cardinality = try c.value(.cardinality, .zeroMany)
        isRelative = try c.value(.isRelative, false)
        role = try c.value(.role, "")
        bend = try c.decodeIfPresent(CGPoint.self, forKey: .bend)
    }
}

extension Association {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.value(.id, UUID())
        name = try c.value(.name, "")
        attributes = try c.value(.attributes, [])
        legs = try c.value(.legs, [])
        position = try c.value(.position, .zero)
        color = try c.value(.color, .auto)
    }
}

extension ModelSettings {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        naming = try c.value(.naming, .telQuel)
        foreignKeysAtEnd = try c.value(.foreignKeysAtEnd, false)
        showTypes = try c.value(.showTypes, true)
        showAttributes = try c.value(.showAttributes, true)
        showGrid = try c.value(.showGrid, true)
        useLabels = try c.value(.useLabels, false)
        showDependencies = try c.value(.showDependencies, false)
    }
}

extension MCDModel {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.value(.version, 1)
        entities = try c.value(.entities, [])
        associations = try c.value(.associations, [])
        inheritances = try c.value(.inheritances, [])
        constraints = try c.value(.constraints, [])
        rules = try c.value(.rules, [])
        notes = try c.value(.notes, [])
        figures = try c.value(.figures, [])
        views = try c.value(.views, [])
        settings = try c.value(.settings, ModelSettings())
    }
}
