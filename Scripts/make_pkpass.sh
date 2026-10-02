#!/usr/bin/env bash
#
# make_pkpass.sh — sign a Bug Coffee loyalty pass into a distributable .pkpass.
#
# A .pkpass must be signed with your Apple "Pass Type ID" certificate + Apple's
# WWDR intermediate certificate. This does the manifest + PKCS#7 signing + zip
# using only `openssl` and `zip` (both ship with macOS). The QR is your Firebase
# UID, which is stable, so you normally run this once.
#
# You can either point it at an unsigned bundle exported from the app, or let it
# build the bundle from scratch given a UID.
#
# Usage:
#   # From a bundle the app exported (unzip the shared file first):
#   ./make_pkpass.sh --bundle ./BugCoffee.pass
#
#   # Or build from a UID directly (uses PassTemplate/ images):
#   ./make_pkpass.sh --uid <FIREBASE_UID> --email you@example.com --name "Иван Иванов"
#
# Required env / files (edit the CONFIG block or export before running).
# Defaults are resolved relative to this script, so it works from the repo root:
#   PASS_CERT   PEM of your Pass Type ID certificate      (default: Scripts/certs/passcert.pem)
#   PASS_KEY    PEM of the matching private key           (default: Scripts/certs/passkey.pem)
#   WWDR_CERT   PEM of Apple WWDR intermediate cert       (default: Scripts/certs/wwdr.pem)
#   TEMPLATE_DIR  dir with icon.png/logo.png images       (default: PassTemplate/)
#   PASS_TYPE_ID / TEAM_ID  must match your certificate
#
# Getting the PEMs from a .p12 you exported from Keychain:
#   openssl pkcs12 -in Certificates.p12 -clcerts -nokeys -out certs/passcert.pem -legacy
#   openssl pkcs12 -in Certificates.p12 -nocerts -nodes  -out certs/passkey.pem  -legacy
# Getting Apple WWDR (download AppleWWDRCAG3.cer from Apple, then):
#   openssl x509 -inform DER -in AppleWWDRCAG3.cer -out certs/wwdr.pem
#
set -euo pipefail

# Resolve paths relative to this script (not the caller's CWD) so it works when
# run as ./Scripts/make_pkpass.sh from the repo root.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Apple Wallet requires at least icon.png; @2x/@3x and the logo are recommended.
REQUIRED_IMAGES=(icon.png)
TEMPLATE_IMAGES=(icon.png icon@2x.png icon@3x.png logo.png logo@2x.png)

# ---- CONFIG ------------------------------------------------------------------
PASS_TYPE_ID="${PASS_TYPE_ID:-pass.com.zerogravityroom.bugwallet}"
TEAM_ID="${TEAM_ID:-4F5J749858}"
ORG_NAME="${ORG_NAME:-Bug Coffee}"
PASS_CERT="${PASS_CERT:-$SCRIPT_DIR/certs/passcert.pem}"
PASS_KEY="${PASS_KEY:-$SCRIPT_DIR/certs/passkey.pem}"
WWDR_CERT="${WWDR_CERT:-$SCRIPT_DIR/certs/wwdr.pem}"
KEY_PASS="${KEY_PASS:-}"   # private-key passphrase, if any
TEMPLATE_DIR="${TEMPLATE_DIR:-$SCRIPT_DIR/../PassTemplate}"
OUT="${OUT:-BugCoffee.pkpass}"
# -----------------------------------------------------------------------------

BUNDLE=""
UID_ARG=""
EMAIL="member"
NAME=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --bundle) BUNDLE="$2"; shift 2 ;;
    --uid)    UID_ARG="$2"; shift 2 ;;
    --email)  EMAIL="$2"; shift 2 ;;
    --name)   NAME="$2"; shift 2 ;;
    --out)    OUT="$2"; shift 2 ;;
    *) echo "Unknown arg: $1" >&2; exit 1 ;;
  esac
done

for f in "$PASS_CERT" "$PASS_KEY" "$WWDR_CERT"; do
  [[ -f "$f" ]] || { echo "Missing required cert file: $f" >&2; exit 1; }
done

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

if [[ -n "$BUNDLE" ]]; then
  cp -R "$BUNDLE"/. "$WORK"/
