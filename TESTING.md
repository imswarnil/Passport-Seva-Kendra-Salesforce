# TESTING.md — Test Strategy and Automation Requirements

> **Status: requirements, not implementation.** This is Phase 8 of the build sequence in [SOLUTION.md §9](SOLUTION.md) — written now so that everything built in Phases 2–7 is built to be testable, and implemented last.
>
> Scenarios come from [DEMO_DATA.md](DEMO_DATA.md); the access claims under test come from [ACCESS_MATRIX.md](ACCESS_MATRIX.md).

---

## 1. What "tested" means here

Salesforce requires 75% Apex coverage to deploy. That number is a deployment gate, not a quality bar — and it is trivially satisfiable by code that calls every line and asserts nothing.

**This build's bar is different: every test asserts an outcome a user would notice.**

| Not a test | A test |
|---|---|
| `advance(app);` — line covered | `advance(app);` then `Assert.areEqual(1, [SELECT COUNT() FROM Passport__c WHERE Application__c = :app.Id])` |
| "the trigger ran" | "exactly one booklet was minted, and re-running minted no second one" |
| "the validation rule exists" | "saving with an unpaid fee throws `DmlException` with the expected message" |
| 92% coverage | Every branch in [AUTOMATION.md §3.2](AUTOMATION.md) has a test that fails if you delete the branch |

**The mutation-test instinct:** for each test, ask "if I deleted the code this covers, would this test fail?" If not, it is coverage, not a test.

---

## 2. The five layers

```
 ┌──────────────────────────────────────────────────────────────┐
 │ 5 · NARRATED END-TO-END      the whole org, telling a story  │  ← the headline
 ├──────────────────────────────────────────────────────────────┤
 │ 4 · PERSONA ACCESS           System.runAs · what's refused   │
 ├──────────────────────────────────────────────────────────────┤
 │ 3 · UI            LWC Jest · Flow tests                      │
 ├──────────────────────────────────────────────────────────────┤
 │ 2 · INTEGRATION   trigger → handler → service, via real DML  │
 ├──────────────────────────────────────────────────────────────┤
 │ 1 · UNIT          service methods in isolation               │
 └──────────────────────────────────────────────────────────────┘
```

### Layer 1 — Unit

Service methods called directly, no DML where avoidable.

- `PSK_FeeServiceTest` — every row of `Fee_Matrix__mdt` resolves; an unmatched combination raises a specific error rather than returning zero.
- `PSK_SlaServiceTest` — normal and Tatkal targets per stage; breach arithmetic at the boundary (exactly on target is not a breach).
- `PSK_RoutingServiceTest` — each status maps to the right queue; an unmapped status leaves ownership untouched rather than nulling it.
- `PSK_ConstantsTest` — every constant matches a real picklist value in the schema. **This one catches a whole class of bug**: a picklist value renamed in Setup while the Apex constant still compiles happily against the stale string.

### Layer 2 — Integration

The trigger path, exercised by real DML — the layer that proves [AUTOMATION.md §3.2](AUTOMATION.md).

**Required tests, one per transition:**

| Test | Asserts |
|---|---|
| `submitGeneratesChecklist` | N rows created, matching the record-type template; `Fee__c` written; `Submitted_Date__c` stamped |
| `submitIsIdempotent` | Re-saving a Submitted application creates **no** second set of checklist rows |
| `docVerificationRoutesToQueue` | `OwnerId` becomes the `Document_Verification` queue Id |
| `pvCreatedOnce` | One `Police_Verification__c`; advancing again creates no second |
| `minorSkipsPv` | A Minor record type never creates a PV record |
| `grantingMintsBooklet` | Exactly one `Passport__c`; every formula field resolves; `Date_of_Expiry__c` = issue + validity |
| `printingCreatesDispatch` | One `Dispatch__c`, owned by the fulfilment queue |
| `deliveredIsTerminal` | Moving back from Delivered throws |
| `qcFailureLoopsBack` | `QC_Passed__c = false` sets the reprint reason and returns status to Printing, **on the same record** |
| `adversePvHaltsApplication` | Application does not advance; the reason is stamped |
| `diplomaticSubmitsForApproval` | `Approval_Status__c = Pending`; the record is locked; Printing is blocked |
| `stageDateReStamps` | `Stage_Entered_Date__c` changes on every status transition and only then |
| `rollupsReflectChecklist` | Verifying an item increments `Checklist_Items_Verified__c` on the parent |

