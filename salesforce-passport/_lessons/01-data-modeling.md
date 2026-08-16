---
number: 1
title: "Data Modeling: Few Objects, Many Fields"
description: >-
  Why a whole application lifecycle lives on one object instead of one per stage, what a record type actually changes, and how to choose between master-detail and lookup as a business call.
concept: Data Modeling
you_will_learn:
  - "Why a whole application lifecycle lives on one object instead of one object per stage"
  - "What a Record Type actually changes (and what it can never change)"
  - "How to decide between master-detail and lookup as a business call, not a technical one"
---

Every beginner who has just learned Salesforce data modeling reaches for the same instinct the first time they're asked to model a process with stages: "Draft is one thing, Submitted is another thing, so they should be different objects." It feels tidy. It is also, almost always, wrong — and the Passport Seva Kendra (PSK) build exists partly to show why.

## The anti-pattern: an object per stage

Imagine modeling a passport application the naive way: `Draft_Application__c` while the citizen is filling out the form, then a `Submitted_Application__c` once they hit submit, then a `Granted_Application__c` once it's approved. It sounds organized. In practice it is a trap. The moment an application moves from Submitted to Granted, you have to *copy every field* from one object to another, re-point every child record (documents, payments, police verification), re-teach every report and dashboard about a new object, and re-grant every permission set access to yet another table. A passport application isn't three different *kinds* of thing — it's one thing moving through time. Splitting it by stage means splitting something that was never actually plural.

PSK.md states the guiding philosophy for this whole build plainly:

> **Design philosophy:** few objects, many fields. We model the whole application lifecycle on one object using a Status picklist and record types — **not** a new object per stage. A half-finished form is the same object in `Draft` status, not a different object.

That's the whole idea in one sentence. A `Passport_Application__c` record created today as a bare-bones Draft is the *exact same row* that will, weeks later, carry a granted date, a printed passport, and a dispatch tracking number. Nothing ever gets copied between objects, because there was only ever one object.

Here is what the two approaches actually cost, side by side:

{% include viz/compare.html
   bad_title="One object per stage"
   bad="Copy every field from one object to the next at each stage::Re-point every child record — documents, payments, verification::Re-teach every report and dashboard about another table::Grant every permission set access to yet another object::Answer “where is this file?” with a UNION across six tables"
   good_title="One object, a Status picklist"
   good="Nothing is copied — one field changes value::Children never move, because the parent never changes::One report source for the entire lifecycle::One set of permissions to maintain::Answer “where is this file?” with a single-object query" %}

## One object, a Status field, and a lifecycle

{% include viz/object.html id="passport_application" group="Lifecycle" %}

One object, one auto-numbered `ARN` (Application Reference Number) that never changes for the life of the record. The lifecycle itself is carried by a single field, `Status__c`:

{% include viz/stages.html
   title="Passport_Application__c.Status__c"
   stages="Draft::Submitted::Payment Pending::Paid::Document Verification::Police Verification::Granting::Printing::Dispatch::Delivered"
   terminal="Rejected::Cancelled"
   current="Police Verification" %}

Moving an application forward is an `UPDATE` of one field on one row — not a `CREATE` on a different table plus a delete or archive of the old one. Reports, list views, sharing rules, and validation rules all key off that same field, so "show me every application currently at Police Verification" is a one-object query, not a UNION across six tables.

{% include viz/note.html kind="key" title="The lifecycle is a value, not a location"
   body="A half-finished application is the same object in `Draft` status — not a different object. Once you believe that, most of the rest of this build follows from it." %}

## What a Record Type actually does

So if it's all one object, how does PSK handle the fact that a Diplomatic application looks meaningfully different from a Minor's application — different picklist options, different required documents, different fee rules? That's the other half of the pattern: **Record Types**. `Passport_Application__c` has six of them: `Fresh`, `Re_Issue`, `Tatkal`, `Lost_Damaged`, `Minor`, and `Diplomatic_Official`.

Here's the part that trips people up: a Record Type is **not** a schema fork. It does not add fields, remove fields, or change what table a row lives in. Every `Passport_Application__c` record, regardless of Record Type, has the exact same 56 columns underneath. What a Record Type changes is narrower and more mundane: which picklist *values* are available on that row, and which page layout / compact layout the user sees. That's it.

Look at the real `Minor.recordType-meta.xml` file:

<div class="code-caption">force-app/main/default/objects/Passport_Application__c/recordTypes/Minor.recordType-meta.xml</div>
```xml
<RecordType xmlns="http://soap.sforce.com/2006/04/metadata">
    <fullName>Minor</fullName>
    <active>true</active>
    <compactLayoutAssignment>PSK_Compact_Minor</compactLayoutAssignment>
    <label>Minor</label>
    <picklistValues>
        <picklist>Booklet_Pages__c</picklist>
        <values>
            <fullName>36</fullName>
            <default>true</default>
        </values>
    </picklistValues>
    <picklistValues>
        <picklist>Validity_Years__c</picklist>
        <values>
            <fullName>5</fullName>
            <default>true</default>
        </values>
    </picklistValues>
    <picklistValues>
        <picklist>Police_Verification_Type__c</picklist>
        <values>
            <fullName>No PV</fullName>
            <default>true</default>
        </values>
    </picklistValues>
    <!-- ... additional picklistValues blocks for ECR_Status__c, Passport_Category__c, etc. -->
</RecordType>
```

