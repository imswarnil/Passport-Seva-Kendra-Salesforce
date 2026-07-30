# PSK.md — Passport Seva Kendra Salesforce Project

> Context and build guide for Claude Code. This file explains **what we are building, how the org is set up, the conventions to follow, and the current state of every layer of the build**. Work through it top to bottom. Deploy with the Salesforce CLI (`sf`). Ask before doing anything destructive.

---

## 1. Project context (read first)

We are building a **custom Salesforce platform for a Passport Seva Kendra (PSK)** — the offices that process Indian passport (and later visa) applications. This is an independent portfolio project (not affiliated with any government body). The goal is a clean, well-architected org that demonstrates core Salesforce skills: data modelling, automation (Flow + Apex), security/sharing, and integrations (n8n + Twilio + AI later).

**Design philosophy:** few objects, many fields. We model the whole application lifecycle on one object using a Status picklist and record types — **not** a new object per stage. A half-finished form is the same object in `Draft` status, not a different object.

**Environment**
- Org: Developer Edition, alias `psk-dev`, user `admin@passportoffice.com`.
- CLI: `sf` (Salesforce CLI). Project uses SFDX source format under `force-app/main/default/`.
- Deploy with: `sf project deploy start`. Retrieve with: `sf project retrieve start`.
- Source API version 67.0 (`sfdx-project.json`). Note that the older `PSK_*` Apex classes still carry `apiVersion` 61.0 in their `.cls-meta.xml`.
- Everything is version-controlled in Git — commit after each object is deployed.

**Guardrails**
- Never delete metadata or data without asking.
- Deploy incrementally (object first, then fields, then layouts, then record types) and confirm each deploy succeeds before moving on.
- After creating fields, they are hidden by default — set field-level security via a permission set (`PSK_App_Access` is the catch-all) so they're visible.
- The org is the source of truth for anything retrieved. Local metadata must be deployed back for changes to take effect.

---

## 2. The object catalogue

All sixteen custom objects below are **built and deployed**. Objects #2–#11 were originally sketched only as a one-line roadmap here and then built out from a blog build-log export (`psk.json`) — this table is their first real documentation in the repository, so treat it as authoritative and keep it current.

Two of them were not in the original roadmap at all and were added because the model needed them: `Citizen__c` (a golden identity record, so the applicant is not an Account) and `Family_Member__c` (citizen-to-citizen links, which also carry the guardian link a minor application needs).