**Bulk safety — mandatory, not optional.** Every one of the above runs a second time with **200 records in one DML**. A trigger that passes single-record and fails at 200 is a trigger that passes your test and fails the data load. This is the discipline the whole handler/service pattern exists to make possible.

```apex
@IsTest
static void submitGeneratesChecklistInBulk() {
    List<Passport_Application__c> apps = PSK_TestFactory.applications(200, 'Fresh');
    Test.startTest();
    PSK_ApplicationService.submit(apps);      // ONE call, 200 records
    Test.stopTest();
    Assert.areEqual(200 * 5, [SELECT COUNT() FROM Document_Checklist_Item__c]);
    Assert.isTrue(Limits.getQueries() < Limits.getLimitQueries() / 2,
                  'query count must not scale with record count');
}
```

That last assertion is the one that matters: it fails if someone puts a SOQL call inside a loop, even though the functional assertion above it would still pass.

### Layer 3 — UI

**Flow tests** (native, in Flow Builder) — given an input record, assert the outcome:
- The intake screen flow creates exactly one application with the right record type.
- The Case → application spawn creates the Re-Issue and back-links `Spawned_Application__c`.
- The before-save normalisation flow upper-cases the pincode and trims the names.

**LWC Jest tests** — rendering and events without a browser:
- The checklist component renders one row per item and fires its "all verified" event exactly once.
- The home dashboard renders stage counts from wired data and handles the empty state without throwing.
- The risk meter renders the right band at the 70 boundary — at 70, below, and above.

### Layer 4 — Persona access

**The layer most builds skip, and the one that proves the security model.** [ACCESS_MATRIX.md](ACCESS_MATRIX.md) is a claim until this exists.

`System.runAs()` is the only way to test sharing, because a test running as the default context sees everything.

```apex
@IsTest
static void frontOfficeCannotSeeDiplomaticApplication() {
    User priya = PSK_TestFactory.persona('PSK_Front_Office');
    Id dipId = PSK_TestFactory.application('Diplomatic_Official').Id;
    Test.startTest();
    System.runAs(priya) {
        Assert.areEqual(0,
            [SELECT COUNT() FROM Passport_Application__c WHERE Id = :dipId],
            'Front Office must not see diplomatic applications');
    }
    Test.stopTest();
}
```

**Required — the refusals.** A security model is proven by what it *stops*, so each of these must be a test that passes because an operation **failed**:

| Must be refused | Persona |
|---|---|
| Delete a Submitted application | every persona, including RPO |
| Delete any `Passport__c` | every persona |
| Delete any `Police_Verification__c` | every persona |
| Edit `Aadhaar_Token__c` | every persona |
| Read `Aadhaar_Token__c` at all | Fulfilment, Help Desk |
| See a Diplomatic/Official application | Front Office, Help Desk |
| Grant with `Payment_Status__c ≠ Paid` | Granting Officer |
| Grant with an open objection or uncleared PV | Granting Officer |
| Reach Printing on an unapproved diplomatic file | Granting Officer |
| Create or edit anything at all | Auditor |
| Hold `modifyAllRecords` | **every persona** — asserted directly against `PermissionSet` metadata |

**Required — the grants.** Each ✓ in the matrix has a positive test: the criteria-based sharing rules genuinely deliver the record. `Tatkal__c = true` → a manager can query it. `Risk_Score__c = 82` → the verification team can. `Status__c = Adverse` → managers can.

### Layer 5 — Narrated end-to-end

The headline deliverable, and the answer to *"show and illustrate what's happening in my org"*.

**What it is:** a single command that drives one application from Draft to Delivered through the real UI, as the real personas, logging in and out as each — and produces a human-readable artefact of what happened at every step.

**Why through the UI and not Apex.** An Apex test proves the *logic* works. It cannot prove that Priya can actually find the Submit button, that the Dynamic Form reveals the guardian fields when it should, that the Path renders, that the record page is assigned to the record type, or that a persona's tab is even visible in their app. Those are the failures that make a demo fall over, and they are invisible to `sf apex run test`.

**Requirements:**

