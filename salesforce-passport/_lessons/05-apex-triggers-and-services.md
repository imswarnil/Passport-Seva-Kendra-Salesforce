---
number: 5
title: "Apex Triggers and the Service Layer Pattern"
description: >-
  One trigger per object, no logic in it, and a service layer underneath. The four reasons that shape beats the alternative, and the idempotency guard that stops duplicate passports.
concept: Apex Architecture
you_will_learn:
  - "Why a trigger file should contain almost no logic at all"
  - "Why logic gets pulled out of the trigger handler into a shared service class"
  - "How to write bulk-safe Apex, and why a bypass guard is non-negotiable"
---

Every Salesforce codebase eventually answers the same question: where does a piece of business logic actually live? Get this wrong and you end up with the same rule implemented twice — once in a trigger, once in a button — quietly drifting out of sync. PSK's Apex layer answers it with a three-tier split: trigger, handler, service. Reading the real files in order shows exactly why each tier exists.

## Tier one: the trigger does almost nothing

Here is the entire trigger file for `Passport_Application__c`:

<div class="code-caption">force-app/main/default/triggers/PassportApplicationTrigger.trigger</div>

```apex
/**
 * All Passport_Application__c automation. Logic lives in
 * PassportApplicationTriggerHandler -- keep this file a pure dispatcher.
 */
trigger PassportApplicationTrigger on Passport_Application__c (
    before insert, before update, after insert, after update
) {
    if (Trigger.isBefore) {
        if (Trigger.isInsert) {
            PassportApplicationTriggerHandler.beforeInsert(Trigger.new);
        } else if (Trigger.isUpdate) {
            PassportApplicationTriggerHandler.beforeUpdate(Trigger.new, Trigger.oldMap);
        }
    } else {
        if (Trigger.isInsert) {
            PassportApplicationTriggerHandler.afterInsert(Trigger.new);
        } else if (Trigger.isUpdate) {
            PassportApplicationTriggerHandler.afterUpdate(Trigger.new, Trigger.oldMap);
        }
    }
}
```

That's it. No field-stamping, no queries, no conditionals about what status means what — just a routing table from trigger context (`before insert`, `after update`, and so on) to a method with a matching name. This is the "thin trigger, fat handler" pattern, and the reason for it is almost entirely about testability and control flow, not style. A trigger body can't be unit-tested in isolation the way a class method can, and a Salesforce object can only have automation running through this one entry point cleanly if that entry point does one job: figure out *which* handler method applies, and call it. Every actual decision — what a status transition means, what gets stamped, what gets created — happens somewhere you can call directly from a test without inserting a record through DML.

## Tier two: the handler owns the trigger-shaped decisions

`PassportApplicationTriggerHandler` is where "what should happen on before-insert" lives. Its own header comment describes the job:

<div class="code-caption">force-app/main/default/classes/PassportApplicationTriggerHandler.cls</div>

```apex
/**
 * Handler for PassportApplicationTrigger.
 *
 * Responsibilities
 *  - stamp Submitted_Date__c / Stage_Entered_Date__c / Granted_Date__c
 *  - copy snapshot fields from the linked Citizen__c, but ONLY when blank, so the
 *    as-submitted snapshot is never overwritten by later citizen edits
 *  - denormalise PSK_Office__r.Region__c onto Region__c so criteria-based
 *    sharing rules (which cannot traverse a lookup) have something to match on
 *  ...
 * Everything short-circuits on PSK_AutomationControl.bypassTriggers so the demo
 * data generator can own child records deterministically.
 */
public with sharing class PassportApplicationTriggerHandler {

    public static void beforeInsert(List<Passport_Application__c> newList) {
        if (PSK_AutomationControl.isBypassed()) {
            return;
        }
        PSK_ApplicationService.ensureCitizens(newList);
        PSK_ApplicationService.copyFromCitizenWhenBlank(newList);
        PSK_ApplicationService.applyRegionFromOffice(newList, null);
        stampDates(newList, null);
        PSK_ApplicationService.applyFees(newList, null);
        applyDefaults(newList);
        PSK_ApplicationService.routeOwnership(newList, null);
    }
```