| # | Object | API Name | Relationship | OWD | Name field | Record types | Purpose |
|---|--------|----------|--------------|-----|-----------|--------------|---------|
| 1 | Passport Application | `Passport_Application__c` | root | Private | Auto Number `ARN-{000000}` | Fresh, Re_Issue, Tatkal, Lost_Damaged, Minor, Diplomatic_Official | The heart of the system — full lifecycle, Draft to Delivered, on one object |
| 2 | PSK Office | `PSK__c` | root | Public Read Only | Text | — | A physical service centre: code, region, address, capacity, manager |
| 3 | Appointment Slot | `Slot__c` | M-D → `PSK__c` | ControlledByParent | Auto Number `SLOT-{0000000}` | — | A bookable capacity block at a centre; roll-up `Booked_Count__c` drives `Is_Available__c` |
| 4 | Appointment | `Appointment__c` | M-D → `Passport_Application__c` **and** M-D → `Slot__c` | ControlledByParent | Auto Number `APT-{000000}` | — | True junction object: Application × Slot, plus check-in/out and counter |
| 5 | Document Checklist Item | `Document_Checklist_Item__c` | M-D → `Passport_Application__c` | ControlledByParent | Auto Number `DCI-{0000000}` | — | One required/received document per row |
| 6 | Objection | `Objection__c` | M-D → `Passport_Application__c` | ControlledByParent | Auto Number `OBJ-{00000}` | — | An issue raised on an application, with resolution notes |
| 7 | Police Verification | `Police_Verification__c` | **Lookup** → `Passport_Application__c` | Private | Auto Number `PV-{00000}` | — | The PV process. Deliberately a lookup, not master-detail: a PV report survives its application and has its own OWD |
| 8 | Payment | `Payment__c` | M-D → `Passport_Application__c` | ControlledByParent | Auto Number `PAY-{000000}` | — | A fee payment with gateway reference and raw response |
| 9 | Renewal | `Renewal__c` | Lookup → `Passport_Application__c` (×2) | Private | Auto Number `REN-{000000}` | — | Upcoming-expiry outreach; `Converted_Application__c` links to the new application it produced |
| 10 | Notification Log | `Notification_Log__c` | Lookup → `Passport_Application__c` | Private | Auto Number `NOTIF-{000000}` | — | Every SMS/WhatsApp sent. `Provider_Message_Id__c` is the Twilio idempotency key |
| 11 | Risk Flag | `Risk_Flag__c` | Lookup → `Passport_Application__c` | Private | Auto Number `RISK-{00000}` | — | Fraud/anomaly flags with severity and a reviewing user |
| 12 | Citizen | `Citizen__c` | root | Private | Text (Citizen Name) | — | The golden identity record — who a person is *now*. KYC status, blacklist flag, language preference |
| 13 | Family Member | `Family_Member__c` | M-D → `Citizen__c` | ControlledByParent | Auto Number `FM-{00000}` | — | Citizen-to-citizen relationship links; carries `Is_Guardian__c` and `Minor_Application__c` |
| 14 | Passport | `Passport__c` | Lookup → `Passport_Application__c`, `Citizen__c`, `PSK__c`, self | Private | Text (Passport Number) | Ordinary, Diplomatic, Official | The issued booklet. Almost entirely derived by formula from the application |
| 15 | Print Job | `Print_Job__c` | M-D → `Passport_Application__c` | ControlledByParent | Auto Number `PRN-{00000}` | — | Booklet printing, batch, QC pass, reprint reason, turnaround |
| 16 | Dispatch | `Dispatch__c` | M-D → `Passport_Application__c` | ControlledByParent | Auto Number `DSP-{00000}` | — | Courier despatch and delivery tracking; delivery address by formula |

Plus two **Custom Metadata Types**, both with deployed records:

| Type | API Name | Records | Purpose |
|---|---|---|---|
| Fee Matrix | `Fee_Matrix__mdt` | 10 | Fee per record type × booklet pages × validity years. Read by automation, not hard-coded |
| SLA Config | `SLA_Config__mdt` | 26 | A normal and a Tatkal target for every processing stage |

### 2.1 The as-submitted snapshot — a deliberate duplication

`Passport_Application__c` carries its own `First_Name__c`, `Last_Name__c`, `Date_of_Birth__c`, `Mobile__c` and full address **even though it also has a `Citizen__c` lookup**. That is on purpose.

A passport application is a legal instrument. The details *as declared at submission* are what get printed into the booklet, what the police verify against, and what an audit would later examine. If those fields were cross-object formulas reading `Citizen__r`, then the day a citizen moved house or corrected a spelling, every historical application would silently rewrite itself — including applications already granted and printed. The record of what was declared would be destroyed by the act of keeping the citizen record current.

So: **`Citizen__c` answers "who is this person now"; the application answers "what did they declare then".** Both are needed, and they are allowed to disagree.

### 2.2 Where duplication *is* avoided

The rule of thumb is: **snapshot a declaration, derive a fact.**

- `Passport__c` re-keys nothing. `Booklet_Pages__c`, `Validity_Years__c`, `ECR_Status__c` and `Passport_Category__c` are `TEXT(Application__r.…)` formulas; `Holder_Name__c` is assembled by formula from the application's name parts; `Place_of_Issue__c` is `PSK_Office__r.Name`. Only the booklet's own facts — file number, issue/expiry dates, status — are stored.
- `Dispatch__c.Delivery_Address__c` is a formula over `Passport_Application__r`'s address lines, so a courier label can never drift from the application.
- `Family_Member__c` reads `Member_Date_of_Birth__c` and `Member_Mobile__c` through `Related_Citizen__r`; `Display_Name__c` falls back to a typed `Member_Name__c` only when no citizen is linked.
- `Print_Job__c.ARN__c` and `Dispatch__c.ARN__c` are `Passport_Application__r.Name`, not stored strings.

---

## 3. Conventions (follow these everywhere)

