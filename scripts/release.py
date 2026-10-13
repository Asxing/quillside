#!/usr/bin/env python3
"""Prepare and publish tag-bound releases. Unsigned builds never become official downloads."""
from pathlib import Path
import argparse
import hashlib
import json
import os
import re
import subprocess
import sys
import zipfile

ROOT = Path(__file__).resolve().parent.parent
MODES = {'source', 'preview', 'notarized'}

def validate(tag, version, mode):
    if not re.fullmatch(r'v\d+\.\d+\.\d+(?:-[0-9A-Za-z]+(?:[.-][0-9A-Za-z]+)*)?', tag):
        raise ValueError('Use a vMAJOR.MINOR.PATCH tag, optionally with a prerelease suffix')
    if tag != 'v' + version:
        raise ValueError('Tag must exactly match VERSION')
    if mode not in MODES:
        raise ValueError('Unknown distribution mode; expected source, preview or notarized')
    return mode != 'notarized' or '-' in version

def git(*args):
    return subprocess.check_output(['git', *args], cwd=ROOT, text=True).strip()

def prepare(tag, mode):
    version = (ROOT / 'VERSION').read_text().strip()
    prerelease = validate(tag, version, mode)
    sha = git('rev-parse', 'HEAD')
    if git('rev-parse', '--verify', f'refs/tags/{tag}^{{commit}}') != sha:
        raise ValueError('Checkout must be the exact release tag')
    if git('status', '--porcelain', '--untracked-files=all'):
        raise ValueError('Release requires a clean committed source tree')
    notes = ROOT / 'docs/releases' / f'{version}.md'
    if not notes.is_file(): raise ValueError('Add reviewed version notes before tagging')
    out = ROOT / 'build/release'
    out.mkdir(parents=True, exist_ok=True)
    metadata = {'schema': 1, 'version': version, 'tag': tag, 'commit': sha, 'distribution': mode, 'prerelease': prerelease}
    (out / 'release-metadata.json').write_text(json.dumps(metadata, indent=2) + '\n')
    status = {
        'source': '**Source preview.** Build the app locally; this release contains no app binary. Apple Developer membership is not required to build the source.',
        'preview': '**Unnotarized tester preview.** The app is ad-hoc signed, not Developer ID signed or Apple-notarized. It may be blocked by Gatekeeper and updates may require permissions again. Prefer a source build if you are not comfortable testing it. See the installation guide; never disable system security globally.',
        'notarized': '**Developer ID signed and notarized macOS release.** Check the SHA-256 before installing. Compatibility and known limitations are described below.',
    }[mode]
    (out / 'release-notes.md').write_text(status + '\n\n' + notes.read_text() + f'\n\nSource commit: `{sha}`\n')
    for key, value in metadata.items():
        if key in {'tag', 'version', 'commit', 'distribution', 'prerelease'}:
            if os.environ.get('GITHUB_OUTPUT'):
                with open(os.environ['GITHUB_OUTPUT'], 'a') as f: f.write(f'{key}={str(value).lower() if isinstance(value, bool) else value}\n')
    print(f'Prepared {tag} ({mode}) at {sha[:12]}')

