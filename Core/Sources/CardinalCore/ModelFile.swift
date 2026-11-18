import Foundation

/// Format de fichier de Cardinal (.mcd) : du JSON lisible et stable (clés triées), identique
/// sur macOS, Windows et Linux. Un fichier Looping (.loo) est converti à la lecture.
enum ModelFile {
    enum Failure: Error, LocalizedError {
        case empty
        case unreadable(String)

        var errorDescription: String? {
            switch self {
            case .empty: "Le fichier est vide."
            case .unreadable(let detail): "Le fichier n'est pas un modèle Cardinal lisible (\(detail))."
            }
        }
    }

    static func encode(_ model: MCDModel) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(model)
    }

    /// Lit un .mcd ou un .loo. `isLooping` vient du type de fichier ; à défaut, le contenu décide :
    /// un JSON commence par « { », éventuellement après des espaces ou une marque UTF-8 (BOM).
    static func read(_ data: Data, isLooping: Bool = false) throws -> MCDModel {
        guard !data.isEmpty else { throw Failure.empty }
        if isLooping || !looksLikeJSON(data) {
            return try LooImporter.model(from: data)
        }
        do {
            return try JSONDecoder().decode(MCDModel.self, from: data)
        } catch let error as DecodingError {
            throw Failure.unreadable(describe(error))
        }
    }

    static func looksLikeJSON(_ data: Data) -> Bool {
        var bytes = data[...]
        if bytes.starts(with: [0xEF, 0xBB, 0xBF]) { bytes = bytes.dropFirst(3) }
        let first = bytes.first { ![0x20, 0x09, 0x0A, 0x0D].contains($0) }
        return first == UInt8(ascii: "{")
    }

    private static func describe(_ error: DecodingError) -> String {
        switch error {
        case .dataCorrupted(let context): context.debugDescription
        case .keyNotFound(let key, _): "champ « \(key.stringValue) » manquant"
        case .typeMismatch(_, let context), .valueNotFound(_, let context):
            "valeur inattendue à « \(context.codingPath.map(\.stringValue).joined(separator: ".")) »"
        @unknown default: "contenu inattendu"
        }
    }
}