else
  [[ -n "$UID_ARG" ]] || { echo "Provide --bundle or --uid" >&2; exit 1; }
  # Show the holder's name next to the membership e-mail when one is given.
  NAME_FIELD=""
  [[ -n "$NAME" ]] && NAME_FIELD="{ \"key\": \"name\", \"label\": \"ИМЕ\", \"value\": \"$NAME\" }, "
  # Build pass.json from the UID.
  cat > "$WORK/pass.json" <<JSON
{
  "formatVersion": 1,
  "passTypeIdentifier": "$PASS_TYPE_ID",
  "teamIdentifier": "$TEAM_ID",
  "organizationName": "$ORG_NAME",
  "description": "Bug Coffee Loyalty Card",
  "serialNumber": "$UID_ARG",
  "storeCard": {
    "headerFields": [{ "key": "program", "label": "BUG COFFEE", "value": "Loyalty" }],
    "primaryFields": [{ "key": "stamps", "label": "ПЕЧАТИ", "value": "0 / 9" }],
    "secondaryFields": [$NAME_FIELD{ "key": "member", "label": "ЧЛЕН", "value": "$EMAIL" }]
  },
  "barcodes": [{ "format": "PKBarcodeFormatQR", "message": "$UID_ARG", "messageEncoding": "iso-8859-1" }],
  "locations": [{ "latitude": 42.69323, "longitude": 23.34402, "relevantText": "Bug Coffee е наблизо" }],
  "maxDistance": 15,
  "backgroundColor": "rgb(31, 4, 9)",
  "foregroundColor": "rgb(255, 255, 255)",
  "labelColor": "rgb(204, 30, 65)"
}
JSON
  # Copy the pass images. Fail loudly if the template dir is missing — a
  # silent skip here is exactly what produces an icon-less, unusable pass.
  [[ -d "$TEMPLATE_DIR" ]] || {
    echo "Template image dir not found: $TEMPLATE_DIR" >&2
    echo "Set TEMPLATE_DIR=... to point at your icon.png/logo.png images." >&2
    exit 1
  }
  for img in "${TEMPLATE_IMAGES[@]}"; do
    [[ -f "$TEMPLATE_DIR/$img" ]] && cp "$TEMPLATE_DIR/$img" "$WORK/$img"
  done
fi

[[ -f "$WORK/pass.json" ]] || { echo "No pass.json in bundle." >&2; exit 1; }

# Wallet rejects a pass without icon.png — verify before we sign.
for img in "${REQUIRED_IMAGES[@]}"; do
  [[ -f "$WORK/$img" ]] || {
    echo "Pass is missing required image '$img'." >&2
    echo "Add it to $TEMPLATE_DIR (or the --bundle dir) and re-run." >&2
    exit 1
  }
done

# 1. manifest.json — SHA1 of every file in the bundle.
python3 - "$WORK" <<'PY'
import hashlib, json, os, sys
work = sys.argv[1]
manifest = {}
for name in sorted(os.listdir(work)):
    p = os.path.join(work, name)
    if name in ("manifest.json", "signature") or not os.path.isfile(p):
        continue
    with open(p, "rb") as f:
        manifest[name] = hashlib.sha1(f.read()).hexdigest()
with open(os.path.join(work, "manifest.json"), "w") as f:
    json.dump(manifest, f)
PY

# 2. signature — detached PKCS#7 (DER) over manifest.json.
PASSIN=()
[[ -n "$KEY_PASS" ]] && PASSIN=(-passin "pass:$KEY_PASS")
openssl smime -binary -sign \
  -certfile "$WWDR_CERT" \
  -signer "$PASS_CERT" \
  -inkey "$PASS_KEY" \
  ${PASSIN[@]+"${PASSIN[@]}"} \
  -in "$WORK/manifest.json" \
  -out "$WORK/signature" \
  -outform DER

# 3. zip it up as the .pkpass. Resolve OUT to an absolute path first so the
# `cd "$WORK"` below doesn't change where it lands.
case "$OUT" in
  /*) OUT_ABS="$OUT" ;;
  *)  OUT_ABS="$PWD/$OUT" ;;
esac
rm -f "$OUT_ABS"
( cd "$WORK" && zip -q -r -X "$OUT_ABS" . -x '.*' )

echo "Wrote $OUT_ABS"
echo "AirDrop or email it to your iPhone and tap to add to Wallet."
