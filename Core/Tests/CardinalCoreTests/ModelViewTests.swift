import Testing
import Foundation
#if SWIFT_PACKAGE
@testable import CardinalCore
#else
@testable import Cardinal
#endif

@Suite("Vues (sous-modèles)")
struct ModelViewTests {
    func model() -> (MCDModel, client: UUID, commande: UUID, produit: UUID) {
        let model = MCDModel.exemple
        return (model, model.entities[0].id, model.entities[1].id, model.entities[2].id)
    }

    @Test("Compléter une sélection : l'association entre deux entités choisies suit, pas les autres")
    func completer() {
        let (model, client, commande, _) = model()
        let refs = model.completed([.entity(client), .entity(commande)])
        let passer = model.associations.first { $0.name == "Passer" }!
        let contenir = model.associations.first { $0.name == "Contenir" }!
        #expect(refs.contains(.association(passer.id)))
        #expect(!refs.contains(.association(contenir.id))) // Produit n'est pas dans la vue
    }

    @Test("Une vue montre ses éléments ; le modèle complet reste entier")
    func visible() {
        var (model, client, commande, produit) = model()
        let view = ModelView(name: "Commandes", refs: Array(model.completed([.entity(client), .entity(commande)])))
        model.views = [view]
        let shown = model.visible(in: view.id)
        #expect(Set(shown.entities.map(\.id)) == [client, commande])
        #expect(shown.associations.map(\.name) == ["Passer"])
        #expect(!shown.entities.contains { $0.id == produit })
        #expect(model.visible(in: nil).entities.count == 3)
        #expect(model.visible(in: UUID()).entities.count == 3) // vue disparue : tout le modèle
        // Le MLD ne dépend jamais de la vue.
        #expect(MLDBuilder.build(model).count == MLDBuilder.build(.exemple).count)
    }

    @Test("Supprimer un élément du modèle le retire aussi de ses vues")
    func suppression() {
        var (model, client, commande, _) = model()
        model.views = [ModelView(name: "V", refs: [.entity(client), .entity(commande)])]
        model.remove(.entity(client))
        #expect(model.views[0].refs == [.entity(commande)])
    }

    @Test("Vues enregistrées ; un ancien fichier sans vues reste lisible ; une référence inconnue est ignorée")
    func fichier() throws {
        var (model, client, _, _) = model()
        model.views = [ModelView(name: "Clients", refs: [.entity(client)])]
        #expect(try ModelFile.read(try ModelFile.encode(model)).views == model.views)
        #expect(try ModelFile.read(Data(#"{"entities":[]}"#.utf8)).views.isEmpty)
        let future = #"{"views":[{"name":"V","refs":[{"tableau":{"_0":"\#(UUID().uuidString)"}}]}]}"#
        let decoded = try ModelFile.read(Data(future.utf8))
        #expect(decoded.views.count == 1 && decoded.views[0].refs.isEmpty)
    }
}