- **Objects:** singular label, PascalCase API with underscores, e.g. `Passport_Application__c`.
- **Fields:** descriptive, no abbreviations, e.g. `Police_Verification_Type__c` not `PV_Typ__c`.
- **Picklists:** use restricted value sets. Reuse a **Global Value Set** for anything shared across objects. Thirteen exist: `Indian_States`, `PSK_Gender`, `PSK_Region`, `PSK_World_Region`, `PSK_Language`, `PSK_Relationship`, `PSK_Severity`, `PSK_Payment_Mode`, `PSK_Payment_Status`, `PSK_Document_Status`, `PSK_Fulfilment_Status`, `PSK_Courier_Partner`, `PSK_Visa_Type`.
- **Record types:** business name, no prefix, e.g. `Fresh`, `Tatkal`. Use record types to *subset* picklists, not to fork the schema.
- **Automation naming:** `Object - Trigger - Purpose`, e.g. `Application - After Save - Route to Queue`.
- **Sharing:** OWD **Private** on anything with personal data; `ControlledByParent` on master-detail children; `Public Read Only` only for reference data like `PSK__c`.
- **PII rule:** never store the Aadhaar number — only `Aadhaar_Verified__c` (checkbox) and `Aadhaar_Token__c` (an opaque provider reference). This follows India's DPDP Act (data minimisation). Shield Platform Encryption is unavailable in Developer Edition, so `Aadhaar_Token__c` is plain text — which makes the discipline load-bearing: never put anything re-identifiable in it.
- **External IDs:** every object carries an `External_Id__c` (unique, external ID) so integration upserts are idempotent.
- **Validation rules:** enforce on submit, not in Draft. Every rule on the application is gated on `NOT(ISPICKVAL(Status__c,"Draft"))` or on a specific later stage, so a half-finished form always saves.

---

## 4. Object #1 — Passport Application (reference spec)

The object that carries the system. 56 custom fields, 6 record types, 4 active validation rules, a Path, three compact layouts.

### 4.1 Object definition
- **Label:** Passport Application / **Plural:** Passport Applications
- **API Name:** `Passport_Application__c`
- **Record Name:** `ARN`, Auto Number, format `ARN-{000000}`
- **Sharing Model (OWD):** Private
- **Enabled:** Reports, Activities, Field History, Search, Bulk API, Streaming API
- **Deployment Status:** Deployed

### 4.2 Fields

Legend — **Req?**: "submit" = enforced only by a validation rule when Status leaves Draft (so Drafts save incomplete).

#### Group A — System & Lifecycle
| Field Label | API Name | Type | Details | Req? |
|---|---|---|---|---|
| Status | `Status__c` | Picklist (restricted) | 12 values, default **Draft** | Yes |
| Payment Status | `Payment_Status__c` | Picklist (restricted) | Global value set `PSK_Payment_Status` — default **Not Paid** | No |
| Submitted Date | `Submitted_Date__c` | Date/Time | Stamped when Draft→Submitted | No |
| Stage Entered Date | `Stage_Entered_Date__c` | Date/Time | Re-stamped on each stage change | No |
| Granted Date | `Granted_Date__c` | Date/Time | | No |
| Citizen | `Citizen__c` | Lookup → `Citizen__c` | The golden identity record. Relationship `Applications` | No † |
| Applicant | `Applicant__c` | Lookup → **Account** | Legacy from the pre-`Citizen__c` design. Kept for compatibility; prefer `Citizen__c` | No |
| PSK Office | `PSK_Office__c` | Lookup → `PSK__c` | Relationship `Passport_Applications` | No |
| External Id | `External_Id__c` | Text(40) | Unique, External ID | No |

† `Citizen_Required_On_Submit` is the validation rule intended to make this required on submit. **It ships inactive** and must only be activated after the citizen backfill has run — see §9.

**Status values (in order):** Draft; Submitted; Payment Pending; Paid; Document Verification; Police Verification; Granting; Printing; Dispatch; Delivered; Rejected; Cancelled.

#### Group B — Applicant Details (the as-submitted snapshot)
`First_Name__c`, `Middle_Name__c`, `Last_Name__c` (Text), `Date_of_Birth__c` (Date, PII), `Gender__c` (Picklist), `Place_of_Birth__c`, `Mobile__c` (Phone), `Email__c`, `Father_Name__c`, `Mother_Name__c`, `Spouse_Name__c`, `Marital_Status__c`.
First name, last name, DOB and mobile are **submit**-required.

