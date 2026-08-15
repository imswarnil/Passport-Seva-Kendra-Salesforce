# SOLUTION.md — What We Are Building, and Why

> **Read order:** this file → [DATA_MODEL.md](DATA_MODEL.md) → [JOURNEYS.md](JOURNEYS.md) → [AUTOMATION.md](AUTOMATION.md) → [ACCESS_MATRIX.md](ACCESS_MATRIX.md) → [DEMO_DATA.md](DEMO_DATA.md) → [TESTING.md](TESTING.md) → [MIGRATION.md](MIGRATION.md).
>
> This is the **solution design**. Nothing here is built yet in its target shape — it describes where the org is going, not where it is. [PSK.md](PSK.md) describes where it is today. The learning contract is [salesforce-concepts.md](salesforce-concepts.md); every design decision below names the concept it teaches.

---

## 1. The one-paragraph version

A Passport Seva Kendra takes an application from a citizen at a counter, checks their documents, has the police verify where they live, gets an officer to authorise the passport, prints the booklet, and couriers it to them. We are building that on Salesforce as **four apps over eight objects**, deliberately small — small enough that every field earns its place, but complete enough that the whole lifecycle runs end to end with automation, approvals, queues and persona-scoped security. It is a teaching build: the org is the artefact, and the [Jekyll course site](salesforce-passport/) is the explanation.

---

## 2. Current situation (honest assessment)

The org is not a greenfield. It has been built once already, and over-built.

| Dimension | Today | Problem |
|---|---|---|
| Custom objects | 17 PSK objects + 2 inherited Wave objects | Too many. Ten of them hold one or two facts that belong as fields on a parent. |
| Custom fields | ~250+ | `Passport_Application__c` alone carries 56. Many were added speculatively and are never read by any automation, layout, or report. |
| Validation rules | 62 | More rules than the process has decision points. Several fire on fields no persona can edit. |
| Apps | 5 custom (`Application_Management_Console`, `PSK_Operations_Console`, `Passport_Validator`, `PSK_Police_Verification_Console`, `Trailhead_Data_Manager`) | Overlapping and unnamed after any real job. Nobody's day maps to "Operations Console". |
| Permission sets | 9 + 3 groups | Roughly right in shape, drifted in detail — PII field-level security does not match the documented intent. |
| Apex | ~18 `PSK_*` classes, 4 triggers | Sound, but written against the 17-object model. Most of it survives the cut; some deletes with its object. |
| Demo data | 162 applications, 71 passports, 94 appointments… | Volume without scenarios. There is a lot of data and almost no *story* in it — no deliberately rejected application, no adverse police report to look at. |
| Inherited Service Analytics / Trailhead template metadata | `DataManager_*` classes, `waveTemplates/`, `OpportunityHistory__c`, `Reseller_Account_Plan__c`, `Internal Zone` community | Noise. Nothing in PSK reads it. It slows every retrieve and it is the reason six unrelated tests fail. |

**The diagnosis:** the build optimised for *coverage of the domain* when it should have optimised for *coverage of the concepts*. A passport office genuinely does have appointment slots and courier partners and renewal outreach — but modelling all of it produced an org where the interesting Salesforce ideas are buried under administrative detail nobody exercises.

---

## 3. Assumptions

These are stated so they can be challenged. Each one, if wrong, changes the design.

1. **This is a portfolio and learning artefact, not a system anyone will operate.** Correctness of *concept demonstration* beats operational completeness. A stage that is real but boring gets collapsed into a picklist value.
2. **Developer Edition constraints hold.** No Shield Platform Encryption, no Enterprise Territory Management, no guaranteed Experience Cloud licences. Anything requiring those is designed-for but not built.
3. **The applicant is not a Salesforce user.** Every citizen interaction is mediated by a staff member at a counter or over the phone. There is no portal. This is a deliberate scope boundary, not an oversight — it keeps the build to internal users and licences we actually have.
4. **Aadhaar numbers are never stored.** Only a verified flag and an opaque token. This is India's DPDP Act data-minimisation principle, and because Shield is unavailable, the discipline is the only control — so it is load-bearing.
5. **The org is the source of truth for what exists; this repo is the source of truth for what *should* exist.** Where they disagree, the repo wins and gets deployed.
6. **One person builds and operates this.** No release train, no multi-org promotion. `psk-dev` is the only org; Git is the only safety net.
7. **"Learn all the concepts" is a real requirement, not a nice-to-have.** Where a smaller design would skip a concept from [salesforce-concepts.md](salesforce-concepts.md), that gap is recorded explicitly in §8 rather than quietly accepted.

---

## 4. What we are building — four apps

The reorganising principle is **one app per job**, named after the job. If you cannot say "I am the person who does X" and have X be an app, the app is wrong.

