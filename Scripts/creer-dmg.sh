#!/bin/zsh
# Fabrique l'image disque d'installation de Cardinal (dist/Cardinal-<version>.dmg) :
# l'app compilée en version finale (Apple Silicon + Intel) et un raccourci vers Applications.
set -e
cd "$(dirname "$0")/.."
xcodegen generate >/dev/null
mkdir -p build.noindex dist
xcodebuild -project Cardinal.xcodeproj -scheme Cardinal -configuration Release -derivedDataPath build.noindex build \
  | grep -E "error:|BUILD (SUCCEEDED|FAILED)"
APP=build.noindex/Build/Products/Release/Cardinal.app
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" $APP/Contents/Info.plist)
DMG=dist/Cardinal-$VERSION.dmg
rm -f $DMG
# Fenêtre d'installation soignée (fond, icônes placées) : dmgbuild écrit la mise en page Finder
# sans piloter Finder. Il s'installe une fois dans un environnement Python local.
VENV=build.noindex/venv-dmg
[ -x $VENV/bin/dmgbuild ] || { python3 -m venv $VENV && $VENV/bin/pip install -q dmgbuild; }
( cd Scripts/dmg && swift fond.swift "$VERSION" && tiffutil -cathidpicheck fond.png fond@2x.png -out fond.tiff >/dev/null )
$VENV/bin/dmgbuild -s Scripts/dmg/reglages.py -D app="$PWD/$APP" -D fond="$PWD/Scripts/dmg/fond.tiff" "Cardinal $VERSION" $DMG >/dev/null
# La copie de travail ne doit pas apparaître dans la liste des applications.
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -u $APP 2>/dev/null || true
shasum -a 256 $DMG | tee $DMG.sha256
ls -lh $DMG
