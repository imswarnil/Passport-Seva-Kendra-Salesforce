# JOURNEYS.md — Personas and User Journeys

> Who touches what, in what order, and what each action does to the data. Schema in [DATA_MODEL.md](DATA_MODEL.md); who is *allowed* to do each of these in [ACCESS_MATRIX.md](ACCESS_MATRIX.md); what the system does automatically in [AUTOMATION.md](AUTOMATION.md).

---

## 1. The cast

Eight personas. One of them never logs in — and that is the most important one to keep in view.

| # | Persona | Example | App | Owns |
|---|---|---|---|---|
| 0 | **Applicant** | Ramesh Iyer, 34 | *none — no login* | nothing; everything is done for him at a counter |
| 1 | **Front Office Officer** | Priya Deshmukh, 27 | 1 | `Citizen__c`, `Passport_Application__c` in Draft/Submitted |
| 2 | **Document Verification Officer** | Anjali Nair, 31 | 1 | `Document_Checklist_Item__c` |
| 3 | **Help Desk Agent** | Kavya Menon, 25 | 2 | `Case` |
| 4 | **Police Verification Officer** | HC Suresh Patil, 42 | 3 | `Police_Verification__c` |
| 5 | **Granting Officer** | Vikram Rao, 45 | 4 | `Passport__c` |
| 6 | **Fulfilment Officer** | Farhan Sheikh, 29 | 4 | `Dispatch__c` |
| 7 | **Regional Passport Officer** | Meenal Kulkarni, 51 | all | approvals, escalations, oversight |
| 8 | **Audit & Compliance Officer** | Deepak Bhosle, 38 | all, read-only | nothing — that's the point |

> **Personas are permission sets, not profiles.** One human can be several. A small office might have one person holding both the Front Office and Help Desk sets — which is why they are composed with **permission set groups** rather than baked into profiles. A profile is a job description you can only have one of; a permission set is a hat.

---

## 2. Persona 0 — The Applicant

**Ramesh Iyer, 34. First-time Tatkal applicant, has an international flight in three weeks.**

Ramesh has no Salesforce login and never will — see [SOLUTION.md §3.3](SOLUTION.md). This persona exists to keep the staff-side design honest: **every field, queue and SLA in the system exists because it changes what happens to Ramesh.**

**What he wants:** a passport before his flight; to know at any moment where his file actually is; not to re-explain his situation to a different officer each visit; and to trust that his identity documents aren't being photocopied around carelessly.

**What used to go wrong:** a physical file that could be "with verification", "with the SP office", or genuinely lost, with nobody at the counter able to say which. Finding out about a missing document only on his *next* visit. Weeks of silence during police verification. A name mismatch surfacing at the granting desk, days after submission.

**What the design does for him, without him seeing any of it:**

| His experience | The mechanism |
|---|---|
| Every officer tells him the same status | One `Status__c` picklist on one record — not a guess per desk |
| He is told what's missing *before* he leaves | The checklist is generated on submit, so the gap is visible immediately |
| His Tatkal urgency is honoured | `Tatkal__c` selects the Tatkal SLA row and shares the file to managers |
| His file doesn't sit in a drawer | Ownership moves to a **queue**, and a queue has a depth you can measure |
| His documents aren't over-collected | No Aadhaar number is stored anywhere — only a verified flag and an opaque token |
| He can phone and ask | App 2: a `Case` with his ARN, answered from the same record |

**Success:** one consistent answer whoever he asks, a Tatkal turnaround that holds, and a booklet at the address he gave — without ever needing to memorise an ARN.

---

## 3. The main line — Draft to Delivered

The full journey of one application across all four apps. Each row is a real user action; **⚙︎** marks what the system does on its own.

