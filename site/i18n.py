"""Build-time website localization. Source Chinese strings act as gettext-style keys."""
from html import escape
from html.parser import HTMLParser
from pathlib import Path
import json
import re

LANGUAGES = {'zh-CN': '简体中文', 'zh-TW': '繁體中文', 'en': 'English'}
DEFAULT_LANGUAGE = 'zh-CN'
PAGES = ('index', 'guide', 'download', 'privacy', 'open-source')
CJK = re.compile(r'[\u3400-\u9fff]')
SITE = Path(__file__).resolve().parent

UI = {
    'sceneTitles': ['从读者的理解出发', '留给未来的自己回看', '讲清结果，也讲清边界'],
    'sceneDescriptions': ['用自然段讲清变化与限制，保持自然衔接，避免夸张判断。', '用观察、依据、边界与下一步组织材料，方便回顾，保留疑问。', '结果先行，说明指标口径、影响与下一步，不补造负责人和日期。'],
    'comments': ['去掉夸大的表述，保留试用的范围和限制。', '保留三位同事的口头反馈，不要扩展成整体满意度。'],
    'editComment': '编辑意见后，点击保存批注', 'emptyComment': '请先写下一条具体意见',
    'commentSaved': '批注已留在网页示例中', 'presetResult': '展示预设结果，不调用模型',
    'applied': '已更新网页示例 · 两条批注仍保留', 'restored': '已恢复原文，批注意见仍保留',
    'editSamples': {
        'title': {'command': '/h1', 'title': '把思路写下来', 'description': '标题，让一页笔记有自己的层次。', 'icon': 'H1', 'label': '标题'},
        'checklist': {'command': '/checklist', 'title': '把下一步列清楚', 'description': '☐ 补记人工复核耗时\n☐ 试用另一类工单', 'icon': '☑', 'label': '核对清单'},
        'template': {'command': '/meeting', 'title': '项目沟通记录', 'description': '议题 · 关键讨论 · 待确认事项\n把常用结构留成自己的模板。', 'icon': '▤', 'label': '插入模板'},
    },
}

class Localizer:
    def __init__(self, locale):
        self.locale = locale
        self.catalog = {} if locale == DEFAULT_LANGUAGE else json.loads((SITE / 'locales' / f'{locale}.json').read_text())['messages']

    def text(self, text):
        key = text.strip()
        if not key or self.locale == DEFAULT_LANGUAGE:
            return text
        if not CJK.search(key):
            return text.translate(str.maketrans({'。': '.', '，': ', ', '：': ': ', '；': '; '})) if self.locale == 'en' else text
        if key not in self.catalog or not self.catalog[key].strip():
            raise ValueError(f'Missing {self.locale} translation: {key}')
        return text[:len(text) - len(text.lstrip())] + self.catalog[key] + text[len(text.rstrip()):]

    def data(self, value):
        if isinstance(value, str): return self.text(value)
        if isinstance(value, list): return [self.data(x) for x in value]
        if isinstance(value, dict): return {k: self.data(v) for k, v in value.items()}
        return value

    def html(self, source, asset_prefix):
        parser = LocalizedHTML(self, asset_prefix)
        parser.feed(source)
        parser.close()
        return ''.join(parser.parts)

class LocalizedHTML(HTMLParser):
    def __init__(self, localizer, asset_prefix):
        super().__init__(convert_charrefs=False)
        self.localizer, self.asset_prefix, self.parts = localizer, asset_prefix, []

    def handle_starttag(self, tag, attrs): self.start(tag, attrs, False)
    def handle_startendtag(self, tag, attrs): self.start(tag, attrs, True)
    def start(self, tag, attrs, closed):
        rendered = []
        for key, value in attrs:
            if value is not None:
                if tag == 'html' and key == 'lang': value = self.localizer.locale
                elif key in {'alt', 'aria-label', 'placeholder', 'title'} or (tag == 'meta' and key == 'content'):
                    value = self.localizer.text(value)
                if key in {'src', 'href'} and value.startswith(('assets/', 'licenses/')):
                    value = self.asset_prefix + value
            rendered.append(key if value is None else f'{key}="{escape(value, quote=True)}"')
        self.parts.append('<' + tag + (' ' + ' '.join(rendered) if rendered else '') + ('/>' if closed else '>'))
    def handle_endtag(self, tag): self.parts.append(f'</{tag}>')
    def handle_data(self, data): self.parts.append(escape(self.localizer.text(data), quote=False))
    def handle_entityref(self, name): self.parts.append(f'&{name};')
    def handle_charref(self, name): self.parts.append(f'&#{name};')
    def handle_decl(self, decl): self.parts.append(f'<!{decl}>')
    def handle_comment(self, data): self.parts.append(f'<!--{data}-->')


def language_links(locale, page, root_alias=False):
    prefix = '' if root_alias else '../'
    localizer = Localizer(locale)
    links = ''.join(f'<a href="{prefix}{code}/{page}.html" lang="{code}" hreflang="{code}" data-locale="{code}"'
                    + (' aria-current="true"' if code == locale else '') + f'>{label}</a>' for code, label in LANGUAGES.items())
    return (f'<details class="language-switch"><summary aria-label="{escape(localizer.text("选择网站语言"))}">'
            f'<span aria-hidden="true">◎</span> {LANGUAGES[locale]} <span aria-hidden="true">⌄</span></summary>'
            f'<nav aria-label="{escape(localizer.text("网站语言"))}">{links}</nav></details>')


def alternate_links(page, root_alias=False):
    prefix = '' if root_alias else '../'
    return ''.join(f'<link rel="alternate" hreflang="{code}" href="{prefix}{code}/{page}.html">' for code in LANGUAGES) + f'<link rel="alternate" hreflang="x-default" href="{prefix}{page}.html">'
