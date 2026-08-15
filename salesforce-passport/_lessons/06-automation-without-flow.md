---
number: 6
title: "Automation Without Assignment Rules or Flow: Queue Routing and Approval Processes"
description: >-
  Configure before you code — and knowing exactly where that stops. Queue routing, approval processes, and the order of execution that explains most automation bugs.
concept: Declarative Automation
you_will_learn:
  - "What a Queue actually is, and how it differs from a Public Group"
  - "How this app replaces Assignment Rules — a Lead/Case-only feature — with a one-line Apex map lookup"
  - "The real limitation that forces role-based approval routing through a Queue instead of a Role directly"
---

Salesforce ships a feature called Assignment Rules that auto-routes new records to the right owner — but it only exists for Leads and Cases. Custom objects like `Passport_Application__c` don't get it. PSK needed the same outcome — "when this record enters a stage, hand it to whoever works that stage" — without a Lead or Case in sight, and the real code shows how that gets built from two more primitive pieces: Queues and a plain Apex map.

## What a Queue actually is

A Queue is a special kind of owner. Where a Public Group exists purely to grant *sharing* — visibility into records someone doesn't own — a Queue is something a record can actually be assigned *to* as its `OwnerId`, and any member of that queue can then "take" the record and become its individual owner. It's Salesforce's built-in model for a shared inbox of work: nobody personally owns the item until someone picks it up.

Here's a real one:

<div class="code-caption">force-app/main/default/queues/Document_Verification.queue-meta.xml</div>

```xml
<?xml version="1.0" encoding="UTF-8"?>
<Queue xmlns="http://soap.sforce.com/2006/04/metadata">
    <doesIncludeBosses>true</doesIncludeBosses>
    <doesSendEmailToMembers>false</doesSendEmailToMembers>
    <name>Document Verification</name>
    <queueMembers>
        <roleAndSubordinates>
            <roleAndSubordinate>Document_Verification</roleAndSubordinate>
        </roleAndSubordinates>
        <users>
            <user>admin@passportoffice.com</user>
        </users>
    </queueMembers>
    <queueSobject>
        <sobjectType>Passport_Application__c</sobjectType>
    </queueSobject>
</Queue>
```

Its membership is a role (`Document_Verification`, plus subordinates) rather than a hand-picked list of users, which matters for the same reason role hierarchies exist at all: whoever holds that role automatically gets the queue's work without anyone having to remember to update a membership list when staff change. `queueSobject` scopes which object this queue can even hold records for — a queue is wired to specific objects, not generic.

## Replacing Assignment Rules with a one-line map lookup

The actual routing decision — which queue a given application should move to — is deliberately boring. It's a single static map:

<div class="code-caption">force-app/main/default/classes/PSK_Constants.cls</div>

```apex
/**
 * Queue DeveloperName a Passport_Application__c should be auto-assigned to
 * when it enters that Status. Statuses not present here (Draft, Submitted,
 * Payment Pending, Paid, and the terminal statuses) keep whoever owns them --
 * that is front-office / applicant-facing work, not a specialist queue.
 * Keep in step with force-app/main/default/queues/*.queue-meta.xml.
 */
public static final Map<String, String> APPLICATION_STAGE_QUEUE =
    new Map<String, String>{
        STATUS_DOC_VERIFICATION => 'Document_Verification',
        STATUS_POLICE_VERIFICATION => 'Police_Verification',
        STATUS_GRANTING => 'Granting',
        STATUS_PRINTING => 'Printing_And_Dispatch',
        STATUS_DISPATCH => 'Printing_And_Dispatch'
    };
```

And the method that reads it, `PSK_ApplicationService.routeOwnership()`, with its own reasoning written directly into the doc comment:

<div class="code-caption">force-app/main/default/classes/PSK_ApplicationService.cls</div>

```apex
/**
 * Auto-assign OwnerId to the specialist queue for the stage a record is
 * entering, replacing manual assignment rules. Only fires on the transition
 * INTO a stage that has a queue (see PSK_Constants.APPLICATION_STAGE_QUEUE),
 * so an officer who has already picked up a record out of the queue keeps it
 * until the record's status moves again -- this never fights a manual
 * reassignment mid-stage.
 */
public static void routeOwnership(List<Passport_Application__c> newList,
                                  Map<Id, Passport_Application__c> oldMap) {
    for (Passport_Application__c app : newList) {
        String priorStatus = (oldMap != null && app.Id != null && oldMap.containsKey(app.Id))
            ? oldMap.get(app.Id).Status__c : null;
        if (app.Status__c == priorStatus) {
            continue;
        }
        String queueName = PSK_Constants.APPLICATION_STAGE_QUEUE.get(app.Status__c);
        if (queueName == null) {
            continue;
        }
        Id qId = queueId(queueName);
        if (qId != null) {
            app.OwnerId = qId;
        }
    }
}
```

