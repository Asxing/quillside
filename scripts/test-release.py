#!/usr/bin/env python3
"""Behavior checks for publish gates and website download claims; no remote mutation."""
from pathlib import Path
import copy
import hashlib
import importlib.util
import json
import tempfile
import unittest
import zipfile
import subprocess
from unittest.mock import patch

ROOT = Path(__file__).resolve().parent.parent

def module(name, path):
    spec=importlib.util.spec_from_file_location(name, ROOT/path); result=importlib.util.module_from_spec(spec);spec.loader.exec_module(result);return result
release=module('quillside_release','scripts/release.py')
site=module('quillside_site_release','scripts/site-release.py')
live_site=module('quillside_live_site','scripts/verify-published-site.py')

class ReleaseGuardTests(unittest.TestCase):
    def test_tag_and_mode_must_match(self):
        for tag,version,mode in [('v1.2.3','1.2.4','source'),('main','1.2.3','source'),('v1.2.3','1.2.3','unknown'),('v1.2.3;bad','1.2.3;bad','source')]:
            with self.assertRaises(ValueError):release.validate(tag,version,mode)
        self.assertTrue(release.validate('v1.2.3','1.2.3','source'))
        self.assertTrue(release.validate('v1.2.3','1.2.3','preview'))
        self.assertFalse(release.validate('v1.2.3','1.2.3','notarized'))
        self.assertTrue(release.validate('v1.2.3-beta.1','1.2.3-beta.1','notarized'))

    def fixture(self,directory,mode='source'):
        d=Path(directory); m={'schema':1,'tag':'v1.2.3','version':'1.2.3','commit':'a'*40,'distribution':mode,'prerelease':mode!='notarized'}
        (d/'release-metadata.json').write_text(json.dumps(m))
        source='Quillside-1.2.3-source.zip'
        with zipfile.ZipFile(d/source,'w') as z:
            z.writestr('Quillside-1.2.3/SOURCE_MANIFEST.json',json.dumps({'version':'1.2.3','basis':'clean-git-commit','base_commit':m['commit']}))
        (d/(source+'.sha256')).write_text(hashlib.sha256((d/source).read_bytes()).hexdigest()+'  '+source+'\n')
        return d,m

    def test_missing_asset_and_wrong_checksum_block_release(self):
        with tempfile.TemporaryDirectory() as directory:
            d,_=self.fixture(directory,'preview')
            with self.assertRaisesRegex(ValueError,'missing'):release.inventory(d)
            for suffix in ('.zip','.dmg'):
                filename='Quillside-1.2.3-UNNOTARIZED-macOS-arm64'+suffix
                (d/filename).write_bytes(b'app')
                (d/(filename+'.sha256')).write_text(hashlib.sha256(b'app').hexdigest()+'  '+filename)
            m=release.inventory(d);self.assertTrue(m['prerelease'])
            (d/'Quillside-1.2.3-source.zip.sha256').write_text('0'*64+'  Quillside-1.2.3-source.zip')
            with self.assertRaisesRegex(ValueError,'checksum'):release.inventory(d)

    def test_source_archive_must_match_commit(self):
        with tempfile.TemporaryDirectory() as directory:
            d,m=self.fixture(directory)
            m['commit']='b'*40;(d/'release-metadata.json').write_text(json.dumps(m))
            with self.assertRaisesRegex(ValueError,'committed release'):release.inventory(d)

    def test_unexpected_file_not_published(self):
        with tempfile.TemporaryDirectory() as directory:
            d,_=self.fixture(directory)
            (d/'unexpected.txt').write_text('not approved for publishing')
            with self.assertRaisesRegex(ValueError,'Unexpected'):release.inventory(d)

    def test_official_requires_accepted_notary_receipt(self):
        with tempfile.TemporaryDirectory() as directory:
            d,_=self.fixture(directory,'notarized');filename='Quillside-1.2.3-macOS-arm64.dmg'
            (d/filename).write_bytes(b'dmg');(d/(filename+'.sha256')).write_text(hashlib.sha256(b'dmg').hexdigest()+'  '+filename)
            (d/'notarization.json').write_text(json.dumps({'id':'test','status':'Invalid'}))
            with self.assertRaisesRegex(ValueError,'Accepted'):release.inventory(d)
            (d/'notarization.json').write_text(json.dumps({'id':'test','status':'Accepted'}))
            self.assertFalse(release.inventory(d)['prerelease'])

    def web_fixture(self,mode):
        m={'tag':'v1.2.3','version':'1.2.3','distribution':mode,'prerelease':mode!='notarized','artifacts':{}}
        r={'tag_name':'v1.2.3','draft':False,'prerelease':m['prerelease'],'html_url':'https://github.com/owner/repo/releases/tag/v1.2.3','published_at':'2026-10-13T00:00:00Z','assets':[]}
        return m,r

    def test_previews_never_enable_official_downloads(self):
        for mode in ['source','preview']:
            m,r=self.web_fixture(mode)
            if mode=='preview':
                for ext in ('.zip','.dmg'):
                    name='Quillside-1.2.3-UNNOTARIZED-macOS-arm64'+ext
                    m['artifacts'][name]='a'*64
                    r['assets'].append({'name':name,'browser_download_url':f'https://github.com/owner/repo/releases/download/v1.2.3/{name}'})
            result=site.website_release({'download_url':'old','notarized':True},r,m,'owner/repo')
            self.assertEqual(result['status'],'preview');self.assertIsNone(result['download_url']);self.assertFalse(result['notarized'])
            self.assertEqual(bool(result['preview_download_url']),mode=='preview')

    def test_preview_download_requires_verified_assets_and_hashes(self):
        m,r=self.web_fixture('preview')
        with self.assertRaisesRegex(ValueError,'SHA-256'):site.website_release({},r,m,'owner/repo')
        for ext in ('.zip','.dmg'):
            name='Quillside-1.2.3-UNNOTARIZED-macOS-arm64'+ext
            m['artifacts'][name]='b'*64
            r['assets'].append({'name':name,'browser_download_url':f'https://github.com/owner/repo/releases/download/v1.2.3/{name}'})
        self.assertIn('UNNOTARIZED',site.website_release({},r,m,'owner/repo')['preview_download_url'])
        r['assets'][0]['browser_download_url']='https://other.invalid/app.zip'
        with self.assertRaisesRegex(ValueError,'unexpected URL'):site.website_release({},r,m,'owner/repo')

    def test_official_download_needs_exact_asset_and_hash(self):
        m,r=self.web_fixture('notarized')
        with self.assertRaises(ValueError):site.website_release({},r,m,'owner/repo')
        name='Quillside-1.2.3-macOS-arm64.dmg';m['artifacts'][name]='a'*64
        r['assets']=[{'name':name,'browser_download_url':f'https://github.com/owner/repo/releases/download/v1.2.3/{name}'},{'name':'notarization.json'}]
        result=site.website_release({},r,m,'owner/repo');self.assertTrue(result['notarized']);self.assertEqual(result['status'],'published')
        r['assets'][0]['browser_download_url']='https://other.invalid/app.dmg'
        with self.assertRaises(ValueError):site.website_release({},r,m,'owner/repo')

    def test_draft_and_channel_mismatch_never_enable_download(self):
        m,r=self.web_fixture('source');r['draft']=True
        with self.assertRaises(ValueError):site.website_release({},r,m,'owner/repo')
        r['draft']=False;r['prerelease']=False
        with self.assertRaises(ValueError):site.website_release({},r,m,'owner/repo')

    def app_fixture(self, directory):
        d,m=self.fixture(directory,'preview')
        for ext in ('.dmg','.zip'):
            name='Quillside-1.2.3-UNNOTARIZED-macOS-arm64'+ext
            (d/name).write_bytes(b'app-package')
            (d/(name+'.sha256')).write_text(hashlib.sha256(b'app-package').hexdigest()+'  '+name)
        (d/'release-notes.md').write_text('Reviewed version notes.')
        return d,m

    def test_publish_adds_downloads_then_checks_uploaded_bytes_before_publication(self):
        for corrupt in (False, True):
            with self.subTest(corrupt=corrupt), tempfile.TemporaryDirectory() as directory:
                d,m=self.app_fixture(directory)
                commands=[]
                def run(args, **kwargs):
                    commands.append(args)
                    return subprocess.CompletedProcess(args, 1 if args[1:3]==['release','view'] else 0)
                def output(args, **kwargs):
                    if '/commits/' in args[2]: return m['commit']
                    self.assertTrue(any(c[1:3]==['release','upload'] for c in commands))
                    assets=[{'name':p.name,'size':p.stat().st_size,'state':'uploaded',
                             'digest':'sha256:'+hashlib.sha256(p.read_bytes()).hexdigest()}
                            for p in d.iterdir() if p.name!='release-notes.md']
                    if corrupt: assets[0]['digest']='sha256:'+'0'*64
                    return json.dumps({'assets':assets,'draft':not any(c[1:3]==['release','edit'] for c in commands),
                                       'prerelease':True,'body':(d/'release-notes.md').read_text()})
                with patch.object(release.subprocess,'run',side_effect=run), patch.object(release.subprocess,'check_output',side_effect=output), patch.dict(release.os.environ, {'GITHUB_STEP_SUMMARY':''}):
                    if corrupt:
                        with self.assertRaisesRegex(ValueError,'Remote asset verification failed'): release.publish(d,'owner/repo')
                        self.assertFalse(any(c[1:3]==['release','edit'] for c in commands))
                    else:
                        release.publish(d,'owner/repo')
                        header=(d/'release-notes.md').read_text().split('---')[0]
                        for ext in ('.dmg','.zip'):
                            self.assertIn(f'https://github.com/owner/repo/releases/download/v1.2.3/Quillside-1.2.3-UNNOTARIZED-macOS-arm64{ext}',header)
                        self.assertIn('not notarized',header)
                        self.assertTrue(any('--prerelease=true' in c for c in commands))
                        self.assertTrue(any('Quillside 1.2.3 — macOS App (DMG + ZIP)' in c for c in commands))

    def test_source_download_header_never_links_an_app(self):
        with tempfile.TemporaryDirectory() as directory:
            d,_=self.fixture(directory)
            header=release.download_header(release.inventory(d),d,'owner/repo')
            self.assertIn('source.zip)',header)
            self.assertNotIn('.dmg',header)
            self.assertIn('no app binary',header)

    def test_pages_selects_newest_published_preview_and_preserves_stable(self):
        def record(number, **overrides):
            return dict({'id':number,'tag_name':f'v1.0.{number}','draft':False,'prerelease':True,
                         'published_at':f'2026-10-{number:02}T00:00:00Z','assets':[{'name':'release-metadata.json'}]},**overrides)
        old=record(1); new=record(2)
        self.assertEqual(site.select_release([old,record(4,draft=True),new,record(3,assets=[])])['tag_name'],'v1.0.2')
        stable=record(1,prerelease=False)
        self.assertEqual(site.select_release([new,stable]),stable)
        self.assertIsNone(site.select_release([record(1,draft=True)]))

    def test_live_site_retries_stale_content_and_checks_every_language(self):
        pages={name:name.encode() for name in live_site.PAGES}
        seen=[]
        def response(url, timeout):
            name=url.removeprefix('https://owner.github.io/repo/')
            seen.append(name)
            return b'old release' if len(seen)==1 else pages[name]
        with patch.object(live_site,'fetch',side_effect=response):
            live_site.verify('https://owner.github.io/repo/',pages,timeout=1,interval=0)
        self.assertEqual(seen,[live_site.PAGES[0],*live_site.PAGES])
        with patch.object(live_site,'fetch',return_value=b'old release'), patch.object(live_site.time,'sleep'), patch.object(live_site.time,'monotonic',side_effect=[0,0,0,2,2]):
            with self.assertRaisesRegex(ValueError,'timed out'):
                live_site.verify('https://owner.github.io/repo/',pages,timeout=1)

if __name__=='__main__':unittest.main(verbosity=2)