### App 1 — PSK Passport Application Management

**Whose job:** the front-office counter officer and the document verification desk.
**What it does:** takes a citizen from "walked in the door" to "file is complete and paid, ready for verification."

Intake of the applicant as a `Citizen__c` golden record; creation of a `Passport_Application__c` under one of five record types; fee calculation from custom metadata; auto-generation of the document checklist on submit; document receipt and verification; raising and resolving objections against specific checklist items.

**Ends when:** `Status__c` reaches *Police Verification* (or *Granting* directly, where the record type calls for no PV).

### App 2 — PSK Support

**Whose job:** the help desk.
**What it does:** handles everything that is a *question or a request about* a passport rather than an application for one — "what stage is my file at", "I need my name changed after marriage", "how do I apply for a visa", "my booklet arrived damaged".

Built on the **standard `Case` object**, deliberately — this is where the curriculum's Phase 10 (Service, Cases & Routing) gets taught for real: Case record types per request category, queues, assignment rules, Email-to-Case, escalation, quick text, and a Knowledge-style set of canned responses. A Case can reference a `Passport_Application__c` or a `Passport__c`, and a request that turns out to need a new application spawns one.

**Why standard Case and not a custom object:** because half of Salesforce's service feature surface — Omni-Channel, entitlements, milestones, Email-to-Case, macros — only works on `Case`. Building a `Query__c` would mean re-implementing all of it badly and learning none of it.

### App 3 — PSK Police Verification

**Whose job:** the verifying officer, half of whose work happens on a doorstep, not a screen.
**What it does:** receives applications that require a field check, records the outcome, and escalates adverse findings.

A `Police_Verification__c` record per check, owned by a queue until an officer picks it up. Deliberately a **lookup** to the application, not master-detail, so the verification report has its own sharing model and outlives the application. Outcome of *Adverse* escalates to managers by sharing rule and blocks the application from advancing.

**Ends when:** outcome is Cleared or Adverse, which unblocks or halts the application.

### App 4 — PSK Passport Authorization & Dispatch

**Whose job:** the granting officer, then the print-and-despatch desk.
**What it does:** the back half — authorise, print, validate, send.

A granting officer reviews a file that is paid, document-verified and PV-cleared, and authorises it. For Diplomatic and Official categories that authorisation routes through a real **approval process** to the Regional Passport Officer and cannot proceed without sign-off. On authorisation a `Passport__c` booklet record is minted, almost entirely by formula from the application so no identity data is retyped. Printing, QC validation and courier despatch are tracked on a single `Dispatch__c` record through to delivery.

**Ends when:** `Status__c` reaches *Delivered*, after which the application is immutable.

### How the four apps connect

```
                    ┌─────────────────────────────────────┐
                    │  App 2 — PSK Support (Case)         │
                    │  questions · name change · visa     │
                    │  enquiry · complaints               │
                    └──────────────┬──────────────────────┘
                       references  │  can spawn
                                   ▼
┌──────────────────┐   PV needed  ┌──────────────────┐  cleared  ┌──────────────────────┐
│ App 1            │─────────────▶│ App 3            │──────────▶│ App 4                │
│ Application Mgmt │              │ Police Verif.    │           │ Authorization &      │
│                  │              │                  │           │ Dispatch             │
│ Citizen          │◀─────────────│ Police_          │  adverse  │ Passport             │
│ Passport_        │   blocks     │ Verification     │───────────│ Dispatch             │
│ Application      │              │                  │  ✗ halt   │                      │
│ Document_        │              └──────────────────┘           └──────────────────────┘
│ Checklist_Item   │                                                        │
└──────────────────┘         ◀───────── no-PV record types ─────────────────┘
                                   (Minor, some Re-Issue) skip App 3
```

One `Passport_Application__c` record travels through all four. The apps are **views onto the same lifecycle**, not separate systems — which is itself the lesson: in Salesforce, an "app" is a navigation and permission boundary, not a data boundary.

---

## 5. What a user can actually do

Concrete operations, because "the app manages applications" is not a specification.

