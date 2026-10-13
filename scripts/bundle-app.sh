#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

APP_NAME="Quillside"
BUNDLE_ID="com.opennotes.app"
VERSION="$(tr -d '[:space:]' < "$PROJECT_DIR/VERSION")"
BUILD_NUMBER="$(tr -d '[:space:]' < "$PROJECT_DIR/BUILD_NUMBER")"
BUILD_TYPE="${1:-release}"
CODE_SIGN_IDENTITY="${OPENNOTES_CODE_SIGN_IDENTITY:-}"
LOCAL_SIGNING_CONFIG="$HOME/Library/Application Support/OpenNotesDevelopmentSigning/identity.json"

if [[ "$BUILD_TYPE" != "debug" && "$BUILD_TYPE" != "release" ]]; then
    echo "Usage: $0 [debug|release]"
    echo "  debug   - Build debug version"
    echo "  release - Build release version (default)"
    exit 1
fi

echo "==> Building $BUILD_TYPE version..."
cd "$PROJECT_DIR"

if [[ "$BUILD_TYPE" == "release" ]]; then
    BIN_DIR="$(swift build --disable-sandbox -c release --show-bin-path)"
    swift build --disable-sandbox -c release
else
    BIN_DIR="$(swift build --disable-sandbox --show-bin-path)"
    swift build --disable-sandbox
fi
BINARY_PATH="$BIN_DIR/$APP_NAME"

if [[ ! -f "$BINARY_PATH" ]]; then
    echo "Error: Binary not found at $BINARY_PATH"
    exit 1
fi

APP_BUNDLE="$PROJECT_DIR/build/$APP_NAME.app"
CONTENTS_DIR="$APP_BUNDLE/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
ENTITLEMENTS_PATH="$PROJECT_DIR/resources/Quillside.entitlements"

echo "==> Creating app bundle at $APP_BUNDLE"
if [[ -d "$APP_BUNDLE" ]]; then
    # Preserve the top-level app bundle so macOS privacy grants keep pointing
    # at the same filesystem object across rebuilds.
    rm -rf "$CONTENTS_DIR"
fi
mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES_DIR"

echo "==> Copying binary..."
cp "$BINARY_PATH" "$MACOS_DIR/$APP_NAME"
chmod 755 "$MACOS_DIR/$APP_NAME"

python3 "$SCRIPT_DIR/prepare-pi-runtime.py"
mkdir -p "$RESOURCES_DIR/PiRuntime"
cp "$PROJECT_DIR/build/pi-runtime/node" "$RESOURCES_DIR/PiRuntime/node"
cp "$PROJECT_DIR/build/pi-runtime/worker.mjs" "$PROJECT_DIR/build/pi-runtime/package.json" "$RESOURCES_DIR/PiRuntime/"
ditto "$PROJECT_DIR/licenses/pi-runtime" "$RESOURCES_DIR/Licenses/PiRuntime"

ICON_PATH="$PROJECT_DIR/resources/AppIcon.icns"
if [[ ! -f "$ICON_PATH" ]]; then
    echo "==> AppIcon.icns missing; generating it..."
    "$SCRIPT_DIR/create-icon.sh"
fi
cp "$ICON_PATH" "$RESOURCES_DIR/AppIcon.icns"
cp "$PROJECT_DIR/resources/Brand/Quillside-Mark.png" "$RESOURCES_DIR/Quillside-Mark.png"
cp "$PROJECT_DIR/resources/Brand/MenuBarTemplate.png" "$RESOURCES_DIR/MenuBarTemplate.png"

