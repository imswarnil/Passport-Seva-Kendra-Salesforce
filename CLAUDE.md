# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working in this repository.

## Overview

Two halves, one repo:

1. **`force-app/`** — an SFDX source-format Salesforce project for a custom **Passport Seva Kendra** app on a Developer Edition org. The org is the source of truth; local metadata must be deployed back for changes to take effect. It's also meant to be deployable, as-is, into a *stranger's* own org to practise with — see `docs/DEPLOY_YOUR_OWN.md`.
2. **Everything else** — a Nuxt 4 app (Cloudflare Workers, Neon Postgres) that teaches the Salesforce build in the open: lessons under `content/lessons/`, accounts/progress/comments/guestbook/resource-submissions backed by Neon, and `/demo-org`, a live read-only proxy into the real Salesforce org.

Read `docs/DEPLOY_YOUR_OWN.md` before touching `force-app/` metadata, `docs/SETUP_WEB.md` before touching the Nuxt app's server/db code, and `docs/SETUP_ORG.md` before touching anything under `server/api/demo-org/**`, `server/utils/sf.ts`, or `server/utils/demo-org-allowlist.ts` — that trio is the entire security boundary between the public internet and the real org, and changes there deserve more scrutiny than typical app code.

- Default org alias: **`psk-dev`** (already set as the project `target-org`, so `--target-org` is optional on `sf` commands).
- Source API version: **67.0** (`sfdx-project.json`). Individual Apex classes carry their own `apiVersion` in their `.cls-meta.xml`.

## Commands

### Salesforce (`force-app/`)

```bash
sf project retrieve start --manifest manifest/package.xml       # pull the entire org
sf project deploy start --source-dir force-app                   # deploy everything
sf project deploy start --metadata ApexClass:LeadController      # deploy one class
sf project deploy start --source-dir force-app --dry-run         # validate without saving
sf apex run test --test-level RunLocalTests --result-format human --code-coverage
sf org open
sf apex tail log
```

Test classes follow `<ClassName>Test` (e.g. `DataManager_Utils` → `DataManager_UtilsTest`); `DataManager_TestUtils` provides shared test-data setup.

### The web platform (Nuxt app)

```bash
pnpm install
pnpm run dev              # local dev, http://localhost:3000
pnpm run db:migrate        # apply db/migrations/*.sql to Neon
pnpm run build             # nuxt build --preset cloudflare_module
pnpm run deploy            # build + wrangler deploy
```

`.env.example` documents every env var; nothing works without a real `NUXT_DATABASE_URL` (see `docs/SETUP_WEB.md`). `/demo-org` additionally needs the `NUXT_SF_*` vars and `NUXT_PUBLIC_DEMO_ORG_ENABLED=true` (see `docs/SETUP_ORG.md`) — it 404s otherwise, which is the correct default state for a fresh checkout.

## Architecture

### Salesforce side

Everything lives under `force-app/main/default/`, split by metadata type. `manifest/package.xml` is the full-org retrieve manifest (includes inherited CRM Analytics/Wave template metadata, not just the PSK app); `manifest/package-psk-core.xml` is the lean, PSK-only subset used for deploying into a fresh org.

Apex falls into a few groups, most of it inherited from Salesforce templates rather than hand-written for this app:

- **DataManager_\*** — data-loading utilities from the Service Analytics (CRM Analytics/Wave) template, feeding the `waveTemplates/` dashboards. Backed by `OpportunityHistory__c` and `Reseller_Account_Plan__c`.
- **Site/community auth** — standard Experience Cloud self-registration/login controllers (`SiteLoginController`, `SiteRegisterController`, etc.), paired with the `Internal Zone` community.
- **PSK_\*** — the app-specific Apex actually being built for Passport Seva Kendra: the trigger/service layer for `Passport_Application__c` and friends.
- **`server/utils/sf.ts`** (Nuxt side) is a *separate* integration from all of the above — a hand-rolled JWT Bearer client used only by the read-only demo proxy, talking to a dedicated low-privilege integration user, not the admin credentials used for deploys.

### Web platform side

`app/` (Nuxt pages/components/composables), `server/` (Nitro API routes + utils), `content/lessons/` (the curriculum, Nuxt Content), `db/migrations/` (Neon schema, applied by `scripts/migrate.mjs`, no migration-tracking table — every statement is `if not exists`, so re-running an already-applied file is a no-op). Sessions are a random token in an httpOnly cookie, hashed before storage (`server/utils/auth.ts`) — never store or log a raw session token.

## Security notes

- `force-app/main/default/connectedApps/N8N.connectedApp-meta.xml` has a real OAuth Consumer Key committed in source, from before this repo went public. A Consumer Key alone isn't a full secret the way a private key is, but rotate it (App Manager → N8N → Manage Consumer Details → rotate, then redeploy the metadata with the new value scrubbed or moved to a substitution variable) rather than leaving a real client identifier for a personal integration sitting in a public repo.
- The `/demo-org` feature is a live credential to the real org sitting behind a public website. Its safety depends on three things staying true: the integration user has *only* `PSK_Demo_Read_Only` assigned, the Connected App (`PSK_Demo_Proxy`) stays `AdminApproved` (never `AllUsers`), and `server/utils/demo-org-allowlist.ts` — not the permission set — stays the actual authority on which objects/fields are queryable. See `docs/SETUP_ORG.md` § "Ongoing responsibility" before changing any of the three.
