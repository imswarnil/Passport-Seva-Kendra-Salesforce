# n8n.md — Integration & Automation Roadmap

> Companion to [PSK.md](PSK.md). PSK.md's §9 "Not started" table flags **n8n / Twilio / AI integrations** as the highest-value unbuilt layer — `Notification_Log__c` exists with a `Provider_Message_Id__c` idempotency key and is empty of real sends. This document is the working catalog of what to build there, for whoever (author or collaborator) picks the project up next.

---

## 1. Why n8n here

Salesforce is the system of record and already does its own *internal* automation — triggers, the `Diplomatic_Official_Grant_Approval` approval process, queue routing via `PSK_Constants.APPLICATION_STAGE_QUEUE`, validation rules, sharing rules. None of that needs n8n and none of it should move there. n8n's job is everything **outside the org boundary**: sending SMS/WhatsApp, receiving payment-gateway and courier webhooks, talking to a (hypothetical) police-department system, running AI over documents, and firing scheduled outreach that has no natural Salesforce-side trigger. Think of n8n as the outbound/inbound integration layer bolted onto the org, not a replacement for anything Apex or Flow already owns.

---

## 2. Connection pattern

**Salesforce → n8n** (the org has something to say):
- **Platform Events** — cleanest for near-real-time, decoupled fan-out (e.g. a `Status_Change__e` event published from a trigger, consumed by an n8n CometD/Streaming API trigger node). Preferred for anything per-record and frequent.
- **Outbound Messages** (SOAP, from a Workflow Rule or Flow) — legacy but zero-code; fine for simple one-way "this fired, here's the record Id" pings.
- **Scheduled Apex / Scheduled Flow polling a REST endpoint** — for batch-shaped work (the SLA sweep, the renewal scan) where an n8n Cron trigger calls a Salesforce REST/Apex REST endpoint on a schedule and pulls a result set, rather than Salesforce pushing per-record. Simpler to reason about than events for anything already "select records matching X".

**n8n → Salesforce** (the workflow has something to write back):
- The **REST API** (`/services/data/vXX.0/sobjects/...` or the **Composite/sObject Collections** endpoints for bulk upserts) is the default. Every PSK object already carries `External_Id__c` (unique, external ID) specifically so n8n can `PATCH .../Notification_Log__c/External_Id__c/<key>` idempotently instead of query-then-insert.
- A **custom Apex REST endpoint** (`@RestResource`) is worth it only where the logic is nontrivial enough that doing it in Apex is safer than doing it in n8n Set/IF nodes — e.g. the SLA breach sweep's stage/Tatkal branching against `SLA_Config__mdt`.
- **Auth**: standard headless server-to-server pattern is a **Connected App with OAuth 2.0 JWT Bearer Flow** — n8n holds a private key, signs a JWT, exchanges it for an access token with no interactive login and no refresh-token expiry risk. Do not use username-password flow for a long-running integration.
- If Salesforce ever needs to call *into* n8n (e.g. trigger a webhook URL), store that URL and any shared secret in a **Named Credential** (+ External Credential for the auth parameter), never as a hardcoded string in Apex — see the `OpenAIChatController` hardcoded-key incident noted in CLAUDE.md as exactly the anti-pattern to avoid repeating.

Keep this section as the reference; don't re-derive the auth flow per automation below.

---

## 3. The automation catalog

Legend for **Priority**: High = build in the first wave (applicant-visible or operationally load-bearing, low integration complexity). Medium = clearly valuable, but either lower frequency or higher build cost. Low = nice-to-have / later.

### 3.1 Notifications (`Notification_Log__c`, Twilio)

