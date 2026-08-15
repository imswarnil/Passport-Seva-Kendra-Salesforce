---
number: 3
title: "Validation Rules: Gate on Submit, Not on Draft"
description: >-
  Rules that enforce at the transition rather than on every keystroke — so a half-finished form always saves, and the gates still hold where they matter.
concept: Validation Rules
you_will_learn:
  - "Why validation rules should be gated by lifecycle stage instead of firing on every save"
  - "How PRIORVALUE() compares a field's before-and-after value inside one rule"
  - "How to layer record-type-conditional rules on top of stage gating"
---

`Passport_Application__c` has 13 validation rules deployed on it today (PSK.md's own §4.7 table only documents the original 4 — the object has grown since that table was last updated, so don't trust a stale doc over the actual directory listing). You can verify the current count yourself:

<div class="code-caption">force-app/main/default/objects/Passport_Application__c/validationRules/</div>
```
Cannot_Grant_With_Pending_Payment.validationRule-meta.xml
Citizen_Required_On_Submit.validationRule-meta.xml
Clearance_Level_Only_For_Diplomatic.validationRule-meta.xml
Consent_Requires_Alert_Mobile.validationRule-meta.xml
Diplomatic_Official_Requires_Approval.validationRule-meta.xml
Diplomatic_Requires_Clearance_Level.validationRule-meta.xml
Lost_Damaged_Requires_Reason.validationRule-meta.xml
Minor_Needs_Guardian_Consent.validationRule-meta.xml
Minor_Validity_Must_Be_5.validationRule-meta.xml
Mobile_Format.validationRule-meta.xml
No_Backward_Move_Once_Delivered.validationRule-meta.xml
Pincode_Format.validationRule-meta.xml
Reissue_Requires_Previous_Passport.validationRule-meta.xml
Require_Core_Fields_On_Submit.validationRule-meta.xml
```

Thirteen rules is a lot to keep straight, but almost all of them follow one convention so consistently that once you see it, the rest of the object reads itself.

## The beginner mistake: unconditional required-field rules

If you're new to validation rules, the very first one you write is usually something like "First Name is required" — a rule with a formula as blunt as `ISBLANK(First_Name__c)`. It seems obviously correct. It also makes the object nearly unusable, because that rule fires on *every single save*, including the very first save of a brand-new, half-empty record. A citizen who has typed in their name but hasn't gotten to their address yet can't save a draft. An office clerk who's building the record over three separate phone calls can't save partial progress between calls. You've turned an incremental form into an all-or-nothing form.

PSK's convention is explicit about avoiding exactly this. From PSK.md §3:

> **Validation rules:** enforce on submit, not in Draft. Every rule on the application is gated on `NOT(ISPICKVAL(Status__c,"Draft"))` or on a specific later stage, so a half-finished form always saves.

That single design decision is why `Status__c` defaulting to `Draft` isn't just cosmetic — it's the escape hatch every other rule on the object is built around.

## The worked example: `Require_Core_Fields_On_Submit`

<div class="code-caption">force-app/main/default/objects/Passport_Application__c/validationRules/Require_Core_Fields_On_Submit.validationRule-meta.xml</div>
```xml
<ValidationRule xmlns="http://soap.sforce.com/2006/04/metadata">
    <fullName>Require_Core_Fields_On_Submit</fullName>
    <active>true</active>
    <errorConditionFormula>AND( NOT(ISPICKVAL(Status__c,"Draft")), OR( ISBLANK(First_Name__c), ISBLANK(Last_Name__c), ISBLANK(Date_of_Birth__c), ISBLANK(Mobile__c), ISBLANK(Address_Line1__c) ) )</errorConditionFormula>
    <errorMessage>First Name, Last Name, Date of Birth, Mobile and Address Line 1 are required before submitting.</errorMessage>
</ValidationRule>
```

Read the formula as two halves joined by `AND`. The first half, `NOT(ISPICKVAL(Status__c,"Draft"))`, is the gate: this whole rule is switched off whenever the record is still a Draft. Only once someone tries to move the record *out* of Draft does the second half even get evaluated — the `OR` block that actually checks whether First Name, Last Name, Date of Birth, Mobile, or Address Line 1 is blank. So the same five fields that were completely optional a moment ago become mandatory the instant somebody tries to advance the stage. A validation rule error only ever fires on a save that's trying to attempt a *transition*, never on a save that's just making incremental progress within Draft.

That's the general shape almost every rule on this object follows: gate on lifecycle state, then check the business condition.

## `PRIORVALUE()`: comparing before and after in one rule

Some rules need to know not just what a field's value *is*, but what it *changed from*. `No_Backward_Move_Once_Delivered` is PSK's cleanest example:

