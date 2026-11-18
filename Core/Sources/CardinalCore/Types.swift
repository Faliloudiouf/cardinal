import Foundation

// MARK: - Types de données
//
// Mêmes familles que la fenêtre « Propriété » de Looping (Texte, Numérique, Date / Heure, Autre),
// plus les types modernes très utilisés : petit et grand entier, horodatage avec fuseau,
// UUID, JSON et énumération. Le générateur SQL traduit chaque type pour chaque SGBD.

enum TypeCategory: String, CaseIterable, Identifiable, Sendable {
    case texte, numerique, dateHeure, autre
    var id: String { rawValue }

    var label: String {
        switch self {
        case .texte: "Texte"
        case .numerique: "Numérique"
        case .dateHeure: "Date / Heure"
        case .autre: "Autre"
        }
    }

    var types: [DataType] { DataType.allCases.filter { $0.category == self } }
}

/// Jeu de caractères d'un texte, comme dans Looping.
enum TextEncoding: String, CaseIterable, Identifiable, Sendable {
    case ascii, unicode, binaire
    var id: String { rawValue }
    var label: String {
        switch self {
        case .ascii: "Caractères ASCII"
        case .unicode: "Caractères Unicode"
        case .binaire: "Binaire"
        }
    }
    var shortLabel: String {
        switch self {
        case .ascii: "ASCII"
        case .unicode: "Unicode"
        case .binaire: "Binaire"
        }
    }
}

/// Stockage d'un texte : longueur variable, fixe, ou texte volumineux.
enum TextStorage: String, CaseIterable, Identifiable, Sendable {
    case variable, fixe, volumineux
    var id: String { rawValue }
    var label: String {
        switch self {
        case .variable: "Variable"
        case .fixe: "Fixe"
        case .volumineux: "Volumineux"
        }
    }
}

enum DataType: String, CaseIterable, Identifiable, Sendable {
    // Texte : jeu de caractères × stockage.
    case varchar, char, text
    case nvarchar, nchar, ntext
    case varbinary, binary, blob
    // Numérique.
    case petitEntier = "smallint", entier = "int", grandEntier = "bigint"
    case decimal, reel = "real", monetaire = "money", compteur = "counter"
    // Date et heure.
    case date, heure = "time", dateHeure = "datetime", horodatage = "timestamptz"
    // Autre.
    case booleen = "boolean", uuid, json, xml, enumeration = "enum"
    case geometrique = "geometry", geographique = "geography", libre

    var id: String { rawValue }

    var category: TypeCategory {
        switch self {
        case .varchar, .char, .text, .nvarchar, .nchar, .ntext, .varbinary, .binary, .blob: .texte
        case .petitEntier, .entier, .grandEntier, .decimal, .reel, .monetaire, .compteur: .numerique
        case .date, .heure, .dateHeure, .horodatage: .dateHeure
        case .booleen, .uuid, .json, .xml, .enumeration, .geometrique, .geographique, .libre: .autre
        }
    }

    /// Nom affiché dans la fenêtre de propriété.
    var label: String {
        switch self {
        case .varchar, .nvarchar, .varbinary: "Variable"
        case .char, .nchar, .binary: "Fixe"
        case .text, .ntext, .blob: "Volumineux"
        case .petitEntier: "Petit entier"
        case .entier: "Entier"
        case .grandEntier: "Grand entier"
        case .decimal: "Décimal"
        case .reel: "Réel"
        case .monetaire: "Monétaire"
        case .compteur: "Compteur"
        case .date: "Date"
        case .heure: "Heure"
        case .dateHeure: "Date-Heure"
        case .horodatage: "Horodatage avec fuseau"
        case .booleen: "Booléen"
        case .uuid: "UUID"
        case .json: "JSON"
        case .xml: "Xml"
        case .enumeration: "Énumération"
        case .geometrique: "Géométrique"
        case .geographique: "Géographique"
        case .libre: "Libre"
        }
    }

    /// Nom complet, utilisé dans les menus (« Texte variable ASCII (VARCHAR) »).
    var menuLabel: String {
        if let encoding, let storage {
            let base = encoding == .binaire ? "Binaire" : "Texte"
            let charset = encoding == .unicode ? " Unicode" : ""
            return "\(base) \(storage.label.lowercased())\(charset)"
        }
        return label
    }

