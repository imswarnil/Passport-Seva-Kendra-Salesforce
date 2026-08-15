# DATA_MODEL.md — The Streamlined Schema

> Target state. See [SOLUTION.md](SOLUTION.md) for why, [MIGRATION.md](MIGRATION.md) for how we get from here to there.
>
> **The rule:** a field exists only if something *reads* it — an automation, a layout, a validation rule, a report, or a formula. "Might be useful later" is not a reason. Every field below names its reader.

---

## 1. The model at a glance

```
                          ┌───────────────┐
                          │   PSK__c      │  reference data
                          │  (office)     │  Public Read Only
                          └───────┬───────┘
                                  │ lookup
                                  │
  ┌────────────────┐  lookup  ┌───▼─────────────────────┐  lookup   ┌──────────────┐
  │  Citizen__c    │◀─────────│ Passport_Application__c │──────────▶│   Case       │
  │ golden identity│          │      THE SPINE          │           │  (standard)  │
  │  Private       │◀────┐    │       Private           │           │  Private     │
  └────────────────┘     │    └───┬──────────┬──────────┘           └──────────────┘
       guardian ─────────┘        │          │                          App 2
       (self-ish lookup)          │ M-D      │ lookup
                                  │          │
              ┌───────────────────▼──┐   ┌───▼────────────────────┐
              │ Document_Checklist_  │   │ Police_Verification__c │
              │      Item__c         │   │      Private           │
              │  ControlledByParent  │   │      App 3             │
              │      App 1           │   └────────────────────────┘
              └──────────────────────┘
                                  │
                    ┌─────────────┴──────────────┐
                    │ lookup                     │ M-D
            ┌───────▼────────┐          ┌────────▼────────┐
            │  Passport__c   │◀─────────│  Dispatch__c    │
            │   the booklet  │  lookup  │ print + courier │
            │    Private     │          │ ControlledByPrnt│
            │     App 4      │          │     App 4       │
            └────────────────┘          └─────────────────┘
                    │
                    └── Previous_Passport__c (self-lookup)
```

**Eight objects.** Seven custom plus standard `Case`. Down from seventeen custom.

| # | Object | Relationship | OWD | Name | Record types | App |
|---|---|---|---|---|---|---|
| 1 | `Passport_Application__c` | root | Private | Auto `ARN-{000000}` | 5 | 1 → 4 |
| 2 | `Citizen__c` | root | Private | Text | — | 1 |
| 3 | `Document_Checklist_Item__c` | **M-D** → application | ControlledByParent | Auto `DOC-{0000000}` | — | 1 |
| 4 | `Police_Verification__c` | **Lookup** → application | Private | Auto `PV-{00000}` | — | 3 |
| 5 | `Passport__c` | Lookup → application, citizen, office, **self** | Private | Text (booklet no.) | 3 | 4 |
| 6 | `Dispatch__c` | **M-D** → application | ControlledByParent | Auto `DSP-{00000}` | — | 4 |
| 7 | `PSK__c` | root | **Public Read Only** | Text | — | reference |
| 8 | `Case` | standard; lookups to application, passport, citizen | Private | Auto `Case Number` | 4 | 2 |

Plus two custom metadata types, unchanged: `Fee_Matrix__mdt` and `SLA_Config__mdt`.

### Why each relationship is the type it is

This table *is* the relationships lesson.

| Pair | Type | Why not the other one |
|---|---|---|
| Checklist item → application | Master-detail | We want cascade delete (a deleted application must not leave orphan checklist rows), inherited sharing (whoever can see the file can see its documents), and **roll-up summaries** — none of which a lookup gives you. |
| Dispatch → application | Master-detail | Same reasoning. A dispatch has no meaning without its application. |
| Police verification → application | **Lookup** | Deliberately *not* master-detail. A verification report is a police record with its own retention and its own sharing model — it must survive the application and be visible to people who cannot see the file. Master-detail would force `ControlledByParent` and cascade-delete a legal record. |
| Passport → application | Lookup | The booklet outlives the application that produced it. Also, a booklet needs its own OWD so an expired-passport report can be shared differently. |
| Passport → Passport | **Self-lookup** | `Previous_Passport__c` chains re-issues, so you can walk a citizen's booklet history. Teaches self-relationships. |
| Application → Citizen | Lookup | Many applications per citizen over a lifetime; the citizen must not be deleted when an application is. |
| Application → Guardian (Citizen) | Second lookup to the same object | Two lookups to `Citizen__c` from one object — teaches that relationship *names* matter (`Applications` vs `Guarded_Applications`). |
| Case → application | Lookup | A query may reference an application, or none at all. |

