# Landing Page AEO/SEO Design

## Goal

Make the existing English landing page discoverable for non-brand searches such as “macOS app switcher” and “macOS window switcher,” strengthen branded `SwitchTab` results, and preserve the current visual design and privacy posture.

The canonical production URL is `https://switchtab.royjen.com/`.

## Success criteria

- `https://switchtab.royjen.com/` returns the production page over HTTPS with status `200`.
- `https://switchtab-landing.pages.dev/*` permanently redirects to the matching custom-domain path with status `301`.
- The document title, description, canonical URL, social metadata, visible hero copy, and structured data describe the same product.
- `/robots.txt` and `/sitemap.xml` return their dedicated text and XML resources instead of the home page.
- Unknown routes return a real `404` response with a branded static error page.
- Google, Bing, and `OAI-SearchBot` can crawl the canonical home page.
- Desktop and mobile browser checks show no visual or accessibility regression.
- Repository landing, workflow, shell, Swift build, and Swift test gates pass before deployment.

## Current findings

- The page already has one semantic `h1`, a meta description, accessible sections, crawlable links, responsive CSS, and a strong product demo.
- The current title and `h1` lead with brand language but do not prominently identify the product as a macOS app and window switcher.
- The page has no canonical link, Open Graph metadata, preferred social image, `WebSite` structured data, or `SoftwareApplication` structured data.
- Requests for `/robots.txt`, `/sitemap.xml`, and arbitrary missing paths currently return the home page HTML with status `200` because no dedicated resources or `404.html` exist.
- The public `pages.dev` URL creates a duplicate-host risk once the custom domain is connected.
- The landing contract currently bans every `script` element. It must allow one non-executable `application/ld+json` block while continuing to reject executable scripts, analytics, trackers, video, canvas, and remote image dependencies.
- A current web search did not surface the `pages.dev` landing page for a `site:` query or the intended non-brand queries. Search Console remains the authoritative index-status source after ownership is verified.

## Scope

### Included

- Search-focused metadata and visible English copy on the existing single landing page.
- A small, visible quick-answers section that directly explains the product, shortcut distinction, permissions, and price.
- `WebSite` and `SoftwareApplication` JSON-LD containing only truthful, visible product facts.
- A static 1200 by 630 social card derived from the existing landing visual system and product imagery.
- Dedicated `robots.txt`, `sitemap.xml`, and `404.html` files.
- Contract tests for metadata, structured data, crawl resources, error handling, and deployment configuration.
- Cloudflare Pages custom-domain configuration and a Bulk Redirect from `pages.dev` to the custom domain.
- Post-deploy browser, HTTP, crawler, Google Search Console, and Bing Webmaster Tools checks.

### Excluded

- Redesigning the hero, demo reel, install section, feature grid, or native macOS app.
- Adding a blog, comparison pages, keyword-generated pages, localization, analytics scripts, trackers, cookies, or new runtime dependencies.
- Adding `FAQPage` markup. Google removed the FAQ rich-result feature in 2026.
- Adding `llms.txt`. Google documents no ranking or generative-search benefit from it.
- Inventing reviews, ratings, download counts, awards, authorship, organization details, or other unsupported authority signals.

## Search and content design

### Document metadata

- Title: `SwitchTab — Free macOS App & Window Switcher`
- Description: `SwitchTab is a free, native macOS app and window switcher. Use Command-Tab for apps and Command-Backtick for windows, with optional live previews.`
- Canonical: `https://switchtab.royjen.com/`
- Open Graph type: `website`
- Open Graph site name: `SwitchTab`
- Open Graph title and description: identical in meaning to the document title and description
- Open Graph URL: the canonical URL
- Open Graph image: `https://switchtab.royjen.com/social-card.png`
- Open Graph image dimensions: 1200 by 630
- Twitter card: `summary_large_image`
- Robots meta: `index, follow, max-image-preview:large`

The metadata must not claim a review score, popularity, performance benchmark, or platform version beyond the repository’s current product truth.

### Hero copy

- Eyebrow: `Free native macOS app and window switcher`
- Heading: `Switch apps. Land on the exact window.`
- Supporting text: `Use Command-Tab to move between apps, then Command-Backtick to choose a window without releasing Command.`

The existing install actions, trust row, and demo remain in place. “macOS 14+,” “Native Swift,” “Free forever,” and the signing/notarization claim remain unchanged.

### Quick answers

Add a section after “How it works” and before the feature grid. Answers are visible without JavaScript, accordions, tabs, or hidden content.

#### What is SwitchTab?

`SwitchTab is a free, native macOS utility for keyboard-first switching between running apps and the windows of the current app.`

#### How is SwitchTab different from macOS Command-Tab?

`macOS Command-Tab switches between apps. SwitchTab keeps that app flow and lets you move into the highlighted app’s windows without releasing Command.`

#### Does SwitchTab require Screen Recording?

`No. Accessibility permission is required to discover and focus windows. Screen Recording is optional and used only for live previews; switching still works with app icons and placeholders.`

#### Is SwitchTab free?

`Yes. SwitchTab has no ads, purchases, subscription, analytics SDK, or account, and no remote service is required for switching.`

## Structured data

Place one JSON-LD script in the document head with an `@graph` containing:

```json
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
```

Do not add `aggregateRating` or `review`. The software node provides machine-readable product semantics but is not expected to qualify for Google’s software-app rich result without a genuine rating or review.

## Crawl and URL design

### `robots.txt`

Serve UTF-8 plain text at `/robots.txt`:

