# AUTOMATION.md — Triggers, Flows and Approvals

> What the system does without being asked. Schema in [DATA_MODEL.md](DATA_MODEL.md), the human side in [JOURNEYS.md](JOURNEYS.md).
>
> **The governing rule: configure before you code.** Apex is for what declarative tools genuinely cannot do — not for what you happen to find easier to write. Every entry below states which it is and why.

---

## 1. Choosing the tool

Work down this list and stop at the first row that fits.

| Need | Tool | Why not the one below it |
|---|---|---|
| Derive a value from fields on the same record, read-only | **Formula field** | Nothing to run, nothing to test, always correct |
| Aggregate children onto a parent | **Roll-up summary** | Free, and it cannot drift the way a maintained field can |
| Block a save | **Validation rule** | Runs before anything else writes; cheapest possible rejection |
| Default or transform a field on the record being saved | **Before-save record-triggered flow** | No extra DML — you mutate the record in flight |
| Create/update *related* records after a save | **After-save record-triggered flow** | The record has an Id by now |
| A human must say yes | **Approval process** | The only tool that genuinely blocks and records attribution |
| Route a `Case` to a team | **Assignment rule** | Standard `Case` machinery, no code |
| Time-based follow-up | **Scheduled path** or **Scheduled Apex** | Flow first; Apex only for volume |
| Bulk logic across many records, complex branching, or reuse from several entry points | **Apex trigger → handler → service** | Everything above has hit its ceiling |
| Callouts, or anything that must not run in the transaction | **Queueable / Batch Apex** | Callouts are illegal in a trigger context |

**Where this build lands:** roughly 60% declarative, 40% Apex. The Apex is concentrated in three places — record minting, fee/SLA lookup, and ownership routing — because all three need bulk safety and are called from more than one entry point.

---

## 2. Order of execution

Not optional knowledge. Almost every "why did my value get overwritten" bug is a misunderstanding of this list.

```
 1.  Record loaded from the database (or initialised for an insert)
 2.  New field values from the request overwrite old ones
 3.  ─▶ BEFORE-SAVE record-triggered flows
 4.  ─▶ before triggers (Apex)
 5.      System validation: required fields, field types, max lengths
 6.  ─▶ Validation rules
 7.  ─▶ Duplicate rules
 8.      Record saved to the database — but NOT committed. The Id now exists.
 9.  ─▶ after triggers (Apex)
10.  ─▶ Assignment rules
11.      Auto-response rules
12.      Workflow rules (legacy)
13.      Escalation rules
14.  ─▶ AFTER-SAVE record-triggered flows
15.      Entitlement processes
16.      Roll-up summary fields recalculated on the parent  ◀── parent may re-run its own triggers
17.      Criteria-based sharing recalculated
18.      COMMIT — DML committed, post-commit logic (email, async) fires
```

**The four consequences that shape this build:**

1. **Validation rules (6) run after before-triggers (4).** So a before-trigger that populates `Region__c` runs *before* any rule could complain it was blank. Ordering is a feature.
2. **Roll-ups recalculate at 16, after both flow passes.** So `Checklist_Items_Verified__c` is **not** reliably current inside a flow on the checklist item itself. Logic that depends on the roll-up must live on the *parent's* update, not the child's. This is the single most common bug in checklist-style designs.
3. **After-save flows (14) run after after-triggers (9).** Where both touch the same field, Apex writes first and Flow wins. We avoid the collision entirely by never letting both own the same field.
4. **Sharing recalculates at 17, after everything.** So `Region__c` must be *stored* — a criteria-based sharing rule cannot read a formula, and cannot traverse a lookup. That platform constraint is why the field exists at all.

---

## 3. Trigger contexts — all seven, with real use cases

One trigger per object, containing no logic, dispatching to a handler class. The point of the table is that **each context exists because it can do something the others cannot.**