---

## 2. `Passport_Application__c` — the spine

**58 fields → 38.** Auto number `ARN-{000000}`, OWD Private, field history on, reports and activities enabled.

### 2.1 Status — 12 values down to 10

```
Draft → Submitted → Document Verification → Police Verification
      → Granting → Printing → Dispatch → Delivered
                   (Rejected · Cancelled are terminal, reachable from anywhere)
```

**Removed:** `Payment Pending` and `Paid`. Payment is a *property* of an application, not a *stage* of it — `Payment_Status__c` already answers "have they paid" and it needs to be answerable at every stage, not just two. Collapsing them removes two stages, two SLA rows, and a whole class of "what if it's Paid but documents aren't verified" ambiguity.

### 2.2 Record types — 6 down to 5

| Record type | Category | Booklet | Validity | PV type | Reason for re-issue |
|---|---|---|---|---|---|
| `Fresh` | Ordinary | 36, 60 | 10, 5 | Pre-PV, Post-PV | — |
| `Re_Issue` | Ordinary | 36, 60 | 10, 5 | No PV, Post-PV | Expiry, Pages Exhausted, Change of Details, **Lost, Damaged** |
| `Tatkal` | Ordinary | 36, 60 | 10, 5 | Post-PV | Expiry, Damaged, Lost |
| `Minor` | Ordinary | 36 | 5 | No PV | — |
| `Diplomatic_Official` | Diplomatic, Official | 60 | 10, 5 | No PV | — |

**Removed:** `Lost_Damaged`. It was a record type whose only distinguishing feature was two picklist values that `Re_Issue` already carries. A lost passport *is* a re-issue with a reason of Lost. This is the record-type lesson in one line: **record types subset picklists; if the subset is the same, it is not a record type.**

### 2.3 Fields

**Group A — Lifecycle (9)**

| Field | Type | Who reads it |
|---|---|---|
| `Status__c` | Picklist, restricted, default Draft | Path, every validation rule, ownership routing, sharing rules |
| `Payment_Status__c` | Picklist (global set `PSK_Payment_Status`) | `Cannot_Grant_With_Pending_Payment` |
| `Submitted_Date__c` | Date/Time | SLA baseline; set by before-update trigger |
| `Stage_Entered_Date__c` | Date/Time | `Days_In_Stage__c`; re-stamped on every status change |
| `Granted_Date__c` | Date/Time | Passport issue date formula |
| `Citizen__c` | Lookup → `Citizen__c` (rel. `Applications`) | Identity; duplicate detection |
| `PSK_Office__c` | Lookup → `PSK__c` | `Place_of_Issue__c` on the booklet; `Region__c` population |
| `Region__c` | Text(40) | **Criteria-based sharing.** Populated by trigger from the office — *not* a formula, because criteria-based sharing can read neither a formula nor a lookup traversal. This field exists purely to work around that platform constraint, and that is exactly why it's worth teaching. |
| `External_Id__c` | Text(40), unique, external ID | Idempotent upsert |

**Group B — The as-submitted declaration (9)**

`First_Name__c`, `Last_Name__c`, `Date_of_Birth__c` (PII), `Gender__c`, `Place_of_Birth__c`, `Mobile__c` (PII), `Email__c`, `Father_Name__c`, `Mother_Name__c`.

