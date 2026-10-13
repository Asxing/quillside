#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
RESOURCES_DIR="$PROJECT_DIR/resources"
WORK_DIR="$(mktemp -d "${TMPDIR:-/private/tmp}/opennotes-icon.XXXXXX")"
ICONSET_DIR="$WORK_DIR/AppIcon.iconset"
MASTER_PNG="$RESOURCES_DIR/AppIcon-1024.png"
ICNS_PATH="$RESOURCES_DIR/AppIcon.icns"

cleanup() {
    case "$WORK_DIR" in
        "${TMPDIR:-/private/tmp}"/opennotes-icon.*)
            rm -rf "$WORK_DIR"
            ;;
    esac
}
trap cleanup EXIT

mkdir -p "$RESOURCES_DIR" "$ICONSET_DIR"

swift "$SCRIPT_DIR/generate-icon.swift" "$MASTER_PNG"

create_size() {
    local pixels="$1"
    local output="$2"
    sips -z "$pixels" "$pixels" "$MASTER_PNG" --out "$ICONSET_DIR/$output" >/dev/null
}

create_size 16 icon_16x16.png
create_size 32 icon_16x16@2x.png
create_size 32 icon_32x32.png
create_size 64 icon_32x32@2x.png
create_size 128 icon_128x128.png
create_size 256 icon_128x128@2x.png
create_size 256 icon_256x256.png
create_size 512 icon_256x256@2x.png
create_size 512 icon_512x512.png
create_size 1024 icon_512x512@2x.png

swift "$SCRIPT_DIR/pack-icns.swift" "$ICONSET_DIR" "$ICNS_PATH"
chmod 644 "$MASTER_PNG" "$ICNS_PATH"

echo "App icon generated:"
echo "  $MASTER_PNG"
echo "  $ICNS_PATH"
