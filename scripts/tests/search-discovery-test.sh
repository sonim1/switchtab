#!/usr/bin/env bash
set -euo pipefail

cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.."

python3 - <<'PY'
from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import urlsplit
import json
import xml.etree.ElementTree as ET

origin = "https://switchtab.royjen.com"
guide_url = origin + "/guides/switch-windows-on-mac/"

class Page(HTMLParser):
    def __init__(self, path):
        super().__init__()
        self.path = path
        self.links = []
        self.assets = []
        self.ids = set()
        self.canonicals = []
        self.meta = {}
        self.h1 = 0
        self.scripts = []
        self.script = None
        self.feed(path.read_text())

    def handle_starttag(self, tag, attributes):
        attrs = dict(attributes)
        if "id" in attrs:
            assert attrs["id"] not in self.ids, (self.path, "duplicate id", attrs["id"])
            self.ids.add(attrs["id"])
        if tag == "a":
            self.links.append(attrs["href"])
        if tag == "img":
            self.assets.append(attrs["src"])
            assert "alt" in attrs, self.path
        if tag == "link":
            if attrs.get("rel") == "canonical":
                self.canonicals.append(attrs["href"])
            elif attrs.get("rel") in {"stylesheet", "icon"}:
                self.assets.append(attrs["href"])
        if tag == "meta":
            self.meta[attrs.get("name", attrs.get("property"))] = attrs.get("content")
        if tag == "h1":
            self.h1 += 1
        if tag == "script":
            assert attrs.get("type") == "application/ld+json" and "src" not in attrs, self.path
            self.script = ""

    def handle_data(self, data):
        if self.script is not None:
            self.script += data

    def handle_endtag(self, tag):
        if tag == "script":
            self.scripts.append(json.loads(self.script))
            self.script = None

def local_file(path):
    relative = path.lstrip("/")
    return Path("docs") / (relative + "index.html" if path.endswith("/") else relative)

home = Page(Path("docs/index.html"))
guide = Page(local_file(urlsplit(guide_url).path))
assert guide.h1 == 1
assert guide.canonicals == [guide_url]
assert guide.meta["og:url"] == guide_url
assert guide.meta["description"]
assert "noindex" not in guide.meta["robots"]
assert len(guide.scripts) == 1 and guide.scripts[0]["mainEntityOfPage"] == guide_url
assert "/guides/switch-windows-on-mac/" in home.links
assert "/" in guide.links and "/#how-it-works" in guide.links
assert "https://github.com/sonim1/switchtab/releases/latest" in guide.links

for page in (home, guide):
    for href in page.links + page.assets:
        parsed = urlsplit(href)
        if parsed.scheme or parsed.netloc:
            continue
        target = local_file(parsed.path) if parsed.path.startswith("/") else page.path.parent / parsed.path
        if not parsed.path:
            target = page.path
        if target.is_dir():
            target /= "index.html"
        assert target.is_file(), (page.path, href, "missing local target")
        if parsed.fragment:
            assert parsed.fragment in Page(target).ids, (page.path, href, "missing fragment")

locations = [node.text for node in ET.parse("docs/sitemap.xml").findall("{*}url/{*}loc")]
assert len(locations) == len(set(locations))
assert guide_url in locations
for url in locations:
    assert url.startswith(origin + "/")
    assert Page(local_file(urlsplit(url).path)).canonicals == [url]

readme = Path("README.md").read_text()
assert 'href="https://switchtab.royjen.com/"' in readme.split("## Installation")[0]
assert 'href="#installation"' in readme
assert readme.index("## Installation") < readme.index("## Quick Start")
assert "brew install --cask sonim1/tap/switchtab" in readme
assert guide_url in readme
print("search discovery contracts passed")
PY