| Context | Record has an Id? | Can you mutate `Trigger.new` without DML? | Its unique power | Used in PSK for |
|---|---|---|---|---|
| `before insert` | ✗ | ✓ | Set fields free of charge | Default `Status__c`, stamp `Stage_Entered_Date__c`, build `External_Id__c` |
| `before update` | ✓ | ✓ | Compare `old` vs `new` and mutate in flight | Re-stamp `Stage_Entered_Date__c` on status change; copy `Region__c` from the office; write `Fee__c` on submit |
| `before delete` | ✓ | n/a | Veto a delete with `addError()` | Block deleting an application past `Submitted`; block deleting any `Police_Verification__c` |
| `after insert` | ✓ | ✗ | Create children — the Id exists now | Mint checklist rows; create `Police_Verification__c`; set queue ownership |
| `after update` | ✓ | ✗ | React to a *transition* | Mint `Passport__c` and `Dispatch__c`; route ownership to queues; submit for approval |
| `after delete` | ✓ | n/a | Clean up or audit what just went | Log an application deletion for the auditor |
| `after undelete` | ✓ | ✗ | Repair state after a restore from the Recycle Bin | Re-point ownership to the right queue for the restored record's status |

### 3.1 `Passport_Application__c` — the trigger that does the most

```apex
trigger PassportApplicationTrigger on Passport_Application__c (
    before insert, before update, before delete,
    after insert, after update, after undelete
) {
    PassportApplicationTriggerHandler.run();   // one line. all logic lives in the handler.
}
```

| Context | What it does | Why this context |
|---|---|---|
| **before insert** | Default `Status__c = Draft`; stamp `Stage_Entered_Date__c`; generate `External_Id__c` | Free field-setting. Doing it after insert would cost a second DML on every record. |
| **before update** | If `Status__c` changed → re-stamp `Stage_Entered_Date__c`. If leaving Draft → look up `Fee_Matrix__mdt` and write `Fee__c`, stamp `Submitted_Date__c`. If `PSK_Office__c` changed → copy `Region__c` across. | All of it mutates *this* record. `Trigger.oldMap` is the only way to know a *transition* happened rather than a value merely being present. |
| **before delete** | `addError()` if `Status__c != 'Draft'` | The only place a delete can be refused. |
| **after insert** | Set `OwnerId` to the right queue | Needs the Id. |
| **after update** | The stage machine — see §3.2 | Needs the Id and needs to create *other* records. |
| **after undelete** | Re-route ownership for the restored status | A restored record keeps its old owner, which may be a user who has since left. |

### 3.2 The stage machine — what gets created on which transition

This is the answer to "how do we get triggers which create records on an event". Each row fires **once**, on the transition into that status, and each is **idempotent** — it queries for an existing child before creating one, so a re-save never mints a duplicate.

| Transition into | Creates | Also does | Idempotency guard |
|---|---|---|---|
| `Submitted` | `Document_Checklist_Item__c` × N, from a per-record-type template | Writes `Fee__c`, stamps `Submitted_Date__c` | Skip if any checklist row already exists |
| `Document Verification` | — | `OwnerId` → `Document_Verification` queue | Owner already the queue |
| `Police Verification` | `Police_Verification__c` × 1 | `OwnerId` → `Police_Verification` queue; `PV_Type__c` from record type | Skip if a PV record exists |
| `Granting` | — | `OwnerId` → `Granting` queue; **if Diplomatic/Official, submit for approval** and set `Approval_Status__c = Pending` | Skip submission if already Pending or Approved |
| `Printing` | `Passport__c` × 1 | Stamps `Granted_Date__c`; sets issue/expiry dates | Skip if a passport exists |
| `Dispatch` | `Dispatch__c` × 1 | `OwnerId` → `Printing_And_Dispatch` queue | Skip if a dispatch exists |
| `Delivered` | — | Stamps `Delivered_Date__c` on the dispatch | — |
| `Rejected` / `Cancelled` | — | Closes any open `Case` linked to the application | — |

> **Why idempotency is non-negotiable.** An after-update trigger can re-fire for reasons you did not cause: a roll-up recalculating on the parent, a workflow field update, a user pressing Save twice, a bulk data load re-touching records. "Create a child on transition" without a guard produces duplicate passports — and a duplicate passport is not a bug report, it is a legal problem. Every create in the table above is `SELECT ... WHERE Application__c IN :ids` first, `INSERT` second.

### 3.3 Triggers on the other objects

