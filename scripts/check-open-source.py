#!/usr/bin/env python3
"""Check the prospective Git source set and delivered MIT notices.

Credential checks are intentionally limited and never print matched values.
This is a release guard, not a complete security or authorship audit.
"""
import argparse
import hashlib
import json
import re
import subprocess
from pathlib import Path
from urllib.request import urlopen

ROOT = Path(__file__).resolve().parent.parent
REQUIRED_COMPONENTS = {"NotesPlus", "NotesBridge", "Yams", "LibYAML", "Humanizer-zh"}
REQUIRED_FILES = (
    "LICENSE", "THIRD_PARTY_NOTICES.md", "README.md", "CONTRIBUTING.md",
    "SECURITY.md", "CODE_OF_CONDUCT.md", "Package.resolved", ".gitignore",
    ".github/ISSUE_TEMPLATE/bug_report.md", ".github/ISSUE_TEMPLATE/feature_request.md",
    ".github/PULL_REQUEST_TEMPLATE.md", ".github/workflows/ci.yml",
)
PRIVATE_SUFFIXES = {".p12", ".pfx", ".pem", ".key", ".csr", ".keychain", ".keychain-db",
                    ".mobileprovision", ".provisionprofile", ".sqlite", ".db", ".dmg", ".zip"}
BINARY_ASSETS = {".png", ".jpg", ".jpeg", ".icns", ".webp", ".gif"}
SECRET_PATTERNS = {
    "private-key": re.compile(r"-----BEGIN (?:RSA |EC |OPENSSH |ENCRYPTED )?PRIVATE KEY-----"),
    "provider-token": re.compile(r"\b(?:sk-(?:proj-|ant-)?[A-Za-z0-9_-]{24,}|gh[pousr]_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{30,}|AKIA[A-Z0-9]{16})\b"),
    "literal-sensitive-value": re.compile(r'''(?i)["'](?:api[_-]?key|password|access_token|refresh_token|client_secret)["']\s*:\s*["']([^"']{8,})["']'''),
}


