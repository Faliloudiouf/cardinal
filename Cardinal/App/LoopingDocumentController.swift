import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Un fichier Looping (.loo) s'ouvre comme un import : dès que sa fenêtre apparaît, le document
/// est détaché du .loo (nouveau document, même nom, type .mcd). Le .loo n'est donc jamais réécrit.
@MainActor
enum LooImport {
    private static var observer: NSObjectProtocol?
    /// Nom d'origine des .loo importés, pour les fenêtres qui apparaissent après coup.
    static var names: [ObjectIdentifier: String] = [:]

    /// Surveille tous les documents ouverts, quelle que soit la voie d'ouverture
    /// (⌘O, Finder, glisser-déposer, Ouvrir récent) : le contrôle est instantané.
    static func startWatching() {
        guard observer == nil else { return }
        observer = NotificationCenter.default.addObserver(
            forName: NSApplication.didUpdateNotification, object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated {
                for document in NSDocumentController.shared.documents {
                    detachIfNeeded(document)
                    // Une fenêtre créée après le détachement reçoit aussi le nom du .loo,
                    // tant que le document n'a pas été enregistré sous un vrai nom.
                    if document.fileURL == nil, let name = names[ObjectIdentifier(document)] {
                        for controller in document.windowControllers where controller.window?.title != name {
                            controller.window?.title = name
                        }
                    }
                }
                BlankDocument.replaceIfNeeded()
            }
        }
    }

    static func detachIfNeeded(_ document: NSDocument?) {
        guard let document, let url = document.fileURL, url.pathExtension.lowercased() == "loo" else { return }
        let name = url.deletingPathExtension().lastPathComponent
        document.fileURL = nil
        document.fileType = UTType.cardinalModel.identifier
        // -[NSDocument setDisplayName:] n'est pas exposé à Swift : on l'appelle par son sélecteur.
        let selector = NSSelectorFromString("setDisplayName:")
        if document.responds(to: selector) { document.perform(selector, with: name) }
        // Les fenêtres ne relisent pas le nom d'elles-mêmes : on le leur impose.
        for controller in document.windowControllers {
            controller.synchronizeWindowTitleWithDocumentName()
            controller.window?.title = name
        }
        LooImport.names[ObjectIdentifier(document)] = name
        // Le modèle converti n'est pas encore enregistré : la fermeture proposera de le sauvegarder en .mcd.
        document.updateChangeCount(.changeDone)
    }
}

/// Comme Pages ou Word : ouvrir un fichier alors que la seule fenêtre est un « Sans titre »
/// encore vierge (jamais modifié, jamais enregistré) remplace cette fenêtre au lieu d'en laisser deux.
@MainActor
enum BlankDocument {
    private static var known: Set<ObjectIdentifier> = []

    static func isBlank(_ document: NSDocument) -> Bool {
        document.fileURL == nil && !document.isDocumentEdited && LooImport.names[ObjectIdentifier(document)] == nil
    }

    static func replaceIfNeeded() {
        let documents = NSDocumentController.shared.documents
        // Un document n'est « connu » qu'une fois sa fenêtre créée : celui dont la fenêtre arrive
        // un peu plus tard est encore traité comme nouveau au passage suivant.
        defer { known = Set(documents.filter { !$0.windowControllers.isEmpty }.map(ObjectIdentifier.init)) }
        // Documents apparus depuis le dernier passage, venant d'un fichier (.mcd, ou .loo importé).
        let opened = documents.filter { !known.contains(ObjectIdentifier($0)) && !isBlank($0) && !$0.windowControllers.isEmpty }
        guard let newcomer = opened.first, newcomer.fileURL != nil || LooImport.names[ObjectIdentifier(newcomer)] != nil else { return }
        let blanks = documents.filter { known.contains(ObjectIdentifier($0)) && isBlank($0) }
        guard !blanks.isEmpty else { return }
        // Le fichier ouvert prend la place (position et taille) de la fenêtre remplacée.
        if let frame = blanks.first?.windowControllers.first?.window?.frame {
            newcomer.windowControllers.first?.window?.setFrame(frame, display: true)
        }
        for blank in blanks { blank.close() }
    }
}

/// Donne accès à la fenêtre AppKit qui héberge une vue SwiftUI.
struct WindowAccessor: NSViewRepresentable {
    let onWindow: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ view: NSView, context: Context) {
        DispatchQueue.main.async {
            if let window = view.window { onWindow(window) }
        }
    }
}
