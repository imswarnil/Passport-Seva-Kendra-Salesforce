# Passport Seva Kendra — Salesforce

A custom Salesforce platform modelling a **Passport Seva Kendra (PSK)** — the offices that process Indian passport (and later visa) applications. This is an independent **portfolio project**, not affiliated with any government body. It exists to demonstrate core Salesforce engineering: data modelling, automation (Flow + Apex), security & sharing, and third-party integrations (n8n + Twilio + AI, in later phases).

## Goal

Manage the full passport application lifecycle — from a half-finished `Draft` form through payment, document and police verification, granting, printing, dispatch and delivery — on a small, deliberate data model.

**Design philosophy — few objects, many fields.** The whole application lifecycle lives on **one** object (`Passport_Application__c`) driven by a `Status` picklist and record types, rather than a new object per stage. A half-finished form is the same object in `Draft` status, not a different object.

## Status

All sixteen custom objects are built and deployed. Full specs — fields, record types, validation rules, security model, automation, UI — live in **[PSK.md](PSK.md)**.

| # | Object | API Name | Relationship | Status |
|---|--------|----------|--------------|--------|
| 1 | Passport Application | `Passport_Application__c` | root | **Built** — 56 fields, 6 record types, 4 validation rules, Path |
| 2 | PSK Office | `PSK__c` | root | **Built** |
| 3 | Appointment Slot | `Slot__c` | M-D → PSK Office | **Built** |
| 4 | Appointment | `Appointment__c` | junction (M-D ×2) | **Built** |
| 5 | Document Checklist Item | `Document_Checklist_Item__c` | M-D → Application | **Built** |
| 6 | Objection | `Objection__c` | M-D → Application | **Built** |
| 7 | Police Verification | `Police_Verification__c` | lookup → Application | **Built** |
| 8 | Payment | `Payment__c` | M-D → Application | **Built** |
| 9 | Renewal | `Renewal__c` | lookup → Application | **Built** |
| 10 | Notification Log | `Notification_Log__c` | lookup → Application | **Built** |
| 11 | Risk Flag | `Risk_Flag__c` | lookup → Application | **Built** |
| 12 | Citizen | `Citizen__c` | root | **Built** — the golden identity record |
| 13 | Family Member | `Family_Member__c` | M-D → Citizen | **Built** |
| 14 | Passport | `Passport__c` | lookup → Application | **Built** — 3 record types |
| 15 | Print Job | `Print_Job__c` | M-D → Application | **Built** |
| 16 | Dispatch | `Dispatch__c` | M-D → Application | **Built** |
| — | Fee Matrix | `Fee_Matrix__mdt` | custom metadata | **Built** — 10 records |
| — | SLA Config | `SLA_Config__mdt` | custom metadata | **Built** — 26 records |

Also built: 13 global value sets, 11 roles, 6 public groups, 6 queues, 9 criteria-based sharing rules, 2 custom apps, 17 tabs, 4 LWCs, 5 `PSK_*` Apex classes with tests.

**In flight:** the 7 persona permission sets and their permission set groups, the trigger/service layer, page layouts for the five newest objects.

**Not started:** the visa department (`Visa_Application__c`, `Country__c`, `Sponsor__c`), approval processes, an Experience Cloud citizen self-service site, reports and dashboards, and the n8n / Twilio / AI integrations.

See **[PSK.md §9](PSK.md)** for the detailed built / in-flight / not-started breakdown.

## Environment

- **Org:** Developer Edition, alias **`psk-dev`**, user `admin@passportoffice.com` (set as the project's default target-org).
- **Format:** SFDX source format under `force-app/main/default/`. Source API version 67.0.
- **Retrieve the org:** `sf project retrieve start --manifest manifest/package.xml`
- **Deploy changes:** `sf project deploy start --source-dir force-app`
- **Run tests:** `sf apex run test --test-level RunLocalTests --code-coverage`

See **[CLAUDE.md](CLAUDE.md)** for detailed commands and the current org's architecture (note: the retrieved org still carries leftover metadata from a Service Analytics template — the PSK app is built fresh on top).

## Conventions

- **Objects:** singular label, PascalCase API with underscores (`Passport_Application__c`).
- **Fields:** descriptive, no abbreviations (`Police_Verification_Type__c`, not `PV_Typ__c`).
- **Picklists:** restricted value sets; shared vocabularies as Global Value Sets. Record types *subset* picklists rather than forking the schema.
- **Sharing:** OWD **Private** on anything holding personal data; `ControlledByParent` on master-detail children.
- **PII / DPDP Act:** never store an Aadhaar number — only `Aadhaar_Verified__c` (checkbox) and `Aadhaar_Token__c` (an opaque token). Data minimisation by design.
- **The as-submitted snapshot:** the application deliberately keeps its own copy of the applicant's declared details rather than reading them from `Citizen__c` by formula. A passport application is a legal instrument; the details as declared at submission must not be rewritten by later edits to the citizen record. See [PSK.md §2.1](PSK.md).
- **Deploy incrementally** (value sets → objects → layouts → security → code → app shell), confirming each step. Never delete metadata or data without asking.

## Working docs

- **[PSK.md](PSK.md)** — the authoritative build guide: object catalogue, field specs, security model, automation layer, UI layer, deploy sequence and live status table.
- **[CLAUDE.md](CLAUDE.md)** — guidance and commands for Claude Code working in this repo.
- **`PSK_Org_Readiness_Report.pdf`** — a print-ready readiness report: ERD, per-object UAT checklist, lifecycle walkthrough script, persona access matrix, prioritised action items, org limits. Regenerate with `node scripts/pdf/generate-report.mjs` (zero dependencies; needs Chrome for the PDF step, or pass `--html-only`). Every count in it is recomputed from the metadata tree at generation time.
