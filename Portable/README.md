# Cardinal pour Windows et Linux

Même moteur que la version Mac, nouvelle interface :

- `moteur/` : le moteur Swift (`Core/Sources/CardinalCore`, par un lien) compilé en WebAssembly,
  avec un pont JSON (`Sources/CardinalWasm/Requetes.swift`).
- `app/` : l'interface (React + TypeScript, Vite) et l'application de bureau (Tauri, dans `src-tauri/`).
- `linux/` : conteneur de construction des paquets Linux.
- `scripts/` : construction du moteur et de l'installateur Windows.

## Construire

| Étape | Commande | Produit |
| --- | --- | --- |
| Moteur | `scripts/moteur.sh` | `app/public/cardinal.wasm` |
| Essai dans le navigateur | `cd app && npx vite` | http://localhost:5173 |
| Appli de bureau (Mac) | `cd app && npx tauri build --bundles app` | `Cardinal.app` |
| Windows (depuis le Mac) | `scripts/windows.sh` | `sortie/Cardinal_0.1.0_x64-setup.exe` |
| Linux (conteneur) | `linux/construire.sh` | `linux/sortie/*.deb, *.rpm, *.AppImage` |

Prérequis : Swift 6.4.2 de swift.org (swiftly) et son SDK WebAssembly, Node 22, Rust, et pour
Linux un moteur de conteneurs (colima). Le flux `.github/workflows/windows-linux.yml` fait la même
chose sur GitHub Actions.
