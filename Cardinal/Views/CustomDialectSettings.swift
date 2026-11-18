import SwiftUI

/// SGBD cible de l'utilisateur : un des 6 SGBD, ou son SGBD personnalisé (Réglages).
enum SQLTarget {
    static let customKey = "sgbdPersonnalise"
    static let usesCustomKey = "sgbdPersonnaliseActif"

    static var usesCustom: Bool { UserDefaults.standard.bool(forKey: usesCustomKey) }

    static var custom: CustomDialect {
        get {
            guard let data = UserDefaults.standard.data(forKey: customKey),
                  let value = try? JSONDecoder().decode(CustomDialect.self, from: data) else { return CustomDialect() }
            return value
        }
        set { UserDefaults.standard.set(try? JSONEncoder().encode(newValue), forKey: customKey) }
    }

    /// Script du modèle pour la cible choisie.
    static func script(for model: MCDModel, dialect: SQLDialect) -> String {
        usesCustom ? SQLGenerator.script(for: model, custom: custom) : SQLGenerator.script(for: model, dialect: dialect)
    }

    static func name(_ dialect: SQLDialect) -> String { usesCustom ? custom.name : dialect.rawValue }
}

/// Sélecteur « SGBD cible » : les 6 SGBD, puis le SGBD personnalisé.
struct SQLTargetPicker: View {
    var title = "SGBD cible"
    @AppStorage(Defaults.dialect) private var dialect: SQLDialect = .mysql
    @AppStorage(SQLTarget.usesCustomKey) private var usesCustom = false
    @AppStorage(SQLTarget.customKey) private var customData = Data()

    private static let customTag = "personnalise"

    var body: some View {
        Picker(title, selection: Binding {
            usesCustom ? Self.customTag : dialect.rawValue
        } set: { tag in
            if tag == Self.customTag {
                usesCustom = true
            } else if let chosen = SQLDialect(rawValue: tag) {
                usesCustom = false
                dialect = chosen
            }
        }) {
            ForEach(SQLDialect.allCases) { Text($0.rawValue).tag($0.rawValue) }
            Divider()
            Text("\(SQLTarget.custom.name) (personnalisé)").tag(Self.customTag)
        }
    }
}

/// Onglet « SGBD personnalisé » des Réglages : nom, SGBD de base, type SQL de chaque type Cardinal.
struct CustomDialectSettings: View {
    @State private var custom = SQLTarget.custom
    @AppStorage(SQLTarget.usesCustomKey) private var usesCustom = false

    var body: some View {
        Form {
            Section {
                TextField("Nom", text: $custom.name, prompt: Text("Mon SGBD"))
                Picker("Basé sur", selection: $custom.base) {
                    ForEach(SQLDialect.allCases) { Text($0.rawValue).tag($0) }
                }
                Toggle("Utiliser ce SGBD pour l'onglet SQL et les exports", isOn: $usesCustom)
            } footer: {
                Text("Laissez un type vide pour garder celui du SGBD de base. Dans le texte : {n} = longueur, {p} = précision, {s} = échelle.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ForEach(TypeCategory.allCases) { category in
                Section(category.label) {
                    ForEach(category.types) { type in
                        LabeledContent(type.menuLabel) {
                            TextField(type.menuLabel, text: binding(for: type),
                                      prompt: Text("par défaut : " + SQLGenerator.sqlType(TypeSpec(kind: type), dialect: custom.base)))
                                .labelsHidden()
                                .font(.system(.body, design: .monospaced))
                                .frame(width: 240)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onChange(of: custom) { _, newValue in SQLTarget.custom = newValue }
    }

    private func binding(for type: DataType) -> Binding<String> {
        Binding {
            custom.types[type.rawValue] ?? ""
        } set: { text in
            custom.types[type.rawValue] = text.isEmpty ? nil : text
        }
    }
}
