# PSK.md — Passport Seva Kendra Salesforce Project

> Context and build guide for Claude Code. This file explains **what we are building, how the org is set up, the conventions to follow, and the exact spec for the first object**. Work through it top to bottom. Deploy with the Salesforce CLI (`sf`). Ask before doing anything destructive.

---

## 1. Project context (read first)

We are building a **custom Salesforce platform for a Passport Seva Kendra (PSK)** — the offices that process Indian passport (and later visa) applications. This is an independent portfolio project (not affiliated with any government body). The goal is a clean, well-architected org that demonstrates core Salesforce skills: data modelling, automation (Flow + Apex), security/sharing, and integrations (n8n + Twilio + AI later).

**Design philosophy:** few objects, many fields. We model the whole application lifecycle on one object using a Status picklist and record types — **not** a new object per stage. A half-finished form is the same object in `Draft` status, not a different object.

**Environment**
- Org: Developer Edition, alias `psk-dev`, user `admin@passportoffice.com`.
- CLI: `sf` (Salesforce CLI). Project uses SFDX source format under `force-app/main/default/`.
- Deploy with: `sf project deploy start`. Retrieve with: `sf project retrieve start`.
- Everything is version-controlled in Git — commit after each object is deployed.

**Guardrails**
- Never delete metadata or data without asking.
- Deploy incrementally (object first, then fields, then layouts, then record types) and confirm each deploy succeeds before moving on.
- After creating fields, they are hidden by default — set field-level security for the System Administrator profile (or add to a permission set) so they're visible.

---

## 2. The full object roadmap (what we will build overall)

Build in this order; dependencies flow downward. **We start with #1 (Passport Application). The rest are for later — do not build them yet unless asked.**

| # | Object | API Name | Purpose |
|---|--------|----------|---------|
| 1 | Passport Application | `Passport_Application__c` | The heart of the system — full lifecycle, draft to delivered. **← build this first** |
| 2 | PSK Office | `PSK__c` | A physical service centre |
| 3 | Appointment Slot | `Slot__c` | A bookable capacity block at a centre |
| 4 | Appointment | `Appointment__c` | Junction: Application × Slot |
| 5 | Document Checklist Item | `Document_Checklist_Item__c` | Required/received documents |
| 6 | Objection | `Objection__c` | An issue raised on an application |
| 7 | Police Verification | `Police_Verification__c` | The PV process (lookup, not master-detail) |
| 8 | Payment | `Payment__c` | A fee payment |
| 9 | Renewal | `Renewal__c` | Upcoming-expiry outreach |
| 10 | Notification Log | `Notification_Log__c` | Every SMS/WhatsApp sent (Twilio idempotency) |
| 11 | Risk Flag | `Risk_Flag__c` | Fraud/anomaly flags |

Later phases: Visa department (`Visa_Application__c`, `Country__c`, `Sponsor__c`), fulfilment (`Print_Job__c`, `Dispatch__c`), and Custom Metadata Types (`Fee_Matrix__mdt`, `SLA_Config__mdt`).

---

## 3. Conventions (follow these everywhere)

- **Objects:** singular label, PascalCase API with underscores, e.g. `Passport_Application__c`.
- **Fields:** descriptive, no abbreviations, e.g. `Police_Verification_Type__c` not `PV_Typ__c`.
- **Picklists:** use restricted value sets. Reuse a **Global Value Set** for anything shared across objects (e.g. Indian States).
- **Record types:** business name, no prefix, e.g. `Fresh`, `Tatkal`.
- **Automation naming (later):** `Object - Trigger - Purpose`, e.g. `Application - After Save - Route to Queue`.
- **Sharing:** OWD **Private** on anything with personal data.
- **PII rule:** never store the Aadhaar number — only `Aadhaar_Verified__c` (checkbox) and `Aadhaar_Token__c` (token). This follows India's DPDP Act (data minimisation).

---

## 4. OBJECT #1 — Passport Application (build spec)

### 4.1 Object definition
- **Label:** Passport Application
- **Plural:** Passport Applications
- **API Name:** `Passport_Application__c`
- **Record Name:** `ARN`, type **Auto Number**, format `ARN-{000000}`, starting number 1
- **Sharing Model (OWD):** Private
- **Enable:** Reports, Activities, Field History, Search
- **Deployment Status:** Deployed

