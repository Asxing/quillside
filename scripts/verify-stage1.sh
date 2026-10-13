#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_DIR"

python3 scripts/check-open-source.py

if rg -n \
    --glob '!verify-stage1.sh' \
    '/tmp/opennotes-(slash|backlinks|actions|db)\.log|HTML preview|Selected text:|text\.prefix\(|debugLog\(' \
    src/Quillside scripts; then
    echo "Stage 1 verification failed: content-bearing diagnostic logging remains."
    exit 1
fi

./scripts/verify.sh

echo "Stage 1 static checks, tests, and debug build passed."
