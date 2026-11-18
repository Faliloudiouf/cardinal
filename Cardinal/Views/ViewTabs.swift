import SwiftUI

/// Onglets des vues (sous-modèles) au-dessus du canevas : « Modèle complet », puis chaque vue.
struct ViewTabs: View {
    @Binding var model: MCDModel
    @ObservedObject var state: WindowState
    @State private var renaming: ModelView.ID?
    @State private var newName = ""

    var body: some View {
        HStack(spacing: 4) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    tab(title: "Modèle complet", symbol: "square.grid.2x2.fill", isActive: state.activeView == nil) {
                        state.activeView = nil
                    }
                    ForEach(model.views) { view in
                        tab(title: view.name, symbol: "rectangle.stack.fill", isActive: state.activeView == view.id) {
                            state.activeView = view.id
                        }
                        .contextMenu { menu(for: view) }
                    }
                }
            }
            Button {
                createView()
            } label: {
                Label("Nouvelle vue", systemImage: "plus.circle.fill")
            }
            .buttonStyle(.borderless)
            .help(state.selection.isEmpty
                  ? "Créer une vue vide (ajoutez-y des éléments ensuite)"
                  : "Créer une vue avec la sélection et ce qui la relie")
            if let current = state.activeView, let view = model.views.first(where: { $0.id == current }) {
                Menu {
                    menu(for: view)
                } label: {
                    Label("Vue", systemImage: "ellipsis.circle.fill").labelStyle(.iconOnly)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("Gérer la vue « \(view.name) »")
            }
        }
        .font(.system(size: 11.5))
        .padding(.horizontal, 10)
        .frame(height: 30)
        .background(.bar)
        .overlay(alignment: .bottom) { Divider() }
        .alert("Renommer la vue", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Nom", text: $newName)
            Button("Renommer") {
                let name = newName.trimmingCharacters(in: .whitespaces)
                if let id = renaming, !name.isEmpty, let index = model.views.firstIndex(where: { $0.id == id }) {
                    model.views[index].name = name
                }
                renaming = nil
            }
            Button("Annuler", role: .cancel) { renaming = nil }
        }
        .onChange(of: model.views.map(\.id)) { _, ids in
            // Vue supprimée (ou annulée) pendant qu'elle était affichée : retour au modèle complet.
            if let current = state.activeView, !ids.contains(current) { state.activeView = nil }
        }
    }

    private func tab(title: String, symbol: String, isActive: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .lineLimit(1)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .foregroundStyle(isActive ? Color.accentColor : Color.secondary)
                .background(isActive ? Color.accentColor.opacity(0.14) : Color.clear, in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func menu(for view: ModelView) -> some View {
        Button("Renommer…") {
            newName = view.name
            renaming = view.id
        }
        Button("Ajouter la sélection à la vue") { update(view.id) { $0.add(model.completed(state.selection)) } }
            .disabled(state.selection.isEmpty)
        Button("Retirer la sélection de la vue") { update(view.id) { v in v.refs.removeAll { state.selection.contains($0) } } }
            .disabled(state.selection.isEmpty)
        Divider()
        Button("Supprimer la vue (les éléments restent dans le modèle)", role: .destructive) {
            model.views.removeAll { $0.id == view.id }
        }
    }

    private func update(_ id: ModelView.ID, _ change: (inout ModelView) -> Void) {
        guard let index = model.views.firstIndex(where: { $0.id == id }) else { return }
        change(&model.views[index])
    }

    private func createView() {
        var counter = model.views.count + 1
        while model.views.contains(where: { $0.name == "Vue \(counter)" }) { counter += 1 }
        let refs = model.completed(state.selection)
        let view = ModelView(name: "Vue \(counter)", refs: refs.sorted { "\($0)" < "\($1)" })
        model.views.append(view)
        state.activeView = view.id
        newName = view.name
        renaming = view.id // on propose tout de suite de la nommer
    }
}
