#!/bin/zsh
# Construit les paquets Linux (.deb, .rpm, .AppImage) dans un conteneur, depuis le Mac.
# Prérequis : colima (ou Docker) et le moteur déjà compilé (Portable/scripts/moteur.sh).
set -e
ICI="$(cd "$(dirname "$0")" && pwd)"
APP="$ICI/../app"
docker build -t cardinal-linux "$ICI"
docker run --rm --platform linux/amd64 \
  -v "$APP:/source:ro" -v cardinal-cargo:/root/.cargo/registry -v cardinal-cible:/cible -v "$ICI/sortie:/sortie" \
  cardinal-linux bash -c '
    set -e
    tar -C /source --exclude=node_modules --exclude=src-tauri/target --exclude=dist -cf - . | tar -C /travail -xf -
    npm ci --no-audit --no-fund
    export CARGO_TARGET_DIR=/cible APPIMAGE_EXTRACT_AND_RUN=1
    npx tauri build --bundles deb,rpm
    # Les outils AppImage sont eux-mêmes des AppImage, qui ne démarrent pas dans un conteneur
    # (pas de FUSE). Premier essai pour les télécharger, puis on les remplace par leur contenu extrait.
    npx tauri build --bundles appimage || true
    cd /root/.cache/tauri
    for outil in *.AppImage; do
      mkdir -p /outils && ok=non
      # Le repère « hsqs » apparaît aussi dans le lanceur : on essaie chaque position.
      for decalage in $(grep -obUa hsqs "$outil" | cut -d: -f1); do
        rm -rf "/outils/$outil"
        if unsquashfs -q -d "/outils/$outil" -o "$decalage" "$outil" >/dev/null 2>&1; then ok=oui; break; fi
      done
      [ "$ok" = oui ] || { echo "Extraction impossible : $outil"; exit 1; }
      printf "#!/bin/sh\nexec \"/outils/%s/AppRun\" \"\$@\"\n" "$outil" > "$outil" && chmod +x "$outil"
    done
    cd /travail
    npx tauri build --bundles appimage
    rm -rf /sortie/* && cp /cible/release/bundle/deb/*.deb /cible/release/bundle/rpm/*.rpm /cible/release/bundle/appimage/*.AppImage /sortie/
    ls -la /sortie'