### 4.2 Fields

Legend — **Req?**: "submit" = enforced only by a validation rule when Status → Submitted (so Drafts save incomplete). **Type** uses Salesforce field types.

#### Group A — System & Lifecycle
| Field Label | API Name | Type | Details | Req? |
|---|---|---|---|---|
| Status | `Status__c` | Picklist (restricted) | Values below; default **Draft** | Yes |
| Payment Status | `Payment_Status__c` | Picklist (restricted) | Not Paid;Pending;Paid;Failed;Refunded — default **Not Paid** | No |
| Submitted Date | `Submitted_Date__c` | Date/Time | Stamped when Draft→Submitted | No |
| Stage Entered Date | `Stage_Entered_Date__c` | Date/Time | Stamped on each stage change | No |
| Granted Date | `Granted_Date__c` | Date/Time | | No |
| Applicant | `Applicant__c` | Lookup → **Account** | The citizen (Person Account). Relationship name `Passport_Applications` | No |
| PSK Office | `PSK_Office__c` | Lookup → **PSK__c** | ⚠ Only add AFTER `PSK__c` exists. Skip for now. | No |
| External Id | `External_Id__c` | Text(40) | Unique, External ID — for integration upserts | No |

**Status values (in order):** Draft; Submitted; Payment Pending; Paid; Document Verification; Police Verification; Granting; Printing; Dispatch; Delivered; Rejected; Cancelled. (Default = Draft.)

#### Group B — Applicant Details
| Field Label | API Name | Type | Details | Req? |
|---|---|---|---|---|
| First Name | `First_Name__c` | Text(80) | | submit |
| Middle Name | `Middle_Name__c` | Text(80) | | No |
| Last Name | `Last_Name__c` | Text(80) | | submit |
| Date of Birth | `Date_of_Birth__c` | Date | PII — restrict FLS | submit |
| Gender | `Gender__c` | Picklist | Male;Female;Transgender | No |
| Place of Birth | `Place_of_Birth__c` | Text(100) | | No |
| Mobile | `Mobile__c` | Phone | | submit |
| Email | `Email__c` | Email | | No |
| Father Name | `Father_Name__c` | Text(120) | | No |
| Mother Name | `Mother_Name__c` | Text(120) | | No |
| Spouse Name | `Spouse_Name__c` | Text(120) | | No |
| Marital Status | `Marital_Status__c` | Picklist | Single;Married;Divorced;Widowed | No |

#### Group C — Address
| Field Label | API Name | Type | Details | Req? |
|---|---|---|---|---|
| Address Line 1 | `Address_Line1__c` | Text(255) | | submit |
| Address Line 2 | `Address_Line2__c` | Text(255) | | No |
| City | `City__c` | Text(60) | | No |
| District | `District__c` | Text(60) | | No |
| State | `State__c` | Picklist | Use Global Value Set `Indian_States` if created, else a plain restricted picklist (Delhi;Maharashtra;Karnataka;Tamil Nadu;Uttar Pradesh;West Bengal;Gujarat;Rajasthan; …add rest) | No |
| Pincode | `Pincode__c` | Text(6) | | No |
| Country | `Country__c` | Text(40) | Default `"India"` | No |
| Years at Address | `Years_At_Address__c` | Number(3,0) | Drives PV type | No |

#### Group D — Application Details
| Field Label | API Name | Type | Details | Req? |
|---|---|---|---|---|
| Passport Category | `Passport_Category__c` | Picklist (restricted) | Ordinary;Diplomatic;Official — default **Ordinary**. **Controlling field** for Clearance Level. | No |
| Clearance Level | `Clearance_Level__c` | Picklist (restricted, **dependent**) | Depends on Passport Category — see 4.3 | No |
| Booklet Pages | `Booklet_Pages__c` | Picklist | 36;60 — default 36 | No |
| Validity Years | `Validity_Years__c` | Picklist | 10;5 — default 10 (5 for minors) | No |
| Tatkal | `Tatkal__c` | Checkbox | default false | No |
| Applied For Minor | `Applied_For_Minor__c` | Checkbox | default false; shows guardian fields via Dynamic Forms | No |
| Guardian Name | `Guardian_Name__c` | Text(120) | | No |
| Guardian Consent | `Guardian_Consent__c` | Checkbox | default false | No |
| Previous Passport No | `Previous_Passport_No__c` | Text(15) | for re-issue | No |
| Previous Passport Expiry | `Previous_Passport_Expiry__c` | Date | | No |
| Reason For Reissue | `Reason_For_Reissue__c` | Picklist | Expiry;Pages Exhausted;Change of Details;Damaged;Lost | No |
| ECR Status | `ECR_Status__c` | Picklist | ECR;ECNR — default ECNR | No |

