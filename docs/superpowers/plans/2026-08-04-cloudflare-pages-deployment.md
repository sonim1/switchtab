# Cloudflare Pages Landing Deployment Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Publish the existing static SwitchTab landing page from `docs/` through Cloudflare Pages with a custom-domain-ready security baseline and privacy-conscious traffic analytics.

**Architecture:** Keep GitHub `main` as the source of truth. Connect the repository to one Cloudflare Pages project whose production branch is `main` and whose output directory is `docs`; no build command or runtime dependency is needed. Add a static `_headers` file beside the landing assets for browser security headers, then enable Cloudflare Web Analytics on the production page only.

**Tech Stack:** Cloudflare Pages, GitHub integration, static HTML/CSS, Cloudflare Web Analytics, `_headers` response rules.

---

## Scope and assumptions

- The current landing page is already implemented at `docs/index.html` and `docs/landing.css`.
- The first deployment uses a Cloudflare-provided `pages.dev` URL; a custom domain is connected only after the production deployment is verified.
- Cloudflare Web Analytics is preferred over Google Analytics because the landing page currently promises no telemetry and Cloudflare documents its Web Analytics as privacy-first and non-personal-data collection.
- No visitor accounts, forms, cookies, server code, or secrets are added.
- Cloudflare account access and the final domain name are external prerequisites. The implementation can complete the `pages.dev` deployment without changing the app release workflow.

## File map

- Create: `docs/_headers` — static response security policy consumed by Cloudflare Pages.
- Create: `docs/assets/AppIcon-256.png` and `docs/assets/AppIcon-32.png` — copies of the app icons that remain inside the Pages output directory.
- Modify: `docs/index.html` — add the Cloudflare Web Analytics beacon only after the production site token is available; keep it absent from local previews and non-production branches.
- Create: `.github/workflows/landing-contract.yml` — validate landing assets, forbidden dependencies, and `_headers` syntax on pull requests.
- Modify: `README.md:76` — replace the repository-relative landing link with the public URL only after the domain is live; keep the source link in the same entry.
- Verify: Cloudflare Pages project settings, deployment URL, custom DNS, HTTPS, analytics dashboard, and security headers.

### Task 1: Add the static security header policy

**Files:**
- Create: `docs/_headers`

- [ ] **Step 1: Add the minimal static-site headers**

Create `docs/_headers` with this exact content:

```text
/*
  X-Content-Type-Options: nosniff
  X-Frame-Options: DENY
  Referrer-Policy: strict-origin-when-cross-origin
  Permissions-Policy: camera=(), microphone=(), geolocation=()
  Content-Security-Policy: default-src 'self'; img-src 'self' data:; style-src 'self'; script-src 'self'; font-src 'self'; connect-src 'self'; frame-ancestors 'none'; base-uri 'self'; form-action 'self'
```

The policy permits the current local icon, local stylesheet, and no scripts. It must be updated in the same change that introduces the Cloudflare analytics beacon, adding only the exact Cloudflare analytics script origin and connect endpoint required by the generated snippet.

- [ ] **Step 2: Verify the policy is scoped to the landing output**

Run:

```bash
test -s docs/_headers
rtk grep -n "X-Content-Type-Options\|Content-Security-Policy" docs/_headers
rtk git diff --check
```

Expected: both required headers are present and `git diff --check` exits 0.

- [ ] **Step 3: Commit the security baseline**

```bash
rtk git add docs/_headers
rtk git commit -m "security: add landing page headers"
```

### Task 2: Add pull-request landing contract checks

**Files:**
- Create: `.github/workflows/landing-contract.yml`
- Create: `scripts/tests/landing-contract-test.sh`

- [ ] **Step 1: Write the contract test**

Create the test with this implementation. It intentionally rejects scripts until Task 4 adds and reviews the exact Cloudflare beacon allowlist:

```bash
#!/usr/bin/env bash
set -euo pipefail

page='docs/index.html'
style='docs/landing.css'
headers='docs/_headers'
icon='SwitchTab/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-256.png'

for path in "$page" "$style" "$headers" "$icon"; do
  test -s "$path" || { echo "missing landing asset: $path" >&2; exit 1; }
done

test "$(rg -o '<h1\b' "$page" | wc -l | tr -d ' ')" = 1
rg -q '<main\b' "$page"
rg -q '<footer\b' "$page"
rg -q 'id="how-it-works"' "$page"
! rg -qi '<script\b|tracker|analytics|http://' "$page" "$style"
rg -q 'X-Content-Type-Options: nosniff' "$headers"
rg -q 'X-Frame-Options: DENY' "$headers"
rg -q 'Content-Security-Policy:' "$headers"
echo 'landing contract passed'
```

- [ ] **Step 2: Run the test red/green against the current tree**

Run:

```bash
bash scripts/tests/landing-contract-test.sh
```

Expected after the test is added: `landing contract passed`.

- [ ] **Step 3: Add a pinned, least-privilege workflow**

Create `.github/workflows/landing-contract.yml` with this workflow. Run the contract on `pull_request` and `push` to `main` with `contents: read`, `ubuntu-latest`, and a short timeout. It must not deploy, access Cloudflare secrets, or run third-party analytics.

