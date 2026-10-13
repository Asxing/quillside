#!/usr/bin/env python3
"""Use an already-approved local development identity. Never creates trust settings.

Private credentials live outside the checkout in a dedicated keychain. This is
local development signing, not Developer ID distribution or notarization.
"""
import json
import fcntl
import shlex
import subprocess
import sys
from pathlib import Path

config_path = Path.home() / "Library/Application Support/OpenNotesDevelopmentSigning/identity.json"
config = json.loads(config_path.read_text())
keychain = config["keychain"]


def checked(arguments):
    result = subprocess.run(arguments, capture_output=True, text=True)
    if result.returncode:
        print(result.stderr.strip() or "Local signing operation failed", file=sys.stderr)
        raise SystemExit(result.returncode)
    return result.stdout


checked(["security", "unlock-keychain", "-p", config["password"], keychain])
valid = checked(["security", "find-identity", "-v", "-p", "codesigning", keychain])
if config["identity"] not in valid:
    raise SystemExit("The prepared local signing identity has not been trusted for code signing.")
if sys.argv[1:] == ["--check"]:
    print("Local development signing identity is ready.")
else:
    # codesign still needs the identity's keychain in the user search list,
    # even when --keychain names it explicitly. Register it only while signing.
    with (config_path.parent / "signing.lock").open("w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        previous = shlex.split(checked(["security", "list-keychains", "-d", "user"]))
        added = keychain not in previous
        try:
            if added:
                checked(["security", "list-keychains", "-d", "user", "-s", *previous, keychain])
            checked(["codesign", "--force", "--sign", config["identity"], "--keychain", keychain, *sys.argv[1:]])
        finally:
            if added:
                current = shlex.split(checked(["security", "list-keychains", "-d", "user"]))
                checked(["security", "list-keychains", "-d", "user", "-s",
                         *(item for item in current if item != keychain)])
