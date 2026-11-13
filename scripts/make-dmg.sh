#!/bin/bash
#
# Fabrique dist/Navloom-<version>.dmg, prêt à publier :
#   1. archive Release, signée avec le certificat auto-signé ;
#   2. vérifie que la signature n'est pas ad-hoc (sinon les autorisations sautent à chaque version) ;
#   3. crée le DMG avec sa fenêtre d'installation (fond, icônes placées, raccourci Applications) ;
#   4. signe le DMG et prépare les notes de version (changelog du README + SHA-256) ;
#   5. signe le DMG pour Sparkle (EdDSA) et réécrit appcast.xml.
#
# Prérequis : brew install create-dmg
# Usage     : ./scripts/make-dmg.sh   (depuis n'importe où)
#
# La première fois, macOS demande d'autoriser le Terminal à piloter le Finder :
# create-dmg s'en sert pour placer les icônes dans la fenêtre. Accepte.

set -euo pipefail
cd "$(dirname "$0")/.."

IDENTITY="Aervorn Code Signing"
BUILD="build/release"
ARCHIVE="$BUILD/Navloom.xcarchive"
STAGE="$BUILD/dmg"
BACKGROUND="$BUILD/background.tiff"
# Paquets Swift (Sparkle) hors de $BUILD, pour ne pas les retélécharger à chaque fois
SPM="build/spm"
SPARKLE_BIN="$SPM/artifacts/sparkle/Sparkle/bin"
REPO="Aervorn/MacOS_Navloom"

step() { printf '\n\033[1;35m▸ %s\033[0m\n' "$1"; }
fail() { printf '\n\033[1;31m✗ %s\033[0m\n' "$1" >&2; exit 1; }

command -v create-dmg >/dev/null || fail "create-dmg est introuvable. Installe-le avec : brew install create-dmg"
security find-identity -p codesigning | grep -q "$IDENTITY" \
    || fail "Certificat « $IDENTITY » introuvable dans le trousseau."

step "Archive Release"
rm -rf "$BUILD"
mkdir -p "$BUILD" dist
# « generic » : app universelle (Apple Silicon + Intel), comme « Any Mac » dans Xcode.
xcodebuild -project Navloom.xcodeproj -scheme Navloom -configuration Release \
    -destination "generic/platform=macOS" \
    -archivePath "$ARCHIVE" -clonedSourcePackagesDirPath "$SPM" archive -quiet

APP="$ARCHIVE/Products/Applications/Navloom.app"
[ -d "$APP" ] || fail "Navloom.app introuvable dans l'archive."
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$APP/Contents/Info.plist")
BUILD_NUMBER=$(/usr/libexec/PlistBuddy -c "Print CFBundleVersion" "$APP/Contents/Info.plist")
echo "Navloom $VERSION (build $BUILD_NUMBER)"
echo "Architectures : $(lipo -archs "$APP/Contents/MacOS/Navloom")"

# La clé publique embarquée doit correspondre à la clé privée du trousseau,
# sinon les apps installées refuseraient la mise à jour.
[ -x "$SPARKLE_BIN/sign_update" ] || fail "Outils Sparkle introuvables dans $SPARKLE_BIN."
APP_KEY=$(/usr/libexec/PlistBuddy -c "Print SUPublicEDKey" "$APP/Contents/Info.plist" 2>/dev/null || true)
KEYCHAIN_KEY=$("$SPARKLE_BIN/generate_keys" -p 2>/dev/null || true)
[ -n "$APP_KEY" ] && [ "$APP_KEY" = "$KEYCHAIN_KEY" ] \
    || fail "SUPublicEDKey de l'app ($APP_KEY) ≠ clé du trousseau ($KEYCHAIN_KEY). Lance ./scripts/sparkle-keys.sh"

step "Vérification de la signature"
codesign --verify --strict --deep "$APP" || fail "La signature de l'app est invalide."
REQUIREMENT=$(codesign -d -r- "$APP" 2>&1 | grep "designated" || true)
echo "$REQUIREMENT"
[[ "$REQUIREMENT" == *"certificate leaf"* ]] \
    || fail "L'app n'est pas signée avec le certificat : les utilisateurs perdraient leurs autorisations à chaque version."

step "Fond de la fenêtre (1x + Retina)"
tiffutil -cathidpicheck Design/dmg/background.png Design/dmg/background@2x.png -out "$BACKGROUND"

step "Création du DMG"
mkdir -p "$STAGE"
ditto "$APP" "$STAGE/Navloom.app"
DMG="dist/Navloom-$VERSION.dmg"
rm -f "$DMG"