#### Group C — Address
`Address_Line1__c` (submit), `Address_Line2__c`, `City__c`, `District__c`, `State__c` (global value set `Indian_States`), `Pincode__c` (Text 6), `Country__c` (default "India"), `Years_At_Address__c` (drives PV type).

#### Group D — Application Details
| Field Label | API Name | Type | Details |
|---|---|---|---|
| Passport Category | `Passport_Category__c` | Picklist (restricted) | Ordinary;Diplomatic;Official — default Ordinary. **Controlling field** for Clearance Level |
| Clearance Level | `Clearance_Level__c` | Picklist (dependent) | Depends on Passport Category — see 4.3 |
| Booklet Pages | `Booklet_Pages__c` | Picklist | 36;60 |
| Validity Years | `Validity_Years__c` | Picklist | 10;5 |
| Tatkal | `Tatkal__c` | Checkbox | Drives the Tatkal SLA row and the manager sharing rule |
| Applied For Minor | `Applied_For_Minor__c` | Checkbox | Shows guardian fields via Dynamic Forms |
| Guardian Name / Consent | `Guardian_Name__c` / `Guardian_Consent__c` | Text / Checkbox | |
| Previous Passport No / Expiry | `Previous_Passport_No__c` / `Previous_Passport_Expiry__c` | Text / Date | For re-issue |
| Reason For Reissue | `Reason_For_Reissue__c` | Picklist | Expiry;Pages Exhausted;Change of Details;Damaged;Lost |
| ECR Status | `ECR_Status__c` | Picklist | ECR;ECNR |

#### Group E — Payment
`Fee__c` (Currency, set from `Fee_Matrix__mdt`), `Payment_Reference__c`, `Payment_Date__c`, `Payment_Mode__c`.

#### Group F — Verification & Compliance
`Aadhaar_Verified__c`, `Aadhaar_Token__c`, `Documents_Verified__c`, `Risk_Score__c` (0–100, drives the high-risk sharing rule), `Police_Verification_Type__c` (Pre-PV;Post-PV;No PV).

#### Group G — Consent & Notifications
`Notification_Consent__c` (gates Twilio sends), `Mobile_For_Alerts__c`, `Consent_Timestamp__c` (DPDP).

#### Group H — Derived (formula, read-only)
| Field | Formula |
|---|---|
| `Applicant_Age__c` | `FLOOR((TODAY() - Date_of_Birth__c) / 365.25)` |
| `Is_Minor__c` | `Applicant_Age__c < 18` |
| `Is_Draft__c` | `ISPICKVAL(Status__c, "Draft")` |

### 4.3 Dependent picklist — Clearance Level
Controlling `Passport_Category__c` → dependent `Clearance_Level__c`.

| Passport Category | Clearance Level values shown |
|---|---|
| Ordinary | *(none)* |
| Diplomatic | Ambassador; Consular; Minister |
| Official | Govt Deputation; Delegation |

### 4.4 Record types and their picklist subsetting

All six active. Record types are used to *narrow* picklists, which is why there is no per-type field explosion.

| Label | API Name | Category | Booklet | Validity | PV type | ECR | Reason for reissue |
|---|---|---|---|---|---|---|---|
| Fresh | `Fresh` | Ordinary | 36, 60 | 10, 5 | Pre-PV, Post-PV | ECR, ECNR | — |
| Re-issue | `Re_Issue` | Ordinary | 36, 60 | 10, 5 | No PV, Post-PV | ECR, ECNR | Change of Details, Expiry, Pages Exhausted |
| Tatkal | `Tatkal` | Ordinary | 36, 60 | 10, 5 | Post-PV | ECR, ECNR | Damaged, Expiry, Lost |
| Lost / Damaged | `Lost_Damaged` | Ordinary | 36, 60 | 10, 5 | Pre-PV | ECR, ECNR | Damaged, Lost |
| Minor | `Minor` | Ordinary | 36 | 5 | No PV | ECNR | — |
| Diplomatic / Official | `Diplomatic_Official` | Diplomatic, Official | 60 | 10, 5 | No PV | ECNR | — |

