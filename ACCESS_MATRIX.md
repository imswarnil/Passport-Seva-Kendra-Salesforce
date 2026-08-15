# ACCESS_MATRIX.md — Who Can See and Do What

> Personas in [JOURNEYS.md](JOURNEYS.md), objects in [DATA_MODEL.md](DATA_MODEL.md).
>
> **The mental split that makes all of this make sense:**
> **Profiles and permission sets decide what you can *do*.**
> **OWD, roles and sharing rules decide which records you can *do it to*.**
> They are two independent gates and you need both. A permission set granting Edit on `Passport_Application__c` lets you edit *the applications you can see* — it does not, by itself, let you see a single one.

---

## 1. The five layers, in the order the platform applies them

```
 ┌──────────────────────────────────────────────────────────────────┐
 │ 1. LICENCE            what the org even has                      │
 ├──────────────────────────────────────────────────────────────────┤
 │ 2. PROFILE            one per user · minimum baseline            │
 │    + PERMISSION SETS  additive · one per persona · the real work │
 │      → object CRUD  (can I create an application at all?)        │
 │      → field FLS    (can I see the Aadhaar token?)               │
 │      → record types, apps, tabs, Apex classes                    │
 ├──────────────────────────────────────────────────────────────────┤
 │ 3. ORG-WIDE DEFAULTS  the floor · Private everywhere personal    │
 ├──────────────────────────────────────────────────────────────────┤
 │ 4. ROLE HIERARCHY     vertical roll-up · managers see below them │
 ├──────────────────────────────────────────────────────────────────┤
 │ 5. SHARING RULES      lateral · criteria-based escalation        │
 │    + QUEUES           ownership by team, not by person           │
 │    + MANUAL / APEX    the exceptions                             │
 └──────────────────────────────────────────────────────────────────┘
                    access = (2) AND ( (3) OR (4) OR (5) )
```

**Access is only ever granted, never revoked, by layers 3–5.** There is no "deny" sharing rule. If you need someone to *not* see something they can currently see, you change the OWD, the role, or the criteria — you cannot add a rule that subtracts. Designing from a Private floor upward is the only workable direction, and that is why every object holding personal data starts Private.

---

## 2. Org-wide defaults

| Object | OWD | Grant access using hierarchies | Why |
|---|---|---|---|
| `Passport_Application__c` | **Private** | ✓ | Personal data plus a legal declaration |
| `Citizen__c` | **Private** | ✓ | Identity data — the most sensitive object in the build |
| `Police_Verification__c` | **Private** | ✓ | A police finding; needs its own model, which is why it is a lookup not a master-detail |
| `Passport__c` | **Private** | ✓ | A legal document |
| `Case` | **Private** | ✓ | Carries applicant contact details |
| `Document_Checklist_Item__c` | **Controlled by Parent** | — | Master-detail. Whoever can see the file sees its documents. Not a choice — master-detail forces it |
| `Dispatch__c` | **Controlled by Parent** | — | Same |
| `PSK__c` | **Public Read Only** | ✓ | An office address is not personal data, and every persona must be able to name one |

> **`Controlled by Parent` is not laziness.** A master-detail child *cannot* have its own OWD — that is part of what you buy when you choose master-detail over lookup, alongside cascade delete and roll-up summaries. If a child genuinely needs independent sharing, that is the signal to make it a lookup. `Police_Verification__c` is exactly that case, and it is the reason it is modelled the way it is.

---

## 3. Role hierarchy

Six roles, down from eleven. A role earns its place only if someone above it genuinely needs to see the records below.

```
CEO_and_Admins
└── Regional_Passport_Officer          Meenal — approvals, escalations, oversight
    ├── Passport_Office_Manager        (operational cover; sees all desks below)
    │   ├── Front_Office               Priya · Kavya
    │   ├── Verification_Team          Anjali · Suresh
    │   └── Fulfilment_Team            Vikram · Farhan
    └── Audit_And_Compliance           Deepak — deliberately a sibling, not a subordinate
```

