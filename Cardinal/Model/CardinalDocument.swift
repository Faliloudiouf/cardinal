import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static let cardinalModel = UTType(exportedAs: "sn.cardinal.mcd")
    static let loopingModel = UTType(importedAs: "sn.cardinal.looping-loo")
    static let sqlScript = UTType(filenameExtension: "sql", conformingTo: .plainText) ?? .plainText
}

/// Un fichier .mcd : du JSON lisible, facile à versionner avec Git.
struct CardinalDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.cardinalModel, .loopingModel, .json] }
    static var writableContentTypes: [UTType] { [.cardinalModel] }

    var model: MCDModel

    init(model: MCDModel = MCDModel()) {
        self.model = model
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        // Un fichier Looping est converti à l'ouverture ; Cardinal l'enregistrera ensuite en .mcd.
        model = try ModelFile.read(data, isLooping: configuration.contentType.conforms(to: .loopingModel))
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        // Sécurité : Cardinal n'écrit jamais dans un fichier Looping.
        if configuration.contentType.conforms(to: .loopingModel) {
            throw CocoaError(.fileWriteUnsupportedScheme)
        }
        return FileWrapper(regularFileWithContents: try Self.encode(model))
    }

    static func encode(_ model: MCDModel) throws -> Data { try ModelFile.encode(model) }
}

/// Fichier texte utilisé pour exporter le script SQL.
struct SQLFile: FileDocument {
    static var readableContentTypes: [UTType] { [.sqlScript, .plainText] }
    var text: String

    init(text: String) { self.text = text }

    init(configuration: ReadConfiguration) throws {
        text = String(decoding: configuration.file.regularFileContents ?? Data(), as: UTF8.self)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}
