#!/usr/bin/env python3
"""Validate locale coverage, page links, language navigation and preview boundaries."""
from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import urlparse, unquote
import json
import re
from i18n import LANGUAGES, DEFAULT_LANGUAGE, PAGES, Localizer, UI

BASE = Path(__file__).resolve().parent / 'dist'
class Page(HTMLParser):
    def __init__(self, path):
        super().__init__()
        self.path = path; self.ids = set(); self.refs = []; self.h1 = 0; self.errors = []
        self.lang = None; self.languages = {}; self.alternates = {}; self.script_id = None; self.scripts = {}
        self.feed(path.read_text())
    def handle_starttag(self, tag, attrs):
        a = dict(attrs)
        if tag == 'html': self.lang = a.get('lang')
        if a.get('id'):
            if a['id'] in self.ids: self.errors.append(f'duplicate id {a["id"]}')
            self.ids.add(a['id'])
        if tag == 'h1': self.h1 += 1
        if tag == 'img' and 'alt' not in a: self.errors.append('image without alt')
        if tag == 'a' and a.get('data-locale'): self.languages[a['data-locale']] = a.get('href')
        if tag == 'link' and a.get('rel') == 'alternate': self.alternates[a.get('hreflang')] = a.get('href')
        if tag == 'script':
            self.script_id = a.get('id')
            if self.script_id: self.scripts[self.script_id] = ''
        for attribute in ('href', 'src'):
            if a.get(attribute): self.refs.append(a[attribute])
    def handle_endtag(self, tag):
        if tag == 'script': self.script_id = None
    def handle_data(self, text):
        if self.script_id: self.scripts[self.script_id] += text
        if self.lang == 'en' and re.search(r'[\u3400-\u9fff]', text) and text.strip() not in LANGUAGES.values():
            self.errors.append('Untranslated Chinese in English page: ' + text.strip()[:80])

pages = {p.resolve(): Page(p) for p in BASE.rglob('*.html')}
errors = []
expected_paths = {BASE / f'{page}.html' for page in PAGES}
expected_paths |= {BASE / locale / f'{page}.html' for locale in LANGUAGES for page in PAGES}
if set(pages) != {p.resolve() for p in expected_paths}: errors.append('Missing or unexpected localized pages')
for path, page in pages.items():
    name = str(path.relative_to(BASE.resolve()))
    errors += [f'{name}: {e}' for e in page.errors]
    locale = DEFAULT_LANGUAGE if path.parent == BASE.resolve() else path.parent.name
    if page.lang != locale: errors.append(f'{name}: incorrect html lang')
    if page.h1 != 1: errors.append(f'{name}: expected one h1')
    if set(page.languages) != set(LANGUAGES): errors.append(f'{name}: incomplete language menu')
    if set(page.alternates) != set(LANGUAGES) | {'x-default'}: errors.append(f'{name}: incomplete hreflang links')
    for code, ref in page.languages.items():
        if (path.parent / urlparse(ref).path).resolve() != (BASE / code / path.name).resolve():
            errors.append(f'{name}: language switch loses current page')
    for code, ref in page.alternates.items():
        target = BASE / ('' if code == 'x-default' else code) / path.name
        if (path.parent / urlparse(ref).path).resolve() != target.resolve(): errors.append(f'{name}: wrong alternate language target')
    for ref in page.refs:
        url = urlparse(ref)
        if url.scheme or url.netloc: continue
        target = (path.parent / unquote(url.path)).resolve() if url.path else path
        if not target.is_relative_to(BASE.resolve()): errors.append(f'{name}: outside site {ref}'); continue
        if not target.exists(): errors.append(f'{name}: missing {ref}'); continue
        if url.fragment and target in pages and unquote(url.fragment) not in pages[target].ids: errors.append(f'{name}: missing fragment {ref}')
    try:
        ui = json.loads(page.scripts['ui-data'])
        if ui != dict(Localizer(locale).data(UI), locales=list(LANGUAGES)): errors.append(f'{name}: wrong dynamic UI language')
        if path.stem == 'index':
            examples = json.loads(page.scripts['scene-data'])
            if len(examples['roles']) != 3: errors.append(f'{name}: missing scenario examples')
            if locale != DEFAULT_LANGUAGE and examples.get('translated_from') != DEFAULT_LANGUAGE: errors.append(f'{name}: translated example lacks provenance')
    except (KeyError, ValueError) as error: errors.append(f'{name}: invalid embedded data ({error})')
    if re.search(r'\{\{[A-Z_]+\}\}', path.read_text()): errors.append(f'{name}: unresolved template marker')
release = json.loads((BASE / 'release.json').read_text())
if release['status'] == 'preview':
    if release['download_url']: errors.append('Preview must not advertise a public download')
    for path in pages:
        if 'content="noindex,nofollow"' not in path.read_text(): errors.append(f'{path.name}: preview must be noindex')
if errors: raise SystemExit('\n'.join(errors))
print(f'PASS: {len(LANGUAGES)} languages, {len(LANGUAGES) * len(PAGES)} localized pages + {len(PAGES)} root aliases, links/assets/anchors, language targets, translated UI and publication state')
