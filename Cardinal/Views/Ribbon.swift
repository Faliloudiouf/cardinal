import SwiftUI

/// Ruban de Cardinal : chaque option montre ce qu'elle produit (miniature dessinée), avec un libellé
/// et un groupe légendé. Le groupe Formalisme est toujours visible ; les outils de dessin, en MCD.
struct Ribbon: View {
    @Binding var model: MCDModel
    @ObservedObject var state: WindowState
    @AppStorage("affichageMLD") private var mldDisplay: MLDDisplay = .textuel
    @AppStorage("umlSimplifie") private var umlSimplified = false
    @AppStorage(Defaults.dialect) private var dialect: SQLDialect = .mysql
    @State private var didCopy = false
    @Environment(\.newDocument) private var newDocument
    @Environment(\.openDocument) private var openDocument
    @Environment(\.openWindow) private var openWindow

    private var files: DocumentActions { DocumentActions(newDocument: newDocument, openDocument: openDocument) }

    var body: some View {
        // Le ruban tient dans la fenêtre, comme dans les logiciels de bureautique : étalé s'il y a
        // la place (inspecteur fermé, grande fenêtre), puis resserré, puis avec des groupes repliés
        // en boutons-menus. Chaque bouton garde toujours son nom ; le défilement est un dernier recours.
        ViewThatFits(in: .horizontal) {
            groups.environment(\.ribbonDensity, .large)
            groups.environment(\.ribbonDensity, .medium)
            groups.environment(\.ribbonDensity, .small)
            groups.environment(\.ribbonDensity, .tiny)
            ScrollView(.horizontal, showsIndicators: false) {
                groups.environment(\.ribbonDensity, .tiny)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.bar)
        .overlay(alignment: .bottom) { Divider() }
    }

    private var groups: some View {
            HStack(alignment: .top, spacing: 0) {
                // Toujours visible, dans toutes les vues : créer, ouvrir, enregistrer.
                RibbonGroup("Fichier") {
                  DensitySwitch {
                    RibbonSplitButton(title: "Nouveau", help: "Nouveau modèle vide (⌘N) ; la flèche propose les exemples et les imports") {
                        Image(systemName: "doc.fill.badge.plus")
                    } action: {
                        files.createEmpty()
                    } menu: {
                        Button("Modèle vide") { files.createEmpty() }
                        Divider()
                        Section("Exemples") {
                            Button("Gestion de commandes") { files.create(.exemple) }
                            Button("Scolarité (héritage, CIF, règle)") { files.create(.exempleScolarite) }
                        }
                        Divider()
                        Button("Importer depuis Looping…") { Task { await files.chooseAndOpen(types: [.loopingModel]) } }
                        Button("Rétroconception d'un script SQL…") { files.reverseEngineerSQL() }
                    }
                    RibbonSplitButton(title: "Ouvrir", help: "Ouvrir un modèle .mcd ou .loo (⌘O) ; la flèche montre les fichiers récents") {
                        Image(systemName: "folder.fill")
                    } action: {
                        Task { await files.chooseAndOpen() }
                    } menu: {
                        Button("Ouvrir…") { Task { await files.chooseAndOpen() } }
                        Divider()
                        Section("Récents") {
                            let recents = RecentFiles.urls
                            if recents.isEmpty {
                                Text("Aucun fichier récent")
                            } else {
                                ForEach(recents.prefix(10), id: \.self) { url in
                                    Button(url.deletingPathExtension().lastPathComponent) { Task { await files.open(url) } }
                                }
                                Button("Effacer la liste") { RecentFiles.clear() }
                            }
                        }
                        Divider()
                        Button("Fenêtre d'accueil") { openWindow(id: WelcomeWindow.id) }
                    }
                    RibbonButton(title: "Enregistrer", help: "Enregistrer le modèle (⌘S)") {
                        Image(systemName: "square.and.arrow.down.fill")
                    } action: {
                        DocumentActions.save()
                    }
                  } tiny: {
                    // Ruban très étroit : les commandes de fichier dans un seul bouton, comme le menu Fichier.
                    RibbonMenuButton(title: "Fichier", systemImage: "doc.fill", help: "Nouveau, ouvrir, enregistrer") {
                        Button("Nouveau modèle") { files.createEmpty() }
                        Menu("Exemples") {
                            Button("Gestion de commandes") { files.create(.exemple) }
                            Button("Scolarité (héritage, CIF, règle)") { files.create(.exempleScolarite) }
                        }
                        Divider()
                        Button("Ouvrir…") { Task { await files.chooseAndOpen() } }
                        Menu("Ouvrir un fichier récent") {
                            ForEach(RecentFiles.urls.prefix(10), id: \.self) { url in
                                Button(url.deletingPathExtension().lastPathComponent) { Task { await files.open(url) } }
                            }
                        }
                        .disabled(RecentFiles.urls.isEmpty)
                        Divider()
                        Button("Enregistrer") { DocumentActions.save() }
                        Divider()
                        Button("Importer depuis Looping…") { Task { await files.chooseAndOpen(types: [.loopingModel]) } }
                        Button("Rétroconception d'un script SQL…") { files.reverseEngineerSQL() }
                    }
                  }
                }
                RibbonDivider()
                RibbonGroup("Formalisme") {
                    FormalismOptions(state: state) {
                        formalismButton(.mcd, title: "E/A", glyph: .formalismMCD, help: "Modèle Entité/Association (⌘1)")
                        formalismButton(.mld, title: "MLD", glyph: .formalismMLD, help: "Modèle logique de données (⌘2)")
                        formalismButton(.uml, title: "UML", glyph: .formalismUML, help: "Diagramme de classes UML (⌘3)")
                        formalismButton(.sql, title: "SQL", glyph: .formalismSQL, help: "Script SQL de création des tables (⌘4)")
                    }
                }
                switch state.mode {
                case .mld: mldGroups
                case .uml: umlGroups
                case .sql: sqlGroups
                case .mcd: EmptyView()
                }
                if state.mode == .mcd {
                    RibbonDivider()
                    RibbonGroup("Pointeur") {
                        toolButton(.select)
                    }
                    RibbonDivider()
                    RibbonGroup("MCD") {
                        toolButton(.entity)
                        toolButton(.association)
                        toolButton(.inheritance)
                        toolButton(.constraint)
                        toolButton(.cif)
                        toolButton(.rule)
                        toolButton(.link)
                    }
                    RibbonDivider()
                    RibbonGroup("Illustration") {
                        DensitySwitch { toolButton(.note) } tiny: { EmptyView() }
                        ShapeOptions(state: state) {
                            // Formes en grille compacte, comme les alignements du groupe Organiser.
                            Grid(horizontalSpacing: 2, verticalSpacing: 2) {
                                GridRow { shapeButton(.rectangle); shapeButton(.ellipse); shapeButton(.image) }
                                GridRow { shapeButton(.line); shapeButton(.arrow) }
                            }
                            .padding(.trailing, 4)
                        }
                    }
                    RibbonDivider()
                    RibbonGroup("Affichage") {
                        DisplayOptions(settings: $model.settings)
                    }
                    RibbonDivider()
                    RibbonGroup("Zoom") {
                        ZoomControl(state: state, canFit: true)
                    }
                    RibbonDivider()
                    RibbonGroup("Organiser") {
                        ArrangeOptions(compact: false) {
                        Grid(horizontalSpacing: 2, verticalSpacing: 2) {
                            GridRow {
                                ForEach(Array(Arranger.Alignment.allCases.prefix(3))) { alignButton($0) }
                            }
                            GridRow {
                                ForEach(Array(Arranger.Alignment.allCases.suffix(3))) { alignButton($0) }
                            }
                        }
                        .disabled(state.selection.count < 2)
                        .padding(.trailing, 4)
                        RibbonButton(title: "Premier plan", help: "Mettre au premier plan (⇧⌘])") {
                            Image(systemName: "square.3.layers.3d.top.filled")
                        } action: {
                            Arranger.reorder(state.selection, front: true, in: &model)
                        }
                        .disabled(state.selection.isEmpty)
                        RibbonButton(title: "Arrière-plan", help: "Mettre à l'arrière-plan (⇧⌘[)") {
                            Image(systemName: "square.3.layers.3d.bottom.filled")
                        } action: {
                            Arranger.reorder(state.selection, front: false, in: &model)
                        }
                        .disabled(state.selection.isEmpty)
                        RibbonButton(title: "Dupliquer", help: "Dupliquer la sélection (⌘D)") {
                            Image(systemName: "plus.square.on.square.fill")
                        } action: {
                            state.selection = model.paste(model.subset(state.selection))
                        }
                        .disabled(state.selection.isEmpty)
                        } menu: {
                            Section("Aligner") {
                                ForEach(Arranger.Alignment.allCases) { alignment in
                                    Button(alignment.label) { Arranger.align(state.selection, alignment, in: &model) }
                                }
                            }
                            .disabled(state.selection.count < 2)
                            Divider()
                            Button("Mettre au premier plan") { Arranger.reorder(state.selection, front: true, in: &model) }
                            Button("Mettre à l'arrière-plan") { Arranger.reorder(state.selection, front: false, in: &model) }
                            Button("Dupliquer") { state.selection = model.paste(model.subset(state.selection)) }
                        }
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.top, 8)
            .padding(.bottom, 4)
            .fixedSize(horizontal: true, vertical: false)
    }

    // MARK: Groupes propres à chaque formalisme

    @ViewBuilder
    private var mldGroups: some View {
        RibbonDivider()
        RibbonGroup("Présentation du MLD") {
            ForEach(MLDDisplay.allCases) { option in
                RibbonButton(title: option.shortTitle, help: option.help, isSelected: mldDisplay == option) {
                    GlyphView(glyph: option.glyph)
                } action: {
                    mldDisplay = option
                }
            }
        }
        RibbonDivider()
        RibbonGroup("Génération") {
            GenerationOptions(model: $model)
        }
        RibbonDivider()
        RibbonGroup("Zoom") { ZoomControl(state: state, canFit: false) }
        RibbonDivider()
        RibbonGroup("Exporter") {
            RibbonButton(title: "XML", help: "Exporter le MLD au format XML") {
                Image(systemName: "chevron.left.forwardslash.chevron.right")
            } action: {
                Exporter.saveMLDXML(model, name: "modele")
            }
        }
    }

    @ViewBuilder
    private var umlGroups: some View {
        RibbonDivider()
        RibbonGroup("Présentation UML") {
            RibbonButton(title: "Standard", help: "Classes avec leurs attributs", isSelected: !umlSimplified) {
                GlyphView(glyph: .formalismUML)
            } action: {
                umlSimplified = false
            }
            RibbonButton(title: "Simplifié", help: "Classes réduites à leur nom", isSelected: umlSimplified) {
                GlyphView(glyph: .umlSimple)
            } action: {
                umlSimplified = true
            }
        }
        RibbonDivider()
        RibbonGroup("Zoom") { ZoomControl(state: state, canFit: false) }
    }

    @ViewBuilder
    private var sqlGroups: some View {
        RibbonDivider()
        RibbonGroup("SGBD cible") {
            VStack(spacing: 4) {
                GlyphView(glyph: .formalismSQL)
                SQLTargetPicker(title: "SGBD")
                .labelsHidden()
                .pickerStyle(.menu)
                .controlSize(.small)
                .fixedSize()
            }
            .padding(.horizontal, 4)
            .help("Choisir le SGBD : MySQL, MariaDB, PostgreSQL, SQLite, SQL Server, Oracle")
        }
        RibbonDivider()
        RibbonGroup("Génération") {
            GenerationOptions(model: $model)
        }
        RibbonDivider()
        RibbonGroup("Script") {
            RibbonButton(title: didCopy ? "Copié" : "Copier", help: "Copier le script (⇧⌘C)") {
                Image(systemName: didCopy ? "checkmark.circle.fill" : "doc.on.doc.fill")
                    .contentTransition(.symbolEffect(.replace))
            } action: {
                SQLView.copy(model, dialect: dialect)
                didCopy = true
                Task {
                    try? await Task.sleep(for: .seconds(1.6))
                    didCopy = false
                }
            }
            .keyboardShortcut("c", modifiers: [.command, .shift])
            RibbonButton(title: "Exporter", help: "Enregistrer le script .sql") {
                Image(systemName: "square.and.arrow.up.fill")
            } action: {
                Exporter.saveSQL(model, dialect: dialect, name: "modele")
            }
        }
        RibbonDivider()
        RibbonGroup("Zoom") { ZoomControl(state: state, canFit: false) }
    }

    private func formalismButton(_ mode: ViewMode, title: String, glyph: Glyph, help: String) -> some View {
        RibbonButton(title: title, help: help, isSelected: state.mode == mode) {
            GlyphView(glyph: glyph)
        } action: {
            state.mode = mode
        }
    }

    private func toolButton(_ tool: Tool) -> some View {
        RibbonButton(title: tool.shortLabel, help: tool.help, isSelected: state.tool == tool) {
            if let glyph = tool.glyph {
                GlyphView(glyph: glyph)
            } else {
                Image(systemName: tool.symbol)
            }
        } action: {
            state.tool = tool
        }
    }

    private func shapeButton(_ tool: Tool) -> some View {
        Button {
            state.tool = tool
        } label: {
            Image(systemName: tool.symbol)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 26, height: 22)
                .foregroundStyle(state.tool == tool ? Color.accentColor : Color.primary)
                .background(state.tool == tool ? Color.accentColor.opacity(0.14) : .clear, in: RoundedRectangle(cornerRadius: 5))
        }
        .buttonStyle(RibbonButtonStyle())
        .help(tool.help)
        .accessibilityLabel(tool.label)
    }

    private func alignButton(_ alignment: Arranger.Alignment) -> some View {
        Button {
            Arranger.align(state.selection, alignment, in: &model)
        } label: {
            Image(systemName: alignment.symbol)
                .font(.system(size: 12, weight: .medium))
                .frame(width: 24, height: 22)
        }
        .buttonStyle(RibbonButtonStyle())
        .help(alignment.label)
        .accessibilityLabel(alignment.label)
    }
}

extension Tool {
    var shortLabel: String {
        switch self {
        case .rule: "Règle"
        default: label
        }
    }

    var help: String {
        switch self {
        case .select: "Sélectionner et déplacer (Échap)"
        case .entity: "Ajouter une entité"
        case .association: "Ajouter une association"
        case .link: "Relier deux éléments : patte, héritage, contrainte, règle"
        case .inheritance: "Ajouter un héritage (spécialisation / généralisation)"
        case .constraint: "Ajouter une contrainte inter-associations : exclusion, totalité, inclusion…"
        case .cif: "Ajouter une contrainte d'intégrité fonctionnelle (CIF)"
        case .rule: "Ajouter une règle de gestion avec code SQL"
        case .note: "Ajouter un titre ou un texte"
        case .rectangle: "Dessiner un rectangle (cadre, regroupement)"
        case .ellipse: "Dessiner une ellipse"
        case .line: "Tracer un trait"
        case .arrow: "Tracer une flèche"
        case .image: "Insérer une image (logo, capture)"
        }
    }
}

/// Zoom : curseur, paliers 50 / 100 / 150 % et bouton Ajuster.
/// Organiser : grille d'alignements et boutons, ou en mode compact un bouton qui ouvre un menu.
private struct ArrangeOptions<Full: View, Items: View>: View {
    var compact: Bool
    @ViewBuilder let full: Full
    @ViewBuilder let menu: Items
    @Environment(\.ribbonCompact) private var ribbonCompact

    var body: some View {
        if ribbonCompact {
            RibbonMenuButton(title: "Organiser", systemImage: "square.3.layers.3d.top.filled",
                             help: "Aligner, premier plan, arrière-plan, dupliquer") { menu }
        } else {
            full
        }
    }
}

/// Options d'affichage : quatre cases, ou en mode compact un bouton qui les regroupe dans un menu.
private struct DisplayOptions: View {
    @Binding var settings: ModelSettings
    @Environment(\.ribbonCompact) private var compact

    var body: some View {
        if compact {
            RibbonMenuButton(title: "Afficher", systemImage: "eye.fill", help: "Propriétés, types, grille, dépendances") {
                Toggle("Propriétés", isOn: $settings.showAttributes)
                Toggle("Types de données", isOn: $settings.showTypes).disabled(!settings.showAttributes)
                Toggle("Grille", isOn: $settings.showGrid)
                Toggle("Dépendances fonctionnelles", isOn: $settings.showDependencies)
            }
        } else {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Toggle("Propriétés", isOn: $settings.showAttributes)
                    Toggle("Types", isOn: $settings.showTypes)
                        .disabled(!settings.showAttributes)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Toggle("Grille", isOn: $settings.showGrid)
                    Toggle("Dépendances", isOn: $settings.showDependencies)
                        .help("Flèche de dépendance fonctionnelle sur les pattes 0,1 et 1,1")
                }
            }
            .toggleStyle(.checkbox)
            .font(.system(size: 11.5))
            .padding(.horizontal, 6)
        }
    }
}

