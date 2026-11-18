import SwiftUI

struct ContentView: View {
    @Binding var document: CardinalDocument
    var fileName = "modele"
    @State private var importedName: String?

    @StateObject private var state: WindowState
    @AppStorage(Defaults.dialect) private var dialect: SQLDialect = .mysql

    init(document: Binding<CardinalDocument>, fileName: String = "modele", initialMode: ViewMode = .mcd, initialSelection: Set<NodeRef> = [],
         initialView: ModelView.ID? = nil) {
        _document = document
        self.fileName = fileName
        let state = WindowState(mode: initialMode, selection: initialSelection)
        state.activeView = initialView
        _state = StateObject(wrappedValue: state)
    }

    var body: some View {
        let diagnostics = Validator.check(document.model)

        VStack(spacing: 0) {
            Ribbon(model: $document.model, state: state)
            Group {
                switch state.mode {
                case .mcd:
                    VStack(spacing: 0) {
                        ViewTabs(model: $document.model, state: state)
                        DiagramView(model: $document.model, selection: $state.selection, tool: $state.tool, zoom: $state.zoom,
                                    fitRequest: state.fitRequest, activeView: state.activeView)
                    }
                case .mld:
                    MLDView(model: document.model, tables: MLDBuilder.build(document.model), zoom: $state.zoom)
                case .uml:
                    UMLView(model: document.model, zoom: $state.zoom)
                case .sql:
                    SQLView(model: document.model, dialect: dialect, zoom: $state.zoom)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 980, minHeight: 560)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            StatusBar(model: document.model, diagnostics: diagnostics, state: state)
        }
        .toolbar { toolbarContent }
        .inspector(isPresented: $state.showInspector) {
            InspectorView(model: $document.model, selection: $state.selection, diagnostics: diagnostics)
                .inspectorColumnWidth(min: 280, ideal: 320, max: 460)
        }
        .onChange(of: state.mode) { _, newMode in
            if newMode != .mcd { state.tool = .select }
        }
        .background(WindowAccessor { window in
            let document = window.windowController?.document as? NSDocument
            LooImport.detachIfNeeded(document)
            // Modèle importé d'un .loo, pas encore enregistré : les exports reprennent son nom.
            if let document, let name = LooImport.names[ObjectIdentifier(document)], document.fileURL == nil, importedName != name {
                importedName = name
            }
        })
        .focusedSceneObject(state)
        .focusedSceneValue(\.cardinalDocument, $document)
        .focusedSceneValue(\.cardinalModel, document.model)
        .focusedSceneValue(\.cardinalFileName, exportName)
    }

    /// Nom proposé pour les exports : celui du fichier, ou du .loo d'origine.
    private var exportName: String { importedName ?? fileName }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Menu {
                ExportMenuItems(model: document.model, fileName: exportName, dialect: dialect)
            } label: {
                Label("Exporter", systemImage: "square.and.arrow.up")
            }
            .help("Exporter le modèle : image, PDF, XML, SQL, impression")

            Button {
                state.showInspector.toggle()
            } label: {
                Label("Inspecteur", systemImage: "sidebar.trailing")
            }
            .help("Afficher ou masquer l'inspecteur (⌥⌘I)")
        }
    }
}

/// Éléments du menu Exporter, partagés entre la barre d'outils et la barre de menus.
struct ExportMenuItems: View {
    let model: MCDModel
    let fileName: String
    let dialect: SQLDialect

    var body: some View {
        Button("Image PNG…", systemImage: "photo") { Exporter.savePNG(model, name: fileName) }
        Button("Document PDF…", systemImage: "doc.richtext") { Exporter.savePDF(model, name: fileName) }
        Button("Copier le diagramme", systemImage: "doc.on.clipboard") { Exporter.copyDiagram(model) }
        Divider()
        Button("MLD au format XML…", systemImage: "chevron.left.forwardslash.chevron.right") {
            Exporter.saveMLDXML(model, name: fileName)
        }
        Button("Script SQL (\(SQLTarget.name(dialect)))…", systemImage: "cylinder.split.1x2") {
            Exporter.saveSQL(model, dialect: dialect, name: fileName)
        }
        Divider()
        Button("Imprimer le diagramme…", systemImage: "printer") { Exporter.print(model) }
    }
}

// MARK: - Valeurs partagées avec les menus de l'appli

struct CardinalModelKey: FocusedValueKey { typealias Value = MCDModel }
struct CardinalFileNameKey: FocusedValueKey { typealias Value = String }

extension FocusedValues {
    var cardinalModel: MCDModel? {
        get { self[CardinalModelKey.self] }
        set { self[CardinalModelKey.self] = newValue }
    }

    var cardinalFileName: String? {
        get { self[CardinalFileNameKey.self] }
        set { self[CardinalFileNameKey.self] = newValue }
    }
}

// MARK: - Barre d'état

private struct StatusBar: View {
    let model: MCDModel
    let diagnostics: [Diagnostic]
    @ObservedObject var state: WindowState

    @State private var showsDiagnostics = false

    var body: some View {
        HStack(spacing: 14) {
            Text("\(model.entities.count) entité\(model.entities.count > 1 ? "s" : "") · \(model.associations.count) association\(model.associations.count > 1 ? "s" : "")")
                .foregroundStyle(.secondary)

            Button {
                showsDiagnostics.toggle()
            } label: {
                if diagnostics.isEmpty {
                    Label("Modèle valide", systemImage: "checkmark.seal.fill").foregroundStyle(.green)
                } else {
                    let errors = diagnostics.filter { $0.severity == .error }.count
                    Label(
                        "\(diagnostics.count) point\(diagnostics.count > 1 ? "s" : "") à corriger",
                        systemImage: errors > 0 ? "xmark.octagon.fill" : "exclamationmark.triangle.fill"
                    )
                    .foregroundStyle(errors > 0 ? .red : .orange)
                }
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showsDiagnostics, arrowEdge: .top) {
                DiagnosticsList(diagnostics: diagnostics) { ref in
                    showsDiagnostics = false
                    state.mode = .mcd
                    state.showInspector = true
                    state.selection = [ref]
                }
            }

            Spacer()

            if state.mode == .mcd {
                Text(state.tool == .select ? "Sélection" : "Outil : \(state.tool.label)")
                    .foregroundStyle(.secondary)
                if !state.selection.isEmpty {
                    Text("\(state.selection.count) sélectionné\(state.selection.count > 1 ? "s" : "")")
                        .foregroundStyle(.secondary)
                }
            }
            Divider().frame(height: 14)
            AppearanceQuickMenu()
        }
        .font(.system(size: 11.5))
        .padding(.horizontal, 14)
        .frame(height: 28)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }
}

private struct DiagnosticsList: View {
    let diagnostics: [Diagnostic]
    let onSelect: (NodeRef) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if diagnostics.isEmpty {
                Label("Aucun problème détecté", systemImage: "checkmark.seal.fill").foregroundStyle(.green)
            }
            ForEach(diagnostics) { diagnostic in
                Button {
                    if let target = diagnostic.target { onSelect(target) }
                } label: {
                    Label {
                        Text(diagnostic.message).multilineTextAlignment(.leading)
                    } icon: {
                        Image(systemName: diagnostic.severity == .error ? "xmark.octagon.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(diagnostic.severity == .error ? .red : .orange)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .font(.callout)
        .padding(16)
        .frame(width: 360, alignment: .leading)
    }
}
