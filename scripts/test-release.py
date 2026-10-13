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

ROOT = Path(__file__).resolve().parent.parent

def module(name, path):
    spec=importlib.util.spec_from_file_location(name, ROOT/path); result=importlib.util.module_from_spec(spec);spec.loader.exec_module(result);return result
release=module('quillside_release','scripts/release.py')
site=module('quillside_site_release','scripts/site-release.py')

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

if __name__=='__main__':unittest.main(verbosity=2)