> **These are snapshots, not formulas, and that is the design.** A passport application is a legal instrument: what was *declared at submission* is what gets printed, what the police verify against, and what an audit examines. If these read through `Citizen__r`, then the day a citizen corrects a spelling, every historical application silently rewrites itself — destroying the record of what was actually declared. `Citizen__c` answers "who is this person now"; the application answers "what did they declare then". **They are allowed to disagree.**

**Removed:** `Middle_Name__c`, `Spouse_Name__c`, `Marital_Status__c`, `Mobile_For_Alerts__c` (a duplicate of `Mobile__c` that nothing read), `Applicant__c` (a legacy `Account` lookup superseded by `Citizen__c`).

**Group C — Address (4)**

`Address_Line1__c`, `City__c`, `State__c` (global set `Indian_States`), `Pincode__c` (Text 6).
**Removed:** `Address_Line2__c`, `District__c`, `Country__c` (always "India"), `Years_At_Address__c` — PV type is now driven by record type alone, which is simpler and was already how it behaved in practice.

**Group D — Application details (9)**

| Field | Type | Note |
|---|---|---|
| `Passport_Category__c` | Picklist | Ordinary / Diplomatic / Official. **Controlling field.** |
| `Clearance_Level__c` | Dependent picklist | Depends on category. Ordinary → none; Diplomatic → Ambassador, Consular, Minister; Official → Govt Deputation, Delegation. The field-dependency lesson. |
| `Booklet_Pages__c` | Picklist | 36 / 60 — feeds the fee lookup |
| `Validity_Years__c` | Picklist | 10 / 5 — feeds the fee lookup |
| `Tatkal__c` | Checkbox | Selects the Tatkal SLA row; drives the manager sharing rule |
| `Guardian__c` | **Lookup → `Citizen__c`** (rel. `Guarded_Applications`) | Replaces the whole `Family_Member__c` object. A minor's guardian is a citizen — a second lookup to the same object. |
| `Guardian_Consent__c` | Checkbox | Required on submit for minors (DPDP) |
| `Previous_Passport_No__c` / `Previous_Passport_Expiry__c` | Text / Date | Re-issue only; shown by Dynamic Forms |
| `Reason_For_Reissue__c` | Picklist | Now carries Lost and Damaged too |

**Removed:** `Applied_For_Minor__c` and `Guardian_Name__c`. The first duplicated `Is_Minor__c` (a formula off DOB — the system can work out that a 9-year-old is a minor without being told); the second is now the guardian citizen's name, reachable through the lookup. `ECR_Status__c` moves to the booklet, where it is actually printed.

**Group E — Payment (4)** — absorbs the whole `Payment__c` object

`Fee__c` (Currency, written from `Fee_Matrix__mdt` on submit), `Payment_Reference__c`, `Payment_Date__c`, `Payment_Mode__c` (global set).

> `Payment__c` existed to model many payments per application. In practice there is exactly one fee per application, so it was a one-to-one child object — which is four fields wearing an object costume. The moment a real refund or part-payment requirement appears, it earns its object back.

**Group F — Verification & risk (5)** — absorbs `Risk_Flag__c`

`Aadhaar_Verified__c` (Checkbox), `Aadhaar_Token__c` (Text, opaque), `Risk_Score__c` (Number 0–100, drives the high-risk sharing rule), `Risk_Reason__c` (Text 255), `Approval_Status__c` (Picklist: Not Required / Pending / Approved / Rejected).

> **Never store an Aadhaar number.** Only the verified flag and an opaque provider token. Shield Platform Encryption is unavailable on Developer Edition, so `Aadhaar_Token__c` is plain text — which makes the discipline the only control. Field-level security makes it readable but never editable, for every persona including the RPO.

**Group G — Consent (2)** — `Notification_Consent__c`, `Consent_Timestamp__c`. DPDP requires provable consent with a timestamp, not an assumption.

**Group H — Derived, read-only (6)**

