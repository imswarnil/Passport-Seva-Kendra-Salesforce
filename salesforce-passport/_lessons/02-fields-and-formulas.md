---
number: 2
title: "Fields & Formulas: Snapshot vs. Derived Data"
concept: Fields & Formulas
you_will_learn:
  - "The difference between a field that snapshots a value and one that derives it live"
  - "Why a passport application deliberately duplicates data instead of referencing it"
  - "A checklist for deciding which behavior any new field on your own objects should have"
---

Once you accept that PSK models an applicant's whole journey on one object (see Lesson 1), a subtler question shows up almost immediately: when a field on one record needs a value that "belongs" to another record, do you *copy* that value in, or do you *compute* it live with a formula every time the record is viewed? Salesforce lets you do either. Picking the wrong one for the wrong field is one of the more expensive mistakes you can make in a real org, because it's invisible until the data is already wrong.

## Two kinds of fields that look identical in Setup

In Setup, a plain Text field and a formula field that happens to return text look almost the same in a list view. But they behave completely differently over time:

- A **snapshot** field stores a value once, at the moment it's written, and never changes again unless something explicitly updates it. It answers "what was true when this record was created or last touched."
- A **derived** field is a live formula that reads from a related record every single time it's displayed or queried. It answers "what is true *right now*, according to the source record."

Both are legitimate. The entire skill is knowing which one a given field should be — and PSK's own object model gives you a clean, real-world example of both, sitting right next to each other.

## Why `Passport_Application__c` snapshots instead of referencing

`Passport_Application__c` has a `Citizen__c` lookup to the golden identity record, `Citizen__c` — the object that answers "who is this person, right now, today." And yet the application *also* carries its own `First_Name__c`, `Last_Name__c`, `Date_of_Birth__c`, `Mobile__c`, and a full address, fields that could, in principle, have been formulas reading `Citizen__r.First_Name__c` and so on. PSK.md is direct about why they aren't:

> A passport application is a legal instrument. The details *as declared at submission* are what get printed into the booklet, what the police verify against, and what an audit would later examine. If those fields were cross-object formulas reading `Citizen__r`, then the day a citizen moved house or corrected a spelling, every historical application would silently rewrite itself — including applications already granted and printed. The record of what was declared would be destroyed by the act of keeping the citizen record current.

Sit with the concrete stakes there for a second. Say a citizen record has a typo in the spelling of a name, and three years later, after their passport has already been printed and mailed, they get it corrected in the `Citizen__c` record. If `Date_of_Birth__c` and `First_Name__c` on the *application* were live formulas off that citizen record, that innocent correction would reach back in time and silently rewrite what a legal document — the application — says was declared back when it was submitted. The application record is supposed to be an unchangeable statement of fact about a specific moment: "this is what this person declared, on this date, and this is what got printed." A formula field can't hold still like that. It can only ever tell you the truth as of right now.

Look at the field metadata for `Date_of_Birth__c` on `Passport_Application__c` — it's about as plain as a field can be:

<div class="code-caption">force-app/main/default/objects/Passport_Application__c/fields/Date_of_Birth__c.field-meta.xml</div>
```xml
<CustomField xmlns="http://soap.sforce.com/2006/04/metadata">
    <fullName>Date_of_Birth__c</fullName>
    <label>Date of Birth</label>
    <required>false</required>
    <type>Date</type>
</CustomField>
```

No formula, no reference to `Citizen__r` anywhere. It's a plain, standalone `Date` field, populated once (typically by whoever keys in the application) and left alone from then on. The `Citizen__c` lookup field even documents this intent directly in its own inline help text:

<div class="code-caption">force-app/main/default/objects/Passport_Application__c/fields/Citizen__c.field-meta.xml</div>
```xml
<CustomField xmlns="http://soap.sforce.com/2006/04/metadata">
    <fullName>Citizen__c</fullName>
    <inlineHelpText>The golden identity record for this applicant. The applicant fields on this application are an immutable snapshot of what was declared at submission and are deliberately not kept in sync with the citizen record.</inlineHelpText>
    <label>Citizen</label>
    <referenceTo>Citizen__c</referenceTo>
    <relationshipName>Applications</relationshipName>
    <type>Lookup</type>
</CustomField>
```

