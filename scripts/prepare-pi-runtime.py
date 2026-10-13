#!/usr/bin/env python3
"""Build the pinned Pi worker and an official, hash-verified Node runtime."""
from pathlib import Path
import hashlib,json,platform,shutil,subprocess,tarfile,urllib.request
ROOT=Path(__file__).resolve().parent.parent
runtime=ROOT/'runtime/pi'; out=ROOT/'build/pi-runtime';out.mkdir(parents=True,exist_ok=True)
dependency_hash = hashlib.sha256((runtime/'package-lock.json').read_bytes() + (runtime/'package.json').read_bytes()).hexdigest()
dependency_stamp = runtime/'node_modules/.quillside-lock-sha256'
if not dependency_stamp.exists() or dependency_stamp.read_text().strip() != dependency_hash:
 subprocess.run(['npm','ci','--ignore-scripts','--no-audit','--no-fund'],cwd=runtime,check=True)
 dependency_stamp.write_text(dependency_hash+'\n')
subprocess.run(['node','build.mjs'],cwd=runtime,check=True)
spec=json.loads((runtime/'node-release.json').read_text());arch={'arm64':'arm64','x86_64':'x64'}[platform.machine()]
name=f"node-{spec['version']}-darwin-{arch}.tar.gz"; archive=out/name
if not archive.exists():
 temporary=archive.with_suffix('.download');urllib.request.urlretrieve(f"https://nodejs.org/dist/{spec['version']}/{name}",temporary);temporary.replace(archive)
assert hashlib.sha256(archive.read_bytes()).hexdigest()==spec['sha256'][name], 'Node distribution hash mismatch'
with tarfile.open(archive) as tf:
 prefix=name.removesuffix('.tar.gz')
 for member,destination in [(prefix+'/bin/node',out/'node'),(prefix+'/LICENSE',out/'NODE-LICENSE')]:
  source=tf.extractfile(member);assert source;destination.write_bytes(source.read())
(out/'node').chmod(0o755)
shutil.copy2(runtime/'dist/worker.mjs',out/'worker.mjs')
shutil.copy2(runtime/'node_modules/@earendil-works/pi-coding-agent/package.json',out/'package.json')
print('Prepared Pi 1.2.0 with verified Node',spec['version'],arch)
