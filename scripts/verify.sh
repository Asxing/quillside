#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
python3 scripts/prepare-pi-runtime.py
npm test --prefix runtime/pi
task_fixture_dir=$(mktemp -d)
python3 scripts/mock-model-server.py --port-file "$task_fixture_dir/port" &
task_fixture_pid=$!
trap 'kill "$task_fixture_pid" 2>/dev/null || true; rm -rf "$task_fixture_dir"' EXIT
for _ in {1..300}; do
    test -f "$task_fixture_dir/port" && break
    if ! kill -0 "$task_fixture_pid" 2>/dev/null; then echo "Synthetic model server exited before becoming ready"; exit 1; fi
    sleep 0.1
done
if [[ ! -f "$task_fixture_dir/port" ]]; then echo "Synthetic model server did not become ready within 30 seconds"; exit 1; fi
export OPENNOTES_TEST_MODEL_BASEURL="http://127.0.0.1:$(cat "$task_fixture_dir/port")"
task_testing_frameworks="${DEVELOPER_DIR:-/Library/Developer/CommandLineTools}/Library/Developer/Frameworks"
if [[ -n "${DEVELOPER_DIR:-}" && "$DEVELOPER_DIR" != */CommandLineTools ]]; then task_testing_frameworks="$DEVELOPER_DIR/Platforms/MacOSX.platform/Developer/Library/Frameworks"; fi
swift test --disable-sandbox --disable-xctest --enable-swift-testing \
    -Xswiftc "-F$task_testing_frameworks" \
    -Xswiftc -Xfrontend -Xswiftc -disable-cross-import-overlays \
    -Xlinker -rpath -Xlinker "$task_testing_frameworks"
swift build --disable-sandbox