The `Booklet_Pages__c` field exists on every application — it's a plain picklist that, on a `Fresh` record, offers `36` or `60`. On a `Minor` record, the *same field* is narrowed down to offer only `36`, and it's pre-defaulted to that value. Same with `Validity_Years__c` (locked to `5` instead of `10` or `5`) and `Police_Verification_Type__c` (locked to `No PV`, since minors typically don't need a standalone police verification visit). Per PSK's own record type table (PSK.md §4.4), the `Diplomatic_Official` record type instead widens `Passport_Category__c` to include `Diplomatic` and `Official`, and unlocks a `Clearance_Level__c` field that only makes sense for those categories.

The mental model: a Record Type is a *lens*, not a *fork*. It's how you tell the same underlying object "when a user picks this business variant, show a smaller, more sensible menu of picklist choices and a layout that foregrounds the fields that matter for this variant." A report that queries across all six record types still gets one consistent schema back — no `Minor_Booklet_Pages__c` vs `Fresh_Booklet_Pages__c` split field pollution to reconcile.

## Master-detail vs. lookup: a business decision, not a wiring choice

The other data-modeling decision every beginner underestimates is: when two objects are related, should it be a master-detail relationship or a lookup? The reflex is to treat this as a technical detail — "master-detail cascades deletes and rollups, lookup doesn't, pick whichever." But in PSK, the choice is explicitly a decision about *business lifecycle and ownership*, and the clearest example is `Police_Verification__c`.

Most of `Passport_Application__c`'s children — `Appointment__c`, `Document_Checklist_Item__c`, `Objection__c`, `Payment__c` — are wired as master-detail, with sharing set to `ControlledByParent`: if the application is deleted, so are they, and their visibility rides entirely on the application's own sharing. That's correct for records that only mean something *in the context of* their parent application.

`Police_Verification__c` breaks that pattern on purpose. PSK.md is explicit about why:

> | Police Verification | `Police_Verification__c` | **Lookup** → `Passport_Application__c` | Private | Auto Number `PV-{00000}` | — | The PV process. Deliberately a lookup, not master-detail: a PV report survives its application and has its own OWD |

Drawn out, the difference between the two kinds of child is the whole lesson:

{% include viz/erd.html
   title="Why each relationship is the type it is"
   rels="Document_Checklist_Item__c|md|Passport_Application__c|Cascade delete, sharing inherited from the parent, and roll-up summaries. A checklist row means nothing without its application.::Dispatch__c|md|Passport_Application__c|Same reasoning — a despatch has no independent existence.::Police_Verification__c|lookup|Passport_Application__c|Deliberately NOT master-detail. A police finding must survive the application and needs its own sharing model.::Passport__c|self|Passport__c|Previous_Passport__c chains each re-issue to the booklet it replaced, so you can walk a citizen's history." %}

The field metadata sets `deleteConstraint` to `SetNull` — if the parent application were ever deleted, the PV record doesn't vanish with it, it just loses the link. That's not an accident of API defaults; it's the field literally encoding a business fact: a police verification report is evidence collected by the Police Verification Team, with its own record-level sharing (`Private` OWD, its own visibility rules for that specific team). It has value independent of whatever happens to the application afterward — an application can be cancelled, but the PV report an officer physically wrote up is still a real document someone may need to reference later. If PSK had modeled it as master-detail, deleting an application would silently destroy a police record that has nothing to do with the application's own lifecycle, and the PV record would have been forced to inherit the application's sharing instead of getting its own.

{% include viz/note.html kind="rule" title="The question to ask before choosing a relationship type"
   body="Not &quot;does this need roll-ups?&quot; but **&quot;does this child's existence and ownership make sense *only* in the context of its parent, or does it have its own lifespan and its own audience?&quot;** Get it wrong and you either lose data you needed to keep, or you leak access to data that should have had tighter sharing." %}

Here is the same lifecycle again, this time showing which steps a person performs and which ones the platform does on its own once the relationships are wired correctly:

{% include viz/flow.html
   title="What one Submit press actually sets off"
   steps="Officer presses Submit|user::Fee written from Fee_Matrix__mdt|auto::Checklist rows generated from the record-type template|auto::Roll-up counts appear on the parent|auto::Owner moves to the Document Verification queue|auto" %}

<div class="pull-quote">A Record Type is a lens on one object, not a fork of it — the schema underneath never splits.</div>
