# DEMO_DATA.md — Scenario Design

> **The problem with the current demo data:** 162 applications, 71 passports, 94 appointments — and not one of them tells a story. There is no deliberately rejected file to look at, no adverse police report, no diplomatic passport waiting on approval. Volume without scenarios.
>
> **The fix:** 24 named scenarios, each a deliberate combination of choices that exercises a specific path. Every branch in [JOURNEYS.md §5](JOURNEYS.md) has at least one record sitting in it, permanently, so you can *open* it.

---

## 1. Design principles

1. **Every scenario has a name and a reason.** Not "Application 47" — "Ramesh, Tatkal, delivered on time". If you cannot say what a record demonstrates, it should not exist.
2. **Failure paths are first-class.** The rejected file, the adverse verification, the QC failure and the abandoned draft are the *interesting* records. A demo where everything works proves nothing about the controls.
3. **Records rest at every stage.** The dashboard should never show an empty stage. Some applications are deliberately frozen mid-flow so each stage, queue and sharing rule has something in it.
4. **Idempotent generation.** `PSK_DemoDataGenerator` matches on `External_Id__c` and upserts. Running it twice changes nothing. Running it after a schema change fixes drift.
5. **No real personal data.** Plausible Indian names, `+91-9XXXXXXXXX` numbers in a reserved range, `demo.invalid` email domains, and `Aadhaar_Token__c` values that are obviously synthetic (`TOKEN-DEMO-0001`). PII discipline applies to fake data too — because fake data has a way of becoming a habit.
6. **Deterministic dates.** Everything is relative to the run date (`TODAY() - 45`, not a hard-coded 2024 date). This is precisely the bug that makes the six inherited Trailhead tests fail today, and it is not being repeated.

---

## 2. The permutation space

Seven independent dimensions. The full cross-product is thousands of combinations; we need the ones that are *behaviourally distinct*.

| Dimension | Values | Distinct outcomes |
|---|---|---|
| Record type | Fresh · Re-Issue · Tatkal · Minor · Diplomatic/Official | 5 |
| Applicant | Adult · Minor (guardian required) | 2 |
| Payment | Paid · Not Paid | 2 |
| Documents | All verified · Objection raised · Objection resolved | 3 |
| Police verification | Not required · Cleared · Adverse · Pending | 4 |
| Approval | Not required · Pending · Approved · Rejected | 4 |
| Fulfilment | Printed clean · QC failed then reprinted · In transit · Delivered | 4 |

**Which combinations matter.** Most of the cross-product is either impossible (a Minor record type forces No PV, so *Minor × Adverse PV* cannot exist) or behaviourally identical (Fresh-36-page and Fresh-60-page differ only in the fee, which one record proves). What remains is **24 scenarios** that between them touch every validation rule, every sharing rule, every trigger branch and every approval outcome.

---

## 3. The 24 scenarios

**A — The happy paths.** One clean run per record type, so each fee row, checklist template and PV route is proven.

| # | Citizen | Record type | Rests at | Proves |
|---|---|---|---|---|
| A1 | Ramesh Iyer, 34 | Tatkal | **Delivered** | The full lifecycle end to end; Tatkal SLA met; the manager sharing rule |
| A2 | Sunita Rao, 41 | Fresh | **Delivered** | Fresh with Pre-PV; 60-page/10-year fee row |
| A3 | Arjun Nair, 29 | Re-Issue | **Delivered** | Re-issue on expiry; `Previous_Passport__c` self-lookup chained to A2's booklet |
| A4 | Aarav Deshmukh, 9 | Minor | **Delivered** | Guardian lookup + consent; forced 36-page/5-year/No PV; App 3 skipped entirely |
| A5 | Amb. Nalini Sharma, 55 | Diplomatic/Official | **Delivered** | Approval sought, granted, and printed only after |

**B — Records resting at every stage.** So no stage, queue or dashboard tile is ever empty.

