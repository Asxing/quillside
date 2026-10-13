#!/usr/bin/env python3
"""Build localized, directly linkable static pages without third-party packages."""
from pathlib import Path
import html
import argparse
import hashlib
import json
import re
import shutil
from i18n import LANGUAGES, DEFAULT_LANGUAGE, PAGES, UI, Localizer, language_links, alternate_links

SITE = Path(__file__).resolve().parent
ROOT = SITE.parent
DIST = SITE / 'dist'
version = (ROOT / 'VERSION').read_text().strip()
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--release-metadata', type=Path, help='Verified GitHub release metadata for the website')
args = parser.parse_args()
release = json.loads((args.release_metadata or (SITE / 'content/release.json')).read_text())
version = release.get('version') or version
release['version'] = version
if release['status'] not in {'preview', 'published'}:
    raise SystemExit('Unknown release status')
if release['status'] == 'published':
    if not (release['notarized'] and release['download_url'] and release['download_url'].startswith('https://')
            and re.fullmatch(r'[a-f0-9]{64}', release['sha256'] or '') and release['published_at']):
        raise SystemExit('Published releases require notarization, HTTPS asset, SHA-256 and publication date')
evidence = json.loads((ROOT / 'docs/real-agent-scenes-0.6.3.json').read_text())
examples = {'date': evidence['date'], 'version': evidence['version'], 'source': evidence['case']['source'],
            'roles': [{key: item[key] for key in ('role', 'prompt', 'candidate', 'style_observation')}
                      for item in evidence['roles']]}
DIST.mkdir(exist_ok=True)
(DIST / '.nojekyll').touch()
brand_sources = {
    'app-icon.png': ROOT / 'resources/AppIcon-1024.png',
    'brand-mark.png': ROOT / 'resources/Brand/Quillside-Mark.png',
    'brand-mark.svg': ROOT / 'resources/Brand/Quillside-Mark.svg',
}
for name, source in brand_sources.items():
    shutil.copy2(source, SITE / 'assets' / name)
brand_revision = hashlib.sha256(b''.join(path.read_bytes() for path in brand_sources.values())).hexdigest()[:12]
site_revision = hashlib.sha256(b''.join((SITE / 'assets' / name).read_bytes() for name in ('site.css', 'site.js'))).hexdigest()[:12]
shutil.copytree(SITE / 'assets', DIST / 'assets', dirs_exist_ok=True)
(DIST / 'licenses').mkdir(exist_ok=True)
shutil.copy2(ROOT / 'LICENSE', DIST / 'licenses/LICENSE.txt')
shutil.copy2(ROOT / 'THIRD_PARTY_NOTICES.md', DIST / 'licenses/THIRD_PARTY_NOTICES.txt')
for path in (ROOT / 'licenses').glob('*.txt'):
    shutil.copy2(path, DIST / 'licenses' / path.name)
shutil.copytree(ROOT / 'licenses/pi-runtime', DIST / 'licenses/pi-runtime', dirs_exist_ok=True)
(DIST / 'release.json').write_text(json.dumps(release, ensure_ascii=False, indent=2) + '\n')


def render(template, values, strict=True):
    for _ in range(6):
        previous = template
        for key, value in values.items():
            template = template.replace('{{' + key + '}}', value)
        if template == previous: break
    if strict and re.search(r'\{\{[A-Z_]+\}\}', template):
        raise ValueError('Unresolved template marker')
    return template


def json_script(value):
    return json.dumps(value, ensure_ascii=False).replace('<', '\\u003c')


repo = release['repository_url']
repo_link = (f'<a class="button primary" href="{html.escape(repo, quote=True)}" rel="noopener noreferrer">在 GitHub 查看源码 ↗</a>'
             if repo and repo.startswith('https://github.com/') else '<p class="status-note">公开仓库尚未开放，首次发布时将在这里提供入口。</p>')
if release['status'] == 'published':
    download = (f'<a class="button primary" href="{html.escape(release["download_url"], quote=True)}">下载 Mac 版 · {{{{VERSION}}}}</a>'
                f'<p class="checksum">SHA-256<br><code>{release["sha256"]}</code></p>')
    release_heading, release_copy = '开始在 Notes 中写得更好。', '正式版本已发布。下载后打开安装包，将应用拖入 Applications。'
