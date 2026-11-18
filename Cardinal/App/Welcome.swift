import AppKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Lancement de l'application

/// Au lancement : ni panneau d'ouverture, ni document vide. C'est la fenêtre d'accueil qui s'affiche.
final class CardinalAppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        // Sans cela, macOS montre un panneau « Ouvrir » au démarrage d'une app à documents.
        UserDefaults.standard.register(defaults: ["NSShowAppCentricOpenPanelInsteadOfUntitledFile": false])
        // Apparence choisie dans les Réglages, appliquée avant l'ouverture de la première fenêtre.
        MainActor.assumeIsolated { AppAppearance.apply() }
    }

    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool { false }

    /// Clic sur l'icône du Dock sans fenêtre ouverte : on revient à l'accueil.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        if !hasVisibleWindows { MainActor.assumeIsolated { WelcomeWindow.show() } }
        return false
    }
}

@MainActor
enum WelcomeWindow {
    static let id = "accueil"
    /// Action d'ouverture de fenêtre fournie par SwiftUI, mémorisée pour le délégué de l'app.
    static var opener: OpenWindowAction?

    static func show() { opener?(id: id) }
}

/// Fichiers récents : ceux que macOS mémorise pour Cardinal, sans les fichiers disparus.
@MainActor
enum RecentFiles {
    static var urls: [URL] {
        NSDocumentController.shared.recentDocumentURLs.filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    static func clear() { NSDocumentController.shared.clearRecentDocuments(nil) }
}

// MARK: - Actions de fichier (accueil et ruban)

/// Créer, ouvrir, importer : une seule implémentation pour l'accueil et le ruban.
@MainActor
struct DocumentActions {
    let newDocument: NewDocumentAction
    let openDocument: OpenDocumentAction

    func createEmpty() { create(MCDModel(settings: Defaults.newModelSettings)) }

    func create(_ model: MCDModel) { newDocument(CardinalDocument(model: model)) }

    /// Panneau d'ouverture ; renvoie vrai si un fichier a été ouvert.
    @discardableResult
    func chooseAndOpen(types: [UTType] = [.cardinalModel, .loopingModel, .json]) async -> Bool {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = types
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return false }
        return await open(url)
    }

    /// Ouvre un fichier ; en cas d'échec, explique pourquoi. Renvoie vrai si c'est ouvert.
    @discardableResult
    func open(_ url: URL) async -> Bool {
        guard FileManager.default.fileExists(atPath: url.path) else {
            Self.alert("« \(url.lastPathComponent) » est introuvable", "Le fichier a été déplacé ou supprimé depuis sa dernière ouverture.")
            return false
        }
        do {
            try await openDocument(at: url)
            NSDocumentController.shared.noteNewRecentDocumentURL(url)
            return true
        } catch {
            Self.alert("Ouverture impossible", "« \(url.lastPathComponent) » n'a pas pu être ouvert : \(error.localizedDescription)")
            return false
        }
    }

    @discardableResult
    func reverseEngineerSQL() -> Bool {
        guard let model = Exporter.importSQLFile() else { return false }
        create(model)
        return true
    }