```text
User-agent: *
Allow: /

User-agent: OAI-SearchBot
Allow: /

Sitemap: https://switchtab.royjen.com/sitemap.xml
```

The specific OpenAI group documents search-crawler intent. The wildcard group keeps Google, Bing, and other standards-compliant crawlers allowed.

### `sitemap.xml`

Serve one canonical home URL. Omit `lastmod` because the static repository has no automated mechanism that can keep it accurate.

```xml
<?xml version="1.0" encoding="UTF-8"?>
<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
  <url>
    <loc>https://switchtab.royjen.com/</loc>
  </url>
</urlset>
```

### Missing paths

Add `docs/404.html` with a concise SwitchTab message and a root link. Cloudflare Pages must return it with status `404`; the file must not contain canonical or structured-data signals that imply it is the home page.

### Host consolidation

1. Associate `switchtab.royjen.com` with the `switchtab-landing` Pages project.
2. Confirm DNS, certificate issuance, HTTPS, and a `200` home response.
3. Create a Cloudflare Bulk Redirect from `switchtab-landing.pages.dev` to `https://switchtab.royjen.com` using status `301`, subpath matching, preserved path suffix, and preserved query string.
4. Confirm the redirect only after the custom domain is healthy.

Do not attempt the host redirect in `docs/_redirects`; Cloudflare Pages does not support domain-level redirects there.

## File responsibilities

- `docs/index.html`: metadata, approved visible copy, quick answers, and JSON-LD.
- `docs/landing.css`: styles for the quick-answers section and any minimal responsive adjustment caused by the copy change.
- `docs/social-card.png`: local 1200 by 630 social preview using existing SwitchTab identity and product imagery.
- `docs/robots.txt`: crawler access policy and sitemap discovery.
- `docs/sitemap.xml`: canonical URL discovery.
- `docs/404.html`: branded missing-route response.
- `scripts/tests/landing-contract-test.sh`: static landing, SEO, JSON-LD, and crawl-resource contracts.
- `scripts/tests/landing-deploy-workflow-test.sh`: custom production URL contract for the deploy workflow.
- `.github/workflows/landing-deploy.yml`: production environment URL only; deployment remains triggered by changes under `docs/**` on `main`.
- `README.md`: replace the repository-relative landing link with the verified custom-domain URL while retaining a source link to `docs/index.html`.

No Swift source, Xcode project, entitlement, update feed, release artifact, or app telemetry code changes.

## Error handling and rollout

- If the custom domain is not active or HTTPS is not healthy, do not enable the `pages.dev` redirect and do not claim deployment completion.
- If JSON-LD validation fails, remove or correct only unsupported fields; never add fabricated ratings to obtain rich-result eligibility.
- If browser QA finds a layout regression, change only the affected landing HTML/CSS and repeat desktop and mobile checks.
- If CI fails, keep the pull request unmerged, diagnose the failure, and rerun the exact failing gate.
- If the production workflow fails after merge, preserve the last successful Pages deployment, inspect the workflow, and redeploy only after the cause is fixed.
- Search indexing and AI citations are not immediate or guaranteed. Deployment completion means crawlability and signals are correct, not that a result already appears.

## Verification

### Repository gates

Run:

```bash
rtk test bash scripts/tests/landing-contract-test.sh
rtk test bash scripts/tests/landing-deploy-workflow-test.sh
rtk test bash -c 'for test_script in scripts/tests/*-test.sh; do bash "$test_script"; done'
rtk test bash -c 'for script in scripts/*.sh scripts/tests/*.sh; do bash -n "$script"; done'
rtk proxy env SPARKLE_PUBLIC_ED_KEY=dummy scripts/build-direct-distribution.sh --prepare-only
rtk swift build
rtk swift test
rtk git diff --check
```

Expected: every command exits `0`; Swift tests report no failures; the private thumbnail benchmark may remain skipped.

### Static and browser checks

- Parse `docs/index.html` and its JSON-LD without errors.
- Run the page through Google Rich Results Test or Schema Markup Validator, recording that no rating/review was supplied.
- Serve the Pages output locally and verify desktop 1440 by 900 and mobile 390 by 844 layouts.
- Confirm the headline, install actions, demo, quick answers, and footer fit without horizontal overflow.
- Confirm there are no console or page errors.
- Confirm `prefers-reduced-motion` still exposes a stable demo frame.
- Confirm the social card is 1200 by 630 and loads from the declared absolute URL after deployment.

### Production checks

```bash
curl -sSIL https://switchtab.royjen.com/
curl -sSI https://switchtab.royjen.com/robots.txt
curl -sSI https://switchtab.royjen.com/sitemap.xml
curl -sSI https://switchtab.royjen.com/this-path-must-not-exist
curl -sSIL https://switchtab-landing.pages.dev/
curl -sSI -A OAI-SearchBot https://switchtab.royjen.com/
```

Expected: canonical home and crawler request return `200`; robots and sitemap return appropriate content types; missing path returns `404`; `pages.dev` returns a `301` chain ending at the custom domain.

## Post-deploy owner actions

After production verification, the owner must:

1. Add `switchtab.royjen.com` as a Domain or URL-prefix property in Google Search Console and complete DNS verification.
2. Submit `https://switchtab.royjen.com/sitemap.xml` and request indexing for the home page.
3. Add and verify the site in Bing Webmaster Tools, then submit the same sitemap.
4. Review Page Indexing, query, impression, click, and branded/non-brand search data after sufficient crawl time.
5. Use real query evidence before approving a separate content-hub project.