private struct ZoomControl: View {
    @ObservedObject var state: WindowState
    var canFit = true
    @Environment(\.ribbonCompact) private var compact

    @Environment(\.ribbonDensity) private var density

    var body: some View {
        switch density {
        case .large: fullBody
        case .medium: compactBody
        case .small, .tiny: menuBody
        }
    }

    /// Replié : un bouton au pourcentage actuel, qui ouvre les commandes de zoom.
    private var menuBody: some View {
        RibbonMenuButton(title: "\(Int((state.zoom * 100).rounded())) %", systemImage: "magnifyingglass", help: "Zoom") {
            Button("Zoom avant") { state.zoomIn() }
            Button("Zoom arrière") { state.zoomOut() }
            Divider()
            ForEach([0.5, 0.75, 1.0, 1.25, 1.5, 2.0], id: \.self) { value in
                Button("\(Int(value * 100)) %") { state.zoom = value }
            }
            if canFit {
                Divider()
                Button("Ajuster à la fenêtre") { state.fit() }
            }
        }
    }

    /// Compact : − , pourcentage (menu des paliers), +.
    private var compactBody: some View {
        HStack(spacing: 2) {
            Button { state.zoomOut() } label: { Image(systemName: "minus.magnifyingglass").frame(width: 24, height: 22) }
                .buttonStyle(RibbonButtonStyle()).help("Zoom arrière (⌘−)")
            Menu {
                ForEach([0.5, 0.75, 1.0, 1.25, 1.5, 2.0], id: \.self) { value in
                    Button("\(Int(value * 100)) %") { state.zoom = value }
                }
                if canFit {
                    Divider()
                    Button("Ajuster à la fenêtre") { state.fit() }
                }
            } label: {
                Text("\(Int((state.zoom * 100).rounded())) %").font(.system(size: 11).monospacedDigit())
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            Button { state.zoomIn() } label: { Image(systemName: "plus.magnifyingglass").frame(width: 24, height: 22) }
                .buttonStyle(RibbonButtonStyle()).help("Zoom avant (⌘+)")
        }
        .padding(.top, 12)
    }

    private var fullBody: some View {
        HStack(alignment: .top, spacing: 6) {
            if canFit {
                RibbonButton(title: "Ajuster", help: "Ajuster à la fenêtre (⌘9)") {
                    Image(systemName: "arrow.up.left.and.down.right.and.arrow.up.right.and.down.left")
                } action: {
                    state.fit()
                }
            }
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Image(systemName: "minus.magnifyingglass").foregroundStyle(.secondary)
                    Slider(value: $state.zoom, in: 0.3...2.5)
                        .controlSize(.mini)
                        .frame(width: 92)
                    Image(systemName: "plus.magnifyingglass").foregroundStyle(.secondary)
                }
                .font(.system(size: 10))
                HStack(spacing: 10) {
                    ForEach([0.5, 1.0, 1.5], id: \.self) { value in
                        let isCurrent = abs(state.zoom - value) < 0.01
                        Button("\(Int(value * 100)) %") { state.zoom = value }
                            .buttonStyle(.borderless)
                            .font(.system(size: 10.5, weight: isCurrent ? .bold : .regular).monospacedDigit())
                            .foregroundStyle(isCurrent ? Color.accentColor : Color.primary)
                            .fixedSize()
                    }
                }
                Text("Zoom actuel : \(Int((state.zoom * 100).rounded())) %")
                    .font(.system(size: 10).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .fixedSize()
            }
            .frame(width: 136, alignment: .leading)
            .padding(.top, 4)
        }
    }
}

