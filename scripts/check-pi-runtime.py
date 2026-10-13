#!/usr/bin/env python3
"""Verify the separately inventoried Pi/Node distribution notices without reading credentials."""
from pathlib import Path
import argparse,hashlib,json
root=Path(__file__).resolve().parent.parent
parser=argparse.ArgumentParser();parser.add_argument('--bundle',type=Path);args=parser.parse_args()
manifest=json.loads((root/'licenses/pi-runtime/manifest.json').read_text());lock=json.loads((root/'runtime/pi/package-lock.json').read_text());errors=[]
for component in manifest['components']:
 if component['name']!='Node.js':
  expected=component['version'];found=any(p.get('version')==expected and (p.get('name')==component['name'] or key.endswith('node_modules/'+component['name'])) for key,p in lock['packages'].items())
  if not found:errors.append('Lockfile mismatch: '+component['name'])
 for item in component['notices']:
  source=root/item['file']
  if not source.exists() or hashlib.sha256(source.read_bytes()).hexdigest()!=item['sha256']:errors.append('Notice mismatch: '+item['file'])
  if args.bundle:
   copied=args.bundle/'Contents/Resources/Licenses/PiRuntime'/source.name
   if not copied.exists() or copied.read_bytes()!=source.read_bytes():errors.append('Missing bundle notice: '+source.name)
if args.bundle:
 for name in ['node','worker.mjs','package.json']:
  if not (args.bundle/'Contents/Resources/PiRuntime'/name).is_file():errors.append('Missing Pi runtime: '+name)
 if (args.bundle/'Contents/Resources/PiRuntime/worker.mjs').exists():
  if (args.bundle/'Contents/Resources/PiRuntime/worker.mjs').read_bytes()!=(root/'runtime/pi/dist/worker.mjs').read_bytes():errors.append('Bundled Pi worker is stale')
if errors:raise SystemExit('\n'.join(errors))
print('PASS:',len(manifest['components']),'Pi/Node runtime component notices and pinned package versions')
