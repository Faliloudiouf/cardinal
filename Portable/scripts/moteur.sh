#!/bin/zsh
# Compile le moteur Swift en WebAssembly et le copie dans l'interface (app/public/cardinal.wasm).
# Prérequis : chaîne Swift 6.4.2 de swift.org (swiftly) et son SDK WebAssembly.
set -e
cd "$(dirname "$0")/../moteur"
[ -f ~/.swiftly/env.sh ] && . ~/.swiftly/env.sh
swift build --swift-sdk swift-6.4.2-RELEASE_wasm -c release
SORTIE=../app/public/cardinal.wasm
if command -v wasm-opt >/dev/null; then
  wasm-opt -Oz --enable-bulk-memory --enable-sign-ext --enable-nontrapping-float-to-int --enable-mutable-globals \
    --strip-debug --strip-producers .build/release/CardinalWasm.wasm -o "$SORTIE"
else
  cp .build/release/CardinalWasm.wasm "$SORTIE"
fi
ls -lh "$SORTIE"