| Object | Contexts | What |
|---|---|---|
| `Document_Checklist_Item__c` | before update | Stamp `Received_Date__c` / `Verified_Date__c` / `Objection_Raised_Date__c` when `Status__c` changes into the matching value |
| `Police_Verification__c` | after insert | Own to the `Police_Verification` queue |
| | after update | On Cleared → advance the parent application. On Adverse → halt the parent and stamp the reason |
| `Passport__c` | before insert | Generate the booklet number; compute `Date_of_Expiry__c` from issue date + validity |
| | before delete | `addError()` — a booklet record is never deleted, only cancelled |
| `Dispatch__c` | before update | On `QC_Passed__c` false → set the reprint reason and roll status back to Printing. On delivery → advance the parent to Delivered |
| `Case` | before insert | Default record type by origin; link `Citizen__c` from the application if one is referenced |
| | after update | On a `Detail_Change` Case closing → verify a `Spawned_Application__c` exists |

### 3.4 The handler pattern, and why

```
PassportApplicationTrigger          ← one trigger per object, zero logic
        │
        ▼
PassportApplicationTriggerHandler   ← dispatches by context; owns the recursion guard
        │
        ▼
PSK_ApplicationService              ← the actual work; bulk-safe; callable from Flow, tests,
                                      Queueables and the trigger alike
        │
        ├── PSK_FeeService           ← Fee_Matrix__mdt lookup
        ├── PSK_SlaService           ← SLA_Config__mdt lookup
        └── PSK_RoutingService       ← queue ownership
```

**Four reasons this shape and not logic-in-the-trigger:**

1. **Testability.** You can call `PSK_ApplicationService.advance(records)` directly and assert on the result. You cannot unit-test a trigger body.
2. **Ordering.** With logic in one trigger you control the sequence explicitly. With logic in several triggers on the same object, execution order is *undefined* — the platform makes no promise.
3. **Reuse.** The same service is called by the trigger, by an `@InvocableMethod` from Flow, by the LWC controller behind the **Advance** button, and by the demo data generator. One implementation, four callers.
4. **Recursion control.** `PSK_AutomationControl` is a static kill switch. A trigger that updates a parent whose roll-up updates the child would otherwise loop. The guard also lets a bulk data load suppress automation deliberately.

**Bulkification is not optional.** Every method takes a `List`, every SOQL is `WHERE Id IN :ids`, and there is no DML inside a loop anywhere. A trigger that works on one record and dies on two hundred is a trigger that works in your test and fails on the data load.

---

## 4. Flows

Where declarative beats code.

| Flow | Type | Object | Does |
|---|---|---|---|
| `Application - Before Save - Normalise` | Record-triggered, **before save** | `Passport_Application__c` | Upper-cases the pincode, trims names, defaults `Country__c` |
| `Application - After Save - Notify Consent` | Record-triggered, after save | `Passport_Application__c` | On status change with `Notification_Consent__c` true, publishes the notification platform event |
| `New Application Intake` | **Screen flow** | — | The guided counter wizard: citizen → declaration → address → record type. Creates the application at the end so a half-abandoned wizard leaves no orphan record |
| `Case - After Save - Spawn Application` | Record-triggered, after save | `Case` | On a `Detail_Change` Case being accepted, creates the Re-Issue application and back-links `Spawned_Application__c` |
| `SLA Warning` | **Scheduled path** on the application | `Passport_Application__c` | Fires at 80% of the stage's SLA target and alerts the owner |
| `Send Notification` | **Subflow**, autolaunched | — | Reused by every flow that needs to tell an applicant something. One implementation of the consent check |

> **Why the intake wizard is a Screen Flow and not just the record page.** A page layout lets you enter fields in any order and submit whatever you like. The counter conversation has a natural order — who are you, where do you live, what are you applying for — and enforcing it conversationally catches a missing document while the applicant is still standing there. That is a UX argument, not a technical one, and it is the right reason to choose a Screen Flow.

---

## 5. Approval process

One approval, and it is the only hard human gate in the system.

**`Diplomatic_Official_Grant_Approval`** on `Passport_Application__c`

