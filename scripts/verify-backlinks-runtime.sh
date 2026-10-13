#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_BUNDLE="$PROJECT_DIR/build/Quillside.app"
LOG_FILE="$(mktemp /private/tmp/opennotes-backlinks-runtime.XXXXXX.log)"
REQUIRE_REAL_LINKS="${OPENNOTES_REQUIRE_REAL_LINKS:-0}"

if [[ ! -d "$APP_BUNDLE" ]]; then
    echo "FAIL: Quillside.app not found at $APP_BUNDLE"
    exit 2
fi

pkill -TERM -x Quillside >/dev/null 2>&1 || true

/usr/bin/log stream \
    --style compact \
    --level debug \
    --predicate 'subsystem == "com.opennotes.app"' \
    >"$LOG_FILE" 2>&1 &
LOG_PID=$!

cleanup() {
    kill "$LOG_PID" >/dev/null 2>&1 || true
    rm -f "$LOG_FILE"
}
trap cleanup EXIT

open -n "$APP_BUNDLE"

GRAPH_LINE=""
for _ in {1..30}; do
    GRAPH_LINE="$(rg 'Link graph built: notes=[0-9]+, sources=[0-9]+' "$LOG_FILE" | tail -1 || true)"
    if [[ -n "$GRAPH_LINE" ]]; then
        break
    fi
    sleep 0.5
done

if [[ -z "$GRAPH_LINE" ]]; then
    echo "FAIL: Quillside did not emit a link-graph result"
    exit 3
fi

SOURCES="$(sed -E 's/.*sources=([0-9]+).*/\1/' <<<"$GRAPH_LINE")"
NOTES="$(sed -E 's/.*notes=([0-9]+).*/\1/' <<<"$GRAPH_LINE")"

if (( NOTES < 1 )); then
    echo "FAIL: Notes database was not readable (notes=0); grant Full Disk Access to this Quillside.app"
    exit 4
fi

if (( SOURCES < 1 )); then
    if [[ "$REQUIRE_REAL_LINKS" == "1" ]]; then
        echo "FAIL: no real backlinks were resolved (notes=$NOTES, sources=$SOURCES)"
        exit 1
    fi
    echo "PASS: Notes database readable; current notes contain no resolved backlinks (notes=$NOTES, sources=$SOURCES)"
    exit 0
fi

echo "PASS: real backlinks detected (notes=$NOTES, sources=$SOURCES)"
