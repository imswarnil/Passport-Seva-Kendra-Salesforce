---
number: 8
title: "Config as Data: Custom Metadata Types Instead of Hardcoded Constants"
description: >-
  Fee tables and SLA targets as custom metadata rather than Apex string literals, so changing a fee is a deploy of a record instead of a code change.
concept: Custom Metadata Types
you_will_learn:
  - "What a Custom Metadata Type actually is, and why it deploys instead of loading like data"
  - "Why 'the passport fee is 1500' belongs in a metadata record, not a number typed into Apex"
  - "A general rule for deciding whether a value belongs in code or in a Custom Metadata Type"
---

Every Salesforce org ends up needing some table of business rules that isn't really "data" in the CRM sense — nobody is going to run a report on it, no user is ever going to open it from a related list on an Account. A fee schedule. A set of SLA targets per stage. A list of which countries require a visa on arrival. The question is where that table should live, and the wrong answer — the one almost every beginner reaches for first — is to just write the numbers straight into Apex. PSK's `Fee_Matrix__mdt` is the concrete example of doing it the right way instead, and reading the Apex that consumes it shows exactly why the difference matters.

## Custom Metadata Type vs. Custom Object: not the same kind of thing

A Custom Object (like `Passport_Application__c`) holds **data**. Rows in it are created and edited by users clicking around the UI, or by Apex running DML — `insert`, `update`, `delete`. Data in a Custom Object is *runtime state*: it changes constantly, it isn't tracked in version control, and two different sandboxes or orgs will have completely different rows in the same object.

A Custom Metadata Type is different in a way that's easy to state and easy to underestimate: **its records are metadata, not data.** `Fee_Matrix__mdt`'s own object definition says so directly:

<div class="code-caption">force-app/main/default/objects/Fee_Matrix__mdt/Fee_Matrix__mdt.object-meta.xml</div>
```xml
<?xml version="1.0" encoding="UTF-8"?>
<CustomObject xmlns="http://soap.sforce.com/2006/04/metadata">
    <description>Statutory fee table. Drives Fee__c on the application so amounts are configuration rather than hard-coded Apex. Money fields are Number because custom metadata types do not support the Currency type.</description>
    <label>Fee Matrix</label>
    <pluralLabel>Fee Matrix</pluralLabel>
    <visibility>Public</visibility>
</CustomObject>
```

That last line of the description is a small, telling detail: Custom Metadata Types don't even support the `Currency` field type, because they're not meant to hold transactional amounts — they're meant to hold *configuration*, and Salesforce's tooling treats them accordingly. Each record isn't a row you `insert` with DML; it's a file, checked into the repo, deployed with the exact same `sf project deploy start` command you'd use to push a class or a field. Here's one real record in full:

<div class="code-caption">force-app/main/default/customMetadata/Fee_Matrix.Fresh_36_10.md-meta.xml</div>
```xml
<?xml version="1.0" encoding="UTF-8"?>
<CustomMetadata xmlns="http://soap.sforce.com/2006/04/metadata" xmlns:xsd="http://www.w3.org/2001/XMLSchema" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
    <label>Fresh - 36 pages - 10 years</label>
    <protected>false</protected>
    <values>
        <field>Application_Type__c</field>
        <value xsi:type="xsd:string">Fresh</value>
    </values>
    <values>
        <field>Booklet_Pages__c</field>
        <value xsi:type="xsd:double">36</value>
    </values>
    <values>
        <field>Validity_Years__c</field>
        <value xsi:type="xsd:double">10</value>
    </values>
    <values>
        <field>Base_Fee__c</field>
        <value xsi:type="xsd:double">1500.0</value>
    </values>
    <values>
        <field>Tatkal_Surcharge__c</field>
        <value xsi:type="xsd:double">2000.0</value>
    </values>
    <values>
        <field>Additional_Booklet_Fee__c</field>
        <value xsi:type="xsd:double">0.0</value>
    </values>
    <values>
        <field>Is_Active__c</field>
        <value xsi:type="xsd:boolean">true</value>
    </values>
</CustomMetadata>
```

That's a file at `force-app/main/default/customMetadata/Fee_Matrix.Fresh_36_10.md-meta.xml`. It has a path. It shows up in `git diff`. Someone reviewing a pull request that changes `1500.0` to `1700.0` sees exactly that change, with a commit message, an author, and a timestamp, the same as they would for a change to a trigger. Compare that to what happens when a fee lives as a row in an ordinary Custom Object: an admin edits it inline from a list view, the number changes in production at 4:47pm on a Tuesday, and the only record of that change is whatever Field History Tracking happens to be turned on for that field, if any. One of those is a change reviewable by a colleague before it ships. The other is a silent runtime edit that nobody signed off on.

## What hardcoding would have looked like, and why it's worse

