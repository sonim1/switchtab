# Landing Page AEO/SEO Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the existing SwitchTab landing page crawlable and answer-ready at `https://switchtab.royjen.com/` without redesigning it.

**Architecture:** Keep the site as static HTML/CSS on Cloudflare Pages. Add truthful visible answers, canonical/social metadata, one JSON-LD graph, dedicated crawl/error resources, and contract coverage; consolidate the generated `pages.dev` host to the custom domain through Cloudflare’s host-level redirect configuration.

**Tech Stack:** HTML5, CSS, Bash contract tests, Python 3 standard library, Ruby/YAML workflow test, Cloudflare Pages/Wrangler, agent-browser, SwiftPM verification

---

## File map

- Modify `docs/index.html`: search metadata, JSON-LD, descriptive hero copy, root links, and quick answers.
- Modify `docs/landing.css`: quick-answer grid and 404 layout styling only.
- Create `docs/social-card.png`: 1200 by 630 product preview.
- Create `docs/robots.txt`: crawler allow rules and sitemap discovery.
- Create `docs/sitemap.xml`: canonical home URL.
- Create `docs/404.html`: real branded missing-route document.
- Modify `scripts/tests/landing-contract-test.sh`: SEO, JSON-LD, crawl resource, PNG dimension, and 404 contracts.
- Modify `scripts/tests/landing-deploy-workflow-test.sh`: custom production environment URL contract.
- Modify `.github/workflows/landing-deploy.yml`: custom production environment URL.
- Modify `README.md`: public landing URL plus source link.
- Create `docs/superpowers/plans/2026-08-24-landing-aeo-seo.md`: this execution plan.

No Swift, Xcode, entitlement, app permission, release artifact, or update feed file changes.

### Task 1: Lock the SEO and crawl contracts

**Files:**
- Modify: `scripts/tests/landing-contract-test.sh:4-79`
- Test: `scripts/tests/landing-contract-test.sh`

- [ ] **Step 1: Add the new required assets to the contract**

Replace the variable and first asset loop with:

```bash
page='docs/index.html'
style='docs/landing.css'
headers='docs/_headers'
icon='docs/AppIcon-256.png'
social_card='docs/social-card.png'
robots='docs/robots.txt'
sitemap='docs/sitemap.xml'
not_found='docs/404.html'

for path in "$page" "$style" "$headers" "$icon" "$social_card" "$robots" "$sitemap" "$not_found"; do
  test -s "$path" || { echo "missing landing asset: $path" >&2; exit 1; }
done
```

- [ ] **Step 2: Add metadata, visible-answer, and JSON-LD assertions**

Insert after the semantic element checks:

```bash
grep -q '<title>SwitchTab — Free macOS App &amp; Window Switcher</title>' "$page"
grep -q '<link rel="canonical" href="https://switchtab.royjen.com/">' "$page"
grep -q '<meta name="robots" content="index, follow, max-image-preview:large">' "$page"
grep -q '<meta property="og:url" content="https://switchtab.royjen.com/">' "$page"
grep -q '<meta property="og:image" content="https://switchtab.royjen.com/social-card.png">' "$page"
grep -q '<meta name="twitter:card" content="summary_large_image">' "$page"
grep -q 'id="quick-answers"' "$page"
grep -q 'What is SwitchTab?' "$page"
grep -q 'How is SwitchTab different from macOS Command-Tab?' "$page"
grep -q 'Does SwitchTab require Screen Recording?' "$page"
grep -q 'Is SwitchTab free?' "$page"
test "$(grep -o '<script type="application/ld+json">' "$page" | wc -l | tr -d ' ')" = 1

python3 - "$page" <<'PY'
from html.parser import HTMLParser
import json
from pathlib import Path
import sys

class Scripts(HTMLParser):
    def __init__(self):
        super().__init__()
        self.capture = False
        self.types = []
        self.buffers = []

    def handle_starttag(self, tag, attrs):
        if tag != "script":
            return
        attributes = dict(attrs)
        self.types.append(attributes.get("type"))
        self.capture = True
        self.buffers.append([])

    def handle_data(self, data):
        if self.capture:
            self.buffers[-1].append(data)

    def handle_endtag(self, tag):
        if tag == "script":
            self.capture = False

parser = Scripts()
parser.feed(Path(sys.argv[1]).read_text())
assert parser.types == ["application/ld+json"], parser.types
payload = json.loads("".join(parser.buffers[0]))
assert payload["@context"] == "https://schema.org"
nodes = {node["@type"]: node for node in payload["@graph"]}
assert nodes["WebSite"]["name"] == "SwitchTab"
assert nodes["WebSite"]["url"] == "https://switchtab.royjen.com/"
app = nodes["SoftwareApplication"]
assert app["operatingSystem"] == "macOS 14 or later"
assert app["offers"] == {"@type": "Offer", "price": "0", "priceCurrency": "USD"}
assert "aggregateRating" not in app
assert "review" not in app
PY
```