**Removed:** `Passport_Processing_Team`, `Document_Verification`, `Police_Verification_Team`, `Granting_Officers`, `Help_Desk_Support`, `Visa_Processing_Team`. Six roles collapsed into three teams, because a role only matters if the hierarchy roll-up is doing work — and a role with one person under it whose records nobody above needs is pure overhead.

**Why Audit is a sibling of the RPO, not below her:** if Deepak sat under Meenal, Meenal would inherit visibility of everything Deepak owns. He owns nothing, so that would be harmless — but it would also imply he *reports* to the person he audits, and the hierarchy is read by humans too. His broad visibility comes from `viewAllRecords` on his permission set, not from where he sits.

---

## 4. The object access matrix

**C**reate · **R**ead · **E**dit · **D**elete · **V**iew All · — none

| Object | Front Office | Doc Verif | Help Desk | Police Verif | Granting | Fulfilment | RPO | Audit |
|---|---|---|---|---|---|---|---|---|
| `Citizen__c` | **CRE** | R | R | R | R | — | CRE**V** | R**V** |
| `Passport_Application__c` | **CRE** | R | R | RE | RE | R | CRE**V** | R**V** |
| `Document_Checklist_Item__c` | R | **CRED** | — | — | R | — | CRED | R**V** |
| `Police_Verification__c` | — | — | — | **CRE** | R | — | CRE**V** | R**V** |
| `Passport__c` | — | — | R | — | **CRE** | RE | CRE**V** | R**V** |
| `Dispatch__c` | — | — | R | — | R | **CRED** | CRED | R**V** |
| `PSK__c` | R | R | R | R | R | R | CRE | R**V** |
| `Case` | R | — | **CRED** | — | R | R | CRED**V** | R**V** |

**Bold** marks the object each persona *owns* — the one their job is defined by.

### The deliberate refusals

Each of these is a design decision, not a gap:

| Nobody has | Because |
|---|---|
| **`modifyAllRecords` on anything** — including the RPO | `viewAllRecords` lets you oversee. `modifyAllRecords` lets you silently rewrite outside the sharing model, which destroys the audit trail's meaning. Seniority is not a reason to bypass the model. |
| **Delete on `Passport_Application__c`** except in Draft | Enforced twice: no `allowDelete` in any persona's permission set, *and* a `before delete` trigger that vetoes past Draft. Belt and braces, because a deleted application takes its checklist and dispatch with it via cascade. |
| **Delete on `Passport__c`** | A booklet is cancelled, never deleted. `before delete` calls `addError()` unconditionally. |
| **Delete on `Police_Verification__c`** | A police finding is a record of fact. This is also why it is a lookup — master-detail would let an application delete cascade over it. |
| **Any create/edit/delete for Audit** | Compliance review and data correction are structurally separated. He cannot fix even an obvious typo — he raises it with someone who can. |

---

## 5. Field-level security — the PII layer

Object access says *whether* you can open a record. FLS says *what you see inside it*. They are configured separately, and treating them as one thing is the mistake this section exists to prevent.

| Field | Front Office | Doc Verif | Help Desk | Police Verif | Granting | Fulfilment | RPO | Audit |
|---|---|---|---|---|---|---|---|---|
| `Aadhaar_Verified__c` | R/E | R | — | R | R | — | R | R |
| `Aadhaar_Token__c` | R | R | **hidden** | R | R | **hidden** | R | R |
| `Date_of_Birth__c` | R/E | R | R | R | R | — | R | R |
| `Mobile__c` | R/E | R | R | R | R | — | R | R |
| `Risk_Score__c` | — | R | — | R | R | — | R/E | R |
| `Risk_Reason__c` | — | R | — | R/E | R | — | R/E | R |
| `Fee__c` | R | — | R | — | R | — | R/E | R |

**Three rules that hold without exception:**

1. **`Aadhaar_Token__c` is read-only for every persona, including the RPO.** It is written once by the KYC integration and never by a human. Nobody's seniority makes editing an identity token appropriate.
2. **Fulfilment and Help Desk cannot see the token at all.** A courier desk does not need an identity token to print a label; a phone agent does not need one to read out a status. Least privilege applied at the field, not just the object.
3. **The Aadhaar *number* is not a field.** It does not exist anywhere in the schema. Only the verified flag and the opaque token. Shield Platform Encryption is unavailable on Developer Edition, so `Aadhaar_Token__c` is plain text — which makes the discipline the only control there is, and therefore load-bearing.

