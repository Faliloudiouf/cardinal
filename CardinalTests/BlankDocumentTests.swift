import AppKit
import Testing
@testable import Cardinal

/// Ouvrir un fichier alors qu'un « Sans titre » vierge est affiché doit remplacer ce dernier,
/// mais jamais un document modifié ou déjà enregistré.
@MainActor
@Suite("Remplacement du document vierge", .serialized)
struct BlankDocumentTests {
    final class Essai: NSDocument {
        override func makeWindowControllers() {
            addWindowController(NSWindowController(window: NSWindow(contentRect: NSRect(x: 100, y: 100, width: 800, height: 500),
                                                                     styleMask: [.titled], backing: .buffered, defer: true)))
        }
        override func data(ofType typeName: String) throws -> Data { Data() }
        override func read(from data: Data, ofType typeName: String) throws {}
    }

    private func document(fichier: URL? = nil, modifie: Bool = false) -> Essai {
        let d = Essai()
        d.fileURL = fichier
        if modifie { d.updateChangeCount(.changeDone) }
        d.makeWindowControllers()
        NSDocumentController.shared.addDocument(d)
        return d
    }

    private func nettoyer() {
        for d in NSDocumentController.shared.documents where d is Essai { NSDocumentController.shared.removeDocument(d) }
        BlankDocument.replaceIfNeeded()
    }

    private var ouverts: [NSDocument] { NSDocumentController.shared.documents.filter { $0 is Essai } }

    @Test("Un fichier ouvert remplace le « Sans titre » vierge")
    func remplaceLeVierge() {
        nettoyer()
        let vierge = document()
        BlankDocument.replaceIfNeeded()
        let fichier = document(fichier: URL(fileURLWithPath: "/tmp/modele.mcd"))
        BlankDocument.replaceIfNeeded()
        #expect(!ouverts.contains(vierge))
        #expect(ouverts.contains(fichier))
        nettoyer()
    }

    @Test("Un « Sans titre » modifié est conservé")
    func garderModifie() {
        nettoyer()
        let modifie = document(modifie: true)
        BlankDocument.replaceIfNeeded()
        _ = document(fichier: URL(fileURLWithPath: "/tmp/modele.mcd"))
        BlankDocument.replaceIfNeeded()
        #expect(ouverts.contains(modifie))
        nettoyer()
    }

    @Test("Un nouveau modèle vide ne ferme pas les autres")
    func nouveauModele() {
        nettoyer()
        let premier = document()
        BlankDocument.replaceIfNeeded()
        let second = document()
        BlankDocument.replaceIfNeeded()
        #expect(ouverts.contains(premier) && ouverts.contains(second))
        nettoyer()
    }

    @Test("Un fichier enregistré n'est jamais remplacé")
    func garderEnregistre() {
        nettoyer()
        let premier = document(fichier: URL(fileURLWithPath: "/tmp/a.mcd"))
        BlankDocument.replaceIfNeeded()
        _ = document(fichier: URL(fileURLWithPath: "/tmp/b.mcd"))
        BlankDocument.replaceIfNeeded()
        #expect(ouverts.contains(premier))
        nettoyer()
    }
}