### 4.5 Page and compact layouts
- Page layout `Passport Application Layout`, sections in this order: **Lifecycle**, **Applicant Details**, **Address**, **Application Details**, **Payment**, **Verification & Compliance**, **Consent & Notifications**, **System**.
- Dynamic Forms on the Lightning record page: show guardian fields only when `Applied_For_Minor__c`; show previous-passport fields only for Re-issue; show `Clearance_Level__c` only for Diplomatic/Official.
- Three compact layouts, so the highlights panel says something useful per context:
  - `PSK_Compact` (assigned) — `Name`, `Status__c`, `Passport_Category__c`, `Citizen__c`, `Risk_Score__c`
  - `PSK_Compact_Minor` — `Name`, `Status__c`, `Guardian_Name__c`, `Guardian_Consent__c`, `Citizen__c`
  - `PSK_Compact_Reissue` — `Name`, `Status__c`, `Previous_Passport_No__c`, `Previous_Passport_Expiry__c`, `Reason_For_Reissue__c`

### 4.6 Path
`Passport_Application_Path`, active, on `Status__c`, with guidance text at each of the 12 stages. **Currently declared for the `Fresh` record type only** — the other five record types render no stage bar. Either add a path per record type or accept that limitation explicitly.

### 4.7 Validation rules

| Rule | Active | Formula | Message |
|---|---|---|---|
| `Require_Core_Fields_On_Submit` | yes | `AND( NOT(ISPICKVAL(Status__c,"Draft")), OR( ISBLANK(First_Name__c), ISBLANK(Last_Name__c), ISBLANK(Date_of_Birth__c), ISBLANK(Mobile__c), ISBLANK(Address_Line1__c) ) )` | First Name, Last Name, Date of Birth, Mobile and Address Line 1 are required before submitting. |
| `Minor_Needs_Guardian_Consent` | yes | `AND( Applied_For_Minor__c, NOT(Guardian_Consent__c), NOT(ISPICKVAL(Status__c,"Draft")) )` | Guardian Consent is required for a minor application before submission. |
| `Cannot_Grant_With_Pending_Payment` | yes | `AND( ISPICKVAL(Status__c,"Granting"), NOT(ISPICKVAL(Payment_Status__c,"Paid")) )` | Payment must be Paid before the application can move to Granting. |
| `No_Backward_Move_Once_Delivered` | yes | `AND( ISPICKVAL(PRIORVALUE(Status__c),"Delivered"), NOT(ISPICKVAL(Status__c,"Delivered")) )` | A Delivered application cannot be moved back to an earlier stage. |
| `Citizen_Required_On_Submit` | **no** | requires `Citizen__c` once Status leaves Draft | Activate only after the citizen backfill — see §9 |

---

## 5. The security model

### 5.1 Role hierarchy
Eleven roles, rooted at `CEO_and_Admins`:

```
CEO_and_Admins
├── Regional_Passport_Officer
│   └── Passport_Office_Manager
│       ├── Passport_Processing_Team
│       ├── Document_Verification
│       ├── Police_Verification_Team
│       ├── Granting_Officers
│       ├── Fulfilment_Team
│       └── Help_Desk_Support
├── Visa_Processing_Team          (waiting for the visa objects)
└── Audit_And_Compliance
```

Verify the actual parentage in `force-app/main/default/roles/*.role-meta.xml` before relying on the shape above — roles are cheap to reparent and the tree drifts.

### 5.2 The seven persona permission sets
Personas are permission sets over a Private OWD, not profiles. One set per job, plus `PSK_App_Access` as the admin/verification catch-all that grants everything.

| Persona | Role | Shape |
|---|---|---|
| Front Office / Data Entry | `Passport_Processing_Team` | Create and edit applications in Draft/Submitted; manage citizens, appointments and slots. No granting, no fulfilment, no risk |
| Document Verification Officer | `Document_Verification` | Read applications; full control of Document Checklist Items and Objections |
| Police Verification Officer | `Police_Verification_Team` | Read applications; full control of Police Verification records |
| Granting Officer | `Granting_Officers` | Edit applications at Granting/Printing; create Passport records. Cannot edit the applicant declaration |
| Print & Dispatch | `Fulfilment_Team` | Full control of Print Jobs and Dispatches; read-only on the application except Status |
| Passport Office Manager / RPO | `Regional_Passport_Officer` | Read/edit everything in the office, plus Risk Flags and blacklisted citizens |
| Audit & Compliance | `Audit_And_Compliance` | Read-only across every PSK object including Notification Logs. No create, edit or delete anywhere |