| # | Operation | App | Actor | Effect |
|---|---|---|---|---|
| 1 | Find or create a citizen identity | 1 | Front Office | `Citizen__c` insert; duplicate rule blocks a second record for the same person |
| 2 | Start an application | 1 | Front Office | `Passport_Application__c` insert in `Draft`; record type chosen up front, subsetting every picklist thereafter |
| 3 | Save a half-finished form | 1 | Front Office | Saves clean — every validation rule is gated on `Status__c ≠ Draft` |
| 4 | Submit the application | 1 | Front Office | Fee written from `Fee_Matrix__mdt`; checklist rows generated; SLA clock starts; ownership moves to a queue |
| 5 | Record the fee as paid | 1 | Front Office | Fields on the application, not a separate ledger; gates granting later |
| 6 | Mark a document received, then verified | 1 | Doc Verification | `Document_Checklist_Item__c` update; roll-up on the parent tracks completeness |
| 7 | Raise an objection on a document | 1 | Doc Verification | Checklist item goes to `Objection Raised` with a reason; application cannot advance |
| 8 | Log a citizen enquiry | 2 | Help Desk | `Case` insert, record type by category, auto-routed to a queue by assignment rules |
| 9 | Convert a request into an application | 2 → 1 | Help Desk | A name-change Case spawns a Re-Issue `Passport_Application__c`, linked back |
| 10 | Claim a verification from the queue | 3 | Police Verification | `Police_Verification__c` owner changes from queue to user |
| 11 | Record a verification outcome | 3 | Police Verification | Cleared advances the application; Adverse halts it and escalates by sharing rule |
| 12 | Authorise a passport | 4 | Granting Officer | Blocked unless paid, documents verified, PV cleared; Diplomatic/Official additionally requires approval |
| 13 | Approve a sensitive grant | 4 | RPO | Approval process step; recorded, attributable, and blocking |
| 14 | Mint the booklet | 4 | Granting Officer | `Passport__c` insert, fields derived by formula from the application |
| 15 | Print, QC-validate, despatch, deliver | 4 | Fulfilment | One `Dispatch__c` record carries all four milestones |
| 16 | Audit any file after the fact | all | Audit & Compliance | Read-only across everything, with field history as the trail |

---

## 6. What this teaches

Every concept in [salesforce-concepts.md](salesforce-concepts.md) mapped to the thing in this build that teaches it. This table is the contract between the org and the course site — a lesson exists for each row.

| Curriculum phase | Concept | Where it lives in this build |
|---|---|---|
| 0 Orientation | Metadata, governor limits, SFDX, CLI | The repo itself; the incremental deploy sequence |
| 1 Data model | Custom objects, field types | The 8 objects |
| | Record types subsetting picklists | 5 on `Passport_Application__c`, 4 on `Case` |
| | Master-detail + cascade + roll-up | `Document_Checklist_Item__c` → application, with a verified-count roll-up |
| | Lookup and why you'd choose it | `Police_Verification__c` → application, deliberately not M-D |
| | Formula fields, cross-object | `Passport__c` derives almost everything from the application |
| | Global value sets | Shared vocabulary across objects |
| | Field dependencies | Passport Category → Clearance Level |
| | Custom metadata types | `Fee_Matrix__mdt`, `SLA_Config__mdt` |
| | **Junction object (M:N)** | **Gap — see §8** |
| 2 Data quality | Validation rules gated on stage | Submit-time enforcement, Draft always saves |
| | Duplicate & matching rules | Preventing two `Citizen__c` for one person |
| | External IDs & upsert | `External_Id__c` on every object |
| | Field history | On the application, for the auditor |
| | PII minimisation | The Aadhaar rule |
| 3 Security | OWD Private + role hierarchy | 6 roles over private data |
| | Permission sets and groups | One per persona, composed into groups |
| | Criteria-based sharing | Tatkal, Diplomatic, Adverse, High-Risk escalations |
| | Queues and public groups | 4 work queues + 1 approval queue |
| | FLS separate from CRUD | Aadhaar token readable, never editable |
| 4 UI | Lightning record pages, Dynamic Forms | Guardian fields appear only for minors |
| | Path, compact layouts, list views | The 10-stage application path |
| | Apps, tabs, quick actions, utility bar | The four apps |
| 5 Automation | Order of execution | Taught explicitly against a real save |
| | Record-triggered flow, before vs after | Field defaulting vs downstream record creation |
| | Approval processes | Diplomatic/Official grant sign-off |
| | Assignment rules, escalation | On `Case` in App 2 |
| 6 Apex | Trigger handler pattern, bulkification | One trigger per object → handler → service |
| | SOQL/DML discipline, collections | The service layer |
| | Async: Queueable, Batch, Scheduled | SLA breach sweep, notification dispatch |
| | Custom metadata in Apex, invocable methods | Fee service, callable from Flow |
| | `with sharing`, `USER_MODE` | Enforced in every service class |
| 7 Frontend | LWC, LDS, wire vs imperative | Checklist component, home dashboard |
| | Events, LMS, custom labels | Component communication, translation-ready strings |
| 8 Integration | Platform events, named credentials | The notification bridge design |
| 10 Service | Cases, queues, Omni-Channel, entitlements | **App 2 in full** |
| 11 Reporting | Report types, formats, dashboards | Office health and SLA reporting |
| 15 Testing | Apex, Flow, Jest, UAT | [TESTING.md](TESTING.md) |
| 16 DevOps | Source format, deploy order, packaging | The migration in [MIGRATION.md](MIGRATION.md) |