So the model ends up with two answers living side by side on purpose: `Citizen__c` answers "who is this person *now*," and the application's own fields answer "what did they declare *then*." They're allowed to disagree, and when they do, that disagreement is itself meaningful — it might mean the citizen moved, or the application had a typo that was later corrected on the citizen record but not backfilled into old applications, which is exactly the kind of thing an auditor would want to be able to see.

## Where deriving IS the right call: `Passport__c`

Flip to a different object in the same build, `Passport__c` — the record representing the actual issued booklet — and the pattern reverses almost entirely. PSK.md's rule of thumb: **snapshot a declaration, derive a fact.**

> `Passport__c` re-keys nothing. `Booklet_Pages__c`, `Validity_Years__c`, `ECR_Status__c` and `Passport_Category__c` are `TEXT(Application__r.…)` formulas; `Holder_Name__c` is assembled by formula from the application's name parts; `Place_of_Issue__c` is `PSK_Office__r.Name`. Only the booklet's own facts — file number, issue/expiry dates, status — are stored.

Here are three of those formula fields, straight from the object's metadata:

<div class="code-caption">force-app/main/default/objects/Passport__c/fields/Booklet_Pages__c.field-meta.xml</div>
```xml
<CustomField xmlns="http://soap.sforce.com/2006/04/metadata">
    <fullName>Booklet_Pages__c</fullName>
    <formula>TEXT(Application__r.Booklet_Pages__c)</formula>
    <label>Booklet Pages</label>
    <type>Text</type>
</CustomField>
```

<div class="code-caption">force-app/main/default/objects/Passport__c/fields/Holder_Name__c.field-meta.xml</div>
```xml
<CustomField xmlns="http://soap.sforce.com/2006/04/metadata">
    <fullName>Holder_Name__c</fullName>
    <formula>TRIM(Application__r.First_Name__c &amp; " " &amp; IF(ISBLANK(Application__r.Middle_Name__c), "", Application__r.Middle_Name__c &amp; " ") &amp; Application__r.Last_Name__c)</formula>
    <label>Holder Name</label>
    <type>Text</type>
</CustomField>
```

<div class="code-caption">force-app/main/default/objects/Passport__c/fields/Place_of_Issue__c.field-meta.xml</div>
```xml
<CustomField xmlns="http://soap.sforce.com/2006/04/metadata">
    <fullName>Place_of_Issue__c</fullName>
    <formula>PSK_Office__r.Name</formula>
    <label>Place of Issue</label>
    <type>Text</type>
</CustomField>
```

Why is deriving correct here, when it was wrong for the applicant's declared details? Because `Passport__c` isn't a second, independent legal declaration — it's a *view* of the application that produced it. `Booklet_Pages__c` on the passport should always match `Booklet_Pages__c` on the application that spawned it; there's no scenario where you'd *want* those two to drift apart, because the passport record doesn't exist to independently assert its own opinion about how many pages it has — the application already decided that, once, and the passport is just surfacing it. Same story for `Holder_Name__c`: nobody wants a "holder name" that a clerk typed in separately and that might silently disagree with what's on the application. Storing it as its own text field would just create a second place for the same fact to go stale or get out of sync. PSK.md notes the same pattern shows up again on `Dispatch__c.Delivery_Address__c` (a formula over the application's address lines, so a courier label can never drift from the application) and on `Print_Job__c.ARN__c` / `Dispatch__c.ARN__c`, which are `Passport_Application__r.Name` rather than stored strings.

## The checklist

When you're adding a new field that pulls its value from a related record, ask yourself one question: **if the source record changes tomorrow, should this field change with it, or should it freeze at what was true when this record was created?**

- If the field represents a *declaration, a legal fact, or evidence tied to a specific moment in time* — snapshot it. Store it as a plain field, written once (usually by automation or a user action at creation time), and never touch it again automatically.
- If the field is *just a convenient, always-current view* of data that genuinely lives somewhere else, and there's no scenario where the two should ever legitimately disagree — derive it with a formula.

Get this backwards in either direction and you get a real bug: snapshot something that should have been derived, and you get stale data nobody remembers to update; derive something that should have been snapshotted, and you get a legal document that silently rewrites its own history.

<div class="pull-quote">Snapshot a declaration, derive a fact — the same rule that keeps a passport honest.</div>
