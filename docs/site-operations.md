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
