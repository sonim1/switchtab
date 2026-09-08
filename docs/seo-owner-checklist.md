# Search registration: owner checklist

The repository supplies crawlable pages, metadata, internal links, `robots.txt`,
and a sitemap. Account ownership and search-engine submissions are separate.
Complete the steps below after the updated site has been deployed.

## Google Search Console

1. Sign in to [Search Console](https://search.google.com/search-console/) with
   the Google account that should own the site.
2. Select an existing verified property covering the site, or add a URL-prefix
   property for `https://switchtab.royjen.com/` and complete the offered ownership
   verification. If using HTML verification, provide only the verification tag or
   file for implementation; never share a password, cookie, or account token.
3. In Sitemaps, submit `https://switchtab.royjen.com/sitemap.xml` and confirm that
   Google can fetch it. It should list the homepage and the Mac switching guide.
4. Use URL Inspection on each page, run the live test, and request indexing:
   - `https://switchtab.royjen.com/`
   - `https://switchtab.royjen.com/guides/switch-windows-on-mac/`
5. Revisit Page indexing and Performance later to check actual indexing, search
   queries, impressions, and clicks. Submission does not guarantee indexing or
   a particular ranking.

Google's [sitemap instructions](https://support.google.com/webmasters/answer/7451001?hl=en)
explain owner permissions, fetching, submission status, and indexing limitations.

## Bing Webmaster Tools

1. Sign in to [Bing Webmaster Tools](https://www.bing.com/webmasters/).
2. Add `https://switchtab.royjen.com/` and complete the site's ownership
   verification flow. If offered, an already verified Search Console property
   can be imported instead.
3. Submit `https://switchtab.royjen.com/sitemap.xml` and inspect its fetch status.

## What does not need account access

- Website, Download, and Installation links at the top of the README.
- GitHub About description, website, and relevant topics.
- A useful guide linked from the homepage, with its own canonical URL,
  social metadata, structured data, and sitemap entry.
- Local link/SEO contract tests and responsive browser verification.

No analytics SDK or visitor-tracking script is needed for these changes.
