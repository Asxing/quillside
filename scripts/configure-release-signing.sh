#!/bin/bash
# Run only in the isolated macOS release job, never in untrusted PR jobs.
set -euo pipefail
for task_secret in DEVELOPER_ID_P12_BASE64 DEVELOPER_ID_P12_PASSWORD APPLE_ID APPLE_TEAM_ID APPLE_APP_PASSWORD; do
    if [[ -z "${!task_secret:-}" ]]; then echo "Missing release secret: $task_secret"; exit 1; fi
done
: "${RUNNER_TEMP:?This script requires an isolated GitHub runner}"
: "${GITHUB_ENV:?Missing GitHub environment file}"
task_signing_dir="$RUNNER_TEMP/quillside-signing"
mkdir -m 700 "$task_signing_dir"
task_keychain="$task_signing_dir/release.keychain-db"
task_keychain_password="$(uuidgen)"
python3 - "$task_signing_dir/certificate.p12" <<'PY'
import base64,os,sys
from pathlib import Path
p=Path(sys.argv[1]);p.write_bytes(base64.b64decode(os.environ['DEVELOPER_ID_P12_BASE64'],validate=True));p.chmod(0o600)
PY
security create-keychain -p "$task_keychain_password" "$task_keychain"
security set-keychain-settings -lut 21600 "$task_keychain"
security unlock-keychain -p "$task_keychain_password" "$task_keychain"
security import "$task_signing_dir/certificate.p12" -k "$task_keychain" -P "$DEVELOPER_ID_P12_PASSWORD" -T /usr/bin/codesign -T /usr/bin/security
security set-key-partition-list -S apple-tool:,apple: -k "$task_keychain_password" "$task_keychain" >/dev/null
security list-keychains -d user -s "$task_keychain"
security default-keychain -d user -s "$task_keychain"
task_identity="$(security find-identity -v -p codesigning "$task_keychain" | awk '/"Developer ID Application:/{print $2; exit}')"
if [[ -z "$task_identity" ]]; then echo 'No Developer ID Application identity in certificate'; exit 1; fi
xcrun notarytool store-credentials quillside-release --apple-id "$APPLE_ID" --team-id "$APPLE_TEAM_ID" --password "$APPLE_APP_PASSWORD" --keychain "$task_keychain"
printf 'OPENNOTES_CODE_SIGN_IDENTITY=%s\nOPENNOTES_NOTARY_PROFILE=quillside-release\n' "$task_identity" >> "$GITHUB_ENV"
