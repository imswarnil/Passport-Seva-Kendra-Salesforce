# CASE_STUDY.md — Building a Passport Seva Kendra on Salesforce

> A portfolio case study of an independent build. Not affiliated with any government body — this is a demonstration project showing data modelling, automation, and security design on the Salesforce platform, using India's real Passport Seva Kendra network as the domain to model against. Deep technical reference: [PSK.md](PSK.md). Persona research this build is grounded in: [PERSONAS.md](PERSONAS.md).

---

## 1. Problem statement

A passport office is, structurally, a document that has to survive contact with eight different people before it becomes a real, physical booklet: an applicant, a front-office clerk, a document verifier, a police officer, a granting officer, a print operator, a courier, and — for a slice of cases — a manager who has to sign off before anything ships. Run that process on paper and a few failure modes show up immediately:

- **No one can answer "where is this file right now."** A paper folder is either on someone's desk, in transit, or lost, and there's no way to tell which without walking around and asking.
- **Verification turnaround is inconsistent and invisible.** Police verification in particular happens off-site, and a manual process has no structural way to flag that a case has gone quiet for two weeks versus two days.
- **There's no audit trail.** When a paper file is the record, review after the fact means re-reading handwritten notes written by the same people being reviewed — there's no independent, tamper-resistant account of what happened and when.
- **Fraud and duplicate-application risk go undetected until someone notices by hand.** A mismatched address, a name that's shown up on three applications this month, an unusually fast Tatkal turnaround with no supporting documents — none of that surfaces unless a specific person happens to spot it.

This build treats that last point as a first-class design requirement, not an afterthought: `Passport_Application__c` carries a `Risk_Score__c` field (0–100), and a standalone `Risk_Flag__c` object records specific fraud/anomaly flags with severity and a reviewing user. A criteria-based sharing rule (`Open_High_Severity_To_Managers`) routes High/Critical flags to management automatically, and a second rule (`High_Risk_To_Verification`) gives the verification team read access to any application scoring above 70 — so a suspicious file gets more eyes on it before it's granted, not after.

## 2. Research approach

The design decisions in this build didn't start from "what can Salesforce do" — they started from working through eight personas end to end (documented in full in [PERSONAS.md](PERSONAS.md)): the Applicant, the Front Office Officer, the Document Verification Officer, the Police Verification Officer, the Granting Officer, the Fulfilment Officer, the Office Manager/RPO, and the Audit & Compliance Officer.

A few things converged across almost all of them:

- **"Where is this file right now" was the universal frustration.** The Applicant wants to know; the Front Office Officer wants to hand off cleanly; the Manager wants an aggregate answer across the whole office. That single complaint is why `Status__c` exists as one restricted, twelve-value picklist that is the *single* source of truth for lifecycle position — not a status per department, not a separate object per stage. It's also why the Path component and queue-based routing exist: the Path makes the current stage visually unambiguous on the record itself, and routing an application into a queue (`Document_Verification`, `Police_Verification`, `Granting`, `Printing_And_Dispatch`, `Objections`, `Risk_Review`) means "who owns this right now" is answered by queue membership, not by asking around.
- **Verification and granting personas both wanted structural gates, not policy reminders.** A paper process relies on an officer remembering that payment must clear before granting. This build enforces it: `Cannot_Grant_With_Pending_Payment` is a validation rule, not a guideline, and it blocks the transition outright.
- **The Manager and Auditor personas both wanted visibility without needing to be looped in manually.** That's what the criteria-based sharing rules deliver — `Tatkal_To_Managers`, `Diplomatic_To_RPO`, `Adverse_To_Managers`, `Blacklisted_To_Managers`, `Open_High_Severity_To_Managers` — sensitive or urgent cases get shared to the right group automatically the moment a field crosses a threshold, rather than depending on someone remembering to escalate.
- **The Granting Officer and Manager personas both wanted accountability on sensitive grants.** That's the origin of the new `Diplomatic_Official_Grant_Approval` approval process, discussed in §4.

## 3. Design philosophy

The architecture follows one rule stated plainly in PSK.md §1: **few objects, many fields.** The entire application lifecycle — from a half-filled intake form to a delivered booklet — lives on one object, `Passport_Application__c`, distinguished by a `Status__c` picklist and by record type, not by moving the record between different objects as it progresses. A Draft is not a different kind of thing from a Granted application; it's the same object in an earlier state. This keeps the data model legible: one place to look for "everything about this application," one set of validation rules, one Path.

The one deliberate exception to "don't duplicate data" is worth explaining, because on the surface it looks like it violates the object's own design rule. `Passport_Application__c` stores its own `First_Name__c`, `Last_Name__c`, `Date_of_Birth__c`, `Mobile__c`, and full address — even though it also holds a `Citizen__c` lookup to a "golden identity" record that already has all of that. This is not an oversight; it's the load-bearing design decision of the whole model (PSK.md §2.1).