| # | Requirement |
|---|---|
| E1 | Drives the **real org** (`psk-dev`) through a browser, not a mock |
| E2 | Logs in as each persona in turn, using the credentials each stage requires — the handoffs are part of what is under test |
| E3 | Covers the full main line: [JOURNEYS.md §3](JOURNEYS.md) steps 1–27 |
| E4 | Covers at least four alternate journeys: objection→recovery, adverse PV, diplomatic approval, QC failure→reprint |
| E5 | **Asserts at each step** — the status is what it should be, the child record exists, the button is present, the blocked action is genuinely blocked |
| E6 | **Screenshots each stage**, captioned with what just happened and why |
| E7 | Emits a **narrated timeline** — step, actor, action, records touched, assertion result — as Markdown |
| E8 | That timeline is published to the [course site](salesforce-passport/) as living proof the build works |
| E9 | Self-cleaning: creates its own data with a `E2E-` external ID prefix and removes exactly that on exit |
| E10 | Runs unattended in one command and exits non-zero on any failed assertion |
| E11 | Failure output names the step, the expected state and the actual state — never just a stack trace |

**Suggested shape** (implementation decision deferred to Phase 8): a Node harness under `scripts/e2e/`, driving the org with a browser automation library, reading its scenario definitions from the same source as `PSK_DemoDataGenerator` so the two can never disagree about what a scenario is.

**The output is a deliverable, not a log.** A page showing eight screenshots — the counter form, the generated checklist, the queue, the adverse report, the locked approval, the minted booklet, the courier record, the delivered file — each captioned with the concept it demonstrates, is simultaneously the test report *and* the best explanation of the system that exists.

---

## 3. Test data

**`PSK_TestFactory`** — one class, and no test may query org data.

```apex
PSK_TestFactory.citizen()                       // minimal valid citizen
PSK_TestFactory.application('Tatkal')           // valid Draft of a record type
PSK_TestFactory.applications(200, 'Fresh')      // bulk
PSK_TestFactory.submitted('Fresh')              // already past Draft, checklist generated
PSK_TestFactory.persona('PSK_Front_Office')     // user + role + permission set assigned
PSK_TestFactory.office()                        // a PSK__c to reference
```

**Rules:**
- `@IsTest(SeeAllData=false)` everywhere. A test that depends on org data passes locally and fails in a fresh org — which is the one place it matters.
- Custom metadata (`Fee_Matrix__mdt`, `SLA_Config__mdt`) is the exception: it is *deployed* metadata, visible in tests without `SeeAllData`, and tests should use the real rows rather than mocking them. If a fee row is wrong, the test should say so.
- `@TestSetup` for shared fixtures, so setup runs once per class rather than once per method.
- Personas are created by the factory with their real role and permission set, so `System.runAs` tests the actual configuration rather than an approximation of it.

---

## 4. Running it

```bash
# Apex — layers 1, 2, 4
sf apex run test --test-level RunLocalTests --result-format human --code-coverage

# One class while iterating
sf apex run test --class-names PSK_ApplicationServiceTest --result-format human

# LWC Jest — layer 3
npm run test:unit

# Flow tests — layer 3, in Flow Builder or:
sf flow test run

# Narrated end-to-end — layer 5
npm run test:e2e            # → reports/e2e/timeline.md + reports/e2e/screenshots/
```

**Targets:**

| Metric | Target | Rationale |
|---|---|---|
| Apex coverage | ≥85% | Above the 75% gate, because the gate is not the goal |
| Assertion density | ≥1 meaningful assert per test method | Coverage without assertions proves nothing |
| Bulk tests | Every trigger path, at 200 records | The failure mode single-record tests cannot see |
| Persona refusal tests | Every ✗ and every "nobody has" in [ACCESS_MATRIX.md](ACCESS_MATRIX.md) | The security model is only proven by what it stops |
| Inherited template test failures | **0** | The six `DataManager_*` failures disappear when that metadata is deleted in Phase 1 |
| E2E | Green, unattended, with a published timeline | The proof that ships |

---

## 5. Definition of done for the test suite

1. `sf apex run test --test-level RunLocalTests` is **fully green** — no known-failing tests, no exceptions carried forward. (Today six inherited Trailhead/Wave tests fail on a hard-coded date; [MIGRATION.md](MIGRATION.md) deletes that metadata rather than fixing it, because nothing in PSK reads it.)
2. Every transition in [AUTOMATION.md §3.2](AUTOMATION.md) has a test that fails if the branch is deleted.
3. Every ✗ in [ACCESS_MATRIX.md §4](ACCESS_MATRIX.md) has a test that passes because the operation was refused.
4. Every scenario in [DEMO_DATA.md §3](DEMO_DATA.md) is reachable by the generator without manual intervention.
5. The narrated E2E run produces a timeline and screenshots, published to the course site.
6. The whole suite runs from a **fresh org** — deploy, seed, test — with no manual Setup steps except the two documented in [MIGRATION.md](MIGRATION.md) that metadata genuinely cannot express.