/// Groupe du ruban : ses boutons, puis sa légende centrée en dessous.
private struct RibbonGroup<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content
    @Environment(\.ribbonDensity) private var density

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 4) {
            HStack(alignment: .top, spacing: 2) { content }
                .frame(height: 54, alignment: .top)
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .tracking(0.3)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, density == .large ? 4 : 1)
        .fixedSize()
    }
}

private struct RibbonDivider: View {
    @Environment(\.ribbonDensity) private var density

    var body: some View {
        Rectangle()
            .fill(Color(nsColor: .separatorColor))
            .frame(width: 1, height: 62)
            .padding(.horizontal, density == .large ? 6 : 3)
            .padding(.top, 2)
    }
}

/// Densité du ruban : étalé, resserré (boutons plus étroits, petits groupes en menus),
/// replié (les formes d'illustration aussi). Les boutons gardent toujours leur nom.
enum RibbonDensity: Sendable { case large, medium, small, tiny }

private struct RibbonDensityKey: EnvironmentKey {
    static let defaultValue = RibbonDensity.large
}

extension EnvironmentValues {
    var ribbonDensity: RibbonDensity {
        get { self[RibbonDensityKey.self] }
        set { self[RibbonDensityKey.self] = newValue }
    }

    /// Resserré ou replié.
    var ribbonCompact: Bool { ribbonDensity != .large }
}

