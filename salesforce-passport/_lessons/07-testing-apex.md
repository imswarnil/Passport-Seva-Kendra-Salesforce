---
number: 7
title: "Testing Apex: Bulk-Safe, Deterministic, No Org Dependency"
description: >-
  Tests that would fail if you deleted the code they cover: bulk-safe, deterministic, and with no dependency on whatever happens to be in the org.
concept: Apex Testing
you_will_learn:
  - "Why Apex tests build their own data with a shared factory instead of querying whatever's already in the org"
  - "What a bulk-safe test actually proves, and why 'avoid SOQL/DML in a for loop' is more than an interview cliché"
  - "Why some values in test data have to be deterministic, and what breaks in CI when they aren't"
---

Salesforce forces a discipline on you that a lot of other platforms don't: you cannot deploy Apex to production without test coverage, and every test has to pass **in the org**, not on your laptop. That single constraint — tests run against a real, multi-tenant, governor-limited runtime — shapes almost everything about how good Apex tests are written. The Passport Seva Kendra (PSK) build has a shared factory class, `PSK_TestDataFactory`, whose job is entirely about making that constraint tractable. Reading it is a better lesson in Apex testing than most tutorials, because every choice in it is a direct answer to something that actually went wrong.

## Tests build their own world

The first line of `PSK_TestDataFactory.cls` states its own rule out loud:

<div class="code-caption">force-app/main/default/classes/PSK_TestDataFactory.cls</div>
```apex
/**
 * Shared test-data builders for the PSK unit tests.
 *
 * Every builder produces records that already satisfy the validation rules on
 * Passport_Application__c -- Require_Core_Fields_On_Submit,
 * Minor_Needs_Guardian_Consent and Cannot_Grant_With_Pending_Payment -- so a test
 * can insert directly at any status without a setup dance.
 *
 * Unit tests must NOT call PSK_DemoDataGenerator: that class writes ~1,200 rows
 * and exists for populating a real org, not for test isolation.
 */
@IsTest
public class PSK_TestDataFactory {
```

Notice what it explicitly forbids: calling the demo data generator that seeds a realistic-looking org for a walkthrough. That might look like a shortcut — the data already exists, why not reuse it? Because "whatever happens to already be in the org" is not a fixed thing. By default, Apex tests can't even see org data unless you opt in with `@IsTest(SeeAllData=true)` — and PSK doesn't. But the deeper reason is about repeatability: a test that passes today because someone happened to seed three `Fresh` applications, and fails next month because someone deleted them, isn't testing your code — it's testing the current contents of a database that changes for reasons that have nothing to do with your Apex. A real test class has to be self-contained: given a clean, empty test database (which is what every Apex test method actually gets — DML in tests is invisible to other transactions), it builds exactly the records it needs, asserts against them, and needs nothing else.

That's what every method in `PSK_TestDataFactory` does. `buildApplication(String status)` doesn't just create a barebones `Passport_Application__c` — the comment above it says it produces a record that "already satisfies the validation rules," because those rules (`Require_Core_Fields_On_Submit`, `Minor_Needs_Guardian_Consent`, `Cannot_Grant_With_Pending_Payment`) fire for every insert, test or not. A factory that skipped them would force every single test method to hand-roll the same boilerplate just to get past validation before it could test anything else.

## What a bulk-safe test actually proves

"Avoid SOQL or DML inside a for loop" is the single most-quoted Apex interview answer, and it's usually recited without anyone showing what it looks like to actually verify. Here's the real thing, from `PassportApplicationTriggerHandlerTest.cls`:

<div class="code-caption">force-app/main/default/classes/PassportApplicationTriggerHandlerTest.cls</div>
```apex
// ----------------------------------------------------------------- Bulk safe

@IsTest
static void testBulkInsertIsSafe() {
    List<Passport_Application__c> apps = new List<Passport_Application__c>();
    for (Integer i = 0; i < 50; i++) {
        Passport_Application__c app = PSK_TestDataFactory.buildApplication(
            PSK_Constants.ALL_STATUSES[Math.mod(i, PSK_Constants.ALL_STATUSES.size())]);
        app.Fee__c = null;
        apps.add(app);
    }

    Test.startTest();
    insert apps;
    Test.stopTest();

    System.assertEquals(50, [SELECT COUNT() FROM Passport_Application__c],
        'All 50 applications should insert in one DML');
    System.assertEquals(0, [
        SELECT COUNT() FROM Passport_Application__c WHERE Fee__c = NULL
    ], 'Every application should have a fee stamped');
    System.assertEquals(0, [
        SELECT COUNT() FROM Passport_Application__c WHERE Citizen__c = NULL
    ], 'Every application should have a citizen');
}
```

