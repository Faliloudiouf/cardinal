import SwiftUI

/// Fenêtre « Propriété », équivalente à celle de Looping : nom, type (Texte, Numérique,
/// Date / Heure, Autre) et ses paramètres, propriétés SQL, commentaire.
/// On modifie une copie : rien n'est appliqué tant qu'on n'a pas cliqué sur OK.
struct AttributeEditor: View {
    @State private var draft: Attribute
    let allowsIdentifier: Bool
    let tint: Color
    let onCommit: (Attribute) -> Void
    @Environment(\.dismiss) private var dismiss

    init(attribute: Attribute, allowsIdentifier: Bool, tint: Color, onCommit: @escaping (Attribute) -> Void) {
        _draft = State(initialValue: attribute)
        self.allowsIdentifier = allowsIdentifier
        self.tint = tint
        self.onCommit = onCommit
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("Nom") {
                    TextField("Nom", text: $draft.name, prompt: Text("nom_de_la_propriete"))
                    TextField("Nom logique", text: $draft.label, prompt: Text("facultatif"))
                }
                Section {
                    Picker("Famille", selection: categoryBinding) {
                        ForEach(TypeCategory.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    typeControls
                    Text(draft.type.help)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } header: {
                    Text("Type")
                }
                Section("SQL généré pour chaque SGBD") {
                    SQLPreview(attribute: draft)
                }
                if !problems.isEmpty {
                    Section {
                        ForEach(problems, id: \.text) { problem in
                            Label(problem.text, systemImage: problem.isError ? "xmark.octagon.fill" : "exclamationmark.triangle.fill")
                                .foregroundStyle(problem.isError ? Color.red : Color.orange)
                                .font(.callout)
                        }
                    }
                }
                Section("Propriétés") {
                    HStack(spacing: 18) {
                        if allowsIdentifier {
                            Toggle("Identifiant", isOn: $draft.isIdentifier)
                        }
                        Toggle("NOT NULL", isOn: $draft.isNotNull).disabled(draft.isIdentifier)
                        Toggle("UNIQUE", isOn: $draft.isUnique).disabled(draft.isIdentifier)
                    }
                    .toggleStyle(.checkbox)
                    TextField("Complément", text: $draft.complement, prompt: Text("ex. DEFAULT 0"))
                        .help("Texte SQL ajouté tel quel à la colonne")
                }
                Section("Commentaire") {
                    TextEditor(text: $draft.comment)
                        .font(.body)
                        .frame(minHeight: 54)
                        .scrollContentBackground(.hidden)
                }
            }
            .formStyle(.grouped)

            Divider()
            HStack {
                Spacer()
                Button("Annuler", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("OK") {
                    var result = draft
                    result.name = result.name.trimmingCharacters(in: .whitespacesAndNewlines)
                    result.spec = result.spec.normalized
                    if result.isIdentifier { result.isNotNull = false; result.isUnique = false }
                    onCommit(result)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(draft.name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(14)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .frame(width: 560, height: 720)
    }

    private var problems: [(text: String, isError: Bool)] { Validator.typeProblems([draft]) }

    private var categoryBinding: Binding<TypeCategory> {
        Binding {
            draft.type.category
        } set: { category in
            guard category != draft.type.category else { return }
            draft.setType(category == .texte ? .varchar : category == .numerique ? .entier
                          : category == .dateHeure ? .date : .booleen)
        }
    }

    private var typeBinding: Binding<DataType> {
        Binding { draft.type } set: { draft.setType($0) }
    }

    @ViewBuilder
    private var typeControls: some View {
        switch draft.type.category {
        case .texte:
            Picker("Jeu de caractères", selection: Binding {
                draft.type.encoding ?? .ascii
            } set: { draft.setType(DataType.text($0, draft.type.storage ?? .variable)) }) {
                ForEach(TextEncoding.allCases) { Text($0.shortLabel).tag($0) }
            }
            .pickerStyle(.segmented)
            Picker("Stockage", selection: Binding {
                draft.type.storage ?? .variable
            } set: { draft.setType(DataType.text(draft.type.encoding ?? .ascii, $0)) }) {
                ForEach(TextStorage.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.radioGroup)
            .horizontalRadioGroupLayout()
            if draft.type.usesLength {
                LengthField(value: $draft.length, range: 1...draft.type.maxLength)
            }
            if draft.type.usesCollation {
                TextField("Collation", text: $draft.collation, prompt: Text("facultatif (ex. utf8mb4_bin)"))
            }
        case .numerique:
            Picker("Type", selection: typeBinding) {
                ForEach(TypeCategory.numerique.types) { Text($0.label).tag($0) }
            }
            .pickerStyle(.radioGroup)
            if draft.type == .decimal {
                Stepper(value: Binding {
                    draft.precision
                } set: {
                    draft.precision = min(max($0, 1), 38)
                    draft.scale = min(draft.scale, draft.precision)
                }, in: TypeSpec.precisionRange) {
                    LabeledContent("Précision (chiffres au total)", value: "\(draft.precision)")
                }
                Stepper(value: $draft.scale, in: 0...draft.precision) {
                    LabeledContent("Échelle (chiffres après la virgule)", value: "\(draft.scale)")
                }
            }
        case .dateHeure:
            Picker("Type", selection: typeBinding) {
                ForEach(TypeCategory.dateHeure.types) { Text($0.label).tag($0) }
            }
            .pickerStyle(.radioGroup)
        case .autre:
            Picker("Type", selection: typeBinding) {
                ForEach(TypeCategory.autre.types) { Text($0.label).tag($0) }
            }
            .pickerStyle(.radioGroup)
            if draft.type == .enumeration {
                EnumValuesEditor(values: $draft.enumValues, tint: tint)
                TextField("Collation", text: $draft.collation, prompt: Text("facultatif"))
            }
            if draft.type == .libre {
                TextField("Type SQL", text: $draft.customType, prompt: Text("ex. CITEXT, INET, YEAR"))
            }
        }
    }
}

/// Longueur : champ numérique et flèches, toujours ramenée dans les bornes.
private struct LengthField: View {
    @Binding var value: Int
    let range: ClosedRange<Int>

    var body: some View {
        LabeledContent("Longueur") {
            HStack(spacing: 4) {
                TextField("Longueur", value: Binding { value } set: { value = min(max($0, range.lowerBound), range.upperBound) },
                          format: .number.grouping(.never))
                    .labelsHidden()
                    .multilineTextAlignment(.trailing)
                    .frame(width: 80)
                Stepper("Longueur", value: $value, in: range).labelsHidden()
            }
        }
    }
}

/// Liste des valeurs d'une énumération, une par ligne.
private struct EnumValuesEditor: View {
    @Binding var values: [String]
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Valeurs autorisées").font(.callout.weight(.medium))
            ForEach(values.indices, id: \.self) { index in
                HStack {
                    TextField("Valeur", text: Binding {
                        index < values.count ? values[index] : ""
                    } set: { if index < values.count { values[index] = $0 } })
                        .labelsHidden()
                        .textFieldStyle(.roundedBorder)
                    Button {
                        if index < values.count { values.remove(at: index) }
                    } label: {
                        Image(systemName: "minus.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
                    .help("Retirer cette valeur")
                }
            }
            Button("Ajouter une valeur", systemImage: "plus.circle.fill") { values.append("") }
                .buttonStyle(.borderless)
                .foregroundStyle(tint)
        }
        .padding(.vertical, 2)
    }
}

/// Type obtenu dans chaque SGBD, pour voir tout de suite ce que le choix produira.
struct SQLPreview: View {
    let attribute: Attribute

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 5) {
            ForEach(SQLDialect.allCases) { dialect in
                GridRow {
                    Text(dialect.rawValue).foregroundStyle(.secondary)
                    Text(definition(for: dialect))
                        .font(.system(.callout, design: .monospaced))
                        .textSelection(.enabled)
                        .lineLimit(2)
                }
            }
        }
        .font(.callout)
    }

    private func definition(for dialect: SQLDialect) -> String {
        let column = MLDColumn(name: attribute.name.isEmpty ? "colonne" : attribute.name.sqlIdentifier, spec: attribute.spec,
                               isPrimaryKey: attribute.isIdentifier, isNullable: !attribute.isNotNull && !attribute.isIdentifier,
                               isUnique: attribute.isUnique)
        var pieces = [SQLGenerator.sqlType(column, dialect: dialect)]
        if let collate = SQLGenerator.collation(column.spec, dialect: dialect) { pieces.append(collate) }
        let table = MLDTable(name: "t", columns: [column], comesFromAssociation: false)
        if let identity = SQLGenerator.identityClause(column, in: table, dialect: dialect) { pieces.append(identity) }
        if dialect == .sqlite, attribute.type == .compteur, attribute.isIdentifier { pieces.append("PRIMARY KEY AUTOINCREMENT") }
        if let check = SQLGenerator.check(column, dialect: dialect) { pieces.append(check) }
        return pieces.joined(separator: " ")
    }
}

/// Menu de type compact, rangé par famille comme dans Looping.
struct TypeMenu: View {
    @Binding var attribute: Attribute

    var body: some View {
        Menu {
            ForEach(TypeCategory.allCases) { category in
                Section(category.label) {
                    ForEach(category.types) { type in
                        Button {
                            attribute.setType(type)
                        } label: {
                            if type == attribute.type {
                                Label(type.menuLabel, systemImage: "checkmark")
                            } else {
                                Text(type.menuLabel)
                            }
                        }
                    }
                }
            }
        } label: {
            Text(attribute.spec.display)
                .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                .lineLimit(1)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.visible)
        .fixedSize()
        .help("Type de la propriété")
    }
}