    static func save() { NSApp.sendAction(#selector(NSDocument.save(_:)), to: nil, from: nil) }

    static func alert(_ title: String, _ message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.runModal()
    }
}

// MARK: - Fenêtre d'accueil

struct WelcomeView: View {
    /// Pour les captures de test : une liste de récents imposée.
    var previewRecents: [URL]?

    @Environment(\.newDocument) private var newDocument
    @Environment(\.openDocument) private var openDocument
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    @State private var recents: [URL] = []

    private var actions: DocumentActions { DocumentActions(newDocument: newDocument, openDocument: openDocument) }

    var body: some View {
        HStack(spacing: 0) {
            actionList
                .frame(width: 390)
            Divider()
            RecentList(recents: recents, open: open, clear: {
                RecentFiles.clear()
                recents = []
            })
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 840, height: 520)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            WelcomeWindow.opener = openWindow
            recents = previewRecents ?? RecentFiles.urls
            // Cardinal lancé en ouvrant un fichier (Finder) : l'accueil s'efface de lui-même.
            guard previewRecents == nil else { return }
            Task {
                try? await Task.sleep(for: .milliseconds(600))
                if !NSDocumentController.shared.documents.isEmpty { dismissWindow(id: WelcomeWindow.id) }
            }
        }
    }

    private var actionList: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Identité : icône, nom, version.
            VStack(alignment: .leading, spacing: 6) {
                Image(nsImage: NSApp?.applicationIconImage ?? NSImage())
                    .resizable()
                    .frame(width: 84, height: 84)
                    .shadow(color: .black.opacity(0.12), radius: 6, y: 3)
                    .padding(.leading, -6)
                Text("Cardinal")
                    .font(.system(size: 30, weight: .bold))
                    .tracking(-0.6)
                Text("Modélisation Merise : MCD, MLD, UML et SQL")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                Text("Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
            .padding(.bottom, 26)

            VStack(alignment: .leading, spacing: 4) {
                WelcomeAction(symbol: "plus.square.fill", title: "Nouveau modèle", detail: "Un MCD vide, prêt à dessiner",
                              shortcut: "⌘N", isPrimary: true) { create(MCDModel(settings: Defaults.newModelSettings)) }
                WelcomeAction(symbol: "folder.fill", title: "Ouvrir un modèle…", detail: ".mcd de Cardinal ou .loo de Looping",
                              shortcut: "⌘O") { openPanel(types: [.cardinalModel, .loopingModel, .json]) }
                WelcomeAction(symbol: "square.and.arrow.down.fill", title: "Importer depuis Looping…", detail: "Le .loo d'origine n'est jamais modifié",
                              shortcut: nil) { openPanel(types: [.loopingModel]) }
                WelcomeAction(symbol: "cylinder.fill", title: "Rétroconception SQL…", detail: "Reconstruit le MCD depuis un script",
                              shortcut: "⇧⌘I") { if actions.reverseEngineerSQL() { dismissWindow(id: WelcomeWindow.id) } }
            }

            Spacer(minLength: 16)

            Text("EXEMPLES")
                .font(.system(size: 10.5, weight: .semibold))
                .tracking(0.8)
                .foregroundStyle(.secondary)
                .padding(.leading, 10)
                .padding(.bottom, 4)
            HStack(spacing: 8) {
                ExampleButton(title: "Commandes", detail: "Entités et associations") { create(.exemple) }
                ExampleButton(title: "Scolarité", detail: "Héritage, CIF, règle") { create(.exempleScolarite) }
            }
        }
        .padding(28)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    // MARK: Actions

    private func create(_ model: MCDModel) {
        actions.create(model)
        dismissWindow(id: WelcomeWindow.id)
    }

    private func openPanel(types: [UTType]) {
        Task { if await actions.chooseAndOpen(types: types) { dismissWindow(id: WelcomeWindow.id) } }
    }

    private func open(_ url: URL) {
        Task { if await actions.open(url) { dismissWindow(id: WelcomeWindow.id) } }
    }
}

/// Une action de l'accueil : icône pleine, titre, explication, raccourci.
private struct WelcomeAction: View {
    let symbol: String
    let title: String
    let detail: String
    let shortcut: String?
    var isPrimary = false
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(isPrimary ? Color.white : Theme.entity)
                    .frame(width: 34, height: 34)
                    .background(isPrimary ? Theme.entityFill : Theme.entity.opacity(0.12), in: RoundedRectangle(cornerRadius: 9))
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.system(size: 13.5, weight: .semibold))
                    Text(detail).font(.system(size: 11.5)).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 8)
                if let shortcut {
                    Text(shortcut).font(.system(size: 11.5, design: .rounded)).foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .contentShape(RoundedRectangle(cornerRadius: 10))
            .background(isHovered ? Color.primary.opacity(0.06) : .clear, in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(PressableStyle())
        .onHover { isHovered = $0 }
    }
}

private struct ExampleButton: View {
    let title: String
    let detail: String
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 3) {
                Label(title, systemImage: "book.closed.fill")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(Theme.association)
                Text(detail).font(.system(size: 11)).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(Theme.association.opacity(isHovered ? 0.16 : 0.09), in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(PressableStyle())
        .onHover { isHovered = $0 }
    }
}

/// Réponse immédiate à l'appui : léger enfoncement, sans délai.
private struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

// MARK: - Fichiers récents

private struct RecentList: View {
    let recents: [URL]
    let open: (URL) -> Void
    let clear: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Récents")
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                if !recents.isEmpty {
                    Button("Effacer la liste", action: clear)
                        .buttonStyle(.borderless)
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 26)
            .padding(.bottom, 10)

            if recents.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "clock.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(.tertiary)
                    Text("Aucun fichier récent")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text("Les modèles que vous ouvrez ou enregistrez apparaîtront ici.")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, 30)
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(recents, id: \.self) { url in
                            RecentRow(url: url) { open(url) }
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.bottom, 12)
                }
            }
        }
        .overlay(alignment: .bottomTrailing) {
            AppearanceQuickMenu()
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .padding(14)
        }
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.6))
    }
}

private struct RecentRow: View {
    let url: URL
    let open: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: open) {
            HStack(spacing: 10) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                    .resizable()
                    .frame(width: 30, height: 30)
                VStack(alignment: .leading, spacing: 2) {
                    Text(url.deletingPathExtension().lastPathComponent)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(Self.folder(of: url))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.head)
                }
                Spacer(minLength: 8)
                if let date = Self.modified(url) {
                    Text(date)
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                        .fixedSize()
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .contentShape(RoundedRectangle(cornerRadius: 8))
            .background(isHovered ? Color.primary.opacity(0.06) : .clear, in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(url.path)
        .contextMenu {
            Button("Ouvrir", action: open)
            Button("Afficher dans le Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
        }
    }

    /// Dossier lisible : « ~/Documents/cours ».
    static func folder(of url: URL) -> String {
        let folder = url.deletingLastPathComponent().path
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return folder.hasPrefix(home) ? "~" + folder.dropFirst(home.count) : folder
    }

    static func modified(_ url: URL) -> String? {
        guard let date = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate else { return nil }
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

/// Commande « Fenêtre d'accueil » du menu Fenêtre.
struct WelcomeMenuItem: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Fenêtre d'accueil") { openWindow(id: WelcomeWindow.id) }
            .keyboardShortcut("1", modifiers: [.command, .shift])
    }
}
