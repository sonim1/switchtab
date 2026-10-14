# SwitchTab website operations

Production: `https://switchtab.royjen.com/`. Cloudflare Pages project:
`switchtab-landing`, production branch `main`, static output `docs/`.

The landing deployment workflow publishes `docs/**` changes on `main`. Manual
redeployments must also select `main`; other refs are skipped. Production
deployments share one job-level concurrency group, so skipped runs do not
cancel an active deployment. The app's
Swift sources, signing, DMG releases and Sparkle updates remain separate.

Run the landing, search-discovery and agent-install contract checks before
publication. Verify both `/` and `/guides/switch-windows-on-mac/`, the sitemap,
robots.txt, a true 404, installation links and mobile layout.

Cloudflare Pages Web Analytics is configured through the project's Metrics
tab and injected at deployment. Keep one beacon per page. The CSP permits only
the Cloudflare script origin and its measurement endpoint in addition to local
resources. App telemetry remains disabled; the footer links to the shared
[website privacy notice](https://royjen.com/privacy/).

The [shared Royjen site runbook](https://github.com/sonim1/royjen/blob/main/docs/site-operations.md)
contains the three-site inventory, analytics definitions, weekly reporting,
search ownership steps and deployment verification. Use production Host filters
and exclude bots. Referrals do not prove downloads; Cloudflare Web Analytics
does not report UTM campaigns or custom conversion events.

See [search owner checklist](seo-owner-checklist.md) for search registration.

## Measurement verification, 2026-10-14

Production homepage and guide browser checks observed one beacon and successful
`POST https://cloudflareinsights.com/cdn-cgi/rum` responses (204), without CSP
errors. This proves delivery to the collection endpoint, not the date-range
totals in the dashboard; the dashboard session required sign-in during this pass.

Record weekly snapshots with UTC timestamp, production Host, bot exclusion and
the same 28-day comparison windows. Keep GitHub DMG asset `download_count`
snapshots by asset ID separately: QA, automation and repeat downloads contribute
to those counts, while R2/Sparkle delivery is outside GitHub's count. Neither
visits nor download counts establish unique installations or active users.

There is no download-click or command-copy event layer. Do not calculate an
installation funnel from page views and GitHub totals. See the
[product and measurement follow-up](product-followup-2026-10-14.md) for evidence,
the public snapshot command and the remaining dashboard/hardware checks.
