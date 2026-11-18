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
    rsync_like() { tar -C /source --exclude=node_modules --exclude=src-tauri/target --exclude=dist -cf - . | tar -C /travail -xf -; }
    rsync_like
    npm ci --no-audit --no-fund
    CARGO_TARGET_DIR=/cible npx tauri build --bundles deb,rpm,appimage
    rm -rf /sortie/* && cp /cible/release/bundle/deb/*.deb /cible/release/bundle/rpm/*.rpm /cible/release/bundle/appimage/*.AppImage /sortie/
    ls -la /sortie'