| # | Stage | Who | App | Action | Records touched |
|---|---|---|---|---|---|
| 1 | — | Front Office | 1 | Search for the citizen by mobile + DOB | `Citizen__c` read |
| 2 | — | Front Office | 1 | Create the citizen if new | `Citizen__c` **insert** — duplicate rule blocks a second record for the same person |
| 3 | Draft | Front Office | 1 | New Application from the citizen record; pick record type | `Passport_Application__c` **insert**, `Status__c = Draft` |
| 4 | Draft | Front Office | 1 | Fill the form over several minutes; save partway | Saves clean — every rule is gated on `Status__c ≠ Draft` |
| 5 | Draft | Front Office | 1 | For a minor: set `Guardian__c` and tick consent | Second lookup to `Citizen__c` |
| 6 | **Submitted** | Front Office | 1 | Press **Submit** | ⚙︎ `Fee__c` written from `Fee_Matrix__mdt`; `Submitted_Date__c` stamped; `Region__c` copied from the office |
| 7 | Submitted | — | — | ⚙︎ | `Document_Checklist_Item__c` **rows generated** from the record-type template |
| 8 | Submitted | Front Office | 1 | Collect the fee, record the reference | `Payment_Status__c = Paid` + 3 fields |
| 9 | **Doc Verification** | — | — | ⚙︎ | Owner reassigned to the `Document_Verification` **queue**; `Stage_Entered_Date__c` re-stamped |
| 10 | Doc Verification | Doc Verification | 1 | Claim the file from the queue | Owner: queue → user |
| 11 | Doc Verification | Doc Verification | 1 | **Mark Received** on each document as it arrives | `Document_Checklist_Item__c` update |
| 12 | Doc Verification | Doc Verification | 1 | **Mark Verified** after checking against the declaration | ⚙︎ `Checklist_Items_Verified__c` roll-up increments |
| 13 | Doc Verification | Doc Verification | 1 | *If something's wrong:* **Raise Objection** on that item | `Open_Objections__c` roll-up > 0 → **advance is blocked** |
| 14 | **Police Verification** | Doc Verification | 1 | Advance once all items are verified | ⚙︎ `Police_Verification__c` **created**, owned by the `Police_Verification` queue |
| 15 | Police Verification | Police Verification | 3 | Claim from the queue, do the field visit | Owner: queue → user |
| 16 | Police Verification | Police Verification | 3 | **Mark Cleared** *or* **Mark Adverse** + reason + severity | Cleared advances; Adverse halts and escalates by sharing rule |
| 17 | **Granting** | Granting Officer | 4 | Open the file shared to him by criteria | `Cannot_Grant_With_Pending_Payment` and `Cannot_Grant_Without_Clearances` are hard stops |
| 18 | Granting | — | — | ⚙︎ *Diplomatic/Official only* | Auto-submitted to the `Diplomatic_Official_Grant_Approval` process → `RPO_Approvals` queue |
| 19 | Granting | RPO | 4 | Approve or reject the sensitive grant | `Approval_Status__c` — blocks Printing until Approved |
| 20 | Granting | Granting Officer | 4 | **Grant** | ⚙︎ `Passport__c` **minted**, nearly all fields by formula; `Granted_Date__c` stamped |
| 21 | **Printing** | — | — | ⚙︎ | `Dispatch__c` **created**; owner → `Printing_And_Dispatch` queue |
| 22 | Printing | Fulfilment | 4 | Log the print batch; **Mark Printed** | `Print_Batch__c`, `Printed_Date__c` |
| 23 | Printing | Fulfilment | 4 | QC-validate the booklet | `QC_Passed__c` — a fail sets `Reprint_Reason__c` and loops back to 22 |
| 24 | **Dispatch** | Fulfilment | 4 | Book the courier | `Courier_Partner__c`, `Tracking_Number__c`; address is a **formula**, never retyped |
| 25 | **Delivered** | Fulfilment | 4 | **Mark Delivered** on courier confirmation | `Received_By__c`, `Transit_Days__c` computed |
| 26 | Delivered | — | — | ⚙︎ | `No_Backward_Move_Once_Delivered` makes the record terminal |
| 27 | any | Audit | — | Reconstruct the whole timeline afterwards | Read-only + field history |

### The same thing as a picture

```
 FRONT OFFICE          DOC VERIFICATION       POLICE VERIF.      GRANTING        FULFILMENT
 ───────────           ────────────────       ─────────────      ────────        ──────────
 Citizen ──▶ Draft ──▶ Submitted ──▶ Doc Verif ──▶ Police Verif ──▶ Granting ──▶ Printing ──▶ Dispatch ──▶ Delivered
                │           │            │              │              │            │            │
                │           │            │              │              │            │            │
             validation   ⚙︎ fee       ⚙︎ owner →     ⚙︎ PV record   ⚙︎ approval  ⚙︎ Dispatch   QC fail
             gated on     ⚙︎ checklist   queue          created       (Dip/Off)    created      ↺ reprint
             leaving        rows                          │              │
             Draft                                   ✗ Adverse      ✗ unpaid /
                                                      halts +        unverified
                                                      escalates      blocked

 ── App 1 ──────────────────────────────┤├── App 3 ──┤├──────── App 4 ─────────────────────────
```

---

## 4. Persona journeys in detail

### 4.1 Front Office Officer — Priya

**Her day:** opens **App 1**, works the `Citizen__c` tab first. Finds or creates the identity, presses **Verify KYC** once documents are sight-checked, then **New Application** from the citizen record so the lookup is pre-filled. She picks the record type up front — and from that moment every picklist on the form is narrowed to valid values for that type, which is why she cannot accidentally give a Minor a 10-year booklet.

