import Foundation
#if canImport(CoreGraphics)
import CoreGraphics // CGRect et ses fonctions ; sous Windows et Linux, Foundation les fournit
#endif

extension MCDModel {
    /// Petit MCD de gestion de commandes, utilisé par « Nouveau à partir de l'exemple » et par les tests.
    static var exemple: MCDModel {
        let client = Entity(
            name: "Client",
            attributes: [
                Attribute(name: "id_client", type: .entier, isIdentifier: true),
                Attribute(name: "nom", type: .varchar, length: 60),
                Attribute(name: "prenom", type: .varchar, length: 60),
                Attribute(name: "email", type: .varchar, length: 120),
            ],
            position: CGPoint(x: 240, y: 220)
        )
        let commande = Entity(
            name: "Commande",
            attributes: [
                Attribute(name: "num_commande", type: .entier, isIdentifier: true),
                Attribute(name: "date_commande", type: .date),
            ],
            position: CGPoint(x: 800, y: 220)
        )
        let produit = Entity(
            name: "Produit",
            attributes: [
                Attribute(name: "ref_produit", type: .varchar, length: 20, isIdentifier: true),
                Attribute(name: "libelle", type: .varchar, length: 100),
                Attribute(name: "prix", type: .decimal),
            ],
            position: CGPoint(x: 1200, y: 500)
        )
        let passer = Association(
            name: "Passer",
            legs: [
                Leg(entityID: client.id, cardinality: .zeroMany),
                Leg(entityID: commande.id, cardinality: .oneOne),
            ],
            position: CGPoint(x: 520, y: 220)
        )
        let contenir = Association(
            name: "Contenir",
            attributes: [Attribute(name: "quantite", type: .entier)],
            legs: [
                Leg(entityID: commande.id, cardinality: .oneMany),
                Leg(entityID: produit.id, cardinality: .zeroMany),
            ],
            position: CGPoint(x: 800, y: 500)
        )
        return MCDModel(entities: [client, commande, produit], associations: [passer, contenir])
    }

    /// MCD de scolarité : héritage, identifiant relatif, association ternaire avec CIF, règle, titre.
    static var exempleScolarite: MCDModel {
        let personne = Entity(name: "Personne", attributes: [
            Attribute(name: "id_personne", type: .entier, isIdentifier: true),
            Attribute(name: "nom", type: .varchar, length: 60, isNotNull: true),
            Attribute(name: "email", type: .varchar, length: 120, isUnique: true),
        ], position: CGPoint(x: 560, y: 170))
        let etudiant = Entity(name: "Etudiant", attributes: [
            Attribute(name: "matricule", type: .varchar, length: 15, isNotNull: true, isUnique: true),
        ], position: CGPoint(x: 330, y: 430))
        let enseignant = Entity(name: "Enseignant", attributes: [
            Attribute(name: "grade", type: .varchar, length: 30),
        ], position: CGPoint(x: 790, y: 430))
        let classe = Entity(name: "Classe", attributes: [
            Attribute(name: "code_classe", type: .varchar, length: 10, isIdentifier: true),
            Attribute(name: "libelle", type: .varchar, length: 60),
        ], position: CGPoint(x: 330, y: 760))
        let matiere = Entity(name: "Matiere", attributes: [
            Attribute(name: "code_matiere", type: .varchar, length: 10, isIdentifier: true),
            Attribute(name: "intitule", type: .varchar, length: 80),
        ], position: CGPoint(x: 1180, y: 760))
        let batiment = Entity(name: "Batiment", attributes: [
            Attribute(name: "id_batiment", type: .entier, isIdentifier: true),
            Attribute(name: "nom_batiment", type: .varchar, length: 40),
        ], position: CGPoint(x: 1180, y: 170))
        let salle = Entity(name: "Salle", attributes: [
            Attribute(name: "num_salle", type: .entier, isIdentifier: true),
            Attribute(name: "capacite", type: .entier),
        ], position: CGPoint(x: 1180, y: 450))

        let heritage = Inheritance(parentID: personne.id, childIDs: [etudiant.id, enseignant.id], kind: .partition, position: CGPoint(x: 560, y: 320))
        let appartenir = Association(name: "Appartenir", legs: [
            Leg(entityID: etudiant.id, cardinality: .oneOne),
            Leg(entityID: classe.id, cardinality: .zeroMany),
        ], position: CGPoint(x: 330, y: 600))
        let enseigner = Association(name: "Enseigner", attributes: [Attribute(name: "volume_horaire", type: .entier)], legs: [
            Leg(entityID: enseignant.id, cardinality: .zeroMany),
            Leg(entityID: classe.id, cardinality: .oneMany),
            Leg(entityID: matiere.id, cardinality: .oneMany),
        ], position: CGPoint(x: 790, y: 760))
        let situer = Association(name: "Situer", legs: [
            Leg(entityID: salle.id, cardinality: .oneOne, isRelative: true),
            Leg(entityID: batiment.id, cardinality: .oneMany),
        ], position: CGPoint(x: 1180, y: 310))
        let cif = Constraint(kind: .cif, links: [
            ConstraintLink(target: .association(enseigner.id)),
            ConstraintLink(target: .entity(enseignant.id), isTarget: true),
        ], position: CGPoint(x: 960, y: 620))
        let regle = Rule(
            name: "Volume horaire positif",
            details: "Le volume horaire d'un enseignement est strictement positif.",
            sql: "ALTER TABLE Enseigner ADD CONSTRAINT ck_volume CHECK (volume_horaire > 0);",
            links: [.association(enseigner.id)],
            position: CGPoint(x: 790, y: 920)
        )
        let titre = Note(text: "Gestion de la scolarité", style: .titre, position: CGPoint(x: 260, y: 70))

        return MCDModel(
            entities: [personne, etudiant, enseignant, classe, matiere, batiment, salle],
            associations: [appartenir, enseigner, situer],
            inheritances: [heritage],
            constraints: [cif],
            rules: [regle],
            notes: [titre]
        )
    }
}
