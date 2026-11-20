# Cardinal

Atelier de modélisation Merise natif pour macOS (SwiftUI) : on dessine le MCD, l'appli en déduit le MLD et le script SQL.

## Fonctionnalités (v0.2)

Voir [PARITE_LOOPING.md](PARITE_LOOPING.md) pour la comparaison détaillée avec Looping 4.1.

- MCD : entités (dont fictives), associations, pattes et cardinalités, identifiants relatifs (R),
  propriétés typées NOT NULL / UNIQUE, couleurs par élément
- Héritage X, T, XT avec trois traductions MLD ; CIF et contraintes inter-associations ; règles de gestion avec SQL ; textes et titres
- Multisélection (Maj-clic, lasso), copier/couper/coller, dupliquer, aligner, premier/arrière-plan, Cmd A
- Vérification du modèle en direct
- MLD textuel, diagramme standard et pattes de corbeau ; diagramme de classes UML (standard et simplifié)
- Script SQL pour 6 SGBD, conventions de nommage, clés étrangères en ALTER TABLE, code des règles
- Rétroconception : MCD reconstruit à partir d'un script SQL (fichier ou presse-papiers)
- Exports PNG, PDF, presse-papiers, XML du MLD, impression (Cmd P)
- Ouverture des fichiers Looping `.loo` (Fichier > Ouvrir), enregistrés ensuite en `.mcd`
- Fichiers `.mcd` en JSON lisible (compatibles Git), annuler/rétablir, mode sombre, zoom et « ajuster à la fenêtre »

## Règles de passage MCD → MLD

1. Chaque entité devient une table ; ses identifiants forment la clé primaire.
2. Association binaire avec une patte 0,1 ou 1,1 : l'entité de cette patte reçoit la clé étrangère.
3. Toute autre association devient une table dont la clé est composée des clés des entités reliées.

## Compiler

```bash
xcodegen generate
open Cardinal.xcodeproj
```

Tests (Swift Testing) :

```bash
xcodebuild -project Cardinal.xcodeproj -scheme Cardinal -derivedDataPath build.noindex test
```

## Organisation

| Dossier | Rôle |
|---|---|
| `Cardinal/Model` | Le MCD (Codable) et le document `.mcd` |
| `Cardinal/Engine` | MCD → MLD, MLD → SQL, validation |
| `Cardinal/Views` | Canevas, inspecteur, vues MLD et SQL |
| `CardinalTests` | Tests du moteur |
| `Exemples` | Un MCD de gestion de commandes |

## Tests de fiabilité

```bash
xcodebuild -project Cardinal.xcodeproj -scheme Cardinal -derivedDataPath build.noindex test
```

Avec exécution réelle des scripts dans PostgreSQL et MariaDB (serveurs temporaires, arrêtés à la fin) :

```bash
Scripts/tester-avec-sgbd.sh
```

- 300 MCD aléatoires (noms réservés, noms très longs, accents, tous les types, réflexives, n-aires,
  héritages X / T / XT, CIF, entités fictives) : le script de chacun doit s'exécuter dans SQLite,
  PostgreSQL et MariaDB, et sa rétroconception redonner le même MLD.
- Mots réservés mesurés sur les serveurs eux-mêmes (`Cardinal/Engine/SQLKeywords.swift`).

## Architecture : un moteur portable, une interface par système

```
Core/                     Moteur sans interface (paquet Swift « CardinalCore »)
  Sources/CardinalCore/   modèle, types, MCD → MLD, SQL des 6 SGBD, rétroconception,
                          lecture .loo, format .mcd, validation, mise en page des diagrammes
  Tests/CardinalCoreTests/
Cardinal/                 Interface macOS (SwiftUI) : fenêtres, ruban, inspecteur, dessin
CardinalTests/            Tests propres à l'interface (captures, types de documents)
```

- Le moteur se compile et se teste seul : `cd Core && swift test`.
- Il n'importe aucune bibliothèque d'interface Apple (vérifié par `PortabilityTests`) ;
  la géométrie vient de Foundation sous Windows et Linux, de CoreGraphics sur Mac.
- `swift test -Xswiftc -DCARDINAL_PORTABLE` le fait fonctionner comme sous Windows ou Linux
  (mesure du texte sans police macOS) : tous les tests doivent passer aussi dans ce mode.
- L'application macOS compile directement les fichiers de `Core/` (une seule copie du code).
  Les futures interfaces Windows et Linux dépendront du paquet `CardinalCore`.

## Icône

Mini MCD : deux entités (bleu institutionnel, couleur des entités dans Cardinal) reliées par une
association (ambre), avec les cardinalités 1,N et 0,N à partir de 256 px. Générée par
`Scripts/icone/icone.swift` dans toutes les tailles de `Cardinal/Assets.xcassets/AppIcon.appiconset`.

## Téléchargement

Installeurs pour macOS, Windows et Linux : [faliloudiouf.com/cardinal](https://faliloudiouf.com/cardinal/)
et [versions GitHub](https://github.com/Faliloudiouf/cardinal/releases).

## Code signing policy

Politique de signature du code.

Free code signing provided by [SignPath.io](https://about.signpath.io), certificate by [SignPath Foundation](https://signpath.org).

- Seuls les installeurs produits par la construction automatique de ce dépôt
  (`.github/workflows/windows-linux.yml`) sont signés, à partir du code source publié ici.
- Chaque version est approuvée manuellement avant signature.
- Committers and reviewers: [Falilou Diouf (@Faliloudiouf)](https://github.com/Faliloudiouf)
- Approvers: [Falilou Diouf (@Faliloudiouf)](https://github.com/Faliloudiouf)

### Privacy policy

This program will not transfer any information to other networked systems unless specifically
requested by the user or the person installing or operating it.

Cardinal fonctionne entièrement hors ligne : les modèles restent sur l'ordinateur de
l'utilisateur et ne sont envoyés nulle part.

## Licence

Cardinal est un logiciel libre distribué sous licence [MIT](LICENSE).