- [ ] **Step 3: Preserve the no-executable-script policy**

Replace the current broad script/video/tracker check with:

```bash
if grep -qiE '<video[[:space:]>]|<canvas[[:space:]>]|tracker|analytics|http://' "$page" "$style"; then
  echo 'landing page must stay free of video, canvas, trackers, analytics, and insecure URLs' >&2
  exit 1
fi
test "$(grep -oE '<script([[:space:]][^>]*)?>' "$page" | wc -l | tr -d ' ')" = 1 || {
  echo 'landing page must contain only its JSON-LD script' >&2
  exit 1
}
```

- [ ] **Step 4: Add crawl, 404, and image assertions**

Insert before the existing demo asset checks:

```bash
grep -qx 'User-agent: \*' "$robots"
grep -qx 'User-agent: OAI-SearchBot' "$robots"
grep -qx 'Sitemap: https://switchtab.royjen.com/sitemap.xml' "$robots"
grep -q '<loc>https://switchtab.royjen.com/</loc>' "$sitemap"
grep -q '<title>Page not found — SwitchTab</title>' "$not_found"
grep -q 'href="/"' "$not_found"
if grep -qE 'rel="canonical"|application/ld\+json' "$not_found"; then
  echo '404 page must not publish home-page search signals' >&2
  exit 1
fi
if grep -q 'href="index.html"' "$page"; then
  echo 'home links must use the canonical root path' >&2
  exit 1
fi

python3 - "$sitemap" "$social_card" <<'PY'
from pathlib import Path
import struct
import sys
import xml.etree.ElementTree as ET

sitemap, card = map(Path, sys.argv[1:])
root = ET.parse(sitemap).getroot()
namespace = {"s": "http://www.sitemaps.org/schemas/sitemap/0.9"}
locations = [node.text for node in root.findall("s:url/s:loc", namespace)]
assert locations == ["https://switchtab.royjen.com/"], locations
data = card.read_bytes()[:24]
assert data[:8] == b"\x89PNG\r\n\x1a\n"
width, height = struct.unpack(">II", data[16:24])
assert (width, height) == (1200, 630), (width, height)
PY
```

- [ ] **Step 5: Run the contract and verify it fails for missing implementation**

Run:

```bash
rtk test bash scripts/tests/landing-contract-test.sh
```

Expected: FAIL with `missing landing asset: docs/social-card.png`.

- [ ] **Step 6: Commit the failing contract**

```bash
rtk git add scripts/tests/landing-contract-test.sh
rtk git commit -m "test: define landing search contracts"
```

### Task 2: Add search metadata and answer-ready content

**Files:**
- Modify: `docs/index.html:3-10,27-35,115-179`
- Modify: `docs/landing.css:226-313`
- Test: `scripts/tests/landing-contract-test.sh`

- [ ] **Step 1: Replace the document head metadata**

Keep charset and viewport first, then use this exact head content before the favicon and stylesheet links:

```html
    <meta name="description" content="SwitchTab is a free, native macOS app and window switcher. Use Command-Tab for apps and Command-Backtick for windows, with optional live previews.">
    <meta name="robots" content="index, follow, max-image-preview:large">
    <title>SwitchTab — Free macOS App &amp; Window Switcher</title>
    <link rel="canonical" href="https://switchtab.royjen.com/">
    <meta property="og:type" content="website">
    <meta property="og:site_name" content="SwitchTab">
    <meta property="og:title" content="SwitchTab — Free macOS App &amp; Window Switcher">
    <meta property="og:description" content="Switch apps with Command-Tab, then land on the exact window with Command-Backtick.">
    <meta property="og:url" content="https://switchtab.royjen.com/">
    <meta property="og:image" content="https://switchtab.royjen.com/social-card.png">
    <meta property="og:image:width" content="1200">
    <meta property="og:image:height" content="630">
    <meta property="og:image:alt" content="SwitchTab switching from macOS apps to a selected window">
    <meta name="twitter:card" content="summary_large_image">
    <meta name="twitter:title" content="SwitchTab — Free macOS App &amp; Window Switcher">
    <meta name="twitter:description" content="Switch apps with Command-Tab, then land on the exact window with Command-Backtick.">
    <meta name="twitter:image" content="https://switchtab.royjen.com/social-card.png">
    <script type="application/ld+json">
      {
        "@context": "https://schema.org",
        "@graph": [
          {
            "@type": "WebSite",
            "@id": "https://switchtab.royjen.com/#website",
            "url": "https://switchtab.royjen.com/",
            "name": "SwitchTab"
          },
          {
            "@type": "SoftwareApplication",
            "@id": "https://switchtab.royjen.com/#software",
            "name": "SwitchTab",
            "url": "https://switchtab.royjen.com/",
            "downloadUrl": "https://github.com/sonim1/switchtab/releases/latest",
            "description": "A free, native macOS app and window switcher for keyboard-first navigation.",
            "applicationCategory": "UtilitiesApplication",
            "operatingSystem": "macOS 14 or later",
            "isAccessibleForFree": true,
            "offers": {
              "@type": "Offer",
              "price": "0",
              "priceCurrency": "USD"
            }
          }
        ]
      }
    </script>
```

- [ ] **Step 2: Replace the hero descriptor, heading, and lead**

Use:

```html
          <p class="eyebrow"><span class="eyebrow-dot" aria-hidden="true"></span> Free native macOS app and window switcher</p>
          <h1 id="hero-title">Switch apps.<br><em>Land on the exact window.</em></h1>
          <p class="hero-lede">Use <kbd>⌘</kbd><kbd>Tab</kbd> to move between apps, then <kbd>⌘</kbd><kbd>`</kbd> to choose a window without releasing Command.</p>
```

Change both brand links from `href="index.html"` to `href="/"`.

- [ ] **Step 3: Add the quick-answer section**

Insert after `#how-it-works` and before `.features`:

```html
      <section class="quick-answers shell" id="quick-answers" aria-labelledby="answers-title">
        <div class="section-heading section-heading--split">
          <div>
            <p class="eyebrow">Quick answers</p>
            <h2 id="answers-title">The macOS switcher,<br><em>without the hunt.</em></h2>
          </div>
          <p class="section-intro">What SwitchTab changes, what it needs, and what it costs.</p>
        </div>
        <div class="answer-grid">
          <article class="answer-card">
            <h3>What is SwitchTab?</h3>
            <p>SwitchTab is a free, native macOS utility for keyboard-first switching between running apps and the windows of the current app.</p>
          </article>
          <article class="answer-card">
            <h3>How is SwitchTab different from macOS Command-Tab?</h3>
            <p>macOS Command-Tab switches between apps. SwitchTab keeps that app flow and lets you move into the highlighted app’s windows without releasing Command.</p>
          </article>
          <article class="answer-card">
            <h3>Does SwitchTab require Screen Recording?</h3>
            <p>No. Accessibility permission is required to discover and focus windows. Screen Recording is optional and used only for live previews; switching still works with app icons and placeholders.</p>
          </article>
          <article class="answer-card">
            <h3>Is SwitchTab free?</h3>
            <p>Yes. SwitchTab has no ads, purchases, subscription, analytics SDK, or account, and no remote service is required for switching.</p>
          </article>
        </div>
      </section>
```

- [ ] **Step 4: Add focused quick-answer styles**

Change the shared section padding selector and add the new rules:

```css
.how-it-works, .quick-answers, .features { position: relative; padding-top: 78px; padding-bottom: 105px; }
.quick-answers { padding-top: 42px; }
.answer-grid { display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); gap: 14px; }
.answer-card { min-height: 196px; padding: 28px; border: 1px solid var(--line); border-radius: var(--radius-md); background: rgba(17, 20, 29, 0.78); }
.answer-card h3 { margin: 0 0 14px; font-size: 22px; font-weight: 600; line-height: 1.2; letter-spacing: -0.025em; }
.answer-card p { margin: 0; color: var(--muted); font-size: 15px; line-height: 1.68; }
```

Inside `@media (max-width: 640px)`, replace the shared section selector and add the grid rule:

```css
  .how-it-works, .quick-answers, .features { padding-top: 62px; padding-bottom: 74px; }
  .quick-answers { padding-top: 32px; }
  .answer-grid { grid-template-columns: 1fr; }
  .answer-card { min-height: 0; padding: 23px; }
```

- [ ] **Step 5: Run the contract and inspect the expected next failure**

```bash
rtk test bash scripts/tests/landing-contract-test.sh
```

Expected: FAIL because crawl, 404, and social-card assets still do not exist.

- [ ] **Step 6: Commit the page content**

```bash
rtk git add docs/index.html docs/landing.css
rtk git commit -m "feat: make landing content search-ready"
```

### Task 3: Add crawler and missing-route resources

**Files:**
- Create: `docs/robots.txt`
- Create: `docs/sitemap.xml`
- Create: `docs/404.html`
- Modify: `docs/landing.css`
- Test: `scripts/tests/landing-contract-test.sh`

- [ ] **Step 1: Create `robots.txt`**

```text
User-agent: *
Allow: /

User-agent: OAI-SearchBot
Allow: /

Sitemap: https://switchtab.royjen.com/sitemap.xml
```

- [ ] **Step 2: Create `sitemap.xml`**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
  <url>
    <loc>https://switchtab.royjen.com/</loc>
  </url>
</urlset>
```

- [ ] **Step 3: Create the static 404 document**

```html
<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <meta name="robots" content="noindex">
    <title>Page not found — SwitchTab</title>
    <link rel="icon" href="/AppIcon-32.png">
    <link rel="stylesheet" href="/landing.css">
  </head>
  <body class="not-found-page">
    <main class="not-found shell">
      <a class="brand" href="/" aria-label="SwitchTab home">
        <img src="/AppIcon-256.png" alt="">
        <span>SwitchTab</span>
      </a>
      <div class="not-found__copy">
        <p class="eyebrow">404</p>
        <h1>That window<br><em>isn’t open.</em></h1>
        <p>The page you requested does not exist.</p>
        <a class="button button--primary" href="/">Return to SwitchTab</a>
      </div>
    </main>
  </body>
</html>
```

- [ ] **Step 4: Add 404 layout styles**

Append before the media queries:

```css
.not-found-page { min-height: 100vh; }
.not-found { display: flex; min-height: 100vh; padding-top: 24px; padding-bottom: 48px; flex-direction: column; }
.not-found__copy { display: grid; max-width: 720px; margin: auto; justify-items: start; }
.not-found__copy h1 { margin: 18px 0 22px; font-size: clamp(58px, 9vw, 112px); font-weight: 600; line-height: 0.92; letter-spacing: -0.065em; }
.not-found__copy p:not(.eyebrow) { margin: 0 0 30px; color: var(--muted); font-size: 18px; }
```

- [ ] **Step 5: Run the contract and verify only the social card remains missing**

```bash
rtk test bash scripts/tests/landing-contract-test.sh
```

Expected: FAIL with `missing landing asset: docs/social-card.png`.

- [ ] **Step 6: Commit crawl resources**

```bash
rtk git add docs/robots.txt docs/sitemap.xml docs/404.html docs/landing.css
rtk git commit -m "feat: add landing crawl resources"
```

### Task 4: Capture the social preview and complete landing contracts

**Files:**
- Create: `docs/social-card.png`
- Test: `scripts/tests/landing-contract-test.sh`

- [ ] **Step 1: Start a local static server**

Run in a persistent terminal:

```bash
rtk proxy python3 -m http.server 4173 --directory docs
```

Expected: server listens on `http://127.0.0.1:4173/`.

- [ ] **Step 2: Capture a deterministic 1200 by 630 viewport**