/// Groupe replié en un seul bouton : symbole, nom et flèche, qui ouvre un menu.
struct RibbonMenuButton<Icon: View, Items: View>: View {
    let title: String
    let help: String
    @ViewBuilder let icon: Icon
    @ViewBuilder let items: Items

    var body: some View {
        Menu {
            items
        } label: {
            VStack(spacing: 4) {
                icon
                    .font(.system(size: 17, weight: .medium))
                    .frame(width: 30, height: 24)
                Text(title + " ▾")
                    .font(.system(size: 10.5))
                    .lineLimit(1)
                    .fixedSize()
            }
            .padding(.horizontal, 5)
            .padding(.vertical, 4)
            .frame(minWidth: 48)
            .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .menuStyle(.button)
        .buttonStyle(RibbonButtonStyle())
        .menuIndicator(.hidden)
        .fixedSize()
        .foregroundStyle(Color.primary)
        .help(help)
        .accessibilityLabel(title)
    }
}

/// Contenu normal, ou contenu replié quand le ruban est très étroit.
private struct DensitySwitch<Full: View, Tiny: View>: View {
    @ViewBuilder let full: Full
    @ViewBuilder let tiny: Tiny
    @Environment(\.ribbonDensity) private var density

    var body: some View {
        if density == .tiny { tiny } else { full }
    }
}

extension RibbonMenuButton where Icon == Image {
    init(title: String, systemImage: String, help: String, @ViewBuilder items: () -> Items) {
        self.init(title: title, help: help, icon: { Image(systemName: systemImage) }, items: items)
    }
}

/// Formalisme : quatre boutons, ou un seul bouton-menu au nom du formalisme affiché (ruban très étroit).
private struct FormalismOptions<Full: View>: View {
    @ObservedObject var state: WindowState
    @ViewBuilder let full: Full
    @Environment(\.ribbonDensity) private var density