def check(bundle=None, online=False):
    errors = []
    candidates = set(subprocess.check_output(
        ["git", "ls-files", "--cached", "--others", "--exclude-standard", "-z"], cwd=ROOT
    ).decode().strip("\0").split("\0")) - {""}
    for name in REQUIRED_FILES:
        if name not in candidates or not (ROOT / name).is_file():
            errors.append(f"Missing required source file: {name}")
    for name in sorted(candidates):
        path = ROOT / name
        if path.is_symlink():
            errors.append(f"Symlink needs explicit distribution review: {name}")
            continue
        if not path.is_file():
            errors.append(f"Source entry is missing: {name}")
            continue
        example_env = path.name == ".env.example" or path.name.endswith(".example")
        private_name = path.name in {"auth.json", "credentials.json", "identity.json"}
        env_file = path.name.startswith(".env") and not example_env
        generated = any(part in {".build", "build", "dist", "__pycache__", "xcuserdata"} or part.endswith(".app") for part in Path(name).parts)
        if path.suffix.lower() in PRIVATE_SUFFIXES or private_name or env_file or generated:
            errors.append(f"Local/generated file in prospective source set: {name}")
        if path.suffix.lower() in BINARY_ASSETS:
            continue
        if path.stat().st_size > 2_000_000:
            errors.append(f"Large non-image file needs review: {name}")
            continue
        try:
            text = path.read_text(encoding="utf-8")
        except UnicodeError:
            errors.append(f"Unreviewed binary file: {name}")
            continue
        for category, pattern in SECRET_PATTERNS.items():
            for match in pattern.finditer(text):
                line = text[:match.start()].count("\n") + 1
                errors.append(f"Potential {category}: {name}:{line} (value redacted)")

    if (ROOT / "runtime/pi/package-lock.json").exists():
        args = ["python3", str(ROOT / "scripts/check-pi-runtime.py")]
        if bundle: args += ["--bundle", str(bundle)]
        result = subprocess.run(args, cwd=ROOT, capture_output=True, text=True)
        if result.returncode: errors.append(result.stdout.strip() or result.stderr.strip())

    manifest = json.loads((ROOT / "licenses/manifest.json").read_text())
    components = manifest["components"]
    names = [item["name"] for item in components]
    if set(names) != REQUIRED_COMPONENTS or len(names) != len(set(names)):
        errors.append("Third-party component inventory changed; review direct and transitive licenses")
    for item in components:
        path = ROOT / item["license_file"]
        if item["license"] != "MIT":
            errors.append(f"Unreviewed license: {item['name']}")
        if item["license_file"] not in candidates or not path.is_file():
            errors.append(f"Missing distributable license: {item['name']}")
            continue
        data = path.read_bytes()
        if hashlib.sha256(data).hexdigest() != item["sha256"]:
            errors.append(f"License differs from reviewed hash: {item['name']}")
        if b"Permission is hereby granted" not in data or b'THE SOFTWARE IS PROVIDED "AS IS"' not in data:
            errors.append(f"Incomplete MIT notice: {item['name']}")
        if online:
            try:
                with urlopen(item["license_url"], timeout=20) as response:
                    if response.read() != data:
                        errors.append(f"License differs from pinned upstream text: {item['name']}")
            except Exception as exc:
                errors.append(f"Cannot verify upstream license: {item['name']} ({type(exc).__name__})")

    root_license = (ROOT / "LICENSE").read_text()
    upstream = (ROOT / "licenses/NotesPlus-MIT.txt").read_text()
    normalize = lambda text: " ".join(text.split())
    for marker in ("Permission is hereby granted", "Copyright (c) 2026 NotesPlus Contributors"):
        if marker not in root_license:
            errors.append("Root MIT license must retain original grant and NotesPlus attribution")
    if "Permission is hereby granted" in root_license:
        if normalize(root_license[root_license.index("Permission is hereby granted"):]) != normalize(upstream[upstream.index("Permission is hereby granted"):]):
            errors.append("Root MIT grant/disclaimer differs from upstream standard text")
    if not root_license.startswith("MIT License\n"):
        errors.append("Root license should use standard MIT title")
    by_name = {item["name"]: item for item in components}
    pins = json.loads((ROOT / "Package.resolved").read_text())["pins"]
    if {pin["identity"] for pin in pins} != {"yams"}:
        errors.append("Swift package inventory changed; audit new dependencies")
    for pin in pins:
        if pin["identity"] == "yams" and pin["state"]["revision"] != by_name["Yams"]["revision"]:
            errors.append("Yams revision differs from reviewed license inventory")
    skill = ROOT / "resources/Skills/humanizer-zh"
    if json.loads((skill / "SOURCE.json").read_text())["commit"] != by_name["Humanizer-zh"]["revision"]:
        errors.append("Bundled Skill revision differs from reviewed inventory")
    if (skill / "LICENSE").read_bytes() != (ROOT / by_name["Humanizer-zh"]["license_file"]).read_bytes():
        errors.append("Bundled Skill and central license copies differ")

    if bundle:
        resources = bundle.resolve() / "Contents/Resources"
        pairs = [(ROOT / name, resources / "Licenses" / name) for name in ("LICENSE", "THIRD_PARTY_NOTICES.md")]
        pairs += [(ROOT / item["license_file"], resources / "Licenses" / Path(item["license_file"]).name) for item in components]
        pairs += [(ROOT / "licenses/manifest.json", resources / "Licenses/manifest.json"),
                  (skill / "LICENSE", resources / "Skills/humanizer-zh/LICENSE")]
        for source, target in pairs:
            if not target.is_file() or target.read_bytes() != source.read_bytes():
                errors.append(f"Bundle license missing or stale: {target.relative_to(resources)}")

    if errors:
        raise SystemExit("\n".join(errors))
    print(f"PASS: {len(candidates)} prospective source files; {len(components)} MIT components; no matched credential patterns")
    if online:
        print("PASS: all five license texts match pinned upstream sources")
    if bundle:
        print("PASS: app bundle contains matching project, component, and Skill notices")
    print("Scope: current Git source set and selected patterns only; not a history, binary-content, security or legal audit.")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--bundle", type=Path, help="Verify licenses delivered in an already-built app")
    parser.add_argument("--online", action="store_true", help="Compare license bytes with pinned upstream sources")
    arguments = parser.parse_args()
    check(arguments.bundle, arguments.online)