    /// Aide affichée sous le choix du type.
    var help: String {
        switch self {
        case .varchar: "Texte court de longueur variable : nom, e-mail, code."
        case .char: "Texte de longueur toujours identique : code pays, code postal."
        case .text: "Texte long sans limite pratique : description, commentaire."
        case .nvarchar, .nchar, .ntext: "Comme le texte ASCII, mais accepte tous les alphabets (accents, arabe, emoji)."
        case .varbinary, .binary: "Octets bruts de taille limitée : empreinte, jeton."
        case .blob: "Fichier ou gros volume d'octets : image, PDF."
        case .petitEntier: "Entier de −32 768 à 32 767 : âge, quantité réduite."
        case .entier: "Entier sur 32 bits : identifiant, quantité."
        case .grandEntier: "Entier sur 64 bits : très grands compteurs, identifiants externes."
        case .decimal: "Nombre exact avec virgule : précision = chiffres au total, échelle = après la virgule."
        case .reel: "Nombre à virgule flottante, approché : mesure scientifique."
        case .monetaire: "Montant exact avec 4 décimales."
        case .compteur: "Entier numéroté automatiquement par le SGBD. À réserver à l'identifiant."
        case .date: "Jour, mois, année."
        case .heure: "Heure de la journée."
        case .dateHeure: "Date et heure, sans fuseau horaire."
        case .horodatage: "Instant précis avec fuseau horaire : journal, création d'un compte."
        case .booleen: "Vrai ou faux."
        case .uuid: "Identifiant universel unique sur 128 bits."
        case .json: "Document JSON, validé par le SGBD quand il le permet."
        case .xml: "Document XML."
        case .enumeration: "Une valeur parmi une liste fermée (ex. « actif, suspendu, clos »)."
        case .geometrique: "Forme sur un plan (point, ligne, polygone)."
        case .geographique: "Forme sur le globe terrestre (latitude, longitude)."
        case .libre: "Type écrit tel quel dans le script, pour un besoin particulier."
        }
    }

    var encoding: TextEncoding? {
        switch self {
        case .varchar, .char, .text: .ascii
        case .nvarchar, .nchar, .ntext: .unicode
        case .varbinary, .binary, .blob: .binaire
        default: nil
        }
    }

    var storage: TextStorage? {
        switch self {
        case .varchar, .nvarchar, .varbinary: .variable
        case .char, .nchar, .binary: .fixe
        case .text, .ntext, .blob: .volumineux
        default: nil
        }
    }

    static func text(_ encoding: TextEncoding, _ storage: TextStorage) -> DataType {
        switch (encoding, storage) {
        case (.ascii, .variable): .varchar
        case (.ascii, .fixe): .char
        case (.ascii, .volumineux): .text
        case (.unicode, .variable): .nvarchar
        case (.unicode, .fixe): .nchar
        case (.unicode, .volumineux): .ntext
        case (.binaire, .variable): .varbinary
        case (.binaire, .fixe): .binary
        case (.binaire, .volumineux): .blob
        }
    }

    var usesLength: Bool { storage == .variable || storage == .fixe }
    var usesPrecision: Bool { self == .decimal }
    var usesCollation: Bool { encoding == .ascii || encoding == .unicode || self == .enumeration }
    var isInteger: Bool { [.petitEntier, .entier, .grandEntier, .compteur].contains(self) }

    /// Longueur maximale acceptée dans la fenêtre (le générateur bascule ensuite sur le type
    /// volumineux du SGBD si sa propre limite est plus basse).
    var maxLength: Int { storage == .fixe ? 8000 : 1_000_000 }

    /// Longueur proposée quand on choisit ce type.
    var defaultLength: Int {
        switch self {
        case .char, .nchar: 10
        case .varbinary, .binary: 16
        default: 50
        }
    }
}

extension DataType: Codable {
    /// Lecture tolérante : les anciens fichiers Cardinal (types « texteCourt », « montant »…)
    /// restent lisibles, et un type inconnu devient un texte variable plutôt qu'une erreur.
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = DataType(rawValue: raw) ?? Self.legacy[raw] ?? .varchar
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    static let legacy: [String: DataType] = [
        "entier": .entier, "reel": .reel, "montant": .decimal, "texteCourt": .varchar,
        "texteLong": .text, "dateHeure": .dateHeure, "booleen": .booleen,
    ]
}