```bash
rtk proxy agent-browser --session landing-social batch --bail "set viewport 1200 630" "open http://127.0.0.1:4173/"
rtk proxy agent-browser --session landing-social screenshot docs/social-card.png
rtk proxy agent-browser --session landing-social close
```

Expected: `docs/social-card.png` exists at exactly 1200 by 630 pixels and shows the landing hero without browser chrome.

- [ ] **Step 3: Run the landing contract**

```bash
rtk test bash scripts/tests/landing-contract-test.sh
```

Expected: `landing contract passed`.

- [ ] **Step 4: Inspect the generated image**

Open `docs/social-card.png` and confirm the icon, descriptive hero copy, primary install button, and product demo are legible. If the animation was captured mid-transition, reload with reduced motion and recapture:

```bash
rtk proxy agent-browser --session landing-social batch --bail "set viewport 1200 630" "set media reduced-motion" "open http://127.0.0.1:4173/"
rtk proxy agent-browser --session landing-social screenshot docs/social-card.png
rtk proxy agent-browser --session landing-social close
```

- [ ] **Step 5: Commit the social card**

```bash
rtk git add docs/social-card.png
rtk git commit -m "feat: add landing social preview"
```

### Task 5: Point deployment and documentation at the custom domain

**Files:**
- Modify: `scripts/tests/landing-deploy-workflow-test.sh:36-54`
- Modify: `.github/workflows/landing-deploy.yml:21-23`
- Modify: `README.md:74-77`
- Test: `scripts/tests/landing-deploy-workflow-test.sh`

- [ ] **Step 1: Add the failing production URL assertion**

Insert after the deploy job is loaded:

```ruby
assert(job.fetch("environment") == {
  "name" => "production",
  "url" => "https://switchtab.royjen.com/",
}, "production environment must link to the canonical custom domain")
```

- [ ] **Step 2: Run the workflow contract and verify it fails**

```bash
rtk test bash scripts/tests/landing-deploy-workflow-test.sh
```

Expected: FAIL with `production environment must link to the canonical custom domain`.

- [ ] **Step 3: Change the workflow environment URL**

Use:

```yaml
    environment:
      name: production
      url: https://switchtab.royjen.com/
```

- [ ] **Step 4: Change the README landing entry**

Use:

```markdown
- [Landing page](https://switchtab.royjen.com/) ([source](docs/index.html)) — an interactive visual introduction to the app and window switching workflow
```

- [ ] **Step 5: Run deployment and landing contracts**

```bash
rtk test bash scripts/tests/landing-deploy-workflow-test.sh
rtk test bash scripts/tests/landing-contract-test.sh
```

Expected: both contracts pass.

- [ ] **Step 6: Commit deployment metadata**

```bash
rtk git add .github/workflows/landing-deploy.yml scripts/tests/landing-deploy-workflow-test.sh README.md
rtk git commit -m "docs: publish landing custom domain"
```

### Task 6: Run full repository and browser verification

**Files:**
- Verify all task files

- [ ] **Step 1: Run every documentation and release-tooling contract**

```bash
rtk test bash -c 'for test_script in scripts/tests/*-test.sh; do bash "$test_script"; done'
rtk test bash -c 'for script in scripts/*.sh scripts/tests/*.sh; do bash -n "$script"; done'
rtk proxy env SPARKLE_PUBLIC_ED_KEY=dummy scripts/build-direct-distribution.sh --prepare-only
```

Expected: all commands exit `0`.

- [ ] **Step 2: Run Swift verification**

```bash
rtk swift build
rtk swift test
```

Expected: build succeeds; 46 tests execute with 0 failures; the private thumbnail fixture benchmark may be skipped.

- [ ] **Step 3: Run desktop browser QA**

```bash
rtk proxy agent-browser --session landing-qa batch --bail "set viewport 1440 900" "open http://127.0.0.1:4173/" "snapshot -i --urls" "screenshot --full .build/landing-seo-desktop.png"
```

Confirm one `h1`, quick-answer headings, install links, pause control, and no horizontal overflow or console/page errors.

- [ ] **Step 4: Run mobile and reduced-motion QA**

