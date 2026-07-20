# Passport Seva Kendra — Salesforce

A custom Salesforce platform modelling a **Passport Seva Kendra (PSK)** — the offices that process Indian passport (and later visa) applications. This is an independent **portfolio project**, not affiliated with any government body. It exists to demonstrate core Salesforce engineering: data modelling, automation (Flow + Apex), security & sharing, and third-party integrations (n8n + Twilio + AI, in later phases).

## Goal

Build a clean, well-architected org that manages the full passport application lifecycle — from a half-finished `Draft` form through payment, document and police verification, granting, printing, dispatch and delivery — on a small, deliberate data model.

**Design philosophy — few objects, many fields.** The whole application lifecycle lives on **one** object (`Passport_Application__c`) driven by a `Status` picklist and record types, rather than a new object per stage. A half-finished form is the same object in `Draft` status, not a different object.

## Roadmap

Objects are built one at a time, in dependency order. Full specs live in **[PSK.md](PSK.md)**.

| # | Object | API Name | Status |
|---|--------|----------|--------|
| 1 | Passport Application | `Passport_Application__c` | **In progress — build first** |
| 2 | PSK Office | `PSK__c` | Planned |
| 3 | Appointment Slot | `Slot__c` | Planned |
| 4 | Appointment | `Appointment__c` | Planned |
| 5 | Document Checklist Item | `Document_Checklist_Item__c` | Planned |
| 6 | Objection | `Objection__c` | Planned |
| 7 | Police Verification | `Police_Verification__c` | Planned |
| 8 | Payment | `Payment__c` | Planned |
| 9 | Renewal | `Renewal__c` | Planned |
| 10 | Notification Log | `Notification_Log__c` | Planned |
| 11 | Risk Flag | `Risk_Flag__c` | Planned |

Later phases add a Visa department (`Visa_Application__c`, `Country__c`, `Sponsor__c`), fulfilment (`Print_Job__c`, `Dispatch__c`), Custom Metadata Types (`Fee_Matrix__mdt`, `SLA_Config__mdt`), and n8n / Twilio / AI integrations.

## Environment

- **Org:** Developer Edition, alias **`psk-dev`**, user `admin@passportoffice.com` (set as the project's default target-org).
- **Format:** SFDX source format under `force-app/main/default/`.
- **Retrieve the org:** `sf project retrieve start --manifest manifest/package.xml`
- **Deploy changes:** `sf project deploy start --source-dir force-app`
- **Run tests:** `sf apex run test --test-level RunLocalTests --code-coverage`

See **[CLAUDE.md](CLAUDE.md)** for detailed commands and the current org's architecture (note: the retrieved org still carries leftover metadata from a Service Analytics template — the PSK app is being built fresh on top).

## Conventions

- **Objects:** singular label, PascalCase API with underscores (`Passport_Application__c`).
- **Fields:** descriptive, no abbreviations (`Police_Verification_Type__c`, not `PV_Typ__c`).
- **Picklists:** restricted value sets; shared sets (e.g. Indian States) as Global Value Sets.
- **Sharing:** OWD **Private** on anything holding personal data.
- **PII / DPDP Act:** never store an Aadhaar number — only `Aadhaar_Verified__c` (checkbox) and `Aadhaar_Token__c` (token). Data minimisation by design.
- **Deploy incrementally** (object → fields → record types → layouts → rules), confirming each step. Never delete metadata or data without asking.

## Working docs

- **[PSK.md](PSK.md)** — the authoritative build guide: full roadmap, conventions, and the complete field/record-type/validation spec for Object #1.
- **[CLAUDE.md](CLAUDE.md)** — guidance and commands for Claude Code working in this repo.