| Field | Kind | Definition |
|---|---|---|
| `Applicant_Age__c` | Formula (Number) | `FLOOR((TODAY() - Date_of_Birth__c) / 365.25)` |
| `Is_Minor__c` | Formula (Checkbox) | `Applicant_Age__c < 18` |
| `Days_In_Stage__c` | Formula (Number) | `TODAY() - DATEVALUE(Stage_Entered_Date__c)` |
| `Checklist_Items_Total__c` | **Roll-up summary** | COUNT of `Document_Checklist_Item__c` |
| `Checklist_Items_Verified__c` | **Roll-up summary** | COUNT where `Status__c = Verified` |
| `Open_Objections__c` | **Roll-up summary** | COUNT where `Status__c = Objection Raised` |

> The three roll-ups replace the old `Documents_Verified__c` checkbox — which someone had to remember to tick. A roll-up cannot be wrong. They also require master-detail, which is precisely why the checklist relationship is master-detail. **Removed formula:** `Is_Draft__c`, which saved nobody from typing `ISPICKVAL(Status__c,"Draft")`.

### 2.4 Validation rules — 14 down to 6

Each gated so a `Draft` always saves.

| Rule | Fires when | Enforces |
|---|---|---|
| `Require_Core_Fields_On_Submit` | leaving Draft | First name, last name, DOB, mobile, address line 1 present |
| `Citizen_Required_On_Submit` | leaving Draft | `Citizen__c` populated — every application belongs to an identity |
| `Minor_Needs_Guardian_Consent` | leaving Draft, `Is_Minor__c` | Guardian lookup + consent checkbox set |
| `Cannot_Grant_With_Pending_Payment` | entering Granting | `Payment_Status__c = Paid` |
| `Cannot_Grant_Without_Clearances` | entering Granting | All checklist items verified, no open objections, and PV cleared where the record type requires it |
| `No_Backward_Move_Once_Delivered` | leaving Delivered | Delivered is terminal |

Eight rules were removed as either duplicative, unreachable (guarding fields no persona can edit at that stage), or better expressed as a required field.

---

## 3. `Citizen__c` — golden identity

**21 → 15.** OWD Private. Text name.

`Citizen_Name__c` (record name), `Date_of_Birth__c`, `Age__c` (formula), `Gender__c`, `Mobile__c`, `Email__c`, `City__c`, `State__c`, `Pincode__c`, `Aadhaar_Verified__c`, `Aadhaar_Token__c`, `KYC_Status__c`, `Is_Blacklisted__c`, `Blacklist_Reason__c`, `Preferred_Language__c`, `External_Id__c`.

**Removed:** `Account__c` (legacy — the applicant is not an Account, which is the whole point of this object), `Citizen_Since__c`, `Notes__c`, `Is_Minor__c` (`Age__c` says it), `Consent_Timestamp__c` and `Notification_Consent__c` (consent is given *per application*, not once forever — that is a DPDP point worth being precise about).

**Duplicate rule:** a matching rule on `Date_of_Birth__c` + fuzzy `Citizen_Name__c` + exact `Mobile__c`, set to **block** on create. This is the object that must not fork.

---

## 4. `Document_Checklist_Item__c` — absorbs `Objection__c`

**8 → 10.** Master-detail → application, `ControlledByParent`, auto number `DOC-{0000000}`.

`Document_Type__c` (picklist), `Status__c` (Required → Received → Verified, or Objection Raised), `Received_Date__c`, `Verified_Date__c`, `Objection_Reason__c`, `Objection_Raised_Date__c`, `Objection_Resolved_Date__c`, `Notes__c`, `External_Id__c`.

> **Why `Objection__c` folded in here.** An objection is always *about a specific document* — "your address proof doesn't match", "the photo is the wrong format". Modelling it as a separate object meant an objection could exist unattached to any document, which made "what is actually wrong with this file" a two-object join. Now an objection is a *status* on the thing it objects to, and `Open_Objections__c` rolls straight up to the application. Objections about something other than a document are `Case`s, which is where they belonged all along.

Rows are **generated by automation** on submit, from a per-record-type template — never typed by hand.

---

## 5. `Police_Verification__c` — absorbs the adverse half of `Risk_Flag__c`

**9 → 11.** Lookup → application, OWD Private, auto number `PV-{00000}`.

