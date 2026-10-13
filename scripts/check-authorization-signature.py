#!/usr/bin/env python3
"""Read-only check: does an existing TCC grant match the installed app's signature?

Never edits TCC, resets permissions, invokes sudo or prints credentials/other apps.
Exit 0: all observed grants match. Exit 1: missing/mismatched grant. Exit 2: records inaccessible.
"""
import argparse
import json
import plistlib
import sqlite3
import subprocess
import tempfile
from pathlib import Path


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--app", default="/Applications/Quillside.app")
    args = parser.parse_args()
    app = Path(args.app).resolve()
    info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
    identifier = info["CFBundleIdentifier"]
    locations = [
        (Path("/Library/Application Support/com.apple.TCC/TCC.db"), ["kTCCServiceAccessibility", "kTCCServiceSystemPolicyAllFiles"]),
        (Path.home() / "Library/Application Support/com.apple.TCC/TCC.db", ["kTCCServiceAppleEvents"]),
    ]
    results = []
    unavailable = False
    for database, services in locations:
        try:
            with sqlite3.connect(database.as_uri() + "?mode=ro", uri=True) as connection:
                for service in services:
                    sql = "SELECT auth_value,csreq FROM access WHERE client=? AND service=?"
                    parameters = [identifier, service]
                    if service == "kTCCServiceAppleEvents":
                        sql += " AND indirect_object_identifier=?"
                        parameters.append("com.apple.Notes")
                    rows = connection.execute(sql, parameters).fetchall()
                    allowed = False
                    matched = False
                    for value, requirement in rows:
                        allowed |= value == 2
                        if not requirement:
                            continue
                        with tempfile.TemporaryDirectory(prefix="opennotes-permission-check-") as directory:
                            file = Path(directory) / "requirement"
                            file.write_bytes(requirement)
                            check = subprocess.run(["codesign", "--verify", "-R", str(file), str(app)], capture_output=True)
                            matched |= value == 2 and check.returncode == 0
                    results.append({"service": service, "record_present": bool(rows), "allowed_in_record": allowed, "current_signature_matches_allowed_record": matched})
        except sqlite3.Error:
            unavailable = True
            results.extend({"service": service, "record_access": "unavailable"} for service in services)
    print(json.dumps({"app": str(app), "version": info.get("CFBundleShortVersionString"), "bundle_id": identifier,
                      "read_only": True, "results": results}, ensure_ascii=False, indent=2))
    if unavailable:
        return 2
    return 0 if all(item["current_signature_matches_allowed_record"] for item in results) else 1


if __name__ == "__main__":
    raise SystemExit(main())