PII fields (`Date_of_Birth__c`, `Mobile__c`, `Aadhaar_Verified__c`, `Aadhaar_Token__c`) are controlled by field-level security *per set*, separately from object access. A persona that can open a record must not automatically read the Aadhaar token.

**Permission set groups** bundle the sets for real-world users who wear two hats (a manager who also grants, for instance). Build them as thin wrappers over the persona sets; never put permissions directly in a group.

### 5.3 Public groups (6)
`PSK_All_Staff`, `PSK_Managers`, `PSK_Verification_Team`, `PSK_Fulfilment_Team`, `PSK_Auditors`, `PSK_Visa_Team` — each defined as one or more `roleAndSubordinates` with `doesIncludeBosses`.

### 5.4 Queues (6)
`Document_Verification`, `Police_Verification`, `Granting`, `Printing_And_Dispatch`, `Objections`, `Risk_Review`. Work routes into a queue and is pulled out by whoever picks it up.

### 5.5 Criteria-based sharing rules
| Object | Rule | Criteria | Shared to | Access |
|---|---|---|---|---|
| `Passport_Application__c` | `Tatkal_To_Managers` | `Tatkal__c = true` | group `PSK_Managers` | Edit |
| `Passport_Application__c` | `High_Risk_To_Verification` | `Risk_Score__c > 70` | role+sub `Police_Verification_Team` | Read |
| `Passport_Application__c` | `Diplomatic_To_RPO` | `Passport_Category__c` includes Diplomatic, Official | role `Regional_Passport_Officer` | Edit |
| `Passport_Application__c` | `Granting_Stage_To_Granting_Officers` | `Status__c` includes Granting, Printing | role `Granting_Officers` | Edit |
| `Passport_Application__c` | `Fulfilment_Stage_To_Fulfilment` | `Status__c` includes Printing, Dispatch, Delivered | role `Fulfilment_Team` | Edit |
| `Citizen__c` | `Blacklisted_To_Managers` | `Is_Blacklisted__c = true` | group `PSK_Managers` | Edit |
| `Passport__c` | `Expiring_To_Officers` | `Status__c` includes Active, Expired | role+sub `Passport_Office_Manager` | Read |
| `Police_Verification__c` | `Adverse_To_Managers` | `Status__c = Adverse` | group `PSK_Managers` | Edit |
| `Risk_Flag__c` | `Open_High_Severity_To_Managers` | `Severity__c` includes High, Critical | group `PSK_Managers` | Edit |

**Two constraints worth writing down**, because they shape the design:

1. **Criteria-based sharing cannot read a formula field.** That is why `Expiring_To_Officers` filters on `Status__c` rather than the obvious `Is_Expiring_Soon__c`, and the rule's own description says so.
2. **Criteria-based sharing cannot traverse a lookup.** So no rule can be written against `PSK_Office__r.Region__c`, and region-based access is currently unimplemented. The fix is a real `Region__c` text field on the application, populated by automation from the office — not a formula, which would fail for the same reason as (1).

**Enterprise Territory Management is not enabled** in this org (`Territory2Model` is not a queryable sObject) and **cannot be enabled by a metadata deploy** — it is a Setup toggle, and an irreversible one. Until someone makes that call, region-based access must be built from public groups plus criteria-based sharing.

---

## 6. The automation layer

### 6.1 Apex
| Class | Role |
|---|---|
| `PSK_Constants` | Central string constants — status values, record type developer names, stage ordering. Nothing else should hard-code a picklist string |
| `PSK_AutomationControl` | Kill switch / recursion guard, so a trigger can be suppressed during a bulk load or a backfill |
| `PSK_HomeController` | Backs the `pskHomeDashboard` LWC — stage counts, SLA breaches, queue depth |
| `PSK_ApplicationSidebarController` | Backs `pskApplicationSidebar` — the per-record context panel |
| `PSK_ApplicationActionsController` | Backs the record-page action buttons (advance stage, spawn fulfilment records) |