Notice something: most of the calls inside `beforeInsert` aren't methods defined in this class at all — they're calls out to `PSK_ApplicationService`. The handler keeps only two things that are genuinely specific to *being a trigger*: `stampDates` (which needs `Trigger.oldMap` to compare a record's new status against its prior one) and `applyDefaults` (defensive field defaults so records survive validation rules). Everything else — fee calculation, region denormalisation, citizen matching, queue routing — is pulled one level further out.

## Tier three: why a service class, and not just more handler methods

`PSK_ApplicationService` is where that logic actually lives, and its own header comment states the reason directly:

<div class="code-caption">force-app/main/default/classes/PSK_ApplicationService.cls</div>

```apex
/**
 * Shared domain logic for Passport_Application__c.
 *
 * Both PassportApplicationTriggerHandler and the @AuraEnabled controllers
 * (PSK_FeeService, PSK_PassportIssuanceController) delegate here so that a fee
 * calculated by a button matches a fee calculated by the trigger, and a passport
 * issued from the UI is identical to one issued by the status transition.
 */
public with sharing class PSK_ApplicationService {
```

This is the whole argument for a service layer in one sentence. A trigger fires when a record saves — but a Lightning button, a `PSK_ApplicationActionsController.advance()` call, or a future integration also needs to compute a fee or issue a passport, and it needs to compute the *same* fee and issue the *same kind of* passport. If `resolveFee()` or `issuePassports()` were private methods buried in the trigger handler, the button's controller would either have to duplicate that logic or find some awkward way to fire a fake trigger context. Instead, both callers — the trigger handler and the `@AuraEnabled` controllers — call the same static methods on `PSK_ApplicationService`. One implementation, two callers, and the fee a Granting Officer sees when they click "Collect Payment" is guaranteed to match the fee the trigger would have computed if the record had saved through the standard flow.

## Bulk safety: one query for the whole batch

Salesforce triggers always fire on a list of records — a single save, a data import of thousands, a bulk API job — and the platform enforces a hard governor limit on how many SOQL queries a transaction can issue. Writing a query inside a `for` loop is the single most common way new Salesforce developers blow that limit, and PSK's service methods are written specifically to avoid it. `applyRegionFromOffice` is a clean example:

```apex
public static void applyRegionFromOffice(List<Passport_Application__c> apps,
                                         Map<Id, Passport_Application__c> oldMap) {
    Set<Id> officeIds = new Set<Id>();
    for (Passport_Application__c app : apps) {
        if (app.PSK_Office__c == null) {
            continue;
        }
        if (needsRegionRefresh(app, oldMap)) {
            officeIds.add(app.PSK_Office__c);
        }
    }
    if (officeIds.isEmpty()) {
        return;
    }
    Map<Id, PSK__c> offices = new Map<Id, PSK__c>([
        SELECT Id, Region__c FROM PSK__c WHERE Id IN :officeIds
    ]);

    for (Passport_Application__c app : apps) {
        if (app.PSK_Office__c == null || !needsRegionRefresh(app, oldMap)) {
            continue;
        }
        PSK__c office = offices.get(app.PSK_Office__c);
        if (office == null || String.isBlank(office.Region__c)) {
            continue;
        }
        app.Region__c = office.Region__c;
    }
}
```

The shape is always the same, and it's worth internalizing as a template: loop once to collect every Id you'll need (`officeIds`), issue exactly one query against that whole set (`WHERE Id IN :officeIds`), build a map keyed by Id, then loop a second time to apply the results. Whether the trigger fires on 1 record or 2,000, this method issues exactly one SOQL query. `seedChecklistItems` does the identical two-pass shape against `Document_Checklist_Item__c`, and `issuePassports` does it three times over — once for existing `Passport__c` records, once for existing `Print_Job__c` records, once for prior-passport lookups by number — specifically so a bulk grant of hundreds of applications at once doesn't multiply queries per record.

## The bypass guard: giving bulk loads an escape hatch

Every one of the handler's entry points opens with the same check:

<div class="code-caption">force-app/main/default/classes/PSK_AutomationControl.cls</div>

```apex
/**
 * Transaction-scoped kill switches for PSK trigger automation.
 *
 * The demo data generator sets {@code bypassTriggers = true} so that it can own
 * child-record creation deterministically instead of racing the
 * PassportApplicationTriggerHandler. Always restore the previous value in a
 * finally block -- statics survive for the whole transaction.
 */
public with sharing class PSK_AutomationControl {

    public static Boolean bypassTriggers = false;

    public static Boolean isBypassed() {
        return bypassTriggers == true;
    }
}
```

This matters because automation and bulk data operations are frequently at odds. `PassportApplicationTriggerHandler.beforeInsert` will happily match-or-create a `Citizen__c`, denormalise a region, and route ownership to a queue — exactly what you want when a real officer submits one application through the UI. But PSK's own demo data generator needs to insert hundreds of applications with specific, pre-decided citizens, offices, and stages, in a specific order, without the trigger racing it or silently overwriting a value the generator just set. Rather than write a second, parallel code path for "loading data," the generator just sets `PSK_AutomationControl.bypassTriggers = true` before its DML and resets it after — every handler method returns on line one, and the generator takes over responsibilities the trigger would normally own. `PSK_AutomationControl` also carries a narrower guard, `inPaymentRollup`, so that when `PaymentTriggerHandler` updates the parent application's payment total, the application handler doesn't re-run logic that would just redo work already in flight — the same idea (stop a specific piece of automation from firing) at a finer grain than the all-or-nothing bypass.

## The real question trigger architecture is answering

Strip away the ceremony and this whole layered structure is answering one plain question, over and over, for every rule you write: *where does this logic need to live so it runs exactly once, at the right moment, for the right reason, and produces the same answer no matter who's asking?* A trigger file answers "which lifecycle event am I in." A handler answers "what does this specific object's lifecycle require." A service class answers "what is this business rule, independent of who's invoking it." None of it is a mysterious framework — it's just discipline about not letting the same fee calculation live in two places that can quietly disagree.

<div class="pull-quote">A trigger's only job is to know which method to call — everything else belongs somewhere that isn't a trigger.</div>