A passport is a legal instrument. What gets printed into the booklet, what the police verify against, and what an audit later examines is **what the applicant declared at the moment of submission** — not whatever happens to be true about that person today. If the application's name and address fields were formulas reading live off `Citizen__r`, then the day that citizen corrected a spelling or moved house, every historical application connected to them — including ones already granted and printed years earlier — would silently rewrite itself. The very act of keeping the citizen record accurate would destroy the historical record of what was actually declared and verified at the time.

So the model draws a hard line: `Citizen__c` answers "who is this person now"; `Passport_Application__c` answers "what did they declare then." They are allowed to disagree, and that disagreement is itself meaningful — it's exactly what a document-verification or audit review would want to be able to see.

Everywhere *else* in the model, the opposite instinct applies — snapshot a declaration, derive a fact. `Passport__c` re-keys nothing off the application: booklet pages, validity years, ECR status, and holder name are formulas, because a booklet doesn't have its own opinion about facts that are already fixed by the application it was issued from. `Dispatch__c.Delivery_Address__c` is a formula over the application's address, so a courier label can never drift from the record. The rule of thumb, stated once and applied consistently: **snapshot a declaration, derive a fact** — and knowing which category a given field belongs to is the actual design skill on display here, not a hard-and-fast object count.

## 4. What the system solves, mapped to personas

| Persona | Old pain point | New Salesforce capability | Object/automation that delivers it |
|---|---|---|---|
| Front Office Officer | No way to tell if a file was genuinely incomplete or something was wrong with it | A single `Status__c` value with submit-gated validation, not a fork into a different form | `Passport_Application__c.Status__c`, `Require_Core_Fields_On_Submit` (fires only once Status leaves Draft) |
| All operating personas | Work assignment depended on someone manually routing a paper file to the right desk | Auto-routing into queues by stage, no assignment-rule maintenance per record | Six queues (`Document_Verification`, `Police_Verification`, `Granting`, `Printing_And_Dispatch`, `Objections`, `Risk_Review`) |
| Document Verification Officer | Document completeness lived in an officer's head; no consistent checklist | Auto-generated `Document_Checklist_Item__c` rows the moment an application is submitted | `Document_Checklist_Item__c` (master-detail to the application), `Mark_Received`/`Mark_Verified` quick actions |
| Granting & Fulfilment Officers | Manual, error-prone creation of the booklet, print batch, and dispatch records — each one a fresh chance to mistype identity data | Automatic minting of `Passport__c`, `Print_Job__c`, and `Dispatch__c` records on status change, with formula fields pulling identity data straight from the application | `PSK_ApplicationActionsController`, `Passport__c`/`Print_Job__c`/`Dispatch__c` formula fields (PSK.md §2.2) |
| Granting Officer & RPO | Diplomatic/Official grants had no structural sign-off — it was a picklist change like any other | A real approval process gating Granting → Printing behind sign-off | `Diplomatic_Official_Grant_Approval` approval process, entry criteria on record type + status |
| Office Manager & Auditor | High-risk, blacklisted, or adverse cases surfaced only if someone happened to notice | Risk scoring plus automatic sharing the moment a threshold is crossed | `Risk_Flag__c`, `Risk_Score__c`, criteria-based sharing rules (`Open_High_Severity_To_Managers`, `Blacklisted_To_Managers`, `Adverse_To_Managers`) |
| Office Manager | No aggregate answer to "how many files are overdue right now" | Ageing and SLA-breach visibility driven by configurable targets, not hard-coded thresholds | `SLA_Config__mdt` (26 records: normal + Tatkal target per stage), `pskHomeDashboard` LWC via `PSK_HomeController` |

## 5. Architecture at a glance

This section is intentionally brief — [PSK.md](PSK.md) is the authoritative deep reference for all of it.

**Data model.** Sixteen custom objects (PSK.md §2), rooted conceptually at `Passport_Application__c` — the single object carrying the full Draft-to-Delivered lifecycle — with satellite objects for offices (`PSK__c`), appointments (`Slot__c`, `Appointment__c`), verification (`Document_Checklist_Item__c`, `Objection__c`, `Police_Verification__c`), money (`Payment__c`), risk (`Risk_Flag__c`), identity (`Citizen__c`, `Family_Member__c`), and fulfilment (`Passport__c`, `Print_Job__c`, `Dispatch__c`). Two custom metadata types, `Fee_Matrix__mdt` and `SLA_Config__mdt`, keep fee schedules and SLA targets as declarative configuration rather than hard-coded values.

