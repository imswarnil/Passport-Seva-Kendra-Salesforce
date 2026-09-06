# Passport Seva Kendra

A Salesforce app modelling a **Passport Seva Kendra (PSK)** — the offices that
process Indian passport applications — built out to real engineering depth
(data model, automation, security & sharing, testing) and then taught in the
open. Independent portfolio project, not affiliated with any government body.

This repo is two things:

1. **`force-app/`** — the actual SFDX Salesforce project. Seventeen custom
   objects plus two custom metadata types, an Apex trigger/service layer,
   validation rules, sharing rules, approval processes. Deployable into your
   own Developer Edition org to learn from or extend — see
   [`docs/DEPLOY_YOUR_OWN.md`](docs/DEPLOY_YOUR_OWN.md).
2. **The rest of the repo** — a Nuxt 4 app (deployed to Cloudflare Workers,
   data in Neon Postgres) that teaches how the Salesforce side was built:
   lessons, a live read-only browser into the real org, comments, a
   guestbook, and a place to submit resources and suggestions.

## The learning platform

- **Lessons** (`content/lessons/`) walk through the actual build — data
  modelling, validation rules, the security/sharing model, the Apex
  trigger/service layer, automation without Flow, testing, config-as-data —
  plus a roadmap lesson on what's genuinely still ahead.
- **`/demo-org`** is a real, live, read-only view into the actual dev org,
  through a dedicated integration user that can only ever see six non-PII
  objects — nothing there can be edited. See
  [`docs/SETUP_ORG.md`](docs/SETUP_ORG.md) for how that's wired and secured.
- Sign up to track lesson progress, comment on lessons, sign the guestbook,
  and submit learning resources or suggestions — all backed by Postgres on
  Neon, running on Cloudflare Workers.

Setting the web side up locally or in production: [`docs/SETUP_WEB.md`](docs/SETUP_WEB.md).

## The Salesforce app

**Design philosophy — few objects, many fields.** The whole application
lifecycle lives on **one** object (`Passport_Application__c`) driven by a
`Status` picklist and record types, rather than a new object per stage. A
half-finished form is the same object in `Draft` status, not a different one.

The full object catalogue, field specs, and status of what's built vs. what's
roadmap now lives in the lessons themselves —
[`content/lessons/2.data-model/3.the-object-catalogue.md`](content/lessons/2.data-model/3.the-object-catalogue.md)
and [`content/lessons/6.whats-next/1.roadmap.md`](content/lessons/6.whats-next/1.roadmap.md)
— rather than duplicated here and left to drift.

### Conventions

- **Objects:** singular label, PascalCase API with underscores (`Passport_Application__c`).
- **Fields:** descriptive, no abbreviations (`Police_Verification_Type__c`, not `PV_Typ__c`).
- **Picklists:** restricted value sets; shared vocabularies as Global Value Sets. Record types *subset* picklists rather than forking the schema.
- **Sharing:** OWD **Private** on anything holding personal data; `ControlledByParent` on master-detail children.
- **PII / DPDP Act:** never store an Aadhaar number — only `Aadhaar_Verified__c` (checkbox) and `Aadhaar_Token__c` (an opaque token). Data minimisation by design. The public `/demo-org` proxy goes further and excludes `Citizen__c` entirely, plus every PII field on the objects it does expose — see `server/utils/demo-org-allowlist.ts`.
- **The as-submitted snapshot:** the application deliberately keeps its own copy of the applicant's declared details rather than reading them from `Citizen__c` by formula. A passport application is a legal instrument; the details as declared at submission must not be rewritten by later edits to the citizen record.
- **Deploy incrementally**, confirming each step. Never delete metadata or data without asking.

### Environment

- **Org:** Developer Edition, alias **`psk-dev`** (set as the project's default target-org).
- **Format:** SFDX source format under `force-app/main/default/`. Source API version 67.0.
- **Retrieve the org:** `sf project retrieve start --manifest manifest/package.xml`
- **Deploy changes:** `sf project deploy start --source-dir force-app`
- **Run tests:** `sf apex run test --test-level RunLocalTests --code-coverage`
- **Deploy into your own org from scratch:** [`docs/DEPLOY_YOUR_OWN.md`](docs/DEPLOY_YOUR_OWN.md)

See [`CLAUDE.md`](CLAUDE.md) for guidance and commands for working in this repo with Claude Code.

## Repo layout

```
force-app/          the Salesforce app (SFDX source format)
manifest/            retrieve/deploy manifests, incl. the lean package-psk-core.xml for a fresh deploy
config/              scratch org definition
app/, server/        the Nuxt 4 platform (pages, components, API routes)
content/lessons/     the curriculum, as Nuxt Content markdown
db/migrations/       Neon Postgres schema
docs/                setup guides (web platform, org demo, deploy-your-own)
```