Every automation in this section writes a `Notification_Log__c` row keyed by `Provider_Message_Id__c` (Twilio's message SID) so a Twilio delivery-status webhook retry can update the same row instead of duplicating it. `Notification_Log__c` fields available: `Channel__c`, `Message_Type__c`, `Message_Body__c`, `Recipient_Number__c`, `Status__c`, `Sent_Date__c`, `Provider_Message_Id__c`, `Passport_Application__c`, `External_Id__c`.

| Automation | Trigger | n8n steps | Salesforce touchpoint | Priority |
|---|---|---|---|---|
| **Status-change SMS/WhatsApp** | `Passport_Application__c.Status__c` changes (Platform Event published from a trigger, or polled every few minutes against `Stage_Entered_Date__c`) | Webhook/Streaming trigger → Switch on new `Status__c` → pick template (12 values in `PSK_Constants.ALL_STATUSES`) → Twilio Send SMS/WhatsApp node → write result back | Reads `Status__c`, `Mobile_For_Alerts__c`, `Notification_Consent__c` (must gate the send — do not message if false) on `Passport_Application__c`; writes `Notification_Log__c` (`Message_Type__c = 'Status Update'`) | **High** — the single most applicant-visible gap; the object model was built for exactly this |
| **Payment reminder** | Scheduled poll: applications with `Status__c = 'Payment Pending'` and `Stage_Entered_Date__c` older than N hours | Cron trigger → SOQL via REST → loop → Twilio send → log | Reads `Passport_Application__c.Payment_Status__c`/`Fee__c`; writes `Notification_Log__c` (`Message_Type__c = 'Payment Reminder'`) | **High** — stuck-in-payment is a common real-world drop-off point and directly recoverable revenue |
| **Appointment reminder** | Scheduled: day-before and morning-of `Slot__c.Slot_Date__c` for `Appointment__c.Status__c = 'Scheduled'` | Cron trigger (twice daily) → SOQL joining `Appointment__c` → `Slot__c` → `Passport_Application__c` → Twilio send → log | Reads `Appointment__c.Status__c`, `Slot__c.Slot_Date__c`/`Start_Time__c`/`PSK_Office__c`; writes `Notification_Log__c` (`Message_Type__c = 'Appointment Reminder'`) | **High** — no-shows are expensive (a booked `Slot__c.Booked_Count__c` slot going unused); reminders are cheap and directly reduce them |
| **Document rejection notice** | `Document_Checklist_Item__c.Status__c` → `'Rejected'` | Platform Event or poll on `Rejection_Reason__c` populated → template includes `Rejection_Reason__c` and resubmission instructions → Twilio/email send → log | Reads `Document_Checklist_Item__c.Document_Type__c`, `Rejection_Reason__c`; writes `Notification_Log__c` against the parent `Passport_Application__c` | **Medium** — valuable but lower volume than status-change; can piggyback on the general template engine once built |
| **Dispatch/delivery tracking updates** | Inbound courier webhook (hypothetical BlueDart/DTDC/India Post/Delhivery API — see `PSK_Constants.COURIER_PARTNERS`) | Webhook node receives carrier status → map to `Dispatch__c.Status__c` values (`PSK_Constants.DISPATCH_STATUSES`) → update `Dispatch__c` via REST → on `'Out for Delivery'`/`'Delivered'`/`'Returned'` also fire an applicant notification | Writes `Dispatch__c.Status__c`, `Tracking_Number__c`, `Delivered_Date__c`, `Delivery_Attempts__c`; writes `Notification_Log__c` | **Medium** — genuinely useful but depends on a real (or convincingly mocked) courier webhook contract, which is more integration surface than the others |

### 3.2 SLA / operations (`SLA_Config__mdt`)

`SLA_Config__mdt` has 26 rows: a normal and a `_Tatkal` variant for each of 13 processing stages. Ageing = now − `Passport_Application__c.Stage_Entered_Date__c`, compared per-record against the row matching current `Status__c` (and whether `Tatkal__c` is true).

| Automation | Trigger | n8n steps | Salesforce touchpoint | Priority |
|---|---|---|---|---|
| **SLA breach sweep** | Scheduled (e.g. hourly) | Cron → call a small Apex REST endpoint (`GET /pskSlaBreaches`) that does the stage/Tatkal branch lookup against `SLA_Config__mdt` server-side (this logic belongs in Apex, not n8n IF nodes — it's exactly the "SLA breach"-adjacent computation `PSK_HomeController` doesn't yet do) → for each breach, Slack/email the owning queue's supervisor (queue mapped via `PSK_Constants.APPLICATION_STAGE_QUEUE`) | Reads `Passport_Application__c.Status__c`, `Stage_Entered_Date__c`, `Tatkal__c`, `SLA_Config__mdt` | **High** — this is the whole point of having 26 SLA config rows sitting unused; directly measurable ops value |
| **Daily ops digest** | Scheduled, once daily (e.g. 8 AM) | Cron → call `PSK_HomeController.getHomeStats` (or a thin wrapper) for stage counts, `openRiskFlags`, `pendingPoliceVerifications`, plus the SLA breach count from above and Tatkal backlog (`tatkalCount`) → format → Slack/email to Passport Office Manager | Reads the same aggregates `pskHomeDashboard` already computes | **Medium** — cheap to build once the breach sweep exists (shares its query logic) and gives management a habit-forming daily touchpoint |

### 3.3 Renewal outreach (`Renewal__c`)

`Renewal__c` fields: `Passport_Application__c` (source), `Expiry_Date__c`, `Notification_Sent_Date__c`, `Follow_Up_Date__c`, `Outreach_Status__c` (`PSK_Constants.RENEWAL_OUTREACH_STATUSES`: Not Started, Notified, Responded, Converted, Ignored), `Converted_Application__c` (lookup to the new application it produces), `External_Id__c`.

| Automation | Trigger | n8n steps | Salesforce touchpoint | Priority |
|---|---|---|---|---|
| **Expiry-approaching scan & outreach** | Scheduled, e.g. monthly | Cron → SOQL for `Passport__c` where `Status__c = 'Active'` and `Date_of_Expiry__c` within N months → upsert `Renewal__c` (External_Id keyed on passport) → Twilio/WhatsApp outreach message → stamp `Notification_Sent_Date__c`, set `Outreach_Status__c = 'Notified'` | Reads `Passport__c.Date_of_Expiry__c`/`Status__c`; writes `Renewal__c` | **High** — proactive renewal is a classic high-ROI outreach pattern and the object was purpose-built for it |
| **Follow-up nudge on non-response** | Scheduled: `Renewal__c.Outreach_Status__c = 'Notified'` and `Follow_Up_Date__c` reached with no response | Cron → SOQL → second-touch message → update `Outreach_Status__c` | Reads/writes `Renewal__c` | **Low** — a second wave that only matters once the first wave is live and has real response data to act on |

### 3.4 Payments

| Automation | Trigger | n8n steps | Salesforce touchpoint | Priority |
|---|---|---|---|---|
| **Payment gateway webhook intake** | Inbound webhook from a UPI/card/net-banking provider | Webhook node → verify provider signature → map gateway status to `PSK_Constants.PAYMENT_RECORD_STATUSES` (`Initiated`/`Success`/`Failed`/`Refunded`) → create/update `Payment__c` via REST, `External_Id__c` = gateway transaction ref for idempotency | Writes `Payment__c.Amount__c`, `Payment_Reference__c`, `Gateway_Response__c`, `Status__c`, `Payment_Mode__c` (`PSK_Constants.PAYMENT_MODES`) | **High** — unblocks a real chunk of the lifecycle; note this is *only* the inbound webhook → `Payment__c` creation step. The rollup to `Passport_Application__c.Payment_Status__c` is (or should be) a Salesforce-side trigger once `Payment__c` exists — n8n does not own that rollup |

### 3.5 Police verification

`Police_Verification__c` fields: `PV_Type__c`, `Status__c` (`PSK_Constants.PV_STATUSES`: Not Initiated, Referred, In Progress, Cleared, Adverse), `Police_Station__c`, `Referred_Date__c`, `Report_Received_Date__c`, `Verifying_Officer__c`, `Remarks__c`, `Passport_Application__c` (lookup, not master-detail — it deliberately outlives the application, per PSK.md §2).

| Automation | Trigger | n8n steps | Salesforce touchpoint | Priority |
|---|---|---|---|---|
| **Referral packet push** | `Police_Verification__c` created (Platform Event or poll on `Status__c = 'Referred'`) | Trigger → assemble a structured payload (applicant snapshot from `Passport_Application__c`, `Police_Station__c`) → push to the (hypothetical) police-department portal/API | Reads `Police_Verification__c` + parent `Passport_Application__c` applicant fields | **Medium** — valuable to model but entirely speculative without a real external system; build the outbound half first, stub the inbound |
| **Report-back intake** | Inbound webhook (or scheduled poll of the hypothetical portal) | Webhook/poll → map external status to `Status__c` (`Cleared`/`Adverse`) → update `Police_Verification__c.Report_Received_Date__c`, `Remarks__c` | Writes `Police_Verification__c` | **Medium** — pairs with the above; without it the referral push is one-way and useless operationally |
| **PV SLA escalation** | Scheduled: `Status__c` in `('Referred','In Progress')` past the matching `SLA_Config__mdt` (Police Verification stage) threshold | Cron → call the same SLA-check endpoint as 3.2 → escalate to `Police_Verification_Team` queue supervisor via Slack/email | Reads `Police_Verification__c.Status__c`, `Referred_Date__c` | **Medium** — a specialization of the general SLA sweep; build after 3.2's endpoint exists so this is a thin extra branch, not new plumbing |

### 3.6 AI / document processing

**Hard constraint applies to every automation in this section**: PSK.md's PII rule is that the Aadhaar number is never stored — only `Aadhaar_Verified__c` (checkbox) and `Aadhaar_Token__c` (opaque token, currently plain text since Shield Platform Encryption is unavailable in Developer Edition). Any OCR/AI step that reads an Aadhaar document image must extract/compare only what's needed (name, DOB, address match) and must never write a full Aadhaar number into `Aadhaar_Token__c`, `Notes__c`, an n8n log, or an AI provider's request/response — not even transiently in a workflow variable that gets persisted in n8n's execution history. Treat "extract Aadhaar number" as an explicitly forbidden operation, not an oversight to avoid.

| Automation | Trigger | n8n steps | Salesforce touchpoint | Priority |
|---|---|---|---|---|
| **Document OCR + validation** | `Document_Checklist_Item__c.Status__c` → `'Received'` (document uploaded) | Trigger → fetch attached file → OCR/vision AI node extracts name/DOB/address (never Aadhaar number) → compare against the application's as-submitted snapshot (`First_Name__c`, `Last_Name__c`, `Date_of_Birth__c`, address fields — PSK.md §2.1's deliberate snapshot, exactly what this needs to check against) → on mismatch, create `Objection__c` (`Objection_Type__c = 'Document Discrepancy'` or `'Name Mismatch'`, per `PSK_Constants.OBJECTION_TYPES`); on clean match, set `Status__c = 'Verified'`, `Verified_Date__c` | Reads `Document_Checklist_Item__c` + parent snapshot fields; writes `Document_Checklist_Item__c.Status__c`/`Verified_Date__c` or creates `Objection__c` | **Medium** — high leverage but the highest build complexity in the catalog (file handling + AI + PII discipline); sequence after the simpler high-priority items are proven |
| **Address/photo quality pre-check** | Same upload trigger, before the full OCR match | Trigger → cheap vision-quality check (blur, glare, wrong document type) → if it fails, immediately notify applicant to resubmit rather than waiting for a human officer to catch it | Reads `Document_Checklist_Item__c`; may write `Rejection_Reason__c` on obvious failures, otherwise queues for officer review | **Low** — a quality gate ahead of the officer, valuable mainly at volume; not worth building before the OCR match step it precedes |
| **Risk-flag triage assist** | `Risk_Flag__c` created (`Status__c = 'Open'`) | Trigger → gather applicant history (prior applications by `Citizen__c`, past `Objection__c` and `Police_Verification__c` outcomes) → AI summarizes into a draft note → write into `Risk_Flag__c.Description__c` or a new note, explicitly labeled as a draft | Reads `Risk_Flag__c`, related `Passport_Application__c`/`Objection__c`/`Police_Verification__c` history; writes a summary field, never `Status__c` or `Severity__c` | **Low** — explicitly NOT auto-deciding risk; it drafts a summary for the human reviewer named in `Reviewed_By__c` to accept or discard. Build only once the higher-priority sends exist, and keep the human decision point real |

