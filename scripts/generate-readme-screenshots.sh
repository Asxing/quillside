#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
OUTPUT_DIR="$PROJECT_DIR/docs/images/regression"

cd "$PROJECT_DIR"

mkdir -p "$OUTPUT_DIR"

task_testing_frameworks="${DEVELOPER_DIR:-/Library/Developer/CommandLineTools}/Library/Developer/Frameworks"
if [[ -n "${DEVELOPER_DIR:-}" && "$DEVELOPER_DIR" != */CommandLineTools ]]; then task_testing_frameworks="$DEVELOPER_DIR/Platforms/MacOSX.platform/Developer/Library/Frameworks"; fi

OPENNOTES_SCREENSHOT_DIR="$OUTPUT_DIR" \
OPENNOTES_PREVIEW_VERSION="$(<"$PROJECT_DIR/VERSION")" \
    swift test --disable-sandbox --disable-xctest --enable-swift-testing \
    -Xswiftc "-F$task_testing_frameworks" \
    -Xswiftc -Xfrontend -Xswiftc -disable-cross-import-overlays \
    -Xlinker -rpath -Xlinker "$task_testing_frameworks" \
    --filter ReadmeScreenshotTests/testGenerateReadmeScreenshots

chmod 644 \
    "$OUTPUT_DIR/backlinks-panel.png" \
    "$OUTPUT_DIR/backlinks-panel-dark.png" \
    "$OUTPUT_DIR/backlinks-permission.png" \
    "$OUTPUT_DIR/floating-format-bar.png" \
    "$OUTPUT_DIR/floating-format-bar-dark.png" \
    "$OUTPUT_DIR/floating-format-bar-reduced-transparency.png" \
    "$OUTPUT_DIR/markdown-shortcuts.png" \
    "$OUTPUT_DIR/menu-bar-status.png" \
    "$OUTPUT_DIR/note-actions-bar.png" \
    "$OUTPUT_DIR/note-actions-bar-dark.png" \
    "$OUTPUT_DIR/onboarding.png" \
    "$OUTPUT_DIR/onboarding-dark.png" \
    "$OUTPUT_DIR/settings-about.png" \
    "$OUTPUT_DIR/settings-general.png" \
    "$OUTPUT_DIR/settings-shortcuts.png" \
    "$OUTPUT_DIR/slash-commands-formatting.png" \
    "$OUTPUT_DIR/slash-commands-top.png" \
    "$OUTPUT_DIR/slash-commands-top-dark.png"

echo "Visual regression screenshots generated in $OUTPUT_DIR"