```bash
rtk proxy agent-browser --session landing-qa batch --bail "set viewport 390 844" "open http://127.0.0.1:4173/" "screenshot --full .build/landing-seo-mobile.png" "set media reduced-motion" "open http://127.0.0.1:4173/" "screenshot .build/landing-seo-reduced-motion.png"
rtk proxy agent-browser --session landing-qa close
```

Confirm cards become one column, copy remains readable, no content clips, and the demo holds a stable representative frame.

- [ ] **Step 5: Verify the focused diff**

```bash
rtk git diff --check origin/main...HEAD
rtk git status --short
rtk git diff --stat origin/main...HEAD
```

Expected: only the files in this plan are changed; worktree is clean after the plan document commit.

### Task 7: Push, review, merge, and deploy

**Files:**
- No new repository files unless review finds a concrete defect

- [ ] **Step 1: Recheck the branch against current origin/main**

```bash
rtk git fetch origin main
rtk git log --left-right --cherry-pick --oneline origin/main...HEAD
```

If origin/main advanced, merge it into the feature branch, rerun Task 6, and do not push until all gates pass.

- [ ] **Step 2: Push the feature branch and create the PR**

```bash
rtk git push -u origin audit/landing-aeo-seo
rtk gh pr create --base main --head audit/landing-aeo-seo --title "feat: make landing page search-ready" --body "## Summary

- publish canonical and social metadata for switchtab.royjen.com
- add visible quick answers and truthful structured data
- add robots, sitemap, 404, and custom-domain deployment contracts

## Verification

- all scripts/tests/*-test.sh
- bash syntax checks
- direct-distribution prepare-only
- swift build and swift test
- desktop, mobile, and reduced-motion browser QA"
```

- [ ] **Step 3: Wait for and review all PR checks**

```bash
rtk gh pr checks --watch
rtk gh pr view --comments
```

Expected: every required check passes and no unresolved review finding remains.

- [ ] **Step 4: Merge the PR**

```bash
rtk gh pr merge --squash --delete-branch
```

Expected: PR is merged into `main`; GitHub triggers the landing deployment because `docs/**` changed.

- [ ] **Step 5: Verify the production workflow**

```bash
rtk gh run list --workflow landing-deploy.yml --limit 3
rtk gh run list --workflow landing-deploy.yml --branch main --limit 1 --json databaseId,status,conclusion,headSha,url
```

Poll the second command until the merge commit’s run reports `status: completed` and `conclusion: success`. Do not continue to production HTTP checks while it is queued or in progress.

- [ ] **Step 6: Configure and verify the custom domain before redirecting**

Using the authenticated Cloudflare account that owns the Pages project:

1. Add `switchtab.royjen.com` to the `switchtab-landing` Pages project.
2. Confirm Cloudflare created or validated the CNAME and issued HTTPS.
3. Verify `curl -sSIL https://switchtab.royjen.com/` ends in status `200`.
4. Create a Bulk Redirect from `switchtab-landing.pages.dev` to `https://switchtab.royjen.com` with `301`, subpath matching, preserved path suffix, and preserved query string.
5. Verify the `pages.dev` URL redirects only after the custom domain is healthy.

- [ ] **Step 7: Run production HTTP and crawler verification**

```bash
rtk proxy curl -sSIL https://switchtab.royjen.com/
rtk proxy curl -sSI https://switchtab.royjen.com/robots.txt
rtk proxy curl -sSI https://switchtab.royjen.com/sitemap.xml
rtk proxy curl -sSI https://switchtab.royjen.com/this-path-must-not-exist
rtk proxy curl -sSIL https://switchtab-landing.pages.dev/
rtk proxy curl -sSI -A OAI-SearchBot https://switchtab.royjen.com/
```

Expected: canonical home and OAI crawler return `200`; robots is plain text; sitemap is XML; missing path returns `404`; `pages.dev` starts with `301` and ends on the custom domain.

- [ ] **Step 8: Hand off search-engine owner actions**

Report these exact remaining owner actions:

1. Verify `switchtab.royjen.com` in Google Search Console.
2. Submit `https://switchtab.royjen.com/sitemap.xml` and request indexing for `/`.
3. Verify the site in Bing Webmaster Tools and submit the same sitemap.
4. Review branded versus non-brand impressions and clicks after crawling; do not promise a ranking date.