---

## 7. Explicitly out of scope

Named so they stop being open questions.

| Not building | Why |
|---|---|
| Experience Cloud citizen portal | One-way Setup toggle, uncertain licences on Developer Edition, cannot be verified by metadata deploy alone. The applicant persona stays staff-mediated. |
| Enterprise Territory Management | Irreversible toggle; the sharing design is built on public groups and criteria-based rules instead. |
| Live n8n / Twilio integration | Requires a running n8n instance and provider credentials that do not exist here. The Salesforce-side contract (platform event + named credential + idempotency key) is designed and testable with mocks; the far side is not built. |
| CRM Analytics / Einstein Discovery | Phase 11b of the curriculum. Deferred until standard reports and dashboards are done — and the inherited Wave template metadata is being removed, not extended. |
| Data Cloud / Agentforce | Phase 12. Not available or not meaningful at this org's scale. |
| Hindi / regional translation | `Preferred_Language__c` exists and custom labels are used throughout so it stays possible, but no translation is authored. |
| Appointment scheduling | Cut. See §8. |

---

## 8. Known concept gaps from the object cut

Cutting to eight objects costs coverage. Recording it rather than pretending otherwise.

**1. Junction object / many-to-many — lost.**
`Appointment__c` was a true junction (two master-detail relationships, to `Slot__c` and to the application). Nothing in the reduced model is M:N. This is a Phase 1 concept and a common interview question.

*Proposed remedy (needs your call):* teach it as a **build-then-discard exercise** in the data-model lesson — construct the junction in a scratch context, prove the roll-ups and cascade behaviour, and delete it — rather than carrying two objects in the shipped org for one concept. Alternative: keep `Slot__c` + `Appointment__c` and accept a 10-object model.

**2. Roll-up summary — narrowed but preserved.**
Only one master-detail pair survives (`Document_Checklist_Item__c`). That is enough to teach roll-ups, cascade delete, `ControlledByParent` sharing and the "roll-ups need master-detail" constraint, but there is exactly one example rather than several.

**3. Notification logging — folded away.**
`Notification_Log__c` is cut, so the n8n write-back target disappears. The idempotency lesson (external ID + upsert) moves onto `Case` and the application's `External_Id__c`. If the integration is ever built for real, the log object comes back.

**4. Inherited Wave/Trailhead metadata — removal has a consequence.**
`OpportunityHistory__c` and `Reseller_Account_Plan__c` back the Service Analytics dashboards that shipped with the org. Deleting them breaks those dashboards. Since PSK reads none of it and Phase 11b is out of scope, that is an acceptable loss — but it is a loss, and it is irreversible. Called out for sign-off in [MIGRATION.md](MIGRATION.md).

---

## 9. Build sequence

Design first, then cut, then build up. Each phase ends with a working org and a lesson written.

| Phase | What | Gate to the next phase |
|---|---|---|
| **0 · Design** | These documents. No metadata touched. | You approve the object cut and the app split. |
| **1 · Cut** | Remove the ten cut objects, three redundant apps, and the inherited template metadata — locally, then a `destructiveChanges` deploy. | Org deploys clean; remaining Apex compiles; tests green. |
| **2 · Schema** | Rebuild the 8 objects lean: fields that are actually read, global value sets, record types, custom metadata. | Schema deploys; no orphaned field references. |
| **3 · Security** | Roles, OWD, permission sets, queues, sharing rules, FLS. | Persona access matrix verified by login-as. |
| **4 · UI** | Four apps, tabs, record pages, Dynamic Forms, Path, compact layouts, list views. | Each persona can do their job from their own app. |
| **5 · Declarative automation** | Record-triggered flows, validation rules, approval process, Case assignment rules. | Flow tests pass. |
| **6 · Apex** | Trigger handlers, service layer, fee and SLA services, async sweep. | Apex tests ≥75% with real assertions. |
| **7 · LWC & reporting** | Checklist component, dashboards, report types, reports. | Renders and wires correctly; Jest green. |
| **8 · Test automation** | The end-to-end walkthrough per [TESTING.md](TESTING.md). | Full lifecycle runs unattended and asserts every stage. |

Phases 2–7 each produce lessons on the course site as they are built, not afterwards — the build log *is* the curriculum.

---

## 10. Definition of done

A phase is done when all five are true:

1. It is **deployed** to `psk-dev` and the deploy is reproducible from source.
2. It is **tested** — Apex, Flow, or Jest as appropriate, with assertions on outcomes rather than coverage for its own sake.
3. It is **demonstrable** — there is demo data that shows it working, including at least one failure path.
4. It is **explained** — a lesson exists on the course site naming the concept, why it exists, and how this build uses it.
5. It **stores no re-identifiable PII** beyond what §3.4 permits.
