import SwiftUI

@main
struct CardinalApp: App {
    @NSApplicationDelegateAdaptor(CardinalAppDelegate.self) private var appDelegate

    init() {
        LooImport.startWatching()
    }

    var body: some Scene {
        // Fenêtre d'accueil, affichée au lancement (créer, ouvrir, exemples, récents).
        Window("Bienvenue dans Cardinal", id: WelcomeWindow.id) {
            WelcomeView()
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultLaunchBehavior(.presented)
        .restorationBehavior(.disabled)

        DocumentGroup(newDocument: CardinalDocument(model: MCDModel(settings: Defaults.newModelSettings))) { file in
            ContentView(
                document: file.$document,
                fileName: file.fileURL?.deletingPathExtension().lastPathComponent ?? "modele"
            )
            .modifier(RegistersWelcomeOpener())
        }
        .defaultSize(width: 1440, height: 900)
        .commands { CardinalCommands() }

        Settings {
            SettingsView()
        }
    }
}

// MARK: - Barre de menus

struct CardinalCommands: Commands {
    var body: some Commands {
        CommandGroup(after: .newItem) { FileMenuItems() }
        CommandGroup(replacing: .printItem) { PrintMenuItem() }
        CommandGroup(after: .pasteboard) { DuplicateMenuItem() }
        CommandGroup(before: .toolbar) { ViewMenuItems() }
        // Toujours actif, même sans document ouvert.
        CommandGroup(before: .toolbar) { AppearanceMenu(); Divider() }
        CommandMenu("Modèle") { ModelMenuItems() }
        CommandMenu("Organiser") { ArrangeMenuItems() }
        CommandGroup(before: .windowList) { WelcomeMenuItem(); Divider() }
    }
}

/// Toute fenêtre de document fournit aussi de quoi rouvrir l'accueil (clic sur le Dock).
private struct RegistersWelcomeOpener: ViewModifier {
    @Environment(\.openWindow) private var openWindow
    func body(content: Content) -> some View {
        content.onAppear { WelcomeWindow.opener = openWindow }
    }
}

private struct FileMenuItems: View {
    @Environment(\.newDocument) private var newDocument
    @FocusedValue(\.cardinalModel) private var model
    @FocusedValue(\.cardinalFileName) private var fileName
    @AppStorage(Defaults.dialect) private var dialect: SQLDialect = .mysql

    var body: some View {
        Menu("Nouveau à partir d'un exemple") {
            Button("Gestion de commandes") { newDocument(CardinalDocument(model: .exemple)) }
                .keyboardShortcut("n", modifiers: [.command, .shift])
            Button("Scolarité (héritage, CIF, règle)") { newDocument(CardinalDocument(model: .exempleScolarite)) }
        }
        Divider()
        Button("Rétroconception d'un script SQL…") {
            if let model = Exporter.importSQLFile() { newDocument(CardinalDocument(model: model)) }
        }
        .keyboardShortcut("i", modifiers: [.command, .shift])
        Button("Rétroconception depuis le presse-papiers") {
            if let model = Exporter.importSQLFromPasteboard() { newDocument(CardinalDocument(model: model)) }
        }
        Divider()
        Menu("Exporter") {
            if let model {
                ExportMenuItems(model: model, fileName: fileName ?? "modele", dialect: dialect)
            }
        }
        .disabled(model == nil)
    }
}

private struct PrintMenuItem: View {
    @FocusedValue(\.cardinalModel) private var model

    var body: some View {
        Button("Imprimer le diagramme…") {
            if let model { Exporter.print(model) }
        }
        .keyboardShortcut("p")
        .disabled(model == nil)
    }
}

private struct DuplicateMenuItem: View {
    @FocusedBinding(\.cardinalDocument) private var document
    @FocusedObject private var state: WindowState?

    var body: some View {
        Button("Dupliquer") {
            guard let state, document != nil else { return }
            state.selection = document!.model.paste(document!.model.subset(state.selection))
        }
        .keyboardShortcut("d")
        .disabled(state?.selection.isEmpty ?? true || state?.mode != .mcd)
    }
}

private struct ViewMenuItems: View {
    @FocusedBinding(\.cardinalDocument) private var document
    @FocusedObject private var state: WindowState?

    var body: some View {
        Group {
            ForEach(Array(ViewMode.allCases.enumerated()), id: \.element) { index, mode in
                Toggle(modeTitle(mode), isOn: Binding(
                    get: { state?.mode == mode },
                    set: { if $0 { state?.mode = mode } }
                ))
                .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")))
            }
            Divider()
            Toggle("Afficher les propriétés", isOn: settingBinding(\.showAttributes))
            Toggle("Afficher les types de données", isOn: settingBinding(\.showTypes))
            Toggle("Afficher la grille", isOn: settingBinding(\.showGrid))
            Toggle("Afficher les dépendances fonctionnelles", isOn: settingBinding(\.showDependencies))
            Divider()
            Button("Zoom avant") { state?.zoomIn() }.keyboardShortcut("+")
            Button("Zoom arrière") { state?.zoomOut() }.keyboardShortcut("-")
            Button("Taille réelle") { state?.actualSize() }.keyboardShortcut("0")
            Button("Ajuster à la fenêtre") { state?.fit() }.keyboardShortcut("9")
            Divider()
            Button(state?.showInspector == true ? "Masquer l'inspecteur" : "Afficher l'inspecteur") {
                state?.showInspector.toggle()
            }
            .keyboardShortcut("i", modifiers: [.command, .option])
            Divider()
        }
        .disabled(state == nil)
    }