Read that carefully, because the shape is the entire point. It builds 50 applications *in memory* first — one list — and only then does a single `insert apps;`. That single statement is what "bulk" means here: it forces `PassportApplicationTrigger` to process all 50 records in one trigger invocation, exactly the way a real data load, an API batch upsert, or a Data Loader import would hit it. If the trigger handler (or, worse, the service class underneath it) had a SOQL query or a DML statement sitting inside a per-record loop, this is exactly the test that would blow up — not with a wrong answer, but with `System.LimitException: Too many SOQL queries: 101`, because Salesforce caps you at 100 synchronous SOQL queries and 150 DML statements per transaction, no matter how patient you are.

But notice the test isn't just checking "did it not crash." It asserts on *behavior*: every one of the 50 records should have `Fee__c` populated (proving `PSK_ApplicationService.resolveFee()` ran for every row, not just the first one some naive implementation might have handled) and every one should have a `Citizen__c` populated (proving the trigger's citizen-backfill logic is bulk-aware too). A bulk test that only checks the row count is a weak test — the real risk in bulk-unsafe code usually isn't "it throws an exception," it's "it silently only processes the first record and nobody notices in a five-row demo."

The companion test, `testBulkUpdateIsSafe`, does the same thing for an update path — 50 Draft applications flipped to Submitted in one `update apps;` — and asserts every single one got `Submitted_Date__c` stamped, "with no per-row SOQL," as the assertion message says directly.

## Determinism: the bug this actually caught

The trickiest kind of test bug isn't the one that fails every time — it's the one that fails *sometimes*, because it depends on something that varies between runs: the current time, a random number, or the order two things happen to execute in. Salesforce makes this worse than most platforms, because **Apex test methods in the same class run in parallel, in separate transactions, by default.** That single platform fact is the reason for this comment in the factory:

<div class="code-caption">force-app/main/default/classes/PSK_TestDataFactory.cls</div>
```apex
/**
 * Apex test methods in one class run in PARALLEL transactions. The builders
 * below stamp unique External_Id__c / Payment_Reference__c / Office_Code__c
 * values, and a plain 1,2,3... counter restarts at 1 in every method -- so two
 * methods racing each other insert the same unique key and the loser fails
 * with an opaque row-level DML error rather than a duplicate-value message.
 * Seeding the counter's namespace per transaction removes the collision.
 */
private static final String RUN =
    String.valueOf(Math.abs(Crypto.getRandomInteger())).right(7).leftPad(7, '0');
```

This is a real, already-fixed bug, not a hypothetical — the commit that took the suite from 21 failures to 188/188 green lists it plainly among the causes: **"Test factory external ids collided because Apex test methods run in parallel and the counter restarted per method."** Picture what that looked like before the fix: `buildApplication()` in one test method stamps `External_Id__c = 'TEST-APP-1'` because its local counter starts at 1; a completely unrelated test method, running at the same moment in its own parallel transaction, does the same thing and also produces `'TEST-APP-1'`. Every field on `Passport_Application__c` carries a `Unique, External ID` constraint (PSK.md §3, "every object carries an `External_Id__c`... so integration upserts are idempotent"), so one of those two inserts fails — not with a message that says "these two test methods collided," but with an opaque duplicate-value DML error that looks, to whoever's debugging it, like a completely unrelated failure. Worse, it's *flaky*: it only shows up when the org's test-parallelization scheduler happens to run those two methods at overlapping moments, so the same class can pass on one run and fail on the next with zero code changes.

The fix is the `RUN` constant above: a random seven-digit string, generated fresh in each transaction, that every key in that transaction is built from. It's not there to make test data look realistic — it's there so two parallel transactions can never independently generate the same key. This is worth sitting with as a general principle: **randomness and determinism aren't opposites in test data, they solve different problems.** A random `RUN` prefix guarantees uniqueness *across* parallel transactions. A deterministic, sequential counter (`nextSeq()`) inside that transaction guarantees predictability *within* it, so two builder calls in the same test method never collide with each other either. You want randomness at the boundary where independent processes could clash, and determinism everywhere you actually need to reason about what the code produced.

## The takeaway

None of this is exotic Apex — it's ordinary list-building and string math. What makes it a real testing discipline is that every piece of it exists because something specific broke first: tests that depended on org state that changed, a trigger that would have silently mishandled anything past record one, and a counter that raced itself across parallel transactions. Good Apex tests aren't written from a checklist; they're written by someone who has already been burned by the thing the test now prevents.

<div class="pull-quote">A test that only passes when it runs alone was never really testing anything.</div>
