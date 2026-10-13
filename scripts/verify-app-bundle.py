#!/usr/bin/env python3
"""Check a distributable app and start its bundled Pi runtime without user credentials."""
from pathlib import Path
import argparse
import json
import os
import plistlib
import selectors
import subprocess
import tempfile
import time

p = argparse.ArgumentParser(description=__doc__)
p.add_argument('bundle', type=Path)
p.add_argument('--version', required=True)
a = p.parse_args()
app = a.bundle.resolve()
info = plistlib.loads((app/'Contents/Info.plist').read_bytes())
assert info['CFBundleIdentifier'] == 'com.opennotes.app'
assert info['CFBundleShortVersionString'] == a.version
assert info['CFBundleExecutable'] == 'Quillside'
subprocess.run(['codesign','--verify','--deep','--strict',str(app)],check=True)
runtime = app/'Contents/Resources/PiRuntime'
for binary in [app/'Contents/MacOS/Quillside',runtime/'node']:
    architectures = subprocess.check_output(['lipo','-archs',str(binary)],text=True).split()
    assert architectures == ['arm64'], f'Unexpected architecture: {binary.name}'
for name in ['worker.mjs','package.json']:
    assert (runtime/name).is_file(),name
for asset in ['AppIcon.icns','Quillside-Mark.png','MenuBarTemplate.png','Skills/humanizer-zh/SKILL.md','Licenses/LICENSE','Licenses/PiRuntime/manifest.json']:
    assert (app/'Contents/Resources'/asset).is_file(),asset
for file in app.rglob('*'):
    assert file.name not in {'auth.json','credentials.json','identity.json'}, 'Credential file in bundle'
    assert file.suffix.lower() not in {'.p12','.pfx','.keychain','.keychain-db'}, 'Signing material in bundle'
with tempfile.TemporaryDirectory(prefix='quillside-distribution-check-') as directory:
    env = {key:os.environ[key] for key in ('HOME',) if key in os.environ}
    env.update(PATH='/usr/bin:/bin',TMPDIR=directory,QUILLSIDE_PI_DIR=directory+'/Pi',PI_OFFLINE='1',PI_PACKAGE_DIR=str(runtime))
    process = subprocess.Popen([str(runtime/'node'),str(runtime/'worker.mjs')],env=env,stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.DEVNULL)
    selector=selectors.DefaultSelector();selector.register(process.stdout,selectors.EVENT_READ)
    result=None;pending=b''
    try:
        process.stdin.write(b'{"method":"catalog"}\n');process.stdin.flush()
        deadline=time.monotonic()+30
        while result is None and time.monotonic()<deadline:
            events=selector.select(timeout=min(1,max(0,deadline-time.monotonic())))
            if not events and process.poll() is not None:break
            for key,_ in events:
                data=os.read(key.fd,8192)
                if not data:raise RuntimeError('Bundled runtime exited without a result')
                pending+=data
                assert len(pending)<1_000_000,'Unexpected runtime response size'
                while b'\n' in pending:
                    row,pending=pending.split(b'\n',1)
                    event=json.loads(row)
                    if event.get('type')=='error':raise RuntimeError('Bundled runtime reported an error')
                    if event.get('type')=='result':result=event['result']
        assert result and result.get('version')=='1.2.0','Bundled Pi failed to start'
        providers=result['providers']
        assert any(x['id']=='openai' for x in providers)
        assert all(x.get('credential') is None for x in providers),'Unexpected credentials in isolated runtime'
        assert process.wait(timeout=5)==0
    finally:
        selector.close()
        if process.poll() is None:process.kill();process.wait(timeout=5)
        process.stdin.close();process.stdout.close()
print(f'PASS: Quillside {a.version}, arm64 app/Node, signatures, resources, no bundled credentials; Pi {result["version"]} starts with {len(providers)} providers and exits.')