`PV_Type__c` (Pre-PV / Post-PV), `Status__c` (Pending → In Progress → Cleared / Adverse), `Police_Station__c`, `Verifying_Officer__c` (Lookup → User), `Referred_Date__c`, `Report_Received_Date__c`, `Adverse_Reason__c`, `Severity__c` (global set `PSK_Severity`), `Remarks__c`, `External_Id__c`.

Created by automation when an application enters *Police Verification*, owned by the `Police_Verification` queue until an officer claims it.

---

## 6. `Passport__c` — the booklet

**20 → 16.** Lookups to application, citizen, office, and **itself**. Three record types: `Ordinary`, `Diplomatic`, `Official`.

**Stored facts (its own):** `Passport_Number__c` (record name), `File_Number__c`, `Date_of_Issue__c`, `Date_of_Expiry__c`, `Status__c`, `External_Id__c`, `Previous_Passport__c` (self-lookup), `Application__c`, `Citizen__c`, `PSK_Office__c`.

**Derived by formula (never retyped):** `Holder_Name__c`, `Booklet_Pages__c`, `Validity_Years__c`, `ECR_Status__c`, `Passport_Category__c` from `Application__r`; `Place_of_Issue__c` from `PSK_Office__r.Name`; `Days_To_Expiry__c` from its own expiry date.

> **Snapshot a declaration, derive a fact.** The application snapshots because the declaration must be frozen. The booklet derives because its contents are *consequences* of the application, and a consequence that can drift from its cause is a bug. Knowing which of the two a field is — before you create it — is the single most useful schema instinct in this build.

**Removed:** `Cancellation_Reason__c`, `Remarks__c`, `Is_Expired__c` (`Days_To_Expiry__c < 0` says it), `Validity_Years__c` stored copy.

---

## 7. `Dispatch__c` — absorbs `Print_Job__c`

**16 → 18.** Master-detail → application, `ControlledByParent`, auto number `DSP-{00000}`.

| Milestone | Fields |
|---|---|
| Print | `Print_Batch__c`, `Printed_Date__c`, `Reprint_Reason__c` |
| Validate | `QC_Passed__c` (checkbox), `QC_Date__c`, `QC_Failure_Reason__c` |
| Despatch | `Courier_Partner__c` (global set), `Tracking_Number__c`, `Dispatched_Date__c`, `Expected_Delivery_Date__c` |
| Deliver | `Delivered_Date__c`, `Received_By__c`, `Transit_Days__c` (formula) |
| Context | `Status__c`, `ARN__c` (formula), `Delivery_Address__c` (formula), `Passport__c`, `External_Id__c` |

> **Why one object instead of two.** Print and despatch are consecutive milestones on the same physical booklet, always one-to-one, always handled by the same desk. Two objects meant a join to answer "where is this booklet", and a `Print_Job__c` with no `Dispatch__c` was a state nobody could interpret. A reprint is `Reprint_Reason__c` plus a new print date on the same record — the history lives in field history, which is where history belongs.

`Delivery_Address__c` is a **formula** over the application's address, so a courier label can never drift from the file.

---

## 8. `PSK__c` — office reference data

**14 → 11.** OWD **Public Read Only** — the only object that is not Private, because an office is not personal data and every persona needs to name one.

`Office_Code__c`, `Office_Name__c`, `Region__c` (global set `PSK_Region`), `Address_Line1__c`, `City__c`, `State__c`, `Pincode__c`, `Contact_Number__c`, `Manager__c` (Lookup → User), `Capacity_Per_Day__c`, `Is_Active__c`.

Maintained only by `PSK_Reference_Data_Admin`. Everyone else reads.

---

## 9. `Case` — App 2, standard object

Standard `Case`, four record types, plus five custom fields:

| Record type | What it handles | Typical outcome |
|---|---|---|
| `Status_Enquiry` | "Where is my application?" | Answered and closed; no records created |
| `Detail_Change` | Name change after marriage, address correction, DOB correction | **Spawns a Re-Issue `Passport_Application__c`** |
| `Visa_Enquiry` | Visa questions and requirements | Answered and closed — this is why no `Visa_Application__c` object is needed |
| `Complaint` | Damaged booklet, delivery failure, service complaint | May spawn a re-issue or a fresh dispatch |