Read closely, this is worth two callouts. First, the guard `if (app.Status__c == priorStatus) continue;` means the method only acts on a genuine transition *into* a stage — an unrelated field edit on a record already sitting in Granting doesn't re-trigger reassignment and doesn't yank the record away from an officer who already claimed it out of the queue. Second, statuses like `Draft`, `Submitted`, and the terminal statuses simply aren't in the map at all, so those stay with whoever currently owns them — front-office, applicant-facing work is deliberately excluded from queue routing, because there's no specialist team to hand it to.

This is what "no Assignment Rules feature available" actually looks like solved in Apex: no rule engine, no criteria builder — a `Map<String,String>` and a lookup, called from the trigger handler you already read about in the previous lesson. `PSK_ApplicationService.queueId()` resolves a queue's DeveloperName to its Id once per transaction (bulk-safe, same pattern as before) and caches it, so this whole mechanism costs one query no matter how many records are routing in the same batch.

## Approval Processes: declarative, not code

Where queue routing is Apex, gating a Diplomatic or Official grant behind sign-off is handled by an Approval Process — a genuinely declarative Salesforce feature: you define entry criteria, one or more approval steps with an assigned approver, and field-update actions that fire on submission, approval, or rejection. No Apex runs inside it.

<div class="code-caption">force-app/main/default/approvalProcesses/Passport_Application__c.Diplomatic_Official_Grant_Approval.approvalProcess-meta.xml</div>

```xml
<entryCriteria>
    <criteriaItems>
        <field>Passport_Application__c.RecordTypeId</field>
        <operation>equals</operation>
        <value>Diplomatic_Official</value>
    </criteriaItems>
    <criteriaItems>
        <field>Passport_Application__c.Status__c</field>
        <operation>equals</operation>
        <value>Granting</value>
    </criteriaItems>
    <booleanFilter>1 AND 2</booleanFilter>
</entryCriteria>
```

`PSK_ApplicationActionsController.advance()` auto-submits a record into this process the moment it enters Granting on the Diplomatic/Official record type, and a validation rule (`Diplomatic_Official_Requires_Approval`) blocks the record from ever reaching Printing until `Approval_Status__c` reads Approved — so the approval isn't just a suggestion, it's structurally enforced by the same validation-rule mechanism covered in earlier lessons.

## The quirk: an approval step can't target a Role

Here's the surprising part, the kind of thing that catches even admins who've built approval processes before. The obvious design is "whoever holds the Regional Passport Officer role approves this." An approval step's `assignedApprover` looks like it should support that directly — but it doesn't. The legal types for an approval step's assigned approver are `user`, `queue`, `relatedUserField`, and ad-hoc — **not** `role`. There is no way to point an approval step straight at a Salesforce Role.

The fix follows the same shape as the `Region__c` workaround from the security lesson: build a Queue whose *membership* is the role you actually want, and point the approval step at the queue instead.

<div class="code-caption">force-app/main/default/queues/RPO_Approvals.queue-meta.xml</div>

```xml
<?xml version="1.0" encoding="UTF-8"?>
<Queue xmlns="http://soap.sforce.com/2006/04/metadata">
    <doesIncludeBosses>true</doesIncludeBosses>
    <doesSendEmailToMembers>false</doesSendEmailToMembers>
    <name>RPO_Approvals</name>
    <queueMembers>
        <roleAndSubordinates>
            <roleAndSubordinate>Regional_Passport_Officer</roleAndSubordinate>
        </roleAndSubordinates>
        <users>
            <user>admin@passportoffice.com</user>
        </users>
    </queueMembers>
    <queueSobject>
        <sobjectType>Passport_Application__c</sobjectType>
    </queueSobject>
</Queue>
```

And the approval step, pointed at that queue:

```xml
<approvalStep>
    <label>Regional Passport Officer Sign-off</label>
    <name>Regional_Passport_Officer_Sign_off</name>
    <allowDelegate>true</allowDelegate>
    <assignedApprover>
        <approver>
            <type>queue</type>
            <name>RPO_Approvals</name>
        </approver>
        <whenMultipleApprovers>FirstResponse</whenMultipleApprovers>
    </assignedApprover>
</approvalStep>
```

`whenMultipleApprovers = FirstResponse` matters here too — since the queue's membership is a whole role-and-subordinates tree, potentially several people, the process is configured so the first RPO to act settles the request rather than requiring every member to weigh in. This `RPO_Approvals` queue exists for no reason *other than* working around the assignedApprover type restriction — it holds no application inventory the way `Document_Verification` or `Granting` do; its entire purpose is to be a role-shaped mailbox an approval step is allowed to point at.

Once you've hit this once, it stops being surprising: a Queue in Salesforce is really just "a named, addressable group of people" — and that makes it the general-purpose adapter any feature can point at when it wants role-based routing but only accepts a queue, a user, or a field. Assignment logic wanted it for `Passport_Application__c`, and an approval step wanted it for the RPO sign-off; same primitive, two different declarative features leaning on it for the same underlying reason.

<div class="pull-quote">When a Salesforce feature won't accept a Role directly, build a Queue shaped like that role and point the feature at the queue instead.</div>
