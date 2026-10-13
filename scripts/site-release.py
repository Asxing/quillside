#!/usr/bin/env python3
"""Build website release state from published GitHub receipts, never from tag names alone."""
from pathlib import Path
import argparse
import json
import os
import re
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parent.parent

def gh_json(*args):
    return json.loads(subprocess.check_output(['gh', *args], text=True))

def website_release(base, release, metadata, repository):
    from importlib.util import spec_from_file_location, module_from_spec
    spec = spec_from_file_location('release_helpers', ROOT / 'scripts/release.py')
    module = module_from_spec(spec); spec.loader.exec_module(module)
    module.validate(metadata['tag'], metadata['version'], metadata['distribution'])
    if release.get('draft') or release['tag_name'] != metadata['tag']: raise ValueError('Release is not published or tag differs')
    if bool(release['prerelease']) != bool(metadata['prerelease']): raise ValueError('Release channel differs from metadata')
    expected_prerelease = module.validate(metadata['tag'], metadata['version'], metadata['distribution'])
    if metadata['prerelease'] != expected_prerelease: raise ValueError('Unexpected prerelease designation')
    expected_url = f'https://github.com/{repository}/releases/tag/{metadata["tag"]}'
    if release['html_url'] != expected_url: raise ValueError('Unexpected release repository')
    result = dict(base, version=metadata['version'], source_release_url=expected_url, status='preview',
                  notarized=False, download_url=None, sha256=None, published_at=None)
    if metadata['distribution'] == 'notarized' and not metadata['prerelease']:
        filename = f'Quillside-{metadata["version"]}-macOS-arm64.dmg'
        digest = metadata['artifacts'].get(filename, '')
        if not re.fullmatch('[a-f0-9]{64}', digest): raise ValueError('Official download lacks SHA-256')
        assets = {x['name']: x for x in release['assets']}
        target = assets.get(filename)
        if not target or 'notarization.json' not in assets: raise ValueError('Official release assets incomplete')
        url = f'https://github.com/{repository}/releases/download/{metadata["tag"]}/{filename}'
        if target['browser_download_url'] != url: raise ValueError('Unexpected asset URL')
        result.update(status='published', notarized=True, download_url=url, sha256=digest, published_at=release['published_at'])
    return result

def main():
    p = argparse.ArgumentParser(description=__doc__); p.add_argument('--tag', default=''); p.add_argument('--output', type=Path, required=True)
    a = p.parse_args(); repository = os.environ.get('GITHUB_REPOSITORY', '')
    if not re.fullmatch(r'[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+', repository): raise SystemExit('Invalid GitHub repository')
    base = json.loads((ROOT / 'site/content/release.json').read_text())
    base['repository_url'] = f'https://github.com/{repository}'
    # Explicit tag is supplied by the successful Release job. Otherwise prefer
    # the latest stable release, then the newest preview, without losing a formal download.
    if a.tag:
        if not re.fullmatch(r'v[0-9A-Za-z.-]+', a.tag): raise SystemExit('Invalid release tag')
        release = gh_json('api', f'repos/{repository}/releases/tags/{a.tag}')
    else:
        releases = gh_json('api', f'repos/{repository}/releases?per_page=100')
        valid = [r for r in releases if not r['draft'] and any(x['name']=='release-metadata.json' for x in r['assets'])]
        stable = [r for r in valid if not r['prerelease']]
        release = (stable or valid or [None])[0]
    if release:
        with tempfile.TemporaryDirectory(prefix='quillside-site-release-') as directory:
            subprocess.run(['gh','release','download',release['tag_name'],'--repo',repository,'--pattern','release-metadata.json','--dir',directory],check=True)
            metadata=json.loads((Path(directory)/'release-metadata.json').read_text())
        base=website_release(base,release,metadata,repository)
    a.output.write_text(json.dumps(base,ensure_ascii=False,indent=2)+'\n')
    print('Website state:',base['status'],'for',repository)

if __name__ == '__main__': main()