Each has a `<ClassName>Test`. Trigger handlers follow the `Object - Trigger - Purpose` naming convention. Test classes must not rely on org data — build their own.

### 6.2 Fee matrix
`Fee_Matrix__mdt`, 10 records keyed on record type × booklet pages × validity years:
`Fresh_36_10`, `Fresh_60_10`, `Re_Issue_36_10`, `Re_Issue_60_10`, `Tatkal_36_10`, `Tatkal_60_10`, `Lost_Damaged_36_10`, `Lost_Damaged_60_10`, `Minor_36_5`, `Diplomatic_Official_60_10`.

Automation reads the matching row on submit and writes `Fee__c`. Changing a fee is a metadata deploy, not a code change — which is the point.

### 6.3 SLA configuration
`SLA_Config__mdt`, 26 records: a normal and a `_Tatkal` variant for each of the thirteen processing stages (`Submitted`, `Payment_Pending`, `Paid`, `Document_Verification`, `Police_Verification`, `Granting`, `Printing`, `Dispatch`). Stage-entry timestamps on the application are compared against the relevant row to compute ageing and breach.

---

## 7. The UI layer

### 7.1 Apps
- **Application Management Console** (`Application_Management_Console`) — the PSK app. Navy `#1A2A5E` header, custom logo, 17 tabs covering every PSK object plus Reports and Dashboards, utility bar `Passport_Application_Management_UtilityBar`, home page `App_Home`.
- **Passport Validator** (`Passport_Validator`) — a small single-purpose app whose home page is the `Passport_Validator` flexipage.

### 7.2 Tabs
One custom tab per PSK object (16), plus `Manager_Overview`.

### 7.3 Lightning pages
- `App_Home` — the console home page: hosts `pskHomeDashboard` and `pskHomeSidebarSummary`.
- `Passport_Application_Record_Page` — record page for `Passport_Application__c`, with header/main/sidebar regions and Dynamic Forms.
- `Passport_Validator` — the validator app's home.

> **Per-record-type activation is a manual step.** Org-default and app-default page assignments deploy; per-record-type activation is not reliably representable in `FlexiPage` metadata. After any deploy that touches record pages, open Lightning App Builder → Activation and assign `Passport_Application_Record_Page` against all six application record types.

### 7.4 LWCs
| Component | Where | What |
|---|---|---|
| `pskHomeDashboard` | `App_Home` | Stage counts, SLA breaches, queue depth |
| `pskHomeSidebarSummary` | `App_Home` sidebar | Compact today-view |
| `pskApplicationSidebar` | record page sidebar | Per-record context — citizen, documents, PV, payments at a glance |
| `pskRiskMeter` | record page | Visual `Risk_Score__c` gauge |

---

## 8. Incremental deploy sequence

Dependencies flow downward; deploy and confirm each step before the next.

```bash
# 0. Always validate first
sf project deploy start --source-dir force-app --dry-run

# 1. Vocabulary before the fields that reference it
sf project deploy start --metadata GlobalValueSet

# 2. Objects: fields, record types, validation rules, compact layouts, list views
sf project deploy start --source-dir force-app/main/default/objects

# 3. UI that references those fields
sf project deploy start --source-dir force-app/main/default/layouts \
                        --source-dir force-app/main/default/flexipages

# 4. Security, in order — groups reference roles, sharing rules reference groups and fields
sf project deploy start --metadata Role
sf project deploy start --metadata Group --metadata Queue
sf project deploy start --metadata PermissionSet --metadata PermissionSetGroup
sf project deploy start --metadata SharingRules

# 5. Configuration records
sf project deploy start --metadata CustomMetadata

# 6. Code and components
sf project deploy start --source-dir force-app/main/default/classes \
                        --source-dir force-app/main/default/triggers \
                        --source-dir force-app/main/default/lwc

# 7. App shell
sf project deploy start --metadata CustomApplication --metadata CustomTab --metadata PathAssistant

# 8. Verify
sf apex run test --test-level RunLocalTests --result-format human --code-coverage
sf org open --path lightning/app/Application_Management_Console
```

Then do the manual steps that metadata cannot express: per-record-type Lightning page activation, and (if it is ever wanted) the Enterprise Territory Management toggle.