```yaml
name: Landing contract

on:
  pull_request:
  push:
    branches: [main]

permissions:
  contents: read

jobs:
  landing:
    runs-on: ubuntu-latest
    timeout-minutes: 5
    steps:
      - uses: actions/checkout@v4
      - name: Validate landing page
        run: bash scripts/tests/landing-contract-test.sh
```

- [ ] **Step 4: Verify CI syntax and commit**

Run the project’s existing workflow contract tests plus the landing test, then commit:

```bash
bash scripts/tests/landing-contract-test.sh
bash scripts/tests/ci-workflow-test.sh
rtk git diff --check
rtk git add .github/workflows/landing-contract.yml scripts/tests/landing-contract-test.sh
rtk git commit -m "test: protect landing page deployment contract"
```

### Task 3: Create and configure the Cloudflare Pages project

**Files:**
- No repository file changes.
- Configure: Cloudflare dashboard, Workers & Pages.

- [ ] **Step 1: Create the project from the GitHub repository**

Connect `sonim1/switchtab`, select the `main` production branch, set the framework preset to none, leave the build command empty, and set the build/output directory to `docs`. Do not add environment variables or secrets.

- [ ] **Step 2: Verify the first production deployment**

Open the production URL displayed in the Cloudflare Pages project and confirm `/`, `/landing.css`, the local app icon, README links, and documentation links load successfully. Confirm a pull-request preview is generated for a harmless docs change, then close/delete the preview without changing production.

- [ ] **Step 3: Confirm headers at the edge**

Use the browser network panel on the production URL and verify `X-Content-Type-Options: nosniff`, `X-Frame-Options: DENY`, `Referrer-Policy`, `Permissions-Policy`, and the CSP are present.

### Task 4: Enable privacy-conscious analytics

**Files:**
- Modify: `docs/index.html`
- Modify: `docs/_headers`

- [ ] **Step 1: Generate the production Web Analytics snippet**

In Cloudflare Web Analytics, create a site for the final production hostname and copy the generated beacon snippet. Do not copy a dashboard token into README, tests, app source, or Swift code.

- [ ] **Step 2: Add the beacon at the end of `<body>`**

Insert the exact Cloudflare-generated script immediately before `</body>`. Do not add event tracking, cookies, forms, or a second analytics provider. Keep the existing page copy claiming no product telemetry accurate: this is aggregate landing-page measurement, not SwitchTab app telemetry.

- [ ] **Step 3: Narrow the CSP to the generated endpoints**

Update only `script-src` and `connect-src` in `docs/_headers` with the exact origins shown by Cloudflare’s generated snippet. Keep `default-src 'self'`, `frame-ancestors 'none'`, and all other restrictions unchanged.

- [ ] **Step 4: Verify analytics and privacy behavior**

Load the production page in a private browser session, confirm the beacon request succeeds, confirm page views appear in Cloudflare’s dashboard, and confirm no cookies or form fields are added. Re-run the landing contract with its expected production exception for the Cloudflare beacon origin.

### Task 5: Attach the custom domain and publish the public link

**Files:**
- Modify: `README.md:76`

- [ ] **Step 1: Verify the domain before connecting it**

Add and verify the domain in Cloudflare before changing DNS. Use a subdomain such as `switchtab.app` or `www.switchtab.app` according to the domain actually owned by the project; do not use wildcard DNS records.

- [ ] **Step 2: Connect the domain and enforce HTTPS**

Complete Cloudflare Pages custom-domain setup, verify DNS, confirm HTTPS, and redirect the `pages.dev` production URL to the custom hostname if the chosen setup requires it. Confirm the custom hostname serves the same deployment and analytics beacon.

- [ ] **Step 3: Update README navigation**

Change the existing documentation entry to show the verified public landing URL while retaining a local source link: use the actual hostname configured in Cloudflare, link its root URL as `Landing page`, and keep `docs/index.html` as the source link. Do not commit a placeholder or an unverified hostname.

- [ ] **Step 4: Run final checks and release the documentation change**

Run:

```bash
bash scripts/tests/landing-contract-test.sh
rtk git diff --check
rtk git status --short --branch
```

Expected: contract passes, no whitespace errors, and only the planned landing/deployment files are changed. Open a PR targeting `main`, wait for CI, merge it, and verify `main` and `origin/main` point to the merge commit.

## Definition of done

- Production landing page is reachable over HTTPS from the Cloudflare Pages URL and, if a domain is available, the final custom hostname.
- `main` pushes deploy automatically; pull requests produce previews without Cloudflare credentials in GitHub Actions.
- Security headers are present at the edge and CSP allows only the assets actually used.
- Cloudflare Web Analytics reports aggregate traffic without adding product telemetry, forms, or visitor accounts.
- README points users to the public landing page and preserves the source link.
- Landing contract, existing release-tooling tests, and `swift test` pass.
- `main`, `origin/main`, and the deployed production commit are identical.

## Risks and decisions

- If no custom domain is owned yet, stop after the verified `pages.dev` deployment and defer only Task 5; do not invent a hostname.
- If Cloudflare’s generated analytics snippet requires a different CSP origin, use the exact generated origin rather than broadening CSP to `*`.
- Do not move the landing page into the macOS app release artifact; web deployment and app release remain separate concerns.