| Setting | Value |
|---|---|
| Entry criteria | `Passport_Category__c ∈ {Diplomatic, Official}` **and** `Status__c = Granting` |
| Submitted by | `PSK_ApplicationService`, automatically, on the transition into Granting — not by a person remembering |
| Approver | The `RPO_Approvals` **queue** (members: `Regional_Passport_Officer` role and subordinates, plus admin as fallback) |
| Record is locked | Yes, while pending |
| On submit | `Approval_Status__c = Pending` |
| On approve | `Approval_Status__c = Approved`; record unlocked |
| On reject | `Approval_Status__c = Rejected`; `Status__c` back to Granting with the rejection comment |
| Enforced by | `Diplomatic_Official_Requires_Approval` — blocks the move to Printing unless Approved |

**Why a queue and not a named user as approver:** a named approver is a single point of failure — one person's leave stops every diplomatic passport in the region. A queue routes to a *role and its subordinates*, so cover is structural.

**Why an approval process rather than a validation rule:** a validation rule can block, but it cannot *record who decided*. The requirement is an attributable, auditable sign-off with a timestamp and a comment — which is exactly and only what an approval process produces.

---

## 6. Asynchronous Apex

Three uses, one per pattern, so each async flavour is taught by something real.

| Class | Type | Why this flavour |
|---|---|---|
| `PSK_NotificationQueueable` | **Queueable** | Callouts cannot happen in a trigger. Enqueued from the after-update trigger, runs after commit, chainable if the send fails and needs a retry |
| `PSK_SlaBreachBatch` | **Batch** | Sweeps every open application nightly comparing `Stage_Entered_Date__c` against `SLA_Config__mdt`. Batch because the record count can exceed a single transaction's limits |
| `PSK_NightlyScheduler` | **Scheduled** | Cron entry point that starts the batch. Scheduling and doing are separate classes so the batch stays independently testable |

`@future` is deliberately **not** used. It cannot be chained, cannot be monitored, takes only primitive arguments, and Queueable does everything it does better. Knowing *why not to use it* is the lesson.

---

## 7. Automation by object — the summary

| Object | Formula | Roll-up | Validation | Flow | Trigger | Approval |
|---|---|---|---|---|---|---|
| `Passport_Application__c` | 3 | 3 | 6 | 3 | 6 contexts | 1 |
| `Citizen__c` | 1 | — | 2 | — | — | — |
| `Document_Checklist_Item__c` | — | — | 2 | — | before update | — |
| `Police_Verification__c` | — | — | 2 | — | after ins/upd | — |
| `Passport__c` | 6 | — | 2 | — | before ins/del | — |
| `Dispatch__c` | 3 | — | 3 | — | before update | — |
| `PSK__c` | — | — | 1 | — | — | — |
| `Case` | — | — | 2 | 1 | before ins, after upd | — |

---

## 8. Anti-patterns this build refuses

Named so they can be recognised, because each one is a real thing found in real orgs.

| Anti-pattern | Why it's wrong | What we do |
|---|---|---|
| SOQL or DML inside a loop | Hits governor limits at ~100 records; passes every single-record test | Query once into a `Map`, collect into a `List`, one DML at the end |
| More than one trigger per object | Execution order between them is undefined by the platform | One trigger, one handler |
| Logic in the trigger body | Untestable in isolation, unreusable | Handler dispatches, service does the work |
| Hard-coded picklist strings in Apex | Renaming a value silently breaks code that still compiles | `PSK_Constants` |
| Hard-coded record type or queue Ids | Ids differ per org; the deploy compiles and then fails at runtime | Query by developer name, cached |
| Creating a child without checking it exists | Duplicate passports on a re-fire | Query first, insert second |
| A checkbox someone must remember to tick | It will be wrong, and nobody will know when | A roll-up summary, which cannot be |
| Cross-object formula onto the declaration fields | Rewrites history when a citizen corrects a spelling | Snapshot the declaration; derive only facts |
| Trigger with no recursion guard | Parent updates child updates parent, forever | `PSK_AutomationControl` |
| A validation rule that fires in Draft | Users cannot save a half-finished form and give up on the system | Every rule gated on `Status__c ≠ Draft` |