Imagine `PSK_ApplicationService.resolveFee()` had been written the "quick" way — a chain of `if` statements with the numbers typed straight in:

```apex
// what it does NOT do
if (applicationType == 'Fresh' && pages == 36 && years == 10) {
    return 1500;
}
```

That compiles fine and works fine, right up until the Passport Seva Kendra genuinely raises its Fresh-36-page-10-year fee to ₹1700. Now changing a *government-set fee schedule* — which in the real world changes on a notification, not a whim — requires editing an Apex class, running the Apex test suite, and pushing a full deployment through whatever release process the org uses, just to change one number nobody would call "logic." Worse, that fee schedule has ten combinations (record type × booklet pages × validity years, per PSK.md §6.2), so a hardcoded version is ten `if` branches an unlucky future developer has to scroll through and hope they matched a typo-free literal to the right business case. There's no single place to look at "the fee schedule" as a table — it's smeared across conditional logic.

Here's what the real `resolveFee()` does instead — it treats the fee schedule as *data to search*, not *logic to branch on*:

<div class="code-caption">force-app/main/default/classes/PSK_ApplicationService.cls</div>
```apex
/**
 * Resolve the fee for a type / pages / validity combination. Widens the match
 * progressively so a combination with no exact Fee_Matrix__mdt row (for
 * example Diplomatic_Official with a 36-page book) still produces a number.
 */
public static FeeBreakdown resolveFee(String applicationType, Decimal pages,
                                      Decimal validityYears, Boolean tatkal) {
    // ...
    for (Fee_Matrix__mdt row : feeMatrix()) {
        if (row.Application_Type__c != applicationType) {
            continue;
        }
        // ... exact match on pages + validity, falling back to same-pages,
        // then same-type, before finally defaulting.
    }
    // ...
}
```

And `feeMatrix()` itself pulls every row with an ordinary SOQL query, exactly as if it were reading a Custom Object — except it's reading configuration, not a table someone could accidentally delete a row from in production:

<div class="code-caption">force-app/main/default/classes/PSK_ApplicationService.cls</div>
```apex
private static List<Fee_Matrix__mdt> feeMatrixCache;

private static List<Fee_Matrix__mdt> feeMatrix() {
    if (feeMatrixCache == null) {
        feeMatrixCache = [
            SELECT Application_Type__c, Booklet_Pages__c, Validity_Years__c,
                   Base_Fee__c, Tatkal_Surcharge__c, Additional_Booklet_Fee__c
            FROM Fee_Matrix__mdt
            // ...
        ];
    }
    return feeMatrixCache;
}
```

Notice too that `resolveFee()` doesn't just do an exact lookup and give up if nothing matches — it progressively widens the search (exact match, then same-pages, then same-type, then a synthetic default) specifically so a combination the fee table doesn't cover yet, like a Diplomatic/Official application on a 36-page book, still returns a sane number instead of a null that would silently break checkout. That's a level of defensive design that's much easier to justify when the underlying source is a queryable, structured table rather than a pile of `if` statements you'd have to re-derive the same fallback behavior into by hand.

Change the fee now, and the change is: edit one `.md-meta.xml` file (or its value in Setup, which round-trips back to the same file on retrieve), deploy it, done. No Apex touched, no test suite at risk of unrelated breakage, and a one-line diff a reviewer can actually read.

## SLA_Config__mdt: the same pattern, a different axis

PSK doesn't stop at fees. `SLA_Config__mdt` — "per-stage service level targets," 26 records, a normal and a Tatkal variant for each of the thirteen processing stages — governs when a work item counts as breaching its SLA and shows up flagged on the work-queue component. Exactly the same reasoning applies: "Document Verification normally gets 24 hours, but a Tatkal file only gets 4" is a policy a business owner sets and revisits, not a fact about how Apex is supposed to behave. Hardcoding thirteen pairs of hour thresholds into a controller class would create the identical problem the fee matrix avoids — a policy question buried inside code that only an engineer can safely touch.

## The general rule

PSK.md states the underlying principle for `Fee_Matrix__mdt` directly: *"changing a fee is a metadata deploy, not a code change — which is the point."* Generalize that one sentence and you get a rule you can apply to almost any value you're about to type into Apex:

**If a business person might reasonably ask you to change this number without touching code, it belongs in a Custom Metadata Type, not a constant.**

A validation threshold, a fee, an SLA target, a list of active regions, a feature toggle scoped to a subset of users — all of these are configuration a non-engineer might legitimately want changed on a Tuesday afternoon. Put them in a Custom Metadata Type, and that Tuesday-afternoon change becomes a small, reviewable, deployable file instead of a support ticket that lands on an engineer's desk.

<div class="pull-quote">If it's a business rule someone could ask you to change, it belongs in metadata — not buried in an if-statement.</div>