---

## 6. Record type visibility

| Record type | Front Office | Doc Verif | Help Desk | Granting | Fulfilment | RPO |
|---|---|---|---|---|---|---|
| `Fresh` / `Re_Issue` / `Tatkal` / `Minor` | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| `Diplomatic_Official` | **✗** | ✓ | **✗** | ✓ | ✓ | ✓ |

A counter officer cannot start a diplomatic application — that intake happens through a different channel entirely. Fulfilment *can* see it, because a diplomatic booklet still needs printing and posting like any other.

---

## 7. Queues

Four work queues plus one approval queue. Down from six.

| Queue | Object | Fed by | Worked by |
|---|---|---|---|
| `Document_Verification` | `Passport_Application__c` | Trigger, on entering Document Verification | Doc Verification Officer |
| `Police_Verification` | `Police_Verification__c` | Trigger, on record creation | Police Verification Officer |
| `Printing_And_Dispatch` | `Dispatch__c` | Trigger, on entering Printing | Fulfilment Officer |
| `Support` | `Case` | Case assignment rules, by record type | Help Desk Agent |
| `RPO_Approvals` | `Passport_Application__c` | Approval process | RPO role + subordinates |

**Removed:** `Granting` (a criteria-based sharing rule on `Status__c` does the job without an ownership change), `Objections` and `Risk_Review` (both objects are gone).

> **Why a queue rather than assigning to a person.** A queue is *ownership by a team*. The record sits in it until someone claims it, which means it has a measurable depth, it survives someone's leave, and "who is responsible right now" has a truthful answer. Round-robin assignment to individuals produces a worse version of this with a hidden failure mode: work assigned to someone who is not there.

---

## 8. Criteria-based sharing rules

Six, down from nine. Each answers "who needs to see this that the hierarchy would not already show it to".

| Object | Rule | Criteria | Shared to | Access |
|---|---|---|---|---|
| `Passport_Application__c` | `Tatkal_To_Managers` | `Tatkal__c = true` | `PSK_Managers` | Edit |
| `Passport_Application__c` | `Diplomatic_To_RPO` | `Passport_Category__c` ∈ Diplomatic, Official | `Regional_Passport_Officer` | Edit |
| `Passport_Application__c` | `Granting_Stage_To_Fulfilment` | `Status__c` ∈ Granting, Printing, Dispatch, Delivered | `Fulfilment_Team` role+sub | Edit |
| `Passport_Application__c` | `High_Risk_To_Verification` | `Risk_Score__c > 70` | `Verification_Team` role+sub | Read |
| `Citizen__c` | `Blacklisted_To_Managers` | `Is_Blacklisted__c = true` | `PSK_Managers` | Edit |
| `Police_Verification__c` | `Adverse_To_Managers` | `Status__c = Adverse` | `PSK_Managers` | Edit |

**Public groups (3, down from 6):** `PSK_All_Staff`, `PSK_Managers`, `PSK_Auditors` — each a `roleAndSubordinates` with `doesIncludeBosses`.

### Two platform constraints that shaped the design

These are worth learning precisely, because both push back on the obvious design:

1. **Criteria-based sharing cannot read a formula field.** So no rule can filter on `Is_Minor__c` or `Days_In_Stage__c`, however natural that would be. Anything a sharing rule filters on must be a *stored* field.
2. **Criteria-based sharing cannot traverse a lookup.** You cannot write `PSK_Office__r.Region__c`. This is why `Region__c` exists as a real Text field on the application, populated by a before-update trigger from the office — and why it deliberately is **not** a formula, which would fail constraint (1) as well.

> This pair is the most useful "the platform said no" lesson in the build. The naive design — a formula that reaches through the office lookup — fails for two independent reasons, and the fix is a stored field maintained by automation. Recognising that shape early saves a lot of rework.

**Escalation is a query, not an action.** Nobody has to *remember* to escalate a Tatkal file or an adverse verification. The record matches criteria; the manager sees it. Escalation that depends on someone deciding to escalate is the thing these rules exist to replace.