    private var choices: [(ViewMode, String, Glyph)] { [
        (.mcd, "E/A", .formalismMCD), (.mld, "MLD", .formalismMLD), (.uml, "UML", .formalismUML), (.sql, "SQL", .formalismSQL),
    ] }

    var body: some View {
        if density == .tiny {
            let current = choices.first { $0.0 == state.mode } ?? choices[0]
            RibbonMenuButton(title: current.1, help: "Changer de formalisme (⌘1 à ⌘4)") {
                GlyphView(glyph: current.2)
            } items: {
                ForEach(choices, id: \.0) { choice in
                    Toggle(choice.1 == "E/A" ? "Entité/Association (E/A)" : choice.1,
                           isOn: Binding { state.mode == choice.0 } set: { if $0 { state.mode = choice.0 } })
                }
            }
        } else {
            full
        }
    }
}

/// Formes d'illustration : grille de petits boutons, ou un bouton « Formes » quand le ruban est replié.
private struct ShapeOptions<Full: View>: View {
    @ObservedObject var state: WindowState
    @ViewBuilder let full: Full
    @Environment(\.ribbonDensity) private var density

    var body: some View {
        if density == .small || density == .tiny {
            // Très étroit : le texte rejoint les formes dans un bouton « Insérer ».
            let tools: [Tool] = density == .tiny ? [.note, .rectangle, .ellipse, .image, .line, .arrow] : [.rectangle, .ellipse, .image, .line, .arrow]
            RibbonMenuButton(title: density == .tiny ? "Insérer" : "Formes", systemImage: "square.on.circle.fill",
                             help: density == .tiny ? "Texte, rectangle, ellipse, image, trait, flèche" : "Rectangle, ellipse, image, trait, flèche") {
                ForEach(tools, id: \.self) { tool in
                    Button { state.tool = tool } label: { Label(tool.label, systemImage: tool.symbol) }
                }
            }
        } else {
            full
        }
    }
}

/// Bouton double, comme dans les logiciels de bureautique : l'icône lance l'action principale,
/// le libellé suivi d'une flèche ouvre le menu des autres choix.
struct RibbonSplitButton<Icon: View, Items: View>: View {
    let title: String
    let help: String
    @ViewBuilder let icon: Icon
    let action: () -> Void
    @ViewBuilder let menu: Items