| # | Citizen | Record type | Rests at | Proves |
|---|---|---|---|---|
| B1 | Farida Sheikh, 26 | Fresh | **Draft** — half-filled, no last name | Validation rules are gated: an incomplete record saves cleanly |
| B2 | Manoj Kulkarni, 38 | Fresh | **Submitted**, unpaid | Checklist generated on submit; `Payment_Status__c = Not Paid` |
| B3 | Priyanka Joshi, 31 | Re-Issue | **Document Verification** | Sitting in the queue, unclaimed — queue depth is non-zero |
| B4 | Ganesh Pillai, 47 | Fresh | **Document Verification** | Claimed by Anjali; 3 of 5 items verified — roll-ups mid-count |
| B5 | Rakesh Verma, 35 | Fresh | **Police Verification** | PV record created and unclaimed in its queue |
| B6 | Latha Menon, 44 | Tatkal | **Police Verification** | Claimed by Suresh, in progress; Tatkal urgency visible to him |
| B7 | Imran Qureshi, 52 | Fresh | **Granting** | All clearances green, awaiting the granting officer |
| B8 | Dr. Vikas Rane, 49 | Diplomatic/Official | **Granting**, approval **Pending** | The record is *locked*; blocked from Printing; sitting in `RPO_Approvals` |
| B9 | Shalini Bose, 33 | Fresh | **Printing** | Booklet minted, dispatch created, not yet printed |
| B10 | Ajay Thakur, 28 | Re-Issue | **Dispatch** | Printed and QC-passed, courier booked, in transit |

**C — Failure and recovery paths.** The scenarios worth actually clicking into.

| # | Citizen | Situation | Rests at | Proves |
|---|---|---|---|---|
| C1 | Deepa Krishnan, 37 | Address proof pincode doesn't match the declaration | **Doc Verification**, 1 open objection | `Open_Objections__c` roll-up blocks advancement; the objection names a *specific document* |
| C2 | Nikhil Sawant, 30 | Same, then resolved | **Police Verification** | Objection raised → resolved → file advances. The recovery path, not just the failure |
| C3 | Sameer Khan, 40 | Applicant unknown at the declared address | **Rejected** | Adverse PV halts the file; `Adverse_To_Managers` sharing fires; `Severity__c = High` |
| C4 | Rohit Patil, 45 | Adverse PV, RPO overrode after review | **Granting** | Managerial override exists, is recorded, and is attributable |
| C5 | Meera Iyer, 39 | Diplomatic grant **rejected** by the RPO | **Granting**, approval Rejected | The approval process can say no, with a comment, and the file goes back |
| C6 | Suresh Reddy, 43 | Booklet failed QC — misprinted page | **Printing**, reprint pending | `QC_Passed__c = false`, `Reprint_Reason__c` set, looped back on the same record |
| C7 | Kavita Deshpande, 36 | Reprinted and shipped after a QC failure | **Delivered** | Field history shows two print dates on one record — "why did this take two attempts" is answerable |
| C8 | Anand Gowda, 50 | Risk score 82 from a data mismatch | **Doc Verification** | `High_Risk_To_Verification` sharing fires at >70 |
| C9 | *(blacklisted)* Vinod Malhotra, 48 | `Is_Blacklisted__c` on the citizen | **Submitted**, flagged | `Blacklisted_To_Managers` fires on `Citizen__c`, not on the application |
| C10 | Pooja Shetty, 27 | Never returned with documents | **Draft**, 90 days old | The abandoned draft — a valid, saveable, permanently incomplete record |
| C11 | Harish Nambiar, 34 | Tatkal that missed its SLA | **Granting**, 9 days in stage | `SLA_Config__mdt` Tatkal row breached; visible on the dashboard |

**D — App 2, Support.** One Case per record type, since the Case journey is its own lifecycle.

| # | Who | Record type | Outcome | Proves |
|---|---|---|---|---|
| D1 | Ramesh Iyer (A1) | `Status_Enquiry` | Closed, no records created | The commonest Case: a question, answered |
| D2 | Sunita Rao (A2) | `Detail_Change` — name change after marriage | **Spawned a Re-Issue application** | Case → application, linked by `Spawned_Application__c` |
| D3 | Walk-in, no application | `Visa_Enquiry` | Closed with a canned response | Why there is no `Visa_Application__c` object — the demand was information |
| D4 | Ajay Thakur (B10) | `Complaint` — booklet arrived damaged | Escalated, unresolved | Escalation rules fire on a timer, not on someone remembering |