---

## 9. Permission sets and groups

Eight persona sets, down from nine, plus one admin catch-all.

| Permission set | Persona | Assigned with role |
|---|---|---|
| `PSK_Front_Office` | Priya | `Front_Office` |
| `PSK_Document_Verification` | Anjali | `Verification_Team` |
| `PSK_Help_Desk` | Kavya | `Front_Office` |
| `PSK_Police_Verification` | Suresh | `Verification_Team` |
| `PSK_Granting_Officer` | Vikram | `Fulfilment_Team` |
| `PSK_Fulfilment_Officer` | Farhan | `Fulfilment_Team` |
| `PSK_Office_Manager` | Meenal | `Regional_Passport_Officer` |
| `PSK_Auditor_Read_Only` | Deepak | `Audit_And_Compliance` |
| `PSK_Reference_Data_Admin` | admin | — |

**Permission set groups** compose them for humans who wear two hats:

| Group | Contains | For |
|---|---|---|
| `PSK_Counter_Staff` | Front Office + Help Desk | A small office where one person does both |
| `PSK_Back_Office` | Granting + Fulfilment | Where the same desk authorises and despatches |
| `PSK_Manager` | Office Manager + Auditor read | An RPO who also needs the audit view |

> **Why permission set groups and not more permission sets.** A group is a *composition*, so `PSK_Front_Office` stays the single definition of what a front office officer can do — fix it once and every group containing it is fixed. Building `PSK_Front_Office_Plus_Help_Desk` as a ninth set means the front-office permissions now exist in two places, and they will diverge. **Never put a permission directly into a group** — a group holds only sets.
>
> Muting permission sets exist for the case where a group grants something you need to take back within that group only. This build has no such case, deliberately: if you need to mute, the component sets are usually wrong.

**Profiles carry almost nothing.** One lean base profile — login hours, password policy, and the standard objects everyone needs — and everything else is a permission set. A user has exactly one profile forever; they can have any number of permission sets, assigned and removed as their job changes. Building personas as profiles is the single most common Salesforce security mistake, because it forces a clone per combination and a clone is a copy that stops being true the moment the original changes.

---

## 10. Approval — the one human gate

Detailed in [AUTOMATION.md §5](AUTOMATION.md). Its access consequences:

| Aspect | Design | Why |
|---|---|---|
| Approver | `RPO_Approvals` **queue** (role + subordinates) | A named approver is a single point of failure — their leave stops every diplomatic passport |
| Record lock | Locked while pending | Nobody edits a file mid-decision |
| Submitter | Automatic, on entering Granting | Removes "someone forgot to submit it" as a failure mode |
| Enforcement | `Diplomatic_Official_Requires_Approval` validation rule blocks Printing | The approval and the block are separate mechanisms, so neither alone can be bypassed |
| Record | Approver, timestamp and comments in the approval history | This is the whole point — a validation rule can block, but it cannot record *who decided* |

---

## 11. How to verify this is actually true

A matrix in a document is a claim. These are the checks that make it a fact — and they are what [TESTING.md](TESTING.md) automates.

1. **Login-as each persona** and attempt the operations in [JOURNEYS.md §3](JOURNEYS.md). Every ✓ must work; every — must fail.
2. **Attempt the refusals explicitly.** Try to delete a Submitted application as the RPO. Try to edit `Aadhaar_Token__c` as anyone. Try to view a diplomatic application as Front Office. A security model is only proven by what it *stops*.
3. **Apex tests using `System.runAs()`** for the record-visibility assertions — the only way to test sharing, since a test running as the default user sees everything.
4. **Check FLS in code**, not just in Setup: service classes run `with sharing` and queries use `WITH USER_MODE`, so a field a persona cannot see is not silently returned by Apex behind their back.
5. **`viewAllRecords` audit** — confirm it is granted only where §4 says, and `modifyAllRecords` nowhere at all.

> **Known drift to fix during the rebuild:** the current org has `Aadhaar_Token__c` fully editable on four permission sets, which contradicts §5.1. That is exactly the kind of gap that a documented matrix plus an automated check catches, and an undocumented intention does not.