    var body: some View {
        VStack(spacing: 2) {
            Button(action: action) {
                icon
                    .font(.system(size: 17, weight: .medium))
                    .frame(width: 30, height: 24)
                    .padding(.horizontal, 7)
                    .padding(.top, 4)
                    .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            }
            .buttonStyle(RibbonButtonStyle())
            .help(help)
            .accessibilityLabel(title)
            Menu {
                menu
            } label: {
                Text(title + " ▾")
                    .font(.system(size: 11))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Plus de choix : \(title.lowercased())")
        }
        .foregroundStyle(Color.primary)
        .frame(minWidth: 56)
    }
}

struct RibbonButton<Icon: View>: View {
    let title: String
    let help: String
    var isSelected = false
    @ViewBuilder let icon: Icon
    let action: () -> Void
    @Environment(\.ribbonCompact) private var compact
    @Environment(\.ribbonDensity) private var density

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                icon
                    .font(.system(size: 17, weight: .medium))
                    .frame(width: 30, height: 24)
                // Le nom reste toujours visible : seul l'espace autour se resserre.
                Text(title)
                    .font(.system(size: compact ? 10.5 : 11, weight: isSelected ? .semibold : .regular))
                    .lineLimit(1)
                    .fixedSize()
            }
            .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
            .padding(.horizontal, density == .tiny ? 1 : (compact ? 2 : 7))
            .padding(.vertical, 4)
            .frame(minWidth: density == .tiny ? 34 : (compact ? 40 : 56))
            .background {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.16) : Color.clear)
            }
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(Color.accentColor.opacity(0.45), lineWidth: 1)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(RibbonButtonStyle())
        .help(help)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Retour visuel immédiat à l'appui (léger enfoncement), survol discret.
