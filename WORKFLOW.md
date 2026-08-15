# WORKFLOW.md — How a Passport Application Actually Moves Through PSK

> Operational reference: what happens at each stage of the lifecycle, who does it, what the system does for you automatically, and what still needs a human. For the data model, security architecture, and build history, see [PSK.md](PSK.md) — this document is the walkthrough, PSK.md is the deep reference. Every claim below is checked against the actual Apex, metadata and permission sets in `force-app/main/default/` as of this session (which added queue routing, checklist auto-seeding, and the Diplomatic/Official approval gate on top of what PSK.md describes).

---

## 1. Overview

Passport Seva Kendra (PSK) is a custom Salesforce app modelling the passport-office application lifecycle on a single object, `Passport_Application__c`, using a 12-value `Status__c` picklist and six record types rather than a new object per stage — a half-finished form is the same record in `Draft` status, not a different object. The lifecycle runs Draft → Submitted → Payment Pending → Paid → Document Verification → Police Verification → Granting → Printing → Dispatch → Delivered, with `Rejected` and `Cancelled` as exits at any non-terminal point. Every forward move is a deliberate human click (the "Advance" action), but each click cascades whatever side effects that transition requires — queue reassignment, document-checklist seeding, passport/print-job/dispatch record creation, approval submission — so staff are never left to remember a manual follow-up step. It is "auto once you act," not unattended automation: nobody's status changes itself, and nobody's judgment (verifying a document, conducting a police check, approving a diplomatic grant) is replaced by code.

---

## 2. The 12-stage lifecycle

Source of truth: `PSK_Constants.LIFECYCLE` / `TERMINAL_STATUSES` (`force-app/main/default/classes/PSK_Constants.cls`), the `NEXT_STATUS` map and side effects in `PSK_ApplicationActionsController.advance()` / `.reject()` / `.rejectWithReason()` / `.cancel()`, and the trigger-side automation in `PassportApplicationTriggerHandler.cls` + `PSK_ApplicationService.cls`.