**Security model.** Eleven roles rooted at `CEO_and_Admins`, eight persona permission sets (`PSK_Officer`, `PSK_Verification_Officer`, `PSK_Granting_Officer`, `PSK_Fulfilment_Officer`, `PSK_Office_Manager`, `PSK_Auditor_Read_Only`, `PSK_Reference_Data_Admin`, and the catch-all `PSK_App_Access`), six queues, and nine criteria-based sharing rules over a Private OWD on every object holding personal data. Field-level security on PII (`Date_of_Birth__c`, `Mobile__c`, `Aadhaar_Verified__c`, `Aadhaar_Token__c`) is controlled per permission set, independent of object-level access — a persona that can open a record does not automatically see the Aadhaar token.

**Automation layer.** Four triggers and twelve service/controller Apex classes (`PSK_ApplicationActionsController`, `PSK_ApplicationService`, `PSK_FeeService`, `PSK_PassportIssuanceController`, and others) drive fee calculation off `Fee_Matrix__mdt`, checklist generation, and the minting of downstream fulfilment records on status change — plus the new `Diplomatic_Official_Grant_Approval` approval process for sensitive grants.

## 6. Outcomes / what a demo shows

The build supports a genuine end-to-end walkthrough, not just a populated schema: an application driven from Draft through every stage to Delivered via the real `PSK_ApplicationActionsController.advance()` action controller — the same code path a Granting or Fulfilment Officer would actually click through — prices itself correctly from `Fee_Matrix__mdt`, and mints **exactly one** booklet, print job, dispatch, and police verification record along the way, with the booklet number matching the correct Indian format and its external ID mirroring it. This was verified directly, not assumed, as part of the Apex build (see the "End-to-end verified" note in the commit history for the trigger/service layer).

The org ships with 188/188 Apex tests passing and code coverage in place across the automation layer. Demo data is fully seeded: `PSK_DemoDataGenerator` populates records across all sixteen custom objects — applications, offices, slots, appointments, citizens, family members, checklist items, payments, police verifications, objections, risk flags, notification logs, passports, print jobs, and dispatches — so a walkthrough doesn't require manually creating a scenario from scratch.

## 7. Honest known gaps / what's next

Being candid about what isn't built yet is part of the point of a portfolio project like this — it shows where the design reasoning stopped, not just where it succeeded.

- **The Diplomatic/Official approval process routes to a placeholder approver.** `Diplomatic_Official_Grant_Approval` is real and active, but its `assignedApprover` is currently hardcoded to a single admin user (`admin@passportoffice.com`) rather than the `Regional_Passport_Officer` role it conceptually belongs to. Salesforce approval processes generally need that kind of approver assignment set up (or at least verified) through Setup rather than pure metadata deploy, so this is flagged as a known, pending fix rather than something silently left wrong.
- **No visa department yet.** `Visa_Application__c`, `Country__c`, and `Sponsor__c` don't exist. The `Visa_Processing_Team` role, `PSK_Visa_Team` group, and `PSK_Visa_Type` value set are already in place waiting for them, but building the objects themselves hasn't started.
- **No citizen-facing self-service.** The Applicant persona (§1 of PERSONAS.md) has no login today — every interaction is staff-mediated. The community that ships with the org (*Internal Zone*) is inherited Service Analytics template residue, not a purpose-built PSK portal.
- **No reports, dashboards, or custom report types.** Zero exist for any PSK object today. Operational questions ("how many Tatkal files breached SLA this month") currently have to be answered by reading records directly rather than through aggregate reporting.
- **Region-based sharing is unimplemented.** Criteria-based sharing rules in Salesforce can't traverse a lookup (no rule can filter on `PSK_Office__r.Region__c`) and can't read a formula field either — both real platform constraints, not oversights, documented in PSK.md §5.5. The fix is a real `Region__c` text field on the application populated by automation, which hasn't been built yet.
- **No n8n / Twilio / AI integrations yet.** `Notification_Log__c` exists with a `Provider_Message_Id__c` field specifically designed as a Twilio idempotency key, but it's currently empty of real sends — there's no live messaging integration wired up. A companion `n8n.md` is planned to catalog the integration roadmap in more detail; it hasn't been written yet.
- **Only one of six record types has a Path.** The stage bar (`Passport_Application_Path`) is declared for the `Fresh` record type only; Re-Issue, Tatkal, Lost/Damaged, Minor, and Diplomatic/Official currently render no visual stage guidance.
- **No Hindi or regional-language translation**, despite `Citizen__c.Preferred_Language__c` already existing as a field to hang it off — `objectTranslations/` are still en_US stubs.

None of these are hidden inside the build; they're tracked explicitly in PSK.md §9 and, for anything touched during this write-up, cross-checked directly against the deployed metadata rather than taken on faith.
