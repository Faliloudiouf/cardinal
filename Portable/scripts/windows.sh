#!/bin/zsh
# Construit l'installateur Windows (.exe NSIS) depuis le Mac, par compilation croisée.
# Prérequis : brew install nsis llvm ; rustup target add x86_64-pc-windows-msvc ; cargo install cargo-xwin
# makensis plante avec une locale « C » : on force une locale UTF-8.
set -e
cd "$(dirname "$0")/../app"
export LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8
export PATH="/opt/homebrew/opt/llvm/bin:/opt/homebrew/opt/rustup/bin:$HOME/.cargo/bin:$PATH"
npx tauri build --runner cargo-xwin --target x86_64-pc-windows-msvc --bundles nsis
mkdir -p ../sortie
cp src-tauri/target/x86_64-pc-windows-msvc/release/bundle/nsis/*.exe ../sortie/
shasum -a 256 ../sortie/*.exe
