#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

APP_NAME="Quillside"
VERSION="$(tr -d '[:space:]' < "$PROJECT_DIR/VERSION")"
APP_BUNDLE="$PROJECT_DIR/build/$APP_NAME.app"
DIST_DIR="$PROJECT_DIR/dist"
PACKAGE_SIGN_IDENTITY="${OPENNOTES_CODE_SIGN_IDENTITY:-}"
NOTARY_PROFILE="${OPENNOTES_NOTARY_PROFILE:-}"

if [[ -z "$PACKAGE_SIGN_IDENTITY" ]]; then
    PACKAGE_SIGN_IDENTITY="$(
        security find-identity -v -p codesigning |
            awk '/"Developer ID Application:/{print $2; exit}'
    )"
fi

if [[ "$PACKAGE_SIGN_IDENTITY" != "-" ]] && ! security find-identity -v -p codesigning | grep -F "$PACKAGE_SIGN_IDENTITY" | grep -q 'Developer ID Application:'; then
    echo "Error: public distribution requires a Developer ID Application identity."
    exit 1
fi

if [[ -z "$PACKAGE_SIGN_IDENTITY" ]]; then
    echo "Error: Developer ID Application identity not found."
    echo "Set OPENNOTES_CODE_SIGN_IDENTITY explicitly to override."
    exit 1
fi

if [[ "$PACKAGE_SIGN_IDENTITY" != "-" && -z "$NOTARY_PROFILE" ]]; then
    echo "Error: Developer ID release requires OPENNOTES_NOTARY_PROFILE."
    echo "Use OPENNOTES_CODE_SIGN_IDENTITY=- only for an explicit local test package."
    exit 1
fi

case "$(uname -m)" in
    arm64)
        ARCH="arm64"
        ;;
    x86_64)
        ARCH="x86_64"
        ;;
    *)
        echo "Error: unsupported architecture: $(uname -m)"
        exit 1
        ;;
esac

DMG_NAME="$APP_NAME-$VERSION-macOS-$ARCH.dmg"
DMG_PATH="$DIST_DIR/$DMG_NAME"
STAGING_DIR="$(mktemp -d "${TMPDIR:-/private/tmp}/opennotes-dmg.XXXXXX")"

cleanup() {
    case "$STAGING_DIR" in
        "${TMPDIR:-/private/tmp}"/opennotes-dmg.*)
            rm -rf "$STAGING_DIR"
            ;;
    esac
}
trap cleanup EXIT

echo "==> Building signed app bundle..."
OPENNOTES_CODE_SIGN_IDENTITY="$PACKAGE_SIGN_IDENTITY" \
    "$SCRIPT_DIR/bundle-app.sh" release

echo "==> Preparing DMG contents..."
mkdir -p "$DIST_DIR"
ditto "$APP_BUNDLE" "$STAGING_DIR/$APP_NAME.app"
ln -s /Applications "$STAGING_DIR/Applications"

echo "==> Creating $DMG_NAME..."
hdiutil create \
    -volname "$APP_NAME" \
    -srcfolder "$STAGING_DIR" \
    -ov \
    -format UDZO \
    "$DMG_PATH"

if [[ "$PACKAGE_SIGN_IDENTITY" != "-" ]]; then
    echo "==> Signing disk image..."
    codesign \
        --force \
        --sign "$PACKAGE_SIGN_IDENTITY" \
        --timestamp \
        "$DMG_PATH"
    codesign --verify --verbose=2 "$DMG_PATH"
fi

echo "==> Verifying disk image..."
hdiutil verify "$DMG_PATH"

if [[ -n "$NOTARY_PROFILE" ]]; then
    echo "==> Submitting disk image for notarization..."
    xcrun notarytool submit "$DMG_PATH" \
        --keychain-profile "$NOTARY_PROFILE" \
        --wait --output-format json > "$STAGING_DIR/notarization-result.json"

    python3 - "$STAGING_DIR/notarization-result.json" "$DIST_DIR/notarization.json" <<'PY'
import json,sys
from pathlib import Path
result=json.loads(Path(sys.argv[1]).read_text())
if result.get('status') != 'Accepted': raise SystemExit('Notarization was not accepted; no release was produced')
Path(sys.argv[2]).write_text(json.dumps({'id':result['id'],'status':'Accepted'},indent=2)+'\n')
PY

    echo "==> Stapling notarization ticket..."
    xcrun stapler staple "$DMG_PATH"
    xcrun stapler validate "$DMG_PATH"
fi

(
    cd "$DIST_DIR"
    shasum -a 256 "$DMG_NAME" > "$DMG_NAME.sha256"
)
chmod 644 "$DMG_PATH" "$DMG_PATH.sha256"

echo ""
echo "DMG:      $DMG_PATH"
echo "Checksum: $DMG_PATH.sha256"