struct RibbonButtonStyle: ButtonStyle {
    @State private var isHovered = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.primary.opacity(configuration.isPressed ? 0.12 : (isHovered ? 0.06 : 0)))
            }
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
            .opacity(isEnabled ? 1 : 0.4)
            .onHover { isHovered = $0 }
    }
}

/// Options de génération SQL, partagées par les rubans MLD et SQL.
private struct GenerationOptions: View {
    @Binding var model: MCDModel

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Picker("Nommage", selection: $model.settings.naming) {
                ForEach(NamingConvention.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.menu)
            .controlSize(.small)
            .fixedSize()
            Toggle("Libellés", isOn: $model.settings.useLabels)
                .help("Nommer les colonnes avec les libellés des propriétés (comme Looping)")
            Toggle("Clés en ALTER TABLE", isOn: $model.settings.foreignKeysAtEnd)
                .help("Créer les clés étrangères à la fin du script")
        }
        .toggleStyle(.checkbox)
        .font(.system(size: 11.5))
        .padding(.horizontal, 6)
    }
}

extension MLDDisplay {
    var shortTitle: String {
        switch self {
        case .textuel: "Textuel"
        case .standard: "Diagramme"
        case .crowsFoot: "Corbeau"
        }
    }

    var help: String {
        switch self {
        case .textuel: "Notation textuelle : Table(clé, …, #clé étrangère)"
        case .standard: "Diagramme des tables avec flèches de clés étrangères"
        case .crowsFoot: "Diagramme en pattes de corbeau (crow's foot)"
        }
    }

    var glyph: Glyph {
        switch self {
        case .textuel: .mldText
        case .standard: .formalismMLD
        case .crowsFoot: .crowsFoot
        }
    }
}