**Retrieving:** `manifest/package.xml` is a ~200-type wildcard manifest, so a full retrieve is slow and drags in Service Analytics template noise. Prefer `sf project retrieve start --metadata CustomObject:Passport_Application__c` for day-to-day work; a scoped `manifest/psk-package.xml` is on the backlog.

---

## 9. Status — built / in flight / not started

### Built and deployed
| Layer | What |
|---|---|
| Data model | All 16 objects, ~230 custom fields, 9 record types across 2 objects, `Fee_Matrix__mdt` (10 records), `SLA_Config__mdt` (26 records) |
| Vocabulary | 13 global value sets |
| Validation | 4 active rules on `Passport_Application__c` |
| Security | 11 roles, 6 public groups, 6 queues, 9 criteria-based sharing rules, `PSK_App_Access` |
| UI | 2 custom apps, 17 tabs, 3 Lightning pages, 4 LWCs, 1 Path, 8 compact layouts |
| Apex | 5 `PSK_*` classes with test classes |
| Demo data | ~40 PSK records seeded across applications, offices, slots, appointments, checklist items, payments, PVs, objections, risk flags, notification logs |

### In flight
| Item | Note |
|---|---|
| The 7 persona permission sets | Being authored. `PSK_App_Access` is the interim catch-all |
| Permission set groups | Depend on the persona sets landing first |
| Trigger + service layer | `PSK_Constants` and `PSK_AutomationControl` are on disk without `.cls-meta.xml`; the handlers that use them are not written yet |
| Page layouts for the newest objects | `Citizen__c`, `Passport__c`, `Print_Job__c`, `Dispatch__c`, `Family_Member__c` have no `Layout` metadata and fall back to an auto-generated layout |
| `Citizen_Required_On_Submit` | Ships **inactive**. Activate only after every existing application has a `Citizen__c` value — otherwise historical records become unsaveable |
| Citizen / Passport / Print Job / Dispatch / Family Member demo data | Objects exist and are empty |

### Not started
| Item | Why it matters |
|---|---|
| **Visa department** — `Visa_Application__c`, `Country__c`, `Sponsor__c` | The `Visa_Processing_Team` role, `PSK_Visa_Team` group and `PSK_Visa_Type` value set already exist waiting for them |
| **Approval processes** | `approvalProcesses/` is absent entirely. Granting a Diplomatic or Official passport is currently a picklist change by anyone with edit access. This is the highest-priority gap in the org |
| **Experience Cloud citizen site** | The applicant journey is entirely staff-mediated. The inherited *Internal Zone* community is Service Analytics template residue, not a PSK portal |
| **Reports, dashboards, custom report types** | Zero exist for any PSK object. Nothing can answer an operational question in aggregate |
| **Paths for the other 5 record types** | Only `Fresh` has a stage bar |
| **Region-based sharing** | Needs a real `Region__c` field on the application first (see §5.5) |
| **n8n / Twilio / AI integrations** | `Notification_Log__c` exists with a `Provider_Message_Id__c` idempotency key and is empty of real sends |
| **Hindi / regional translation** | `objectTranslations/` are en_US stubs, despite `Citizen__c.Preferred_Language__c` existing |

---

## 10. What NOT to do

- **Do not enable Enterprise Territory Management** without an explicit decision. It is irreversible and it is not what the current sharing design assumes.
- **Do not activate `Citizen_Required_On_Submit`** until the citizen backfill has run and returns zero nulls.
- **Do not write a picklist string literal in Apex.** Use `PSK_Constants`.
- **Do not add a cross-object formula to the applicant declaration fields** on `Passport_Application__c`. Read §2.1 first — that duplication is the design.
- **Do not delete metadata or data without asking**, including the stray inherited template metadata. Some of it is load-bearing for the Wave dashboards that came with the org.
- **Do not deploy the whole tree** when a scoped deploy will do. A full `--source-dir force-app` deploy drags in the Service Analytics template and takes minutes.

---

*A companion `PSK_Org_Readiness_Report.pdf` is generated from the live metadata tree by `node scripts/pdf/generate-report.mjs`. It carries the per-object UAT checklist, the lifecycle walkthrough script, the persona access matrix and the prioritised action list. Regenerate it after any significant deploy — every count in it is recomputed from the tree, so a stale copy is obvious.*