**Custom fields:** `Passport_Application__c` (Lookup), `Passport__c` (Lookup), `Citizen__c` (Lookup), `Spawned_Application__c` (Lookup, set when a Case creates an application), `External_Id__c`.

Standard `Case` gives us — for free, and as curriculum Phase 10 — assignment rules, escalation rules, Email-to-Case, auto-response, entitlements and milestones, Omni-Channel, macros and quick text. A `Query__c` custom object would have re-implemented a worse version of each.

---

## 10. The cut list

Ten custom objects removed, 104 custom fields, 26 validation rules. Every one names where its data goes.

| Object | Fields | Verdict | Where it goes |
|---|---|---|---|
| `Payment__c` | 8 | **Delete** | 4 fields on the application. Exactly one payment per application — a 1:1 child is a fieldset, not an object. |
| `Print_Job__c` | 14 | **Delete** | Merged into `Dispatch__c` as the print milestone. |
| `Objection__c` | 8 | **Delete** | Becomes a status + reason on `Document_Checklist_Item__c`; non-document objections become `Case`. |
| `Risk_Flag__c` | 8 | **Delete** | `Risk_Score__c` + `Risk_Reason__c` on the application; adverse-PV detail onto `Police_Verification__c`. |
| `Family_Member__c` | 9 | **Delete** | The only relationship the process needs is guardian-of-a-minor — now a `Guardian__c` lookup to `Citizen__c`. |
| `Notification_Log__c` | 9 | **Delete** | The integration it existed for is out of scope. Returns if n8n is ever built for real. |
| `Renewal__c` | 7 | **Delete** | A renewal *is* a Re-Issue application. Expiry outreach becomes a report over `Passport__c.Days_To_Expiry__c`. |
| `Visa_Application__c` | 26 | **Delete** | Metadata-only MVP with no automation, no persona working it, no journey through it. Visa questions become a `Case` record type in App 2. |
| `Appointment__c` | 7 | **Delete** | Scheduling is out of scope. **Cost: the junction-object concept — see [SOLUTION.md §8](SOLUTION.md).** |
| `Slot__c` | 8 | **Delete** | Same. |
| `OpportunityHistory__c` | 7 | **Delete** | Inherited Service Analytics template. Nothing in PSK reads it. |
| `Reseller_Account_Plan__c` | 5 | **Delete** | Same. |

**Apps:** `PSK_Operations_Console`, `Passport_Validator`, `PSK_Police_Verification_Console` and `Trailhead_Data_Manager` are replaced by the four job-named apps. `Application_Management_Console` is renamed and re-scoped as App 1.

**Also removed:** the `DataManager_*` Apex classes and `waveTemplates/` bundles they serve (this is what fixes the six failing inherited tests), and the `Internal Zone` Experience Cloud residue.

> ⚠️ Deleting `OpportunityHistory__c` and `Reseller_Account_Plan__c` **breaks the Service Analytics dashboards** that shipped with the org. That is accepted — CRM Analytics is out of scope — but it is irreversible and needs explicit sign-off. See [MIGRATION.md](MIGRATION.md).

---

## 11. Before and after

| | Before | After | Change |
|---|---|---|---|
| Custom objects | 17 (+2 inherited) | 7 (+ standard `Case`) | **−12** |
| Custom fields | ~250 | ~135 | **−46%** |
| Validation rules | 62 | ~30 | **−52%** |
| Record types | 9 | 12 (5 application, 3 passport, 4 case) | +3, all load-bearing |
| Custom apps | 5 | 4 | one per job |
| Master-detail pairs | 8 | 2 | enough to teach roll-ups without repetition |
| Roll-up summaries | 1 | 3 | replacing manual checkboxes |
| Standard objects used | 0 | 1 (`Case`) | unlocks all of Phase 10 |
