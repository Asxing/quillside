#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
VERSION="$(tr -d '[:space:]' < "$PROJECT_DIR/VERSION")"
APP_BUNDLE="$PROJECT_DIR/build/Quillside.app"
OUTPUT="$PROJECT_DIR/build/release-app"
[[ "$(uname -m)" == arm64 ]] || { echo 'The tester preview currently supports Apple Silicon only.'; exit 1; }
OPENNOTES_CODE_SIGN_IDENTITY=- "$SCRIPT_DIR/bundle-app.sh" release
python3 "$SCRIPT_DIR/check-open-source.py" --bundle "$APP_BUNDLE"
python3 "$SCRIPT_DIR/verify-app-bundle.py" "$APP_BUNDLE" --version "$VERSION"
mkdir -p "$OUTPUT"
NAME="Quillside-$VERSION-UNNOTARIZED-macOS-arm64"
WORK="$(mktemp -d "${TMPDIR:-/private/tmp}/quillside-preview.XXXXXX")"
cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT
mkdir "$WORK/image"
ditto "$APP_BUNDLE" "$WORK/image/Quillside.app"
ln -s /Applications "$WORK/image/Applications"
cat > "$WORK/image/INSTALL.txt" <<'TEXT'
Quillside — Apple Silicon tester preview / Apple Silicon 测试版

1. Drag Quillside.app into Applications, then open it.
2. This build is ad-hoc signed and NOT notarized by Apple.
3. Only if you trust this download, follow Apple's per-app Open Anyway flow:
   https://support.apple.com/en-us/102445
4. Grant the requested Notes/Accessibility permissions. Updates may require them again.
5. Configure your own model account. Node and Pi are included; no developer tools are needed.

将 Quillside.app 拖入 Applications 后打开。本版未公证，首次启动可能被 macOS 阻止。
请先确认来源，再按 Apple 官方说明为此应用选择“仍要打开”。不要关闭系统的全局安全保护。
更新后可能需要重新授予辅助功能与 Notes 自动化权限。模型需自行配置。
TEXT
ditto -c -k --sequesterRsrc --keepParent "$APP_BUNDLE" "$OUTPUT/$NAME.zip"
hdiutil create -volname "Quillside $VERSION Preview" -srcfolder "$WORK/image" -ov -format UDZO "$OUTPUT/$NAME.dmg" >/dev/null
hdiutil verify "$OUTPUT/$NAME.dmg" >/dev/null
python3 - "$OUTPUT" "$NAME" <<'PY'
from pathlib import Path
import hashlib,sys,zipfile
out=Path(sys.argv[1]);name=sys.argv[2]
with zipfile.ZipFile(out/(name+'.zip')) as archive:
    if archive.testzip() is not None:raise SystemExit('Corrupt application ZIP')
    assert 'Quillside.app/Contents/MacOS/Quillside' in archive.namelist()
for ext in ('.zip','.dmg'):
    p=out/(name+ext)
    p.with_suffix(p.suffix+'.sha256').write_text(f'{hashlib.sha256(p.read_bytes()).hexdigest()}  {p.name}\n')
print('Created DMG and ZIP tester packages with SHA-256 files.')
PY