def inventory(directory):
    m = json.loads((directory / 'release-metadata.json').read_text())
    validate(m['tag'], m['version'], m['distribution'])
    version = m['version']; mode = m['distribution']
    expected = {f'Quillside-{version}-source.zip', f'Quillside-{version}-source.zip.sha256'}
    if mode == 'preview': expected.add(f'Quillside-{version}-UNNOTARIZED-macOS-arm64.zip')
    if mode == 'notarized': expected |= {f'Quillside-{version}-macOS-arm64.dmg', f'Quillside-{version}-macOS-arm64.dmg.sha256', 'notarization.json'}
    if not all((directory / p).is_file() for p in expected): raise ValueError('Required release artifacts are missing')
    with zipfile.ZipFile(directory / f'Quillside-{version}-source.zip') as archive:
        source_manifest = json.loads(archive.read(f'Quillside-{version}/SOURCE_MANIFEST.json'))
        if (source_manifest.get('basis') != 'clean-git-commit' or source_manifest.get('base_commit') != m['commit']
                or source_manifest.get('version') != version):
            raise ValueError('Source archive does not match the committed release')
    allowed = expected | {'release-metadata.json', 'release-notes.md', 'SHA256SUMS'}
    unexpected = {p.name for p in directory.iterdir()} - allowed
    if unexpected: raise ValueError('Unexpected release artifacts: ' + ', '.join(sorted(unexpected)))
    if mode == 'notarized':
        receipt = json.loads((directory / 'notarization.json').read_text())
        if receipt.get('status') != 'Accepted' or not receipt.get('id'): raise ValueError('An Accepted notarization receipt is required')
    files = {p: hashlib.sha256((directory / p).read_bytes()).hexdigest() for p in sorted(expected)}
    for name in expected:
        if name.endswith('.sha256'):
            fields = (directory / name).read_text().strip().split()
            target = name[:-7]
            if len(fields) != 2 or fields[1] != target or fields[0] != files[target]: raise ValueError('Artifact checksum mismatch')
    m['artifacts'] = files
    m['prerelease'] = validate(m['tag'], m['version'], mode)
    (directory / 'release-metadata.json').write_text(json.dumps(m, indent=2) + '\n')
    (directory / 'SHA256SUMS').write_text(''.join(f'{digest}  {name}\n' for name, digest in files.items()))
    return m

def publish(directory, repository):
    if not re.fullmatch(r'[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+', repository): raise ValueError('Invalid repository')
    m = inventory(directory)
    tag = m['tag']
    remote_sha = subprocess.check_output(['gh', 'api', f'repos/{repository}/commits/{tag}', '--jq', '.sha'], text=True).strip()
    if remote_sha != m['commit']: raise ValueError('Remote tag moved after the build')
    exists = subprocess.run(['gh', 'release', 'view', tag, '--repo', repository, '--json', 'isDraft'], capture_output=True, text=True)
    if exists.returncode == 0:
        raise ValueError('Release already exists; do not replace published assets or an unreviewed draft')
    # The API check above already established repository access. Draft creation
    # fails safely if another run created the release in the meantime.
    subprocess.run(['gh', 'release', 'create', tag, '--repo', repository, '--verify-tag', '--draft',
                    '--title', f'Quillside {m["version"]}' + (' — developer preview' if m['prerelease'] else ''),
                    '--notes-file', str(directory / 'release-notes.md'),
                    *(['--prerelease'] if m['prerelease'] else [])], check=True)
    assets = [str(p) for p in sorted(directory.iterdir()) if p.name != 'release-notes.md']
    subprocess.run(['gh', 'release', 'upload', tag, '--repo', repository, *assets], check=True)
    remote_names = json.loads(subprocess.check_output(['gh', 'release', 'view', tag, '--repo', repository, '--json', 'assets'], text=True))
    if {x['name'] for x in remote_names['assets']} != {Path(x).name for x in assets}: raise ValueError('Remote release assets are incomplete; draft retained')
    subprocess.run(['gh', 'release', 'edit', tag, '--repo', repository, '--draft=false',
                    '--prerelease=' + str(m['prerelease']).lower(), '--latest=' + str(not m['prerelease']).lower()], check=True)
    print(f'https://github.com/{repository}/releases/tag/{tag}')

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest='command', required=True)
    p = sub.add_parser('prepare'); p.add_argument('--tag', required=True); p.add_argument('--distribution', default='source')
    p = sub.add_parser('publish'); p.add_argument('--directory', type=Path, default=Path('build/release')); p.add_argument('--repository', required=True)
    p = sub.add_parser('inventory'); p.add_argument('--directory', type=Path, default=Path('build/release'))
    a = parser.parse_args()
    try:
        if a.command == 'prepare': prepare(a.tag, a.distribution)
        elif a.command == 'publish': publish(a.directory, a.repository)
        else: print(json.dumps(inventory(a.directory), indent=2))
    except (ValueError, KeyError, zipfile.BadZipFile) as e:
        sys.exit(str(e))