She fills Groups B–D over several minutes while the applicant finds documents in a folder. It saves half-finished, every time, because **every validation rule on this object is gated on `Status__c ≠ Draft`**. That single convention is the difference between a form people can use and one they fight.

On **Submit**, three things happen without her: the fee appears, the checklist appears, and the file leaves her hands for a queue. She tells the applicant exactly which documents to bring, reading off a list the system generated rather than one she remembered.

**Cannot:** select the Diplomatic/Official record type; delete an application; grant, verify, print or despatch anything; see `Police_Verification__c` at all.

**Her failure mode the design prevents:** submitting an application that is missing a core field, and finding out three desks later.

### 4.2 Document Verification Officer — Anjali

**Her day:** works a **list view** over the `Document_Verification` queue, not an inbox. She claims a file, then works its checklist rows — **Mark Received** as physical documents arrive, **Mark Verified** once each is checked against the declaration on the parent application.

When something is wrong she raises an objection **on the specific checklist item**, not on the application in general. The difference matters: "your file has a problem" is not actionable; "your address proof shows a different pincode than you declared" is. The roll-up `Open_Objections__c` on the parent then blocks advancement automatically — she does not have to remember to hold the file back.

**Cannot:** create or edit an application (read-only — she checks the declaration, she doesn't author it); touch police verification, granting, or fulfilment; edit `Aadhaar_Token__c`.

### 4.3 Help Desk Agent — Kavya (App 2)

**Her day:** every inbound question, on the phone or by email. She logs a `Case`, and the record type she picks decides everything downstream:

| Someone asks | Record type | What she does |
|---|---|---|
| "Where is my application?" | `Status_Enquiry` | Looks up the ARN, reads the status, closes the Case. No records created. |
| "I got married, I need my name changed" | `Detail_Change` | **Spawns a Re-Issue application** from the Case; `Spawned_Application__c` links them so the request and its outcome stay joined |
| "How do I get a visa for Germany?" | `Visa_Enquiry` | Answers from a canned response and closes. *This is why there is no `Visa_Application__c` object — the demand was information, not a workflow.* |
| "My booklet arrived damaged" | `Complaint` | Escalates; may spawn a re-issue or a fresh dispatch |

Cases she can't resolve **escalate on a timer** rather than on someone remembering. This is the one place in the build that uses assignment rules, escalation rules and Email-to-Case — standard `Case` machinery that a custom object would not have.

**Cannot:** verify documents, grant, or despatch. She can read an application and create one only through the Case-spawn action.

### 4.4 Police Verification Officer — Suresh (App 3)

**His day is half off-screen.** He pulls the day's verifications from the `Police_Verification` queue, batches them by neighbourhood, and leaves. The actual work — visiting the declared address, talking to neighbours — happens on a doorstep. Only the outcome comes back into Salesforce.

Because `Passport_Category__c` and `Tatkal__c` are visible to him, he knows before leaving the desk which files are urgent. On return: **Mark Cleared**, or **Mark Adverse** with a reason and a severity.

An **Adverse** outcome does three things at once: halts the application, shares it to `PSK_Managers` by criteria-based sharing rule, and becomes a permanent record that outlives the application — which is exactly why `Police_Verification__c` is a **lookup and not a master-detail**. A cascade delete must never be able to erase a police finding.

**Cannot:** create applications; see fulfilment or payment; edit the Aadhaar token.

### 4.5 Granting Officer — Vikram (App 4)

**His day:** files arrive in his view automatically — a criteria-based sharing rule grants Edit the moment `Status__c` hits Granting, so no one reassigns anything to him.

He is the persona the system argues with most, deliberately. Two validation rules are hard stops he cannot talk his way past: no granting with payment outstanding, and no granting without every checklist item verified and PV cleared where required. In the paper world both of those were discovered *after* the fact.

For a Diplomatic or Official file, pressing Grant does not grant. It **submits for approval** to the `RPO_Approvals` queue, and the file cannot reach Printing until `Approval_Status__c = Approved`. He is not the last word on a sensitive passport, and the system makes that structural rather than cultural.

On a clean grant he mints the `Passport__c` — the only persona who can. He retypes nothing: holder name, booklet pages, validity, ECR status and category are all **formulas** off the application.

**Cannot:** edit the applicant's declaration; create a second booklet for an application; print or despatch; delete anything.

### 4.6 Fulfilment Officer — Farhan (App 4)

**His day:** one `Dispatch__c` record per booklet, carrying four milestones — print, QC, despatch, deliver. A QC failure sets a reprint reason and loops back to print on the *same* record, so "why did this take two attempts" is answerable months later from field history.

He never types a delivery address: `Delivery_Address__c` is a formula over the application. The single most common real-world fulfilment error — a transcription slip between file and courier label — is made structurally impossible.

**Cannot:** create a `Passport__c`; edit the application beyond its status; see citizens, checklists, verifications or payments. Fulfilment is a lane, and it is a narrow one.

### 4.7 Regional Passport Officer — Meenal

**Her day starts on a dashboard,** not a record: stage counts, SLA breaches, queue depth. Then she works whatever the sharing rules pushed at her. Five rules route to her automatically — Tatkal files, Diplomatic/Official files, blacklisted citizens, adverse verifications, and high-risk scores. **She never has to be told to escalate; escalation is a query.**

She is the assigned approver on `Diplomatic_Official_Grant_Approval`, which is the only human gate in the system that blocks a record from moving.

Her permission set is the broadest — full CRUD across every object plus `viewAllRecords` where oversight requires it — but deliberately **not `modifyAllRecords`**. She can see everything in her office; she cannot silently overwrite outside the sharing model. That distinction is one of the sharper security lessons in the build.

### 4.8 Audit & Compliance Officer — Deepak

**Read-only on every object, `viewAllRecords` on the ones that matter.** No create, no edit, no delete — not even to fix an obvious typo. Compliance review and data correction are structurally separated, because a trail written by the people being audited is not a trail.

He reconstructs what happened from field history on the application, checks that PII discipline held (was the Aadhaar token ever populated with something re-identifiable?), and confirms that sensitive paths took the route they were meant to — that every Diplomatic grant carries a real approval, that every adverse verification was actioned.

His visibility is not gated by queue membership or sharing criteria, which makes him the only persona who sees the *whole* picture. That asymmetry is the design.

---

## 5. Alternate journeys

The main line is the boring case. These are the ones worth testing.

| Journey | Trigger | What happens | Ends |
|---|---|---|---|
| **Objection and recovery** | A document fails verification | Checklist item → Objection Raised; roll-up blocks advance; applicant is told exactly what to bring; item → Verified on return | Rejoins the main line at step 14 |
| **Adverse verification** | Police report is adverse | Application halts; shared to managers; RPO decides | `Rejected`, or manual override with a documented reason |
| **Diplomatic approval** | Category is Diplomatic/Official and the file enters Granting | Auto-submitted for approval; blocked from Printing | Approved → main line; Rejected → back to Granting |
| **QC failure and reprint** | `QC_Passed__c` is false | `Reprint_Reason__c` set, back to print on the same record | Rejoins at step 24 |
| **Tatkal under SLA pressure** | `Tatkal__c` is true | Tatkal SLA rows apply throughout; shared to managers from submission | Delivered — or a breach visible on the dashboard |
| **Name change via Support** | Citizen calls after marriage | `Detail_Change` Case → spawns a Re-Issue application → the Case closes when the new application is Delivered | Two linked records telling one story |
| **Blacklisted citizen** | `Is_Blacklisted__c` on the citizen | Citizen shared to managers; new applications flagged at intake | RPO decision |
| **Minor application** | `Is_Minor__c` is true | Guardian lookup + consent required on submit; Dynamic Forms reveals the fields; record type forces 36 pages / 5 years / No PV | Main line, skipping App 3 |
| **Abandoned draft** | Applicant never returns | Stays in `Draft` indefinitely — valid, saveable, incomplete | Cancelled by a sweep, or resumed |

---

## 6. Where the handoffs actually happen

Every stage boundary is one of three mechanisms, and knowing which is which is the point:

| Handoff | Mechanism | Why this one |
|---|---|---|
| Front Office → Doc Verification | **Queue ownership change** | The work needs to sit somewhere claimable by a team, not assigned to a person who might be on leave |
| Doc Verification → Police Verification | **New record + queue** | A different object with a different lifecycle and its own sharing — not a status change |
| Police Verification → Granting | **Criteria-based sharing rule** | Nobody reassigns anything; the file appears in the granting officer's view because it *matches criteria* |
| Granting → RPO | **Approval process** | The only handoff that needs a named human to say yes, recorded and attributable |
| Granting → Fulfilment | **New record + criteria sharing** | `Dispatch__c` is created; the fulfilment role gains access by status |
| Any → Manager | **Criteria-based sharing rule** | Escalation is a standing query, not an action someone has to remember to take |
| Applicant → System | **`Case`** | The only inbound channel, because the applicant has no login |
