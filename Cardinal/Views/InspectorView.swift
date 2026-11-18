import SwiftUI

/// Panneau de droite : édite l'élément sélectionné, ou résume le modèle et ses réglages.
struct InspectorView: View {
    @Binding var model: MCDModel
    @Binding var selection: Set<NodeRef>
    let diagnostics: [Diagnostic]

    var body: some View {
        if selection.count > 1 {
            MultiSelectionInspector(model: $model, selection: $selection)
        } else if let ref = selection.first {
            single(ref)
        } else {
            OverviewInspector(model: $model, diagnostics: diagnostics, selection: $selection)
        }
    }

    @ViewBuilder
    private func single(_ ref: NodeRef) -> some View {
        let delete = {
            model.remove(ref)
            selection = []
        }
        switch ref {
        case .entity(let id):
            if let binding = bind(\.entities, id) {
                EntityInspector(entity: binding, onDelete: delete)
            }
        case .association(let id):
            if let binding = bind(\.associations, id) {
                AssociationInspector(association: binding, entities: model.entities, onDelete: delete,
                                     onToggleBend: { model.toggleBend(association: id, leg: $0) })
            }
        case .inheritance(let id):
            if let binding = bind(\.inheritances, id) {
                InheritanceInspector(inheritance: binding, entities: model.entities, onDelete: delete)
            }
        case .constraint(let id):
            if let binding = bind(\.constraints, id) {
                ConstraintInspector(constraint: binding, model: model, onDelete: delete)
            }
        case .rule(let id):
            if let binding = bind(\.rules, id) {
                RuleInspector(rule: binding, model: model, onDelete: delete)
            }
        case .note(let id):
            if let binding = bind(\.notes, id) {
                NoteInspector(note: binding, onDelete: delete)
            }
        case .figure(let id):
            if let binding = bind(\.figures, id) {
                FigureInspector(figure: binding, onDelete: delete)
            }
        }
    }

    /// Liaison par identifiant : elle reste valide même si l'élément est supprimé entre-temps.
    private func bind<T: Identifiable>(_ path: WritableKeyPath<MCDModel, [T]>, _ id: UUID) -> Binding<T>? where T.ID == UUID {
        guard let current = model[keyPath: path].first(where: { $0.id == id }) else { return nil }
        return Binding(
            get: { model[keyPath: path].first { $0.id == id } ?? current },
            set: { newValue in
                if let index = model[keyPath: path].firstIndex(where: { $0.id == id }) {
                    model[keyPath: path][index] = newValue
                }
            }
        )
    }
}

/// Nom d'un élément pour l'afficher dans une liste de liens.
func displayName(of ref: NodeRef, in model: MCDModel) -> String {
    switch ref {
    case .entity(let id): model.entity(id)?.name ?? "Entité supprimée"
    case .association(let id): model.association(id)?.name ?? "Association supprimée"
    case .inheritance: "Héritage"
    case .constraint(let id): "Contrainte " + (model.constraints.first { $0.id == id }?.kind.rawValue ?? "")
    case .rule(let id): model.rules.first { $0.id == id }?.name ?? "Règle"
    case .note: "Texte"
    case .figure(let id): model.figures.first { $0.id == id }?.kind.label ?? "Illustration"
    }
}

// MARK: - Illustration

private struct FigureInspector: View {
    @Binding var figure: Figure
    let onDelete: () -> Void

