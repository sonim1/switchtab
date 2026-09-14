#!/usr/bin/env bash
set -euo pipefail

python3 - <<'PY'
from html.parser import HTMLParser
from pathlib import Path
import re

prompt_path = Path('docs/install-with-ai.txt')
assert prompt_path.is_file(), 'missing public agent installation prompt'
prompt = prompt_path.read_text().strip()
readme = Path('README.md').read_text()
html = Path('docs/index.html').read_text()

class Prompt(HTMLParser):
    def __init__(self):
        super().__init__()
        self.capture = False
        self.parts = []
        self.count = 0

    def handle_starttag(self, tag, attrs):
        attributes = dict(attrs)
        if tag == 'textarea' and attributes.get('id') == 'agent-install-prompt':
            assert 'readonly' in attributes
            self.capture = True
            self.count += 1

    def handle_data(self, data):
        if self.capture:
            self.parts.append(data)

    def handle_endtag(self, tag):
        if tag == 'textarea':
            self.capture = False

parser = Prompt()
parser.feed(html)
assert parser.count == 1, 'one selectable installation prompt required'
assert ''.join(parser.parts).strip() == prompt, 'homepage prompt drift'
section = readme.split('### Install with AI', 1)[1].split('\n## ', 1)[0]
blocks = re.findall(r'```text\n(.*?)\n```', section, re.DOTALL)
assert blocks == [prompt], 'README prompt drift'
assert '<label for="agent-install-prompt">Installation prompt</label>' in html
assert '<summary>Install with AI</summary>' in html
assert 'href="/install-with-ai.txt"' in html
assert 'https://switchtab.royjen.com/install-with-ai.txt' in section
print('agent installation contract passed')
PY