---

## 4. Coverage check

Does the set actually exercise everything? This table is the acceptance test for the scenario design itself.

| Must be exercised | By |
|---|---|
| All 5 application record types | A1–A5 |
| All 10 status values | B1–B10, C3 (Rejected), C10 (Draft) |
| All 4 Case record types | D1–D4 |
| Every fee row in `Fee_Matrix__mdt` | A1–A5 across booklet/validity combinations |
| Both Tatkal and normal SLA rows | A1, B6, C11 vs the rest |
| Every checklist template | A1–A5, one per record type |
| Roll-up mid-count (not 0, not complete) | B4 |
| Objection raised **and** resolved | C1, C2 |
| PV: not required / pending / cleared / adverse | A4 / B5 / A1 / C3 |
| Approval: pending / approved / rejected | B8 / A5 / C5 |
| QC failure and reprint | C6, C7 |
| All 6 criteria-based sharing rules | A1 (Tatkal), A5 (Diplomatic), B7 (Granting stage), C8 (High risk), C9 (Blacklisted), C3 (Adverse) |
| All 5 queues non-empty | B3, B5, B9, B8, D4 |
| Guardian lookup on `Citizen__c` | A4 |
| `Previous_Passport__c` self-lookup | A3 → A2's booklet |
| Every validation rule *triggerable* | B1, B2, C1, C3, B8 |
| Field history with a visible trail | C7 |
| Idempotency guards | Re-running the generator changes nothing |

**Not exercised, and deliberately so:** the notification platform event (no n8n instance), and anything requiring an Experience Cloud licence. Both are out of scope per [SOLUTION.md §7](SOLUTION.md).

---

## 5. Volume

| Object | Records | Note |
|---|---|---|
| `PSK__c` | 4 | One per region — reference data, seeded first |
| `Citizen__c` | 30 | 24 applicants + 4 guardians + 2 blacklisted |
| `Passport_Application__c` | 24 | One per scenario |
| `Document_Checklist_Item__c` | ~110 | 4–6 per submitted application, from the templates |
| `Police_Verification__c` | 11 | Only where the record type requires one |
| `Passport__c` | 9 | Only granted files |
| `Dispatch__c` | 9 | One per booklet |
| `Case` | 4 | D1–D4 |
| **Total** | **~200** | Down from ~700 |

**A third of the data, and all of the meaning.** Two hundred records is small enough to read in a list view, which is what makes it a demo rather than a dataset.

---

## 6. How it is generated

`PSK_DemoDataGenerator`, rewritten against the new schema.

```bash
sf apex run --file scripts/apex/seed-demo-data.apex     # idempotent — safe to re-run
sf apex run --file scripts/apex/reset-demo-data.apex    # deletes only External_Id__c LIKE 'DEMO-%'
```

**Six requirements on the generator:**

1. **Idempotent.** Upsert on `External_Id__c`, never blind insert. Every demo record's external ID starts `DEMO-` so the reset script can find exactly them and nothing else.
2. **Bulk-safe.** One DML per object, in dependency order. It is the same code path the real triggers use, so if the generator hits a governor limit, that is a real bug in the automation, not a test-harness problem.
3. **Automation on, not suppressed.** The generator drives records through `PSK_ApplicationService.advance()` rather than writing end states directly. A booklet that appears because the trigger minted it proves something; a booklet inserted directly proves nothing.
4. **Dates relative to run date.** No literals. `Submitted_Date__c = TODAY() - 45`.
5. **Ownership assigned to the right personas.** Records rest with the user or queue that would really hold them, so logging in as a persona shows a realistic desk.
6. **Reversible.** The reset script scopes strictly to `DEMO-%`. It must never be capable of deleting a record a human created.
