# Parité fonctionnelle Looping 4.1 → Cardinal

Sources : analyse externe de `Looping.exe` (92 commandes du ruban, textes de l'interface)
et pages officielles « Fonctionnalités » et « Nouveautés » de looping-mcd.fr.
Aucun code de Looping n'est repris : Cardinal est une réécriture originale.

Légende : ✅ fait · 🟡 en partie · ⏳ prévu

## Modélisation Entité/Association

| Fonctionnalité Looping | Cardinal |
|---|---|
| Entités, associations, pattes, cardinalités | ✅ |
| Propriétés typées, identifiants | ✅ |
| NOT NULL et UNIQUE par propriété | ✅ phase 1 |
| Entité fictive (non générée dans le MLD) | ✅ phase 1 |
| Identifiant relatif (association transformée en entité faible) | ✅ phase 1 |
| Héritage : spécialisation / généralisation (X, T, XT, sans contrainte) | ✅ phase 1 |
| Migration des propriétés du surtype vers les sous-types (option) | ✅ phase 1 |
| Contrainte d'intégrité fonctionnelle (CIF), multicible | ✅ phase 1 |
| Contraintes inter-associations (I, X, T, XT, S, =) | ✅ phase 1 (dessin) |
| Règles de gestion avec code SQL associé | ✅ phase 1 |
| Flèches de dépendances fonctionnelles (DF) | ⏳ phase 2 |
| Textes, titres, rectangles, ellipses, flèches, images, flux (MOF) | 🟡 phase 1 : textes et titres |
| Casser un lien (points de cassure) | ⏳ phase 2 |

## Modèles dérivés

| Fonctionnalité Looping | Cardinal |
|---|---|
| MLD en temps réel | ✅ |
| MLD textuel | ✅ |
| MLD graphique standard et pattes de corbeau (crow's foot) | ✅ phase 1 |
| Diagramme de classes UML (standard, simplifié) | ✅ phase 1 |
| Script LDD en temps réel | ✅ |
| SGBD : MySQL, MariaDB, PostgreSQL, SQLite, SQL Server, Oracle | ✅ |
| Access | ⏳ phase 2 |
| SGBD personnalisé, types libres prédéfinis | ⏳ phase 2 |
| Convention de nommage (snake, camel, Pascal, telle quelle) | ✅ phase 1 |
| Clés étrangères en ALTER TABLE en fin de script (option) | ✅ phase 1 |
| Rétroconception : MCD à partir d'un script DDL | ✅ phase 1 |

## Édition et présentation

| Fonctionnalité Looping | Cardinal |
|---|---|
| Annuler / rétablir | ✅ (illimité) |
| Couper, copier, coller, tout sélectionner, inverser la sélection | ✅ phase 1 |
| Multisélection | ✅ phase 1 |
| Aligner (gauche, droite, haut, bas, centres), premier plan / arrière-plan | ✅ phase 1 |
| Grille, zoom 50/100/150 %, ajuster à la fenêtre | ✅ phase 1 |
| Afficher/masquer types, propriétés (MCD simplifié) | ✅ phase 1 |
| Couleur par entité / association | ✅ phase 1 |
| Polices et couleurs personnalisables globalement | ⏳ phase 2 |
| Multi-vues et sous-modèles | ⏳ phase 2 |
| Thèmes d'interface | ✅ (clair / sombre natifs) |
| Récupération automatique après plantage | ✅ (sauvegarde auto et versions de macOS) |

## Fichiers et exports

| Fonctionnalité Looping | Cardinal |
|---|---|
| Nouveau, ouvrir, enregistrer, fermer | ✅ (natif macOS) |
| Export image du modèle | ✅ phase 1 (PNG, PDF) |
| Modèle vers le presse-papiers | ✅ phase 1 |
| Export MLD au format XML | ✅ phase 1 |
| Export du script en fichier texte | ✅ |
| Impression et aperçu | ✅ phase 1 |
| Lecture des fichiers `.loo` | ✅ entités, propriétés (code, libellé, type, identifiant), associations, cardinalités, rôles, positions |
| Libellés des propriétés, rôles des pattes | ✅ (option « colonnes nommées par libellé ») |

## En plus de Looping

Vérification du modèle en direct · fichiers JSON lisibles et versionnables avec Git ·
interface native macOS (mode sombre, pavé tactile, raccourcis Cmd) · tests automatisés du moteur.

## UML et lisibilité (16/11/2026)

- UML du fichier LoopingEntrepriseServices2.loo : multiplicités et rôles identiques à la capture de Looping pour les 8 associations (test `UMLParityTests`), classe-association Realiser, réflexive EtreCompose dessinée en boucle.
- Classes à trois compartiments et visibilité « + », comme Looping.
- Lisibilité vérifiée par tests sur 6 modèles (dont un modèle chargé, serré, et tout empilé au même point) : aucun texte sur un autre texte, une boîte ou un trait ; aucune boîte traversée par un trait ; chaque cardinalité plus proche de sa patte que de toute autre.
- Moteur : `Cardinal/Engine/Readability.swift` (placeur d'étiquettes, écartement, recherche locale anti-traversée), `UMLLayout.swift`, `MCDLabelLayout` (pattes réparties le long des côtés).

## Types de données (16/11/2026)

Fenêtre « Propriété » équivalente à celle de Looping, avec en plus les types modernes.

| Famille | Looping | Cardinal |
|---|---|---|
| Texte | ASCII / Unicode / Binaire × Variable / Fixe / Volumineux, longueur, collation | identique |
| Numérique | Entier, Décimal, Réel, Monétaire, Compteur | identique + Petit entier, Grand entier ; précision et échelle du décimal |
| Date / Heure | Date, Heure, Date-Heure | identique + Horodatage avec fuseau |
| Autre | Booléen, Xml, Géométrique, Géographique, Libre | identique + UUID, JSON, Énumération (valeurs contrôlées) |
| Propriétés | Identifiant, NOT NULL, UNIQUE, Complément, Commentaire, Nom logique | identique |

- Traduction pour les 6 SGBD ; une longueur au-delà de la limite d'un SGBD bascule sur son type volumineux ; le compteur devient AUTO_INCREMENT / IDENTITY / AUTOINCREMENT, et un simple entier dans les clés étrangères.
- Énumération : ENUM en MySQL/MariaDB, CHECK (… IN …) ailleurs ; booléen et JSON contrôlés quand le SGBD n'a pas de vrai type.
- Aperçu du SQL des 6 SGBD dans la fenêtre ; le validateur signale énumération vide, type libre vide, décimal invalide, compteur mal placé.
- Rétroconception : tous ces types, AUTO_INCREMENT/IDENTITY/SERIAL, CHARACTER SET, COLLATE, DEFAULT, COMMENT, CHECK ; un type inconnu est gardé en type Libre.
- Anciens fichiers Cardinal lus sans perte (anciens noms de types traduits).
- Codes de type Looping connus à l'import .loo : texte, décimal, date, booléen (les autres codes restent à relever sur un fichier exemple).
