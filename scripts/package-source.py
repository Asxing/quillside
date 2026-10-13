#!/usr/bin/env python3
"""Create a reviewed source ZIP; uncommitted snapshots require --working-tree."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import zipfile

ROOT = Path(__file__).resolve().parent.parent
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--working-tree", action="store_true", help="Create an explicitly labeled local review snapshot")
args = parser.parse_args()
subprocess.run(["python3", str(ROOT / "scripts/check-open-source.py")], cwd=ROOT, check=True)
head = subprocess.run(["git", "rev-parse", "--verify", "HEAD"], cwd=ROOT, capture_output=True, text=True)
commit = head.stdout.strip() if head.returncode == 0 else None
status = subprocess.check_output(["git", "status", "--porcelain", "--untracked-files=all"], cwd=ROOT)
if not args.working_tree and (not commit or status.strip()):
    raise SystemExit("Formal source archives require a committed, clean checkout. Use --working-tree only for a local review snapshot.")
version = (ROOT / "VERSION").read_text().strip()
if not version or any(char not in "0123456789.-abcdefghijklmnopqrstuvwxyz" for char in version.lower()):
    raise SystemExit("Invalid version for source archive")
paths = sorted(set(subprocess.check_output(
    ["git", "ls-files", "--cached", "--others", "--exclude-standard", "-z"], cwd=ROOT
).decode().strip("\0").split("\0")) - {""})
output = ROOT / "build" / f"Quillside-{version}-source{'-preview' if args.working_tree else ''}.zip"
output.parent.mkdir(exist_ok=True)
prefix = f"Quillside-{version}/"
manifest = {
    "version": version,
    "basis": "working-tree-review-snapshot" if args.working_tree else "clean-git-commit",
    "base_commit": commit,
    "files": {},
}
with zipfile.ZipFile(output, "w", compression=zipfile.ZIP_DEFLATED) as archive:
    for name in paths:
        path = ROOT / name
        if path.is_symlink() or not path.resolve().is_relative_to(ROOT):
            raise SystemExit(f"Unsafe source path: {name}")
        data = path.read_bytes()
        manifest["files"][name] = hashlib.sha256(data).hexdigest()
        info = zipfile.ZipInfo(prefix + name, date_time=(2026, 1, 1, 0, 0, 0))
        info.compress_type = zipfile.ZIP_DEFLATED
        info.external_attr = (0o100755 if path.stat().st_mode & 0o111 else 0o100644) << 16
        archive.writestr(info, data)
    archive.writestr(prefix + "SOURCE_MANIFEST.json", json.dumps(manifest, ensure_ascii=False, indent=2) + "\n")
digest = hashlib.sha256(output.read_bytes()).hexdigest()
output.with_suffix(output.suffix + ".sha256").write_text(f"{digest}  {output.name}\n")
print(f"Source archive: {output}\nBasis: {manifest['basis']}\nFiles: {len(paths)}\nSHA-256: {digest}")