#### Group E — Payment
| Field Label | API Name | Type | Details | Req? |
|---|---|---|---|---|
| Fee | `Fee__c` | Currency(16,2) | set by Flow from `Fee_Matrix__mdt` later | No |
| Payment Reference | `Payment_Reference__c` | Text(64) | gateway id | No |
| Payment Date | `Payment_Date__c` | Date/Time | | No |
| Payment Mode | `Payment_Mode__c` | Picklist | UPI;Net Banking;Debit Card;Credit Card;Challan | No |

#### Group F — Verification & Compliance
| Field Label | API Name | Type | Details | Req? |
|---|---|---|---|---|
| Aadhaar Verified | `Aadhaar_Verified__c` | Checkbox | default false — the flag, never the number | No |
| Aadhaar Token | `Aadhaar_Token__c` | Text(64) | token only; use Shield encryption in a real org | No |
| Documents Verified | `Documents_Verified__c` | Checkbox | default false | No |
| Risk Score | `Risk_Score__c` | Number(3,0) | 0–100 | No |
| Police Verification Type | `Police_Verification_Type__c` | Picklist | Pre-PV;Post-PV;No PV | No |

#### Group G — Consent & Notifications
| Field Label | API Name | Type | Details | Req? |
|---|---|---|---|---|
| Notification Consent | `Notification_Consent__c` | Checkbox | default false — gates Twilio sends | No |
| Mobile For Alerts | `Mobile_For_Alerts__c` | Phone | Twilio target | No |
| Consent Timestamp | `Consent_Timestamp__c` | Date/Time | when consent captured (DPDP) | No |

#### Group H — Derived (Formula, read-only)
| Field Label | API Name | Type | Formula |
|---|---|---|---|
| Applicant Age | `Applicant_Age__c` | Formula (Number, 0 dp) | `FLOOR((TODAY() - Date_of_Birth__c) / 365.25)` |
| Is Minor | `Is_Minor__c` | Formula (Checkbox) | `Applicant_Age__c < 18` |
| Is Draft | `Is_Draft__c` | Formula (Checkbox) | `ISPICKVAL(Status__c, "Draft")` |

### 4.3 Dependent picklist — Clearance Level
Controlling field: `Passport_Category__c`. Dependent field: `Clearance_Level__c`.

| Passport Category (controlling) | Clearance Level values shown (dependent) |
|---|---|
| Ordinary | *(none)* |
| Diplomatic | Ambassador; Consular; Minister |
| Official | Govt Deputation; Delegation |

### 4.4 Record Types (the passport types)
Create these record types on `Passport_Application__c`, all Active, assigned to the System Administrator profile:

| Label | API Name | Notes |
|---|---|---|
| Fresh | `Fresh` | First-time application |
| Re-issue | `Re_Issue` | Shows Previous Passport fields + Reason For Reissue |
| Tatkal | `Tatkal` | Expedited; extra annexures |
| Lost / Damaged | `Lost_Damaged` | FIR/affidavit; mandatory PV |
| Minor | `Minor` | Shows Guardian fields; 5-year validity |
| Diplomatic / Official | `Diplomatic_Official` | Restricted; Passport Category Diplomatic/Official |

> Start with **Fresh** and **Tatkal** if doing all six at once is noisy; add the rest after.