    private func modeTitle(_ mode: ViewMode) -> String {
        switch mode {
        case .mcd: "Modèle conceptuel (MCD)"
        case .mld: "Modèle logique (MLD)"
        case .uml: "Diagramme de classes (UML)"
        case .sql: "Script SQL"
        }
    }

    private func settingBinding(_ path: WritableKeyPath<ModelSettings, Bool>) -> Binding<Bool> {
        Binding(
            get: { document?.model.settings[keyPath: path] ?? false },
            set: { document?.model.settings[keyPath: path] = $0 }
        )
    }
}

private struct ModelMenuItems: View {
    @FocusedBinding(\.cardinalDocument) private var document
    @FocusedObject private var state: WindowState?
    @AppStorage(Defaults.dialect) private var dialect: SQLDialect = .mysql

    var body: some View {
        Group {
            Section("Outils") {
                ForEach(Tool.allCases) { tool in
                    Toggle(isOn: Binding(
                        get: { state?.tool == tool },
                        set: { if $0 { state?.mode = .mcd; state?.tool = tool } }
                    )) {
                        Label(tool.label, systemImage: tool.symbol)
                    }
                }
            }
            Divider()
            SQLTargetPicker()
            Picker("Convention de nommage", selection: Binding(
                get: { document?.model.settings.naming ?? .telQuel },
                set: { document?.model.settings.naming = $0 }
            )) {
                ForEach(NamingConvention.allCases) { Text($0.label).tag($0) }
            }
            Toggle("Clés étrangères en ALTER TABLE à la fin", isOn: Binding(
                get: { document?.model.settings.foreignKeysAtEnd ?? false },
                set: { document?.model.settings.foreignKeysAtEnd = $0 }
            ))
            Toggle("Nommer les colonnes avec les libellés", isOn: Binding(
                get: { document?.model.settings.useLabels ?? false },
                set: { document?.model.settings.useLabels = $0 }
            ))
        }
        .disabled(state == nil)
    }
}

private struct ArrangeMenuItems: View {
    @FocusedBinding(\.cardinalDocument) private var document
    @FocusedObject private var state: WindowState?

    var body: some View {
        let selection = state?.selection ?? []
        Group {
            ForEach(Arranger.Alignment.allCases) { alignment in
                Button(alignment.label) {
                    guard document != nil else { return }
                    Arranger.align(selection, alignment, in: &document!.model)
                }
                .disabled(selection.count < 2)
            }
            Divider()
            Button("Mettre au premier plan") {
                guard document != nil else { return }
                Arranger.reorder(selection, front: true, in: &document!.model)
            }
            .keyboardShortcut("]", modifiers: [.command, .shift])
            .disabled(selection.isEmpty)
            Button("Mettre à l'arrière-plan") {
                guard document != nil else { return }
                Arranger.reorder(selection, front: false, in: &document!.model)
            }
            .keyboardShortcut("[", modifiers: [.command, .shift])
            .disabled(selection.isEmpty)
        }
        .disabled(state?.mode != .mcd)
    }
}

// MARK: - Réglages

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettings()
                .tabItem { Label("Général", systemImage: "gearshape.fill") }
            NewModelSettings()
                .tabItem { Label("Nouveaux modèles", systemImage: "doc.badge.plus") }
            CustomDialectSettings()
                .tabItem { Label("SGBD personnalisé", systemImage: "cylinder.split.1x2.fill") }
        }
        .frame(width: 580, height: 480)
    }
}

private struct GeneralSettings: View {
    @AppStorage(Defaults.dialect) private var dialect: SQLDialect = .mysql
    @AppStorage("affichageMLD") private var mldDisplay: MLDDisplay = .textuel
    @AppStorage("umlSimplifie") private var umlSimplified = false

    var body: some View {
        Form {
            Section("Apparence") {
                AppearancePicker()
            }
            SQLTargetPicker()
            Text("Utilisé pour l'onglet SQL et l'export du script.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Picker("Affichage du MLD", selection: $mldDisplay) {
                ForEach(MLDDisplay.allCases) { Text($0.rawValue).tag($0) }
            }
            Picker("Diagramme UML", selection: $umlSimplified) {
                Text("Standard").tag(false)
                Text("Simplifié").tag(true)
            }
        }
        .formStyle(.grouped)
    }
}

private struct NewModelSettings: View {
    @AppStorage(Defaults.naming) private var naming: NamingConvention = .telQuel
    @AppStorage(Defaults.foreignKeysAtEnd) private var foreignKeysAtEnd = false
    @AppStorage(Defaults.useLabels) private var useLabels = false
    @AppStorage(Defaults.showTypes) private var showTypes = true
    @AppStorage(Defaults.showGrid) private var showGrid = true

    var body: some View {
        Form {
            Section {
                Picker("Convention de nommage", selection: $naming) {
                    ForEach(NamingConvention.allCases) { Text($0.label).tag($0) }
                }
                Toggle("Clés étrangères en ALTER TABLE à la fin", isOn: $foreignKeysAtEnd)
                Toggle("Nommer les colonnes avec les libellés", isOn: $useLabels)
            } header: {
                Text("Génération SQL")
            }
            Section {
                Toggle("Afficher les types de données", isOn: $showTypes)
                Toggle("Afficher la grille", isOn: $showGrid)
            } header: {
                Text("Affichage")
            } footer: {
                Text("Ces choix s'appliquent aux nouveaux modèles ; chaque modèle garde ensuite ses propres réglages.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