// MARK: - Type complet (type + paramètres)

/// Un type avec ses paramètres : c'est ce que reçoivent le MLD et le générateur SQL.
struct TypeSpec: Hashable, Sendable {
    var kind: DataType
    var length: Int = 50
    var precision: Int = 15
    var scale: Int = 2
    var enumValues: [String] = []
    var custom: String = ""
    var collation: String = ""

    static let precisionRange = 1...38

    /// Copie d'une clé dans une autre table : un compteur y devient un simple entier
    /// (la valeur est recopiée, pas générée), et le complément SQL ne suit pas.
    var asForeignKey: TypeSpec {
        var spec = self
        if spec.kind == .compteur { spec.kind = .entier }
        return spec
    }

    /// Paramètres ramenés dans des bornes valides (la fenêtre l'empêche déjà, mais un fichier
    /// modifié à la main ou importé ne doit jamais produire un script faux).
    var normalized: TypeSpec {
        var spec = self
        spec.length = min(max(length, 1), kind.maxLength)
        spec.precision = min(max(precision, Self.precisionRange.lowerBound), Self.precisionRange.upperBound)
        spec.scale = min(max(scale, 0), spec.precision)
        spec.enumValues = Self.cleanValues(enumValues)
        spec.custom = custom.trimmingCharacters(in: .whitespacesAndNewlines)
        spec.collation = String(collation.filter { $0.isLetter || $0.isNumber || "_-.".contains($0) })
        return spec
    }

    /// Valeurs d'énumération : sans blanc autour, sans vide, sans doublon (ordre conservé).
    static func cleanValues(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    /// Notation générique affichée sur les diagrammes, proche de celle de Looping.
    var display: String {
        let spec = normalized
        switch spec.kind {
        case .varchar: return "VARCHAR(\(spec.length))"
        case .char: return "CHAR(\(spec.length))"
        case .text: return "TEXT"
        case .nvarchar: return "NVARCHAR(\(spec.length))"
        case .nchar: return "NCHAR(\(spec.length))"
        case .ntext: return "NTEXT"
        case .varbinary: return "VARBINARY(\(spec.length))"
        case .binary: return "BINARY(\(spec.length))"
        case .blob: return "BLOB"
        case .petitEntier: return "SMALLINT"
        case .entier: return "INT"
        case .grandEntier: return "BIGINT"
        case .decimal: return "DECIMAL(\(spec.precision),\(spec.scale))"
        case .reel: return "REAL"
        case .monetaire: return "MONEY"
        case .compteur: return "COUNTER"
        case .date: return "DATE"
        case .heure: return "TIME"
        case .dateHeure: return "DATETIME"
        case .horodatage: return "TIMESTAMPTZ"
        case .booleen: return "LOGICAL"
        case .uuid: return "UUID"
        case .json: return "JSON"
        case .xml: return "XML"
        case .enumeration:
            let list = spec.enumValues.joined(separator: ",")
            return list.count > 24 ? "ENUM(\(spec.enumValues.count) valeurs)" : "ENUM(\(list))"
        case .geometrique: return "GEOMETRY"
        case .geographique: return "GEOGRAPHY"
        case .libre: return spec.custom.isEmpty ? "LIBRE" : spec.custom.uppercased()
        }
    }
}

extension Attribute {
    var spec: TypeSpec {
        get {
            TypeSpec(kind: type, length: length, precision: precision, scale: scale,
                     enumValues: enumValues, custom: customType, collation: collation)
        }
        set {
            type = newValue.kind
            length = newValue.length
            precision = newValue.precision
            scale = newValue.scale
            enumValues = newValue.enumValues
            customType = newValue.custom
            collation = newValue.collation
        }
    }

    /// Change de type en gardant des paramètres sensés (longueur par défaut du nouveau type, etc.).
    mutating func setType(_ newType: DataType) {
        guard newType != type else { return }
        let keepsLength = type.usesLength && newType.usesLength && type.storage == newType.storage
        type = newType
        if newType.usesLength && !keepsLength { length = newType.defaultLength }
        if !newType.usesCollation { collation = "" }
        if newType == .enumeration && enumValues.isEmpty { enumValues = ["valeur1", "valeur2"] }
    }
}