### 3.7 Approval process support (new this build)

The `Diplomatic_Official_Grant_Approval` approval process is auto-submitted by `PSK_ApplicationActionsController.submitForApproval()` the moment a Diplomatic/Official application enters `Granting` (see the class's `advance()` method) — there is no manual "click submit" step. The approver is currently the org admin, a placeholder pending real role-based routing.

| Automation | Trigger | n8n steps | Salesforce touchpoint | Priority |
|---|---|---|---|---|
| **Approval notification** | Approval request created (Platform Event on the ProcessInstance/ProcessInstanceWorkitem, or a scheduled poll) | Trigger → Slack/email/SMS to the approver with a deep link to the record (`https://<org>/lightning/r/Passport_Application__c/<Id>/view`) | Reads `Passport_Application__c.Approval_Status__c`, `RecordType.DeveloperName` | **Medium** — real gap today (nobody is pinged when this fires), but low volume since it only applies to the Diplomatic/Official record type |
| **Approval escalation** | Scheduled: `Approval_Status__c = 'Pending'` past N days | Cron → SOQL → escalate to the next role up (`Regional_Passport_Officer`'s manager, or `CEO_and_Admins`) | Reads `Approval_Status__c` (`PSK_Constants.APPROVAL_STATUSES`) | **Low** — a safety net for a low-volume, already-rare record type; build once the base notification proves the pattern |

### 3.8 Data hygiene / ops

| Automation | Trigger | n8n steps | Salesforce touchpoint | Priority |
|---|---|---|---|---|
| **Weekly duplicate-citizen sweep** | Scheduled, weekly | Cron → pull recent `Citizen__c` records → run near-miss matching (fuzzy name + DOB + mobile) beyond the exact-match `PSK_ApplicationService.citizenKey()` logic the trigger already applies at insert time → flag candidate pairs for manual merge (Slack digest or a lightweight `Objection__c`-style holding record) | Reads `Citizen__c`; does not write merges automatically | **Medium** — exact-match dedup already exists in Apex; this only adds value once real (non-demo) data volume exists to produce near-misses worth reviewing |
| **Storage/limits monitoring digest** | Scheduled, e.g. weekly | Cron → call `PSK_DemoDataGenerator.storageReportFromUI()` (or a small dedicated Apex REST wrapper, since that method is presently demo-data-scoped) → format → Slack/email to admin | Reads org storage stats via the existing report method | **Low** — genuinely convenient but purely operational housekeeping on a Developer Edition org with generous free limits; low urgency |

**Author's additions** — plausible and domain-appropriate, not requested verbatim in the brief:

| Automation | Trigger | n8n steps | Salesforce touchpoint | Priority |
|---|---|---|---|---|
| **Slot capacity rebalancing alert** | Scheduled or on `Slot__c.Booked_Count__c` update | Cron/poll → find `PSK__c` offices where upcoming slots are >90% booked (`Is_Available__c` roll-up) while sibling offices in the same region are under-booked → notify the office manager to open more capacity or suggest cross-office booking | Reads `Slot__c.Capacity__c`/`Booked_Count__c`/`Is_Available__c`, `PSK__c` | **Low** — useful once there are multiple real offices competing for the same applicant pool; low priority on a single-office demo org |
| **No-show follow-up** | `Appointment__c.Status__c = 'No Show'` | Trigger → automatic re-booking offer message (link to slot picker) instead of leaving the applicant to re-initiate | Reads/writes `Appointment__c.Status__c`; writes `Notification_Log__c` | **Medium** — directly recovers appointments that would otherwise silently stall the application at Document Verification/PV scheduling |
| **Print job QC failure alert** | `Print_Job__c` status moves to a reprint-triggering state (`PSK_Constants.PRINT_STATUSES` includes `'Reprint Required'`, reasons in `REPRINT_REASONS`) | Trigger → notify `Fulfilment_Team` queue owner immediately rather than waiting for the next manual check | Reads `Print_Job__c.Status__c`/reprint reason | **Low** — a small, cheap win once the fulfilment flow is otherwise instrumented; not worth its own build slot early |
| **Dispatch failure / return-to-sender handling** | `Dispatch__c.Status__c = 'Returned'` or `'Lost in Transit'` | Trigger → notify Fulfilment Team + trigger an applicant outreach asking for an address correction, tying into `Return_Reason__c` (`PSK_Constants.DISPATCH_RETURN_REASONS`) | Reads/writes `Dispatch__c`; writes `Notification_Log__c` | **Medium** — a returned passport booklet is a real operational failure mode worth automating a recovery path for, and reuses the same courier-webhook plumbing as 3.1's dispatch tracking automation |

---

## 4. Sequencing recommendation

If only five of the above get built, build these first — ranked for applicant-visible impact and low integration complexity, in build order:

1. **Status-change SMS/WhatsApp** (§3.1) — the object model (`Notification_Log__c`, `Provider_Message_Id__c`) was purpose-built for this; it's the most-referenced gap in PSK.md §9; and it establishes the template-engine + Twilio-send + idempotent-log pattern every later notification automation reuses.
2. **Payment gateway webhook intake** (§3.4) — unblocks the lifecycle at a real chokepoint (`Payment Pending` → `Paid`) and is a clean, self-contained webhook-in/`Payment__c`-out shape with no dependency on anything else in this doc.
3. **SLA breach sweep** (§3.2) — the 26-row `SLA_Config__mdt` is sitting unused; this is the highest-leverage *operational* (not applicant-facing) automation, and its Apex REST endpoint becomes shared infrastructure for the PV SLA escalation and daily digest later.
4. **Appointment reminder** (§3.1) — cheap to build once the Twilio-send pattern from #1 exists, and directly reduces costly no-shows against booked `Slot__c` capacity.
5. **Expiry-approaching renewal scan** (§3.3) — the only proactive (not reactive) automation in the top five; `Renewal__c` and `Converted_Application__c` exist solely for this and are otherwise dead schema.

Everything else in the catalog is real work worth doing, but these five cover the two biggest gaps (applicant communication, and using the SLA/renewal schema that already exists) with the least new integration surface.

---

## 5. What NOT to automate yet

- **Police verification outcomes** (`Police_Verification__c.Status__c` = Cleared/Adverse) stay a human decision. n8n may push the referral and ingest the report, but the Cleared/Adverse call is not something an AI or workflow should make — only relay what the external process reports.
- **Grant approvals** — the `Diplomatic_Official_Grant_Approval` process exists precisely so a Regional Passport Officer decides. n8n's role here is notification and escalation reminders (§3.7), never auto-approving or auto-rejecting.
- **Risk scoring / `Risk_Flag__c` disposition** — AI may draft a summary (§3.6) but must never set `Status__c`, `Severity__c`, or otherwise auto-triage a flag. `Reviewed_By__c` stays a real person.
- **Anything touching Aadhaar** — no automation may extract, store, log, or pass through a full Aadhaar number at any point, even transiently in an n8n execution log or an AI prompt/response. Only `Aadhaar_Verified__c` (boolean) and the existing `Aadhaar_Token__c` (opaque reference) are legitimate to touch, and only to read/confirm, not to derive from document text. This follows the same DPDP-minded discipline PSK.md already establishes for the schema — extending it to every integration is not optional.
- **Auto-deciding document mismatches beyond flagging** — the OCR step (§3.6) creates an `Objection__c` on mismatch; it does not resolve one. `Resolution_Notes__c`/`Resolved_Date__c` stay human-authored.
