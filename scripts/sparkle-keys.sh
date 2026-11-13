#!/bin/bash
#
# Inscrit la clé publique EdDSA de Sparkle dans Support/Info.plist (SUPublicEDKey).
#
# La clé est celle du trousseau de session (élément « Private key for signing Sparkle
# updates ») : la même que pour les autres applis Aervorn. Si elle n'existe pas encore,
# generate_keys la crée. Sauvegarde-la (scripts/sparkle-keys.sh --export) : sans elle,
# les apps déjà installées refuseront toutes les mises à jour suivantes.
#
# Prérequis : Xcode (pour télécharger le paquet Sparkle)

set -euo pipefail
cd "$(dirname "$0")/.."

SPM="build/spm"
BIN="$SPM/artifacts/sparkle/Sparkle/bin"
PLIST="Support/Info.plist"

if [ ! -x "$BIN/generate_keys" ]; then
    xcodebuild -resolvePackageDependencies -project Navloom.xcodeproj -scheme Navloom \
        -clonedSourcePackagesDirPath "$SPM" -quiet
fi

if [ "${1:-}" = "--export" ]; then
    OUT="$HOME/Desktop/sparkle-private-key.txt"
    "$BIN/generate_keys" -x "$OUT"
    echo "Clé privée exportée dans $OUT : range-la dans ton gestionnaire de mots de passe, puis supprime le fichier."
    exit 0
fi

# Crée la clé si elle n'existe pas encore, sinon affiche la clé publique existante
"$BIN/generate_keys" >/dev/null
PUBLIC=$("$BIN/generate_keys" -p)
[ -n "$PUBLIC" ] || { echo "Impossible de lire la clé publique." >&2; exit 1; }

/usr/libexec/PlistBuddy -c "Set :SUPublicEDKey $PUBLIC" "$PLIST"
echo "Clé publique : $PUBLIC"
echo "$PLIST mis à jour."
