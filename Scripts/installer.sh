#!/bin/zsh
# Compile Cardinal en version finale et l'installe dans /Applications.
# Les copies de travail (dossier build) sont retirées de la liste des applications de macOS,
# pour qu'un seul « Cardinal » apparaisse dans le Launchpad et le Finder.
set -e
cd "$(dirname "$0")/.."
LSR=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
xcodegen generate >/dev/null
mkdir -p build.noindex   # « .noindex » : Spotlight et le Launchpad ignorent les copies de travail
xcodebuild -project Cardinal.xcodeproj -scheme Cardinal -configuration Release -derivedDataPath build.noindex build \
  | grep -E "error:|BUILD (SUCCEEDED|FAILED)"
osascript -e 'quit app "Cardinal"' 2>/dev/null || true
sleep 1
rm -rf /Applications/Cardinal.app
ditto build.noindex/Build/Products/Release/Cardinal.app /Applications/Cardinal.app
$LSR -f /Applications/Cardinal.app
retirer_copies() {
  for app in build.noindex/Build/Products/*/Cardinal.app(N); do $LSR -u "$app" 2>/dev/null || true; done
}
retirer_copies
echo "Cardinal installé dans /Applications."