    var body: some View {
        Form {
            Section {
                ColorSwatches(color: $figure.color, fallback: Color.primary.opacity(0.55))
                if figure.kind == .rectangle || figure.kind == .ellipse {
                    Toggle("Remplir", isOn: $figure.isFilled)
                }
                if figure.kind.isStroke {
                    Picker("Forme", selection: $figure.kind) {
                        Text("Trait").tag(FigureKind.line)
                        Text("Flèche").tag(FigureKind.arrow)
                    }
                    .pickerStyle(.segmented)
                    Button("Inverser le sens", systemImage: "arrow.left.arrow.right") {
                        figure.setEnds(figure.end, figure.start)
                    }
                } else {
                    LabeledContent("Taille") {
                        HStack(spacing: 4) {
                            TextField("Largeur", value: Binding { Int(figure.size.width) } set: { figure.size.width = CGFloat(max(Int(Figure.minimumSize), $0)) },
                                      format: .number.grouping(.never))
                                .frame(width: 54)
                            Text("×").foregroundStyle(.secondary)
                            TextField("Hauteur", value: Binding { Int(figure.size.height) } set: { figure.size.height = CGFloat(max(Int(Figure.minimumSize), $0)) },
                                      format: .number.grouping(.never))
                                .frame(width: 54)
                        }
                        .textFieldStyle(.roundedBorder)
                        .multilineTextAlignment(.trailing)
                    }
                }
                if figure.kind == .image {
                    Button("Remplacer l'image…", systemImage: "photo.fill") {
                        if let image = FigureImage.choose() {
                            figure.imageData = image.data
                            figure.size = image.size
                        }
                    }
                }
            } header: {
                InspectorHeader(title: figure.kind.label, symbol: Tool(rawValue: figure.kind.rawValue)?.symbol ?? "photo.fill", tint: Color.primary.opacity(0.7))
            }
            Section {
                Button("Supprimer", systemImage: "trash.fill", role: .destructive, action: onDelete)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Entité

private struct EntityInspector: View {
    @Binding var entity: Entity
    let onDelete: () -> Void

    var body: some View {
        Form {
            Section {
                TextField("Nom", text: $entity.name)
                Toggle("Entité fictive (pas de table)", isOn: $entity.isFictive)
                    .help("Comme « Date » dans une association ternaire : dessinée, mais absente du MLD.")
                ColorSwatches(color: $entity.color, fallback: Theme.entityFill)
            } header: {
                InspectorHeader(title: "Entité", symbol: "rectangle.fill", tint: Theme.entity)
            }
            AttributesSection(attributes: $entity.attributes, allowsIdentifier: true, tint: Theme.entity)
            Section {
                Button("Supprimer l'entité", systemImage: "trash.fill", role: .destructive, action: onDelete)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Association

private struct AssociationInspector: View {
    @Binding var association: Association
    let entities: [Entity]
    let onDelete: () -> Void
    let onToggleBend: (Leg.ID) -> Void

    var body: some View {
        Form {
            Section {
                TextField("Nom", text: $association.name)
                ColorSwatches(color: $association.color, fallback: Theme.associationFill)
            } header: {
                InspectorHeader(title: "Association", symbol: "capsule.fill", tint: Theme.association)
            }
            Section("Pattes") {
                if association.legs.isEmpty {
                    Text("Choisissez l'outil Lien, puis cliquez sur cette association et sur une entité.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                ForEach($association.legs) { $leg in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(entities.first { $0.id == leg.entityID }?.name ?? "Entité supprimée")
                                .fontWeight(.medium)
                            Spacer()
                            RemoveButton(help: "Retirer cette patte") {
                                association.legs.removeAll { $0.id == leg.id }
                            }
                        }
                        Picker("Cardinalité", selection: $leg.cardinality) {
                            ForEach(Cardinality.allCases) { Text($0.rawValue).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        TextField("Rôle", text: $leg.role, prompt: Text("Rôle (facultatif)"))
                            .textFieldStyle(.roundedBorder)
                            .help("Nomme la patte ; utile pour les associations réflexives (ex. EtreCompose / EtreComposant)")
                        if leg.cardinality.isMaxOne && association.legs.count == 2 {
                            Toggle("Identifiant relatif (R)", isOn: $leg.isRelative)
                                .help("L'entité est identifiée en partie par l'autre entité (entité faible).")
                        }
                        Button(leg.bend == nil ? "Ajouter une cassure" : "Redresser la patte",
                               systemImage: leg.bend == nil ? "point.topleft.down.to.point.bottomright.curvepath.fill" : "line.diagonal") {
                            onToggleBend(leg.id)
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(Theme.association)
                        .help(leg.bend == nil ? "Fait passer la patte par un point que vous déplacez sur le canevas" : "Supprime le point de cassure")
                    }
                    .padding(.vertical, 2)
                }
            }
            AttributesSection(attributes: $association.attributes, allowsIdentifier: false, tint: Theme.association)
            Section {
                Button("Supprimer l'association", systemImage: "trash.fill", role: .destructive, action: onDelete)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Héritage

private struct InheritanceInspector: View {
    @Binding var inheritance: Inheritance
    let entities: [Entity]
    let onDelete: () -> Void

    var body: some View {
        Form {
            Section {
                Picker("Surtype", selection: $inheritance.parentID) {
                    Text("Aucun").tag(UUID?.none)
                    ForEach(entities) { Text($0.name).tag(UUID?.some($0.id)) }
                }
                Picker("Contrainte", selection: $inheritance.kind) {
                    ForEach(InheritanceKind.allCases) { Text($0.label).tag($0) }
                }
                Picker("Dans le MLD", selection: $inheritance.strategy) {
                    ForEach(InheritanceStrategy.allCases) { Text($0.label).tag($0) }
                }
            } header: {
                InspectorHeader(title: "Héritage", symbol: "triangle.fill", tint: Theme.entity)
            }
            Section("Sous-types") {
                if inheritance.childIDs.isEmpty {
                    Text("Avec l'outil Lien, cliquez sur l'héritage puis sur chaque sous-type. Le premier lien désigne le surtype.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                ForEach(inheritance.childIDs, id: \.self) { child in
                    HStack {
                        Text(entities.first { $0.id == child }?.name ?? "Entité supprimée")
                        Spacer()
                        RemoveButton(help: "Retirer ce sous-type") { inheritance.childIDs.removeAll { $0 == child } }
                    }
                }
            }
            Section {
                Button("Supprimer l'héritage", systemImage: "trash.fill", role: .destructive, action: onDelete)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Contrainte

private struct ConstraintInspector: View {
    @Binding var constraint: Constraint
    let model: MCDModel
    let onDelete: () -> Void

    var body: some View {
        Form {
            Section {
                Picker("Type", selection: $constraint.kind) {
                    ForEach(ConstraintKind.allCases) { Text($0.label).tag($0) }
                }
            } header: {
                InspectorHeader(title: "Contrainte", symbol: "c.circle.fill", tint: Theme.constraint)
            }
            Section("Éléments reliés") {
                if constraint.links.isEmpty {
                    Text("Avec l'outil Lien, cliquez sur la contrainte puis sur les associations et entités concernées.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                ForEach($constraint.links) { $link in
                    HStack {
                        Text(displayName(of: link.target, in: model))
                        Spacer()
                        if constraint.kind == .cif, case .entity = link.target {
                            Toggle("Cible", isOn: $link.isTarget)
                                .toggleStyle(.checkbox)
                                .help("Entité déterminée par la CIF : elle sort de la clé primaire de l'association.")
                        }
                        RemoveButton(help: "Retirer ce lien") { constraint.links.removeAll { $0.id == link.id } }
                    }
                }
            }
            SQLSection(sql: $constraint.sql)
            Section {
                Button("Supprimer la contrainte", systemImage: "trash.fill", role: .destructive, action: onDelete)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Règle

private struct RuleInspector: View {
    @Binding var rule: Rule
    let model: MCDModel
    let onDelete: () -> Void

    var body: some View {
        Form {
            Section {
                TextField("Nom", text: $rule.name)
                TextField("Description", text: $rule.details, prompt: Text("Ex. : un client ne peut pas commander plus de 10 produits"), axis: .vertical)
                    .lineLimit(2...6)
            } header: {
                InspectorHeader(title: "Règle de gestion", symbol: "r.square.fill", tint: Theme.rule)
            }
            Section("Éléments concernés") {
                ForEach(rule.links, id: \.self) { target in
                    HStack {
                        Text(displayName(of: target, in: model))
                        Spacer()
                        RemoveButton(help: "Retirer ce lien") { rule.links.removeAll { $0 == target } }
                    }
                }
                if rule.links.isEmpty {
                    Text("Avec l'outil Lien, reliez la règle aux éléments qu'elle concerne.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            SQLSection(sql: $rule.sql)
            Section {
                Button("Supprimer la règle", systemImage: "trash.fill", role: .destructive, action: onDelete)
            }
        }
        .formStyle(.grouped)
    }
}

private struct SQLSection: View {
    @Binding var sql: String

    var body: some View {
        Section {
            TextEditor(text: $sql)
                .font(.system(size: 12, design: .monospaced))
                .frame(minHeight: 90)
                .scrollContentBackground(.hidden)
        } header: {
            Text("Code SQL associé")
        } footer: {
            Text("Ajouté à la fin du script SQL (déclencheur, CHECK, vue…).")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Texte

private struct NoteInspector: View {
    @Binding var note: Note
    let onDelete: () -> Void

    var body: some View {
        Form {
            Section {
                Picker("Style", selection: $note.style) {
                    Text("Titre").tag(NoteStyle.titre)
                    Text("Texte").tag(NoteStyle.texte)
                }
                .pickerStyle(.segmented)
                TextField("Texte", text: $note.text, axis: .vertical)
                    .lineLimit(1...8)
            } header: {
                InspectorHeader(title: "Texte", symbol: "textformat", tint: .secondary)
            }
            Section {
                Button("Supprimer le texte", systemImage: "trash.fill", role: .destructive, action: onDelete)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Sélection multiple

private struct MultiSelectionInspector: View {
    @Binding var model: MCDModel
    @Binding var selection: Set<NodeRef>
    @State private var color: NodeColor = .auto

    var body: some View {
        Form {
            Section {
                Text("\(selection.count) éléments sélectionnés").font(.headline)
            } header: {
                InspectorHeader(title: "Sélection", symbol: "square.on.square.fill", tint: Theme.entity)
            }
            Section("Aligner") {
                Grid(horizontalSpacing: 8, verticalSpacing: 8) {
                    GridRow {
                        ForEach(Array(Arranger.Alignment.allCases.prefix(3))) { alignButton($0) }
                    }
                    GridRow {
                        ForEach(Array(Arranger.Alignment.allCases.suffix(3))) { alignButton($0) }
                    }
                }
                HStack {
                    Button("Premier plan", systemImage: "square.3.layers.3d.top.filled") { Arranger.reorder(selection, front: true, in: &model) }
                    Button("Arrière-plan", systemImage: "square.3.layers.3d.bottom.filled") { Arranger.reorder(selection, front: false, in: &model) }
                }
            }
            Section("Couleur des entités et associations") {
                ColorSwatches(color: $color, fallback: Theme.entityFill)
                    .onChange(of: color) { _, newColor in
                        for ref in selection {
                            switch ref {
                            case .entity(let id):
                                if let i = model.entities.firstIndex(where: { $0.id == id }) { model.entities[i].color = newColor }
                            case .association(let id):
                                if let i = model.associations.firstIndex(where: { $0.id == id }) { model.associations[i].color = newColor }
                            default: break
                            }
                        }
                    }
            }
            Section {
                Button("Supprimer la sélection", systemImage: "trash.fill", role: .destructive) {
                    for ref in selection { model.remove(ref) }
                    selection = []
                }
            }
        }
        .formStyle(.grouped)
    }

    private func alignButton(_ alignment: Arranger.Alignment) -> some View {
        Button {
            Arranger.align(selection, alignment, in: &model)
        } label: {
            Image(systemName: alignment.symbol).frame(maxWidth: .infinity)
        }
        .help(alignment.label)
    }
}

// MARK: - Vue d'ensemble

private struct OverviewInspector: View {
    @Binding var model: MCDModel
    let diagnostics: [Diagnostic]
    @Binding var selection: Set<NodeRef>

    var body: some View {
        Form {
            Section {
                LabeledContent("Entités", value: "\(model.entities.count)")
                LabeledContent("Associations", value: "\(model.associations.count)")
                LabeledContent("Tables générées", value: "\(MLDBuilder.build(model).count)")
            } header: {
                InspectorHeader(title: "Modèle", symbol: "square.grid.3x3.fill", tint: Theme.entity)
            }

            Section("Vérification") {
                if diagnostics.isEmpty {
                    Label("Aucun problème détecté", systemImage: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                }
                ForEach(diagnostics) { diagnostic in
                    Button {
                        if let target = diagnostic.target { selection = [target] }
                    } label: {
                        Label {
                            Text(diagnostic.message).foregroundStyle(.primary)
                        } icon: {
                            Image(systemName: diagnostic.severity == .error ? "xmark.octagon.fill" : "exclamationmark.triangle.fill")
                                .foregroundStyle(diagnostic.severity == .error ? .red : .orange)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }

            Section("Génération SQL") {
                Picker("Nommage", selection: $model.settings.naming) {
                    ForEach(NamingConvention.allCases) { Text($0.label).tag($0) }
                }
                Toggle("Clés étrangères en ALTER TABLE à la fin", isOn: $model.settings.foreignKeysAtEnd)
                Toggle("Nommer les colonnes avec les libellés", isOn: $model.settings.useLabels)
                    .help("Comme Looping : « Identifiant du client » devient Identifiant_du_client")
            }

            Section("Pour commencer") {
                HelpRow(glyph: .entity, text: "Outil Entité, puis clic sur le canevas.")
                HelpRow(glyph: .link, text: "Outil Lien : une association, puis ses entités.")
                HelpRow(glyph: .inheritance, text: "Héritage : posez-le, puis cliquez le surtype et les sous-types.")
                HelpRow(glyph: .cif, text: "CIF : posez-la, puis cliquez l'association et l'entité cible.")
                HelpRow(symbol: "key.fill", text: "La clé marque l'identifiant d'une entité.")
                HelpRow(symbol: "command", text: "Maj-clic ou lasso : sélection multiple. Cmd C / V : copier-coller.")
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Composants

private struct AttributesSection: View {
    @Binding var attributes: [Attribute]
    let allowsIdentifier: Bool
    let tint: Color
    @State private var editing: Attribute?

    var body: some View {
        Section("Propriétés") {
            ForEach($attributes) { $attribute in
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        if allowsIdentifier {
                            Button {
                                attribute.isIdentifier.toggle()
                            } label: {
                                Image(systemName: attribute.isIdentifier ? "key.fill" : "key")
                                    .foregroundStyle(attribute.isIdentifier ? tint : .secondary)
                                    .frame(width: 16)
                            }
                            .buttonStyle(.borderless)
                            .help(attribute.isIdentifier ? "Identifiant (clé primaire)" : "Faire de cette propriété un identifiant")
                        }
                        TextField("Nom de la propriété", text: $attribute.name, prompt: Text("nom_propriete"))
                            .labelsHidden()
                            .textFieldStyle(.roundedBorder)
                        RemoveButton(help: "Supprimer la propriété") { attributes.removeAll { $0.id == attribute.id } }
                    }
                    TextField("Libellé", text: $attribute.label, prompt: Text("Libellé (facultatif)"))
                        .labelsHidden()
                        .textFieldStyle(.plain)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .padding(.leading, allowsIdentifier ? 24 : 0)
                        .help("Libellé lisible, utilisé dans le MLD si l'option « Libellés » est activée")
                    HStack(spacing: 6) {
                        TypeMenu(attribute: $attribute)
                        if attribute.type.usesLength {
                            NumberField(value: $attribute.length, range: 1...attribute.type.maxLength, width: 46,
                                        help: "Longueur maximale")
                        } else if attribute.type == .decimal {
                            NumberField(value: $attribute.precision, range: TypeSpec.precisionRange, width: 30,
                                        help: "Précision : chiffres au total")
                            NumberField(value: $attribute.scale, range: 0...attribute.precision, width: 26,
                                        help: "Échelle : chiffres après la virgule")
                        }
                        Button {
                            editing = attribute
                        } label: {
                            Image(systemName: "slider.horizontal.3")
                        }
                        .buttonStyle(.borderless)
                        .help("Toutes les options : type, collation, complément, commentaire…")
                        Spacer(minLength: 0)
                        if !attribute.isIdentifier {
                            FlagToggle(label: "NN", isOn: $attribute.isNotNull, help: "NOT NULL : valeur obligatoire")
                            FlagToggle(label: "U", isOn: $attribute.isUnique, help: "UNIQUE : pas de doublon")
                        }
                    }
                    .padding(.leading, allowsIdentifier ? 24 : 0)
                }
                .padding(.vertical, 3)
            }
            .onMove { attributes.move(fromOffsets: $0, toOffset: $1) }

            Button("Ajouter une propriété", systemImage: "plus.circle.fill") {
                attributes.append(Attribute(name: ""))
            }
            .buttonStyle(.borderless)
            .foregroundStyle(tint)
        }
        .sheet(item: $editing) { attribute in
            AttributeEditor(attribute: attribute, allowsIdentifier: allowsIdentifier, tint: tint) { result in
                // La propriété a pu être supprimée entre-temps : on ne recrée rien.
                if let index = attributes.firstIndex(where: { $0.id == result.id }) { attributes[index] = result }
            }
        }
    }
}

/// Champ numérique compact, toujours ramené dans ses bornes.
private struct NumberField: View {
    @Binding var value: Int
    let range: ClosedRange<Int>
    let width: CGFloat
    let help: String

    var body: some View {
        TextField(help, value: Binding { value } set: { value = min(max($0, range.lowerBound), range.upperBound) },
                  format: .number.grouping(.never))
            .labelsHidden()
            .textFieldStyle(.roundedBorder)
            .multilineTextAlignment(.trailing)
            .frame(width: width)
            .help(help)
    }
}

private struct FlagToggle: View {
    let label: String
    @Binding var isOn: Bool
    let help: String

    var body: some View {
        Button(label) { isOn.toggle() }
            .font(.system(size: 10, weight: .bold, design: .rounded))
            .lineLimit(1)
            .fixedSize()
            .buttonStyle(.borderless)
            .foregroundStyle(isOn ? Color.white : Color.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2.5)
            .background(isOn ? Theme.entityFill : Color.primary.opacity(0.07), in: Capsule())
            .help(help)
    }
}

private struct ColorSwatches: View {
    @Binding var color: NodeColor
    let fallback: Color

    var body: some View {
        HStack(spacing: 8) {
            Text("Couleur")
            Spacer()
            ForEach(NodeColor.allCases) { option in
                Button {
                    color = option
                } label: {
                    Circle()
                        .fill(option.fill(default: fallback))
                        .frame(width: 16, height: 16)
                        .overlay {
                            if option == color {
                                Circle().strokeBorder(Color.primary, lineWidth: 2).padding(-3)
                            }
                        }
                }
                .buttonStyle(.plain)
                .help(option.label)
            }
        }
    }
}

private struct RemoveButton: View {
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "minus.circle.fill")
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.borderless)
        .help(help)
        .accessibilityLabel(help)
    }
}

private struct InspectorHeader: View {
    let title: String
    let symbol: String
    let tint: Color

    var body: some View {
        Label(title, systemImage: symbol)
            .font(.system(size: 11, weight: .semibold))
            .tracking(0.6)
            .textCase(.uppercase)
            .foregroundStyle(tint)
    }
}

private struct HelpRow: View {
    var glyph: Glyph?
    var symbol: String = ""
    let text: String

    var body: some View {
        HStack(spacing: 10) {
            Group {
                if let glyph {
                    GlyphView(glyph: glyph)
                } else {
                    Image(systemName: symbol).foregroundStyle(Theme.entity)
                }
            }
            .frame(width: 30)
            Text(text).font(.callout)
        }
    }
}