| Status | What happens at this stage | Who owns / works it | Automatic vs. manual | Record(s) auto-created |
|---|---|---|---|---|
| **Draft** | Applicant/officer captures details. Incomplete records save fine — validation rules only bite on submit. | Whoever created it (typically `PSK_Officer` — front office). No queue. | Manual: filling in the form and clicking **Advance** ("Move to Submitted"). | — |
| **Submitted** | Record leaves Draft. `Submitted_Date__c` is stamped. | Stays with the front-office officer. No queue. | **Automatic** the moment the transition lands: `PassportApplicationTriggerHandler.handleFulfilment` detects the genuine Draft→Submitted move and calls `PSK_ApplicationService.seedChecklistItems()`, which inserts one `Document_Checklist_Item__c` per document type in `checklistTemplate(recordType)` (varies by record type — e.g. Minor gets 4 items, Tatkal gets 5 including an Affidavit). Manual: getting the record to pass `Require_Core_Fields_On_Submit` and `Minor_Needs_Guardian_Consent` in the first place. | `Document_Checklist_Item__c` rows (one per required document type for that record type) |
| **Payment Pending** | Application is waiting on the fee. | Front office. No queue. | Manual: officer clicks Advance to signal payment is being collected. | — |
| **Paid** | `advance()` sets `Payment_Status__c = 'Paid'` when moving out of Payment Pending; `Payment_Date__c` is auto-stamped by `PassportApplicationTriggerHandler.applyDefaults()` the moment status is Paid. | Front office. No queue (Document Verification is the next queued stage). | **Automatic**: payment-status flip and date stamp. Manual: actually taking the payment (`Collect_Payment` quick action / `Payment__c` record). | — |
| **Document Verification** | Application enters the document-check queue. | **`Document_Verification` queue** — worked by `PSK_Document_Verification_Officer`. | **Automatic**: `PSK_ApplicationService.routeOwnership()` reassigns `OwnerId` to the `Document_Verification` queue (replaces manual assignment rules). Manual: the officer actually checks each `Document_Checklist_Item__c` (`Mark_Received`, `Mark_Verified` quick actions) — this is a human judgment call, not automated. | — |
| **Police Verification** | `advance()` sets `Documents_Verified__c = true` and inserts a `Police_Verification__c` record (`Status = 'Referred'`, `PV_Type__c` from the application or defaulted to `Post-PV`, `Police_Station__c` derived from the applicant's city/district). That PV record is itself assigned to the `Police_Verification` queue. | **`Police_Verification` queue** — worked by `PSK_Verification_Officer`. | **Automatic**: PV record creation, its queue assignment, and the parent application's own queue reassignment (`routeOwnership`). Manual: the officer conducts the actual field/records check and updates the PV record (`Mark_Cleared` / `Mark_Adverse` quick actions). | `Police_Verification__c` (Status = Referred) |
| **Granting** | `advance()` force-updates the most recent `Police_Verification__c` to `Status = 'Cleared'`, `Report_Received_Date__c = today` — clicking Advance out of Police Verification assumes clearance. `Granted_Date__c` is stamped; `Payment_Status__c` is re-confirmed `Paid`. If the record type is `Diplomatic_Official`, `advance()` also calls `Approval.process()` to auto-submit it into the `Diplomatic_Official_Grant_Approval` approval process (see §4). | **`Granting` queue** — worked by `PSK_Granting_Officer`. | **Automatic**: PV force-clear, date stamps, queue routing, and (Diplomatic/Official only) approval submission. Manual: an officer who found an *adverse* PV report should use `Mark_Adverse` + reject the application rather than clicking Advance, since Advance itself does not check the PV outcome — it assumes the officer already resolved it. | — (Diplomatic/Official: an approval request is created) |
| **Printing** | Booklet issuance. `PassportApplicationTriggerHandler.handleFulfilment` calls `PSK_ApplicationService.issuePassports()`, which creates a `Passport__c` (booklet number, dates, category) and a `Print_Job__c` (`Status = Queued`) — idempotent, skips if a passport already exists for the application. `Diplomatic_Official_Requires_Approval` (validation rule) blocks the record from ever reaching this status until `Approval_Status__c = 'Approved'` for Diplomatic/Official record types. | **`Printing_And_Dispatch` queue** — worked by `PSK_Fulfilment_Officer`. | **Automatic**: `Passport__c` + `Print_Job__c` creation, queue routing. Manual: for Diplomatic/Official, a human Regional Passport Officer approval must have already cleared (see §4) — the system will not let the record in otherwise. For everyone else, the Granting Officer just clicks Advance. | `Passport__c`, `Print_Job__c` |
| **Dispatch** | `PassportApplicationTriggerHandler.handleFulfilment` calls `PSK_ApplicationService.createDispatches()`, creating a `Dispatch__c` (courier partner, tracking number, expected delivery date) — also idempotent, and back-fills a passport/print job first if a record somehow skipped straight to Dispatch. | **`Printing_And_Dispatch` queue** (same queue as Printing). | **Automatic**: `Dispatch__c` creation, queue routing. Manual: the fulfilment officer actually prints the booklet, does QC, and marks the print job `Printed` (`Mark_Printed` quick action) before/around this transition. | `Dispatch__c` |
| **Delivered** | Terminal, happy-path end state. No queue entry for Delivered in `APPLICATION_STAGE_QUEUE`, so ownership simply stays wherever it was (the fulfilment queue/officer). `No_Backward_Move_Once_Delivered` validation rule locks the record here. | Whoever last owned it (fulfilment team). | Manual: courier delivery confirmation (`Mark_Delivered` quick action on `Dispatch__c`), recording `Received_By__c`. | — |
| **Rejected** | Terminal exit, reachable from any non-terminal status via `reject()` / `rejectWithReason()`. If a reason is supplied, a best-effort `Objection__c` is created (`Objection_Type__c = 'Other'`, `Status__c = 'Escalated'`) so the rejection is visible on the record's timeline. This is also where a Diplomatic/Official grant lands if the approval is **rejected** (see §4). | Whoever owned the record when rejected. | **Automatic**: the Objection__c audit trail (best-effort — a failed insert does not block the rejection). Manual: the actual decision to reject. | `Objection__c` (only if a reason was given) |
| **Cancelled** | Terminal exit, reachable from any non-terminal status via `cancel()` — distinct from Rejected: this is the *applicant's* choice, not a departmental decision. No child records are created. | Whoever owned the record when cancelled. | Manual only. | — |

**A subtlety worth being explicit about:** `PassportApplicationTriggerHandler.applyDefaults()` also silently forces `Payment_Status__c = 'Paid'` for any record sitting at or beyond Granting (`PSK_Constants.REQUIRES_PAID`), as a safety net so `Cannot_Grant_With_Pending_Payment` never blocks a record that legitimately reached that stage through the normal flow. This means the payment gate is effectively double-enforced: once by the validation rule, once by a defensive default in the trigger.

---

## 3. Persona-by-persona: who does what

Nine permission sets exist in `force-app/main/default/permissionsets/`. `PSK_App_Access` is the admin/verification catch-all (full CRUD + `viewAllRecords` on every PSK object) used for building and testing the org — the eight `PSK_*` sets below are the real job-shaped personas, each granted on top of the base Salesforce user license.

| Persona (permission set) | Plain-English role | Queue(s) worked | Stage(s) acted on | Can / cannot see | Lightning App | Relevant quick actions |
|---|---|---|---|---|---|---|
| **`PSK_Officer`** | Front-office / data-entry counter clerk | None (owns records directly, not via queue) | Draft → Submitted → Payment Pending → Paid | Create/edit `Passport_Application__c`, `Citizen__c`, `Appointment__c`, `Document_Checklist_Item__c` (no delete on any). Create-only on `Payment__c` and `Notification_Log__c` (no edit/delete). Read-only on `PSK__c`, `Slot__c`. **`Date_of_Birth__c`/`Mobile__c`/`Aadhaar_Verified__c` are editable** — this is the role that collects them at intake. `Aadhaar_Token__c` is read-only even here — it's an opaque provider reference no human persona should hand-type. Record types visible: Fresh, Re_Issue, Tatkal, Minor, Lost_Damaged — **`Diplomatic_Official` is not in the set**, so this persona genuinely cannot open a diplomatic/official application. | `Application_Management_Console`, `Passport_Validator` | `Citizen__c.New_Passport_Application`, `Citizen__c.New_Family_Member`, `Citizen__c.Verify_KYC`, `Passport_Application__c.Collect_Payment`, `Passport_Application__c.New_Appointment`, `Passport_Application__c.New_Document_Item` |
| **`PSK_Document_Verification_Officer`** | Document-verification officer | `Document_Verification` | Document Verification | Full CRUD on `Document_Checklist_Item__c` and `Objection__c`; read-only (not edit/create/delete) on `Passport_Application__c` and `Citizen__c`. No access at all to `Police_Verification__c` or `Risk_Flag__c` — those stayed with the Police Verification Officer's set. **All PII fields on the application are read-only** (`editable=false` across the board) — this persona holds the "must not automatically read/edit the Aadhaar token" principle from PSK.md §5.2, reading it for context only. All six record types visible, including Diplomatic_Official. | `Application_Management_Console` only (not `Passport_Validator`) | `Document_Checklist_Item__c.Mark_Received`, `Document_Checklist_Item__c.Mark_Verified`, `Passport_Application__c.New_Objection`, `Objection__c.Resolve_Objection` |
| **`PSK_Verification_Officer`** | Police-verification officer | `Police_Verification` | Police Verification | Full CRUD on `Police_Verification__c`; create/edit (not delete) on `Risk_Flag__c`; edit (not create/delete) on `Passport_Application__c`; read-only on `Citizen__c`. No access to `Document_Checklist_Item__c` or `Objection__c` — split out to `PSK_Document_Verification_Officer`. **PII fields on the application (`Date_of_Birth__c`, `Mobile__c`, `Aadhaar_Verified__c`, `Aadhaar_Token__c`) are read-only** — this persona verifies against the declaration, it doesn't edit it, matching the "must not automatically read/edit" principle in PSK.md §5.2. All six record types visible, including Diplomatic_Official. | `Application_Management_Console`, `PSK_Police_Verification_Console`, `Passport_Validator` | `Police_Verification__c.Mark_Cleared`, `Police_Verification__c.Mark_Adverse`, `Passport_Application__c.Raise_Risk_Flag` |
| **`PSK_Granting_Officer`** | Grants or rejects applications, issues passports (including Diplomatic/Official) | `Granting` | Granting → Printing | Edit `Passport_Application__c`; create/edit (not delete) `Passport__c`; edit `Objection__c`; read-only `Police_Verification__c` and `Citizen__c`. **PII fields on the application are read-only** — matches "cannot edit the applicant declaration" in PSK.md §5.2's original persona spec. Reads (not edits) `Approval_Status__c`. All six record types visible. | `Application_Management_Console`, `Passport_Validator` | `Passport_Application__c.New_Objection`, `Objection__c.Resolve_Objection` (advance/reject actions come from the sidebar LWC, backed by `PSK_ApplicationActionsController`) |
| **`PSK_Fulfilment_Officer`** | Owns printing and dispatch | `Printing_And_Dispatch` | Printing, Dispatch, Delivered | Full CRUD `Dispatch__c` and `Print_Job__c`; edit (not create/delete) `Passport__c`; read-only `Passport_Application__c` and `PSK__c`, `Slot__c`. **All PII fields on the application are read-only** (`editable=false` across the board) — this is the one persona whose field-level security matches the "read-only on the application except operational fields" description in PSK.md §5.2. | `Application_Management_Console`, `Passport_Validator` | `Passport_Application__c.New_Print_Job`, `Passport_Application__c.New_Dispatch`, `Print_Job__c.Mark_Printed`, `Dispatch__c.Mark_Delivered`, `Passport__c.Report_Lost` |
| **`PSK_Office_Manager`** | Passport Office Manager / oversight — the closest analogue to the Regional Passport Officer for day-to-day purposes | All (oversight, not queue-bound work) | All stages (view/oversight; can edit anywhere) | Full CRUD on every PSK object, `viewAllRecords=true` on `Citizen__c`, `PSK__c`, `Passport_Application__c`, `Passport__c`, `Police_Verification__c`, `Notification_Log__c`, `Renewal__c`, `Risk_Flag__c` (not `modifyAllRecords` — cannot bypass sharing to edit records outside normal access). Extra user permissions: `TransferAnyEntity`, `ViewRoles`, `ViewSetup`. All PII fields fully editable. All six record types visible. | `Application_Management_Console`, `Passport_Validator` | Broadest tab set of any persona (16 tabs) — no single action set; this role uses whichever quick action the situation calls for |
| **`PSK_Reference_Data_Admin`** | Maintains offices, appointment slots, Fee Matrix and SLA Config | None | None (reference data, not application-stage work) | CRUD on `PSK__c` and `Slot__c` only. **No access at all to `Passport_Application__c` or `Citizen__c`** — zero PII exposure by construction. Custom-metadata-type access to `Fee_Matrix__mdt` and `SLA_Config__mdt`. | `Application_Management_Console` only (not `Passport_Validator`) | `PSK__c.New_Slot` |
| **`PSK_Auditor_Read_Only`** | Audit & Compliance | None | None (read-only across the board) | Read-only, `viewAllRecords=true`, on every PSK object — including `Notification_Log__c` and all PII fields (`Date_of_Birth__c`, `Mobile__c`, `Aadhaar_Verified__c`, `Aadhaar_Token__c` are all `readable=true`, `editable=false`). No create/edit/delete anywhere. All record types visible. | `Application_Management_Console`, `Passport_Validator` | None — read-only role, no quick actions granted |

**The PII field-level-security point from PSK.md §5.2, checked against the real permission sets:** the principle stated there ("a persona that can open a record must not automatically read/edit the Aadhaar token") now holds for every persona except `PSK_Office_Manager` and `PSK_Officer`. `PSK_Reference_Data_Admin` has no access to the object at all; `PSK_Fulfilment_Officer`, `PSK_Verification_Officer`, `PSK_Document_Verification_Officer`, and `PSK_Granting_Officer` all have PII fields read-only. `PSK_Officer` keeps `Date_of_Birth__c`/`Mobile__c`/`Aadhaar_Verified__c` editable since it's the intake role that collects them, but `Aadhaar_Token__c` is read-only there too. `PSK_Office_Manager` keeps full PII edit access deliberately — PSK.md §5.2 describes this role as "Read/edit everything in the office," which is intentional oversight breadth, not drift. `PSK_Auditor_Read_Only` is a separate, deliberate exception (compliance needs to see the data, just never change it).

---

## 4. Who approves what

### 4.1 Diplomatic/Official grant approval — a real approval process

`force-app/main/default/approvalProcesses/Passport_Application__c.Diplomatic_Official_Grant_Approval.approvalProcess-meta.xml`

- **Trigger condition:** `RecordType.DeveloperName = 'Diplomatic_Official' AND Status__c = 'Granting'`. The application is auto-submitted the instant it enters Granting — `PSK_ApplicationActionsController.advance().submitForApproval()` calls `Approval.process()` right after the status-changing `update`. Submission is best-effort: if it fails (record already under approval, approval process unavailable in a test context, etc.) the status move that already committed is not rolled back, and the failure is silently swallowed rather than surfaced.
- **Who can submit:** the record owner, or anyone in the `Granting_Officers` or `Passport_Office_Manager` roles (`allowedSubmitters`).
- **Approver:** a single step, "Regional Passport Officer Sign-off," assigned to the `RPO_Approvals` queue (`force-app/main/default/queues/RPO_Approvals.queue-meta.xml`), whose members are the `Regional_Passport_Officer` role and its subordinates (via `roleAndSubordinates`), plus the admin user as a fallback — so approvals correctly route to Regional Passport Officers.
- **On submit:** `Approval_Status__c` is field-updated to `Pending` (`initialSubmissionActions`).
- **On approve:** `Approval_Status__c` → `Approved` (`finalApprovalActions`). This is what satisfies the `Diplomatic_Official_Requires_Approval` validation rule and lets the record proceed to Printing.
- **On reject:** `Approval_Status__c` → `Rejected`, **and** a field update sends `Status__c` back to `Document Verification` (`finalRejectionActions`, two actions: `Approval_Status_Rejected` + `Send_Back_To_Document_Verification`). The application re-enters the `Document_Verification` queue via the same `routeOwnership` logic that fires on any status change — it is not stuck in limbo, it goes back a stage for rework.
- **Recall:** allowed (`allowRecall=true`); recalling resets `Approval_Status__c` back to `Pending`.

### 4.2 The two validation-rule gates — automatic blocks, not human approvals

These are not approval processes and involve no sign-off queue — they are hard stops enforced at save time, worth distinguishing from §4.1's human-in-the-loop process:

- **`Cannot_Grant_With_Pending_Payment`** (`objects/Passport_Application__c/validationRules/Cannot_Grant_With_Pending_Payment.validationRule-meta.xml`): `AND(ISPICKVAL(Status__c,"Granting"), NOT(ISPICKVAL(Payment_Status__c,"Paid")))`. Blocks the save outright if an application tries to reach Granting without `Payment_Status__c = 'Paid'`. In practice this rarely fires because `PassportApplicationTriggerHandler.applyDefaults()` force-sets `Payment_Status__c = 'Paid'` for any record at or beyond Granting before the validation rule even evaluates — the rule is a backstop, not the primary enforcement.
- **`Citizen_Required_On_Submit`**: would require `Citizen__c` to be populated once `Status__c` leaves Draft. **Ships inactive** — per PSK.md §9, it must only be activated after every existing application has been backfilled with a `Citizen__c` value, or historical Draft-created records become unsaveable.
- **`Diplomatic_Official_Requires_Approval`** technically belongs here too as a validation-rule gate (see §4.1) — it's what makes the approval process load-bearing rather than optional.

---

## 5. Page layouts — who sees what

Lightning Record Pages (`force-app/main/default/flexipages/`), one per object plus record-type variants for the application:

| Object | Record Page(s) |
|---|---|
| `Passport_Application__c` | `Passport_Application_Record_Page` (base), plus record-type variants `Passport_Application_Record_Page_Minor`, `Passport_Application_Record_Page_Reissue`, `Passport_Application_Record_Page_Diplomatic` |
| `Citizen__c` | `Citizen_Record_Page` |
| `PSK__c` | `PSK_Office_Record_Page` |
| `Slot__c` | `Slot_Record_Page` |
| `Passport__c` | `Passport_Record_Page` |
| `Print_Job__c` | `Print_Job_Record_Page` |
| `Dispatch__c` | `Dispatch_Record_Page` |
| `Police_Verification__c` | `Police_Verification_Record_Page` |

Plus app-level home pages: `App_Home` (Application Management Console), `PSK_Operations_Home` (PSK Operations Console), `Passport_Validator` (Validator app home), and `Fulfilment_Board` (a tab in PSK Operations Console).

**Dynamic Forms on the application record page** (PSK.md §4.5, unchanged this session): three conditional sections render only when relevant, rather than showing every field to every user regardless of applicability —

- **Guardian fields** (`Guardian_Name__c`, `Guardian_Consent__c`) show only when `Applied_For_Minor__c` is checked.
- **Previous-passport fields** (`Previous_Passport_No__c`, `Previous_Passport_Expiry__c`, `Reason_For_Reissue__c`) show only for the Re-issue record type.
- **`Clearance_Level__c`** shows only for Diplomatic/Official.

Note the caveat carried over from PSK.md §4.6: the `Passport_Application_Path` (the visual stage bar) is currently declared for the `Fresh` record type only — the other five record types (including Diplomatic_Official, which is the one with the extra approval stage) render no stage bar. This is a known gap, not new this session.

---

## 6. What's still manual (and what genuinely isn't)

The system is "auto once you act" — a click on Advance cascades its required side effects, but nothing advances a record's `Status__c` on its own, and no human judgment call is replaced by code. Concretely:

**Still manual, by design:**
- Clicking **Advance** at every single stage — there is no scheduled job or record-triggered flow that walks a record through the lifecycle unattended.
- **Verifying documents** — a `Document_Checklist_Item__c` being auto-*seeded* does not mean it's auto-*verified*; a `PSK_Document_Verification_Officer` has to actually inspect each one and click `Mark_Received` / `Mark_Verified`.
- **Conducting the police verification** — the `Police_Verification__c` record is auto-created and auto-routed to the right queue, but the field/records check itself, and the decision to mark it `Cleared` or `Adverse`, is entirely human. Notably, `advance()` force-clears the PV record when the application leaves Police Verification regardless of its current status — so an officer with an adverse finding must act (mark Adverse, reject the application) *before* anyone clicks Advance, not after.
- **Deciding the Diplomatic/Official grant approval** — approve or reject is a human call by the assigned Regional Passport Officer, routed via the `RPO_Approvals` queue; the system only handles the plumbing of submission, field updates, and routing the record back a stage on rejection.
- **Collecting payment and confirming delivery** — `Payment_Status__c` flips to Paid on the officer's Advance click, but the actual payment collection and the actual courier handoff/receipt confirmation (`Mark_Delivered`, `Received_By__c`) are real-world actions a person performs and then records.
- **Printing and QC** — `Print_Job__c` is auto-created in `Queued` status, but the physical print run, quality check, and `Mark_Printed` action are done by a person.

**Fully automatic, once the triggering click happens:**
- Queue reassignment on every stage that has one (`routeOwnership` — replaces manual assignment rules entirely).
- Document-checklist seeding on Draft→Submitted.
- Police Verification record creation (and its own queue assignment) on entering Police Verification.
- `Passport__c` + `Print_Job__c` creation on entering Printing; `Dispatch__c` creation on entering Dispatch — both idempotent, safe to re-trigger.
- Diplomatic/Official approval submission on entering Granting, and the field updates / status rollback that follow an approve or reject decision.
- Date stamps (`Submitted_Date__c`, `Stage_Entered_Date__c`, `Granted_Date__c`, `Payment_Date__c`) and the `Payment_Status__c = Paid` safety-net default for anything at or beyond Granting.
- The `Objection__c` audit-trail record created on a reasoned rejection.

The dividing line is consistent throughout: **anything that changes `Status__c` is a human decision; everything that has to happen as a *consequence* of that decision is automatic.**