<div class="code-caption">force-app/main/default/objects/Passport_Application__c/validationRules/No_Backward_Move_Once_Delivered.validationRule-meta.xml</div>
```xml
<ValidationRule xmlns="http://soap.sforce.com/2006/04/metadata">
    <fullName>No_Backward_Move_Once_Delivered</fullName>
    <active>true</active>
    <errorConditionFormula>AND( ISPICKVAL(PRIORVALUE(Status__c),"Delivered"), NOT(ISPICKVAL(Status__c,"Delivered")) )</errorConditionFormula>
    <errorMessage>A Delivered application cannot be moved back to an earlier stage.</errorMessage>
</ValidationRule>
```

`PRIORVALUE(Status__c)` returns whatever `Status__c` held *before* this save started — the value as it was the last time the record was successfully saved. `Status__c` (with no function wrapper) is the value being saved *right now*, in this transaction. So the rule reads: "if the status used to be Delivered, and it's no longer Delivered after this save, block it." That's the only way to express "you can't undo a completed delivery" — a plain `ISPICKVAL(Status__c, ...)` check on its own can only ever see the *new* value, never what it used to be. Whenever a rule needs to compare a before-and-after within a single save (not "is this value X" but "did this value *change* from X to something else"), `PRIORVALUE()` is the tool.

Notice this rule doesn't bother gating on Draft at all — a record that's already reached Delivered is, by definition, nowhere near Draft, so the gate would be redundant. The stage-gating convention isn't "always write `NOT(ISPICKVAL(Status__c,"Draft"))` no matter what" — it's "only let a rule fire once it's actually reached the point in the lifecycle where the rule's business condition is meant to apply." Here, that condition is baked directly into comparing prior and current status.

## Layering in record-type conditions

Stage isn't the only thing rules can gate on — some business rules only make sense for a specific *shape* of application, which is where Record Type comes back in from Lesson 1. `Minor_Needs_Guardian_Consent` combines both a stage gate and a data-shape condition:

<div class="code-caption">force-app/main/default/objects/Passport_Application__c/validationRules/Minor_Needs_Guardian_Consent.validationRule-meta.xml</div>
```xml
<ValidationRule xmlns="http://soap.sforce.com/2006/04/metadata">
    <fullName>Minor_Needs_Guardian_Consent</fullName>
    <active>true</active>
    <errorConditionFormula>AND( Applied_For_Minor__c, NOT(Guardian_Consent__c), NOT(ISPICKVAL(Status__c,"Draft")) )</errorConditionFormula>
    <errorMessage>Guardian Consent is required for a minor application before submission.</errorMessage>
</ValidationRule>
```

Three conditions, all `AND`ed together: the applicant is a minor (`Applied_For_Minor__c` is a checkbox, not the `Minor` Record Type itself — an application can be filed for a minor under different record types), guardian consent hasn't been checked, and the record isn't in Draft. Only when all three are true does the save get blocked. This is the same "gate first, then check the business condition" shape as `Require_Core_Fields_On_Submit`, just with an extra condition layered in: not every application needs this rule to apply, only ones where `Applied_For_Minor__c` is true. Elsewhere on the object, `Clearance_Level_Only_For_Diplomatic.validationRule-meta.xml` and `Diplomatic_Requires_Clearance_Level.validationRule-meta.xml` do the equivalent thing keyed on the `Diplomatic_Official` Record Type instead of a checkbox — same pattern, different discriminator.

## What all thirteen rules have in common

Once you've read a handful of these, a pattern falls out: every validation rule on this object is really answering the question "what has to be true at *this specific point* in the record's life?" The two things almost every rule checks to establish "this point" are `Status__c` (which lifecycle stage) and Record Type (which business variant). A validation rule that doesn't reference either of those is usually checking something that's *always* true regardless of stage — for instance `Mobile_Format`, which validates the phone number's shape (`REGEX(Mobile__c, "^[6-9][0-9]{9}$")`) the moment it's non-blank, Draft included, because a malformed phone number is never useful at any stage, draft or not; it deliberately leaves *making* Mobile mandatory to `Require_Core_Fields_On_Submit` instead of also policing that here.

The lesson generalizes past this one object: whenever you write a validation rule, ask "is this business rule actually true unconditionally, or is it only true once the record has reached a certain state?" If it's the latter — and for anything modeling a multi-stage process, it usually is — gate it. Otherwise you've built a form that can only ever be filled out perfectly in one sitting, which is not how real work happens.

<div class="pull-quote">A validation rule isn't "this must always be true" — it's "this must be true by the time you get here."</div>