VOLICON=()
[ -f "$APP/Contents/Resources/AppIcon.icns" ] && VOLICON=(--volicon "$APP/Contents/Resources/AppIcon.icns")

# Fenêtre de 660 × 400 points de contenu (la hauteur inclut la barre de titre).
# Les positions des icônes correspondent à la flèche dessinée dans le fond.
create-dmg \
    --volname "Navloom $VERSION" \
    ${VOLICON[@]+"${VOLICON[@]}"} \
    --background "$BACKGROUND" \
    --window-pos 200 120 \
    --window-size 660 428 \
    --icon-size 128 \
    --text-size 13 \
    --icon "Navloom.app" 180 200 \
    --hide-extension "Navloom.app" \
    --app-drop-link 480 200 \
    "$DMG" "$STAGE"

step "Signature du DMG"
codesign --sign "$IDENTITY" "$DMG"
codesign --verify "$DMG"

step "Notes de version"
SHA=$(shasum -a 256 "$DMG" | cut -d' ' -f1)
NOTES="dist/Navloom-$VERSION-notes.md"
# Section « ### <version> » du changelog du README anglais
CHANGES=$(awk -v v="### $VERSION" '$0 == v {on=1; next} on && /^##/ {exit} on' README.md)
[ -n "$CHANGES" ] || fail "Pas de section « ### $VERSION » dans le changelog de README.md."
cat > "$NOTES" <<NOTES_EOF
## What's new

$CHANGES

## Installation

Download \`Navloom-$VERSION.dmg\` below, open it and drag **Navloom** onto **Applications**.

> [!WARNING]
> Navloom isn't notarized by Apple: the first time, macOS blocks it. Open **System Settings › Privacy & Security** and click **Open Anyway** next to the message about Navloom. Details in the [README](https://github.com/$REPO#-installation).

**SHA-256:** \`$SHA\`
NOTES_EOF
echo "$(pwd)/$NOTES"

step "Mise à jour Sparkle (appcast.xml)"
# Signe les octets du DMG avec la clé privée du trousseau : sparkle:edSignature="…" length="…"
ED_ATTRS=$("$SPARKLE_BIN/sign_update" "$DMG")
[[ "$ED_ATTRS" == *edSignature* ]] || fail "Signature Sparkle impossible : $ED_ATTRS"
MIN_OS=$(/usr/libexec/PlistBuddy -c "Print LSMinimumSystemVersion" "$APP/Contents/Info.plist")
PUB_DATE=$(LC_ALL=C date -u "+%a, %d %b %Y %H:%M:%S +0000")

# Changelog d'un README (section « ### <version> ») converti en HTML simple pour la fenêtre de Sparkle
changelog_html() {
    awk -v v="### $VERSION" '$0 == v {on=1; next} on && /^##/ {exit} on && /^- / {sub(/^- /, ""); print}' "$1" \
        | sed -E 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g; s/\*\*([^*]+)\*\*/<b>\1<\/b>/g; s/`([^`]+)`/<code>\1<\/code>/g; s/\[([^]]+)\]\(([^)]+)\)/<a href="\2">\1<\/a>/g; s/^(.*)$/<li>\1<\/li>/'
}
NOTES_EN="<ul>$(changelog_html README.md)</ul>"
NOTES_FR="<ul>$(changelog_html README.fr.md)</ul>"

# Une seule entrée suffit : Sparkle ne regarde que la version la plus récente
cat > appcast.xml <<APPCAST_EOF
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Navloom</title>
    <link>https://github.com/$REPO</link>
    <item>
      <title>Navloom $VERSION</title>
      <pubDate>$PUB_DATE</pubDate>
      <sparkle:version>$BUILD_NUMBER</sparkle:version>
      <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>$MIN_OS</sparkle:minimumSystemVersion>
      <description><![CDATA[$NOTES_EN]]></description>
      <description xml:lang="fr"><![CDATA[$NOTES_FR]]></description>
      <enclosure url="https://github.com/$REPO/releases/download/v$VERSION/Navloom-$VERSION.dmg" type="application/octet-stream" $ED_ATTRS />
    </item>
  </channel>
</rss>
APPCAST_EOF
xmllint --noout appcast.xml 2>/dev/null || true
echo "$(pwd)/appcast.xml"

step "Terminé"
echo "$(pwd)/$DMG"
echo "SHA-256 : $SHA"
echo
echo "Pour publier, dans cet ordre (les apps installées lisent appcast.xml sur la branche main) :"
echo "  1. gh release create v$VERSION \"$DMG\" --title \"Navloom $VERSION\" --notes-file \"$NOTES\""
echo "  2. git add appcast.xml && git commit -m \"Appcast $VERSION\" && git push"
