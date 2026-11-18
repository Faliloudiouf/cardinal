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
STAGE=$(mktemp -d)
ditto $APP "$STAGE/Cardinal.app"
ln -s /Applications "$STAGE/Applications"
DMG=dist/Cardinal-$VERSION.dmg
rm -f $DMG
hdiutil create -volname "Cardinal $VERSION" -srcfolder "$STAGE" -ov -format UDZO -fs HFS+ $DMG >/dev/null
rm -rf "$STAGE"
# La copie de travail ne doit pas apparaître dans la liste des applications.
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -u $APP 2>/dev/null || true
shasum -a 256 $DMG | tee $DMG.sha256
ls -lh $DMG