else:
    download = '<span class="button disabled" aria-disabled="true">正式安装包准备中</span><a class="text-link" href="guide.html">先了解如何使用 <span aria-hidden="true">↗</span></a>'
    release_heading, release_copy = '准备好，再交到你手上。', '当前为官网预览。应用已完成本机核心流程验收，正式安装包将在签名、公证与安装测试完成后提供。'

if release.get('source_release_url'):
    download += f'<a class="text-link" href="{html.escape(release["source_release_url"], quote=True)}">查看 GitHub 源码与测试版本 ↗</a>'

metadata = {
    'index': ('Quillside Notes', ''),
    'guide': ('快速上手', '从安装与授权，到第一次在原文中完成修改。'),
    'download': ('获取 Quillside', '查看当前版本、支持范围与正式发布进度。'),
    'privacy': ('数据与隐私', '了解 Quillside 在本地保存什么，以及使用远程 AI 时发送什么。'),
    'open-source': ('开源与反馈', '了解许可证、代码来源、公开计划和反馈方式。'),
}
header = (SITE / 'templates/header.html').read_text()
footer = (SITE / 'templates/footer.html').read_text()
for locale in LANGUAGES:
    localizer = Localizer(locale)
    localized_examples = examples
    if locale != DEFAULT_LANGUAGE:
        translation = json.loads((SITE / 'locales' / f'{locale}.examples.json').read_text())
        if translation['version'] != examples['version'] or translation['source_sha256'] != hashlib.sha256(json_script(examples).encode()).hexdigest():
            raise ValueError(f'{locale} example translations need review against the current evidence')
        localized_examples = translation
    for root_alias in ([False, True] if locale == DEFAULT_LANGUAGE else [False]):
        destination = DIST if root_alias else DIST / locale
        destination.mkdir(exist_ok=True)
        prefix = '' if root_alias else '../'
        for page in PAGES:
            template = (SITE / 'templates' / ('index.html' if page == 'index' else 'page.html')).read_text()
            source = render(template, {'HEADER': header, 'FOOTER': footer,
                           'BODY': '' if page == 'index' else (SITE / 'content' / f'{page}.html').read_text()}, strict=False)
            values = {
                'VERSION': html.escape(version), 'BRAND_REVISION': brand_revision,
                'SITE_REVISION': site_revision,
                'LOCALE': locale, 'ROOT_ALIAS': str(root_alias).lower(),
                'ALTERNATES': alternate_links(page, root_alias),
                'LANGUAGE_SWITCH': language_links(locale, page, root_alias),
                'UI_JSON': json_script(dict(localizer.data(UI), locales=list(LANGUAGES))),
                'EXAMPLES_JSON': json_script(localized_examples), 'EXAMPLE_VERSION': html.escape(examples['version']),
                'EXAMPLE_TRANSLATION_NOTE': '' if locale == DEFAULT_LANGUAGE else localizer.text(' · 本页为中文材料译文，非另一次模型测试'),
                'TITLE': html.escape(localizer.text(metadata[page][0])), 'DESCRIPTION': html.escape(localizer.text(metadata[page][1])),
                'RELEASE_HEADING': html.escape(localizer.text(release_heading)), 'RELEASE_COPY': html.escape(localizer.text(release_copy)),
                'DOWNLOAD_ACTION': localizer.html(download, prefix), 'REPOSITORY_ACTION': localizer.html(repo_link, prefix),
                'ARCHITECTURE': html.escape(release['architecture']), 'MIN_MACOS': html.escape(release['minimum_macos']),
                'TESTED_MACOS': html.escape(release['tested_macos']),
                'CURRENT_STAGE': localizer.text('已发布' if release['status'] == 'published' else '开发版 · 正式发布准备中'),
            }
            (destination / f'{page}.html').write_text(render(localizer.html(source, prefix), values))
(DIST / 'robots.txt').write_text('User-agent: *\nDisallow: /\n' if release['status'] == 'preview' else 'User-agent: *\nAllow: /\n')
print(f'Built {len(LANGUAGES) * len(PAGES)} localized pages + {len(PAGES)} compatible root pages · {version} · {release["status"]}')