### 4.5 Page Layouts
- Create/edit the layout so fields are grouped into sections in this order: **Lifecycle**, **Applicant Details**, **Address**, **Application Details**, **Payment**, **Verification & Compliance**, **Consent & Notifications**, **System**.
- Prefer **Dynamic Forms** on the Lightning record page: show `Guardian_Name__c` and `Guardian_Consent__c` only when `Applied_For_Minor__c = true`; show `Previous_Passport_No__c`, `Previous_Passport_Expiry__c`, `Reason_For_Reissue__c` only for the Re-issue record type; show `Clearance_Level__c` only when Passport Category is Diplomatic or Official.
- Compact layout (highlights panel): `Name (ARN)`, `Status__c`, `Passport_Category__c`, `Applicant__c`, `Risk_Score__c`.

### 4.6 Path
- Add a **Path** on `Status__c` across the lifecycle values, with brief guidance text at each stage. This is the visual progress bar.

### 4.7 Validation Rules (enforce only on submit — Drafts stay saveable)
Create these, each firing only when the record is being submitted or beyond (i.e. Status is not Draft):

1. **Require core fields on submit** — block if `Status` ≠ Draft AND any of First Name / Last Name / Date of Birth / Mobile / Address Line 1 is blank.
   `AND( NOT(ISPICKVAL(Status__c,"Draft")), OR( ISBLANK(First_Name__c), ISBLANK(Last_Name__c), ISBLANK(Date_of_Birth__c), ISBLANK(Mobile__c), ISBLANK(Address_Line1__c) ) )`
2. **Minor needs guardian consent** — `AND( Applied_For_Minor__c, NOT(Guardian_Consent__c), NOT(ISPICKVAL(Status__c,"Draft")) )`
3. **Cannot grant with a pending payment** — `AND( ISPICKVAL(Status__c,"Granting"), NOT(ISPICKVAL(Payment_Status__c,"Paid")) )`
4. **No backward move once Granted** — `AND( ISPICKVAL(PRIORVALUE(Status__c),"Granted"), NOT(ISPICKVAL(Status__c,"Granted")) )`

### 4.8 Field-Level Security
After deploying fields, grant the **System Administrator** profile Read/Edit on all new custom fields (formula fields Read-only). Either update the profile metadata or create and assign a permission set `PSK_App_Access`. Confirm fields are visible on the record page afterward.

---

## 5. Build & deploy sequence for Object #1

Do these as ordered steps, deploying and confirming after each:

1. **Object shell** — create `Passport_Application__c` with the Auto Number name field and OWD Private → `sf project deploy start` → confirm.
2. **Fields** — create all fields from 4.2 (skip `PSK_Office__c` until `PSK__c` exists). Deploy → confirm.
3. **Dependent picklist** — wire `Clearance_Level__c` to `Passport_Category__c` per 4.3. Deploy → confirm.
4. **Record types** — create per 4.4, assign to admin profile. Deploy → confirm.
5. **Field-level security** — grant admin access per 4.8. Deploy → confirm fields visible.
6. **Page layout + compact layout + Dynamic Forms** — per 4.5. Deploy → confirm.
7. **Path** — per 4.6.
8. **Validation rules** — per 4.7. Deploy → confirm Drafts still save but submit enforces.
9. **Smoke test** — create a record: leave it in Draft with few fields (should save), then set Status = Submitted with fields blank (should be blocked). Set Passport Category = Diplomatic and confirm Clearance Level shows the diplomatic values only.
10. **Commit** to Git with a clear message.

---

## 6. Definition of done for Object #1
- [ ] Object exists with ARN auto-number name and OWD Private
- [ ] All fields from 4.2 created (except PSK_Office, deferred)
- [ ] Clearance Level is dependent on Passport Category and filters correctly
- [ ] 6 record types created and assigned to admin
- [ ] Admin can see/edit all fields on the record page
- [ ] Dynamic Forms hide/show guardian, re-issue, and clearance fields correctly
- [ ] Path shows on the record
- [ ] Validation rules enforce on submit but Drafts save freely
- [ ] Smoke test passes
- [ ] Committed to Git

---

## 7. What NOT to do yet
- Do not build objects #2–#11 or the Visa objects — this pass is **only** Object #1.
- Do not add the `PSK_Office__c` lookup until `PSK__c` exists (it will fail).
- Do not wire n8n / Twilio / AI yet — that's a later phase.
- Do not change org-wide security settings beyond setting this object's OWD to Private.

---

*When Object #1 is done and committed, stop and report what was created so we can review before starting Object #2 (PSK Office).*