# Licenses are distributed with the app without becoming product marketing.
mkdir -p "$RESOURCES_DIR/Licenses"
cp "$PROJECT_DIR/LICENSE" "$RESOURCES_DIR/Licenses/LICENSE"
cp "$PROJECT_DIR/THIRD_PARTY_NOTICES.md" "$RESOURCES_DIR/Licenses/THIRD_PARTY_NOTICES.md"
cp "$PROJECT_DIR"/licenses/*-MIT.txt "$RESOURCES_DIR/Licenses/"
cp "$PROJECT_DIR/licenses/manifest.json" "$RESOURCES_DIR/Licenses/manifest.json"
ditto "$PROJECT_DIR/resources/Skills" "$RESOURCES_DIR/Skills"

echo "==> Creating Info.plist..."
cat > "$CONTENTS_DIR/Info.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIconName</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundleDisplayName</key>
    <string>$APP_NAME</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundleVersion</key>
    <string>$BUILD_NUMBER</string>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.productivity</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSAppTransportSecurity</key>
    <dict><key>NSAllowsLocalNetworking</key><true/></dict>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>NSAppleEventsUsageDescription</key>
    <string>Quillside uses Notes automation only after you request an action that needs the current note.</string>
</dict>
</plist>
EOF

echo "==> Creating PkgInfo..."
echo -n "APPL????" > "$CONTENTS_DIR/PkgInfo"

if [[ -z "$CODE_SIGN_IDENTITY" && -f "$LOCAL_SIGNING_CONFIG" ]]; then
    python3 "$SCRIPT_DIR/sign-local-development.py" --check
    CODE_SIGN_IDENTITY="local-development"
fi

if [[ -z "$CODE_SIGN_IDENTITY" ]]; then
    CODE_SIGN_IDENTITY="$(
        security find-identity -v -p codesigning |
            awk '/"Apple Development:/{print $2; exit}'
    )"
fi

if [[ -z "$CODE_SIGN_IDENTITY" ]]; then
    CODE_SIGN_IDENTITY="-"
    echo "==> No Apple Development identity found; using ad-hoc signing."
    echo "    macOS privacy permissions may need to be granted again after rebuilding."
fi

echo "==> Signing app bundle..."
SIGN_ARGS=(
    --force
    --sign "$CODE_SIGN_IDENTITY"
    --identifier "$BUNDLE_ID"
)

if [[ -f "$ENTITLEMENTS_PATH" ]]; then
    SIGN_ARGS+=(--entitlements "$ENTITLEMENTS_PATH")
fi

NODE_SIGN_ARGS=(--force --sign "$CODE_SIGN_IDENTITY" --identifier com.quillside.pi-node)
if [[ "$CODE_SIGN_IDENTITY" != "-" ]] &&
   security find-identity -v -p codesigning |
       grep -F "$CODE_SIGN_IDENTITY" |
       grep -q "Developer ID Application:"; then
    SIGN_ARGS+=(--options runtime --timestamp)
    NODE_SIGN_ARGS+=(--options runtime --timestamp --entitlements "$PROJECT_DIR/resources/PiRuntime.entitlements")
fi

if [[ "$CODE_SIGN_IDENTITY" == "local-development" ]]; then
    python3 "$SCRIPT_DIR/sign-local-development.py" --identifier com.quillside.pi-node "$RESOURCES_DIR/PiRuntime/node"
    LOCAL_SIGN_ARGS=(--identifier "$BUNDLE_ID")
    if [[ -f "$ENTITLEMENTS_PATH" ]]; then LOCAL_SIGN_ARGS+=(--entitlements "$ENTITLEMENTS_PATH"); fi
    python3 "$SCRIPT_DIR/sign-local-development.py" "${LOCAL_SIGN_ARGS[@]}" "$APP_BUNDLE"
else
    codesign "${NODE_SIGN_ARGS[@]}" "$RESOURCES_DIR/PiRuntime/node"
    codesign "${SIGN_ARGS[@]}" "$APP_BUNDLE"
fi
codesign --verify --deep --strict "$APP_BUNDLE"

echo ""
echo "=========================================="
echo "  App bundle created successfully!"
echo "=========================================="
echo ""
echo "Location: $APP_BUNDLE"
echo "Signing identity: $CODE_SIGN_IDENTITY"
echo ""
echo "To run:"
echo "  open \"$APP_BUNDLE\""
echo ""
echo "To grant Accessibility permission:"
echo "  1. Open System Settings"
echo "  2. Go to Privacy & Security → Accessibility"
echo "  3. Click '+' and add $APP_NAME.app"
echo "  4. Or drag $APP_NAME.app into the list"
echo ""
echo "To install to Applications:"
echo "  cp -R \"$APP_BUNDLE\" /Applications/"
echo ""
