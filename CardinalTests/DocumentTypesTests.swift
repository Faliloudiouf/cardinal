import AppKit
import Testing
@testable import Cardinal

/// Vérifie l'ouverture des .loo et des .mcd telle que le Finder et la fenêtre Ouvrir la font.
@MainActor
@Suite("Types de documents", .serialized)
struct DocumentTypesTests {
    @Test("Les .loo et les .mcd sont proposés dans la fenêtre Ouvrir")
    func typesLisibles() {
        let controller = NSDocumentController.shared
        let classes = controller.documentClassNames.compactMap { NSClassFromString($0) as? NSDocument.Type }
        let readable = Set(classes.flatMap { $0.readableTypes })
        #expect(readable.contains("sn.cardinal.looping-loo"))
        #expect(readable.contains("sn.cardinal.mcd"))
    }

    @Test("Ouvrir un .loo crée un document sans titre et ne modifie jamais le fichier")
    func ouvertureLooSansEcriture() async throws {
        let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../Core/Tests/CardinalCoreTests/Fixtures/LoopingEntrepriseServices2.loo")
        let copy = FileManager.default.temporaryDirectory.appendingPathComponent("test-\(UUID().uuidString).loo")
        try FileManager.default.copyItem(at: fixture, to: copy)
        defer { try? FileManager.default.removeItem(at: copy) }
        let before = try Data(contentsOf: copy)

        let document: NSDocument? = try await withCheckedThrowingContinuation { continuation in
            NSDocumentController.shared.openDocument(withContentsOf: copy, display: false) { document, _, error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume(returning: document) }
            }
        }
        let opened = try #require(document)
        // Même sans fenêtre (cas le plus défavorable), le document doit être détaché du .loo.
        try await Task.sleep(for: .seconds(0.5))
        NSApp.updateWindows()
        try await Task.sleep(for: .seconds(0.5))
        #expect(opened.fileURL == nil, "le document importé doit être détaché du .loo")
        #expect(opened.fileType == "sn.cardinal.mcd")
        #expect(opened.displayName.hasPrefix("test-"))

        // Même après une sauvegarde automatique, le .loo reste identique.
        opened.updateChangeCount(.changeDone)
        try? await opened.autosave(withImplicitCancellability: false)
        #expect(try Data(contentsOf: copy) == before)
        opened.close()
    }
}
