---
number: 4
title: "Security: Roles, Permission Sets, Sharing, and Least Privilege"
description: >-
  Two independent gates that beginners collapse into one: what you can do, and which records you can do it to. Personas as permission sets, and escalation as a standing query.
concept: Security Model
you_will_learn:
  - "Why this org uses one thin baseline plus additive permission sets instead of a profile per job"
  - "What Organization-Wide Default controls versus what a permission set controls"
  - "Why criteria-based sharing can't read a formula field or cross a lookup — and how the build works around both"
---

Salesforce security has three separate axes that beginners almost always collapse into one: *can this person see this object at all*, *can they see this particular record*, and *can they see this particular field on it*. PSK's build keeps all three deliberately distinct, and walking through the real metadata is the fastest way to see why that separation matters.

## Profiles vs. permission sets: one baseline, many additions

The old Salesforce pattern is one profile per job — a Front Office profile, a Granting Officer profile, an Auditor profile — each a complete, standalone bundle of object access, field access, tab visibility, and app assignment. The problem is maintenance: eleven job profiles means eleven places to update when a new field ships, and profiles can't be layered, so any overlap between two jobs gets copy-pasted.

PSK does the opposite. There's a single admin/verification catch-all, `PSK_App_Access`, and then nine job-specific permission sets — `PSK_Officer`, `PSK_Document_Verification_Officer`, `PSK_Verification_Officer`, `PSK_Granting_Officer`, `PSK_Fulfilment_Officer`, `PSK_Office_Manager`, `PSK_Reference_Data_Admin`, `PSK_Auditor_Read_Only`, and `PSK_Visa_Officer` — confirmed directly off the filesystem under `force-app/main/default/permissionsets/`. Each is scoped to exactly one job's shape of access, and permission sets are *additive*: a user's effective access is the union of everything assigned to them. A manager who also grants applications just gets two permission sets, not a thirteenth profile that duplicates both.

`PSK_Reference_Data_Admin` is the cleanest illustration of what "additive and scoped" buys you. It grants CRUD on `PSK__c` and `Slot__c` only — no access at all to `Passport_Application__c` or `Citizen__c`. Someone maintaining office capacity and fee tables has zero PII exposure, by construction, because the permission set simply never grants it. You can't accidentally leak applicant data through a permission set that was never asked to carry it.

## OWD vs. permission set: two different questions

Passport_Application__c has Organization-Wide Default **Private**. That single setting answers one question only: *by default, who can see a record they don't own and aren't shared into?* Answer: nobody. Everything else — can a Document Verification Officer open the app at all, can they edit `Status__c`, can they see `Aadhaar_Token__c` — is a completely separate question answered by object permissions and field-level security on a permission set.

This is the split beginners miss: OWD is about *record visibility by default*, permission sets are about *what you're allowed to do once you can see a record*. A user can have full "Edit" object permission on `Passport_Application__c` in their permission set and still see zero records, because Private OWD means they're not shared into any of them yet. Conversely, sharing rules (below) can grant a user *record access* to applications they don't own, but that access is still capped by whatever their permission set's field-level security allows on those records. The two mechanisms stack; neither one alone tells you what a user can actually do.

## Field-level security is its own axis — the Aadhaar token example

The permission set for the Granting Officer, `PSK_Granting_Officer`, has full object-level Edit on `Passport_Application__c`:

<div class="code-caption">force-app/main/default/permissionsets/PSK_Granting_Officer.permissionset-meta.xml</div>

```xml
<objectPermissions>
    <allowCreate>false</allowCreate>
    <allowDelete>false</allowDelete>
    <allowEdit>true</allowEdit>
    <allowRead>true</allowRead>
    <modifyAllRecords>false</modifyAllRecords>
    <object>Passport_Application__c</object>
    <viewAllRecords>false</viewAllRecords>
</objectPermissions>
```

And yet, on the very same permission set, the PII fields are locked to read-only:

```xml
<fieldPermissions>
    <editable>false</editable>
    <field>Passport_Application__c.Aadhaar_Token__c</field>
    <readable>true</readable>
</fieldPermissions>
<fieldPermissions>
    <editable>false</editable>
    <field>Passport_Application__c.Date_of_Birth__c</field>
    <readable>true</readable>
</fieldPermissions>
<fieldPermissions>
    <editable>false</editable>
    <field>Passport_Application__c.Mobile__c</field>
    <readable>true</readable>
</fieldPermissions>
```

Object CRUD and field-level security are genuinely independent settings, evaluated independently, and this is the concrete proof: a Granting Officer can open an application, change its status, add an Objection — but cannot touch the applicant's declared date of birth, mobile number, or Aadhaar token. That maps directly onto the design intent written in `PSK.md` §5.2 — *"Cannot edit the applicant declaration"* — and this session's fix is exactly this: earlier, `PSK_Granting_Officer` had these PII fields fully editable, which meant a role whose job is to grant or reject an application could silently rewrite the very facts a police verification was run against. Object-level "Edit" access said yes; field-level security is what actually says no.

The other permission sets show the same axis used for different purposes. `PSK_Fulfilment_Officer` and `PSK_Document_Verification_Officer` set every PII field to `editable=false` across the board — read-only, because printing a booklet or checking a document doesn't require touching what the applicant declared. `PSK_Auditor_Read_Only` sets `readable=true`/`editable=false` everywhere on every object, `viewAllRecords=true` — compliance needs to see everything, but "see" is the entire verb; it can never become "change."

## Criteria-based sharing: what it can and can't reach

Sharing rules answer a different question again: *besides the record owner, who else gets access, and to which records specifically?* PSK uses criteria-based sharing rules on `Passport_Application__c` — rules that grant access based on a field value rather than a static group of records. The real rule set:

<div class="code-caption">force-app/main/default/objects/Passport_Application__c/sharingRules/Passport_Application__c.sharingRules-meta.xml</div>

```xml
<sharingCriteriaRules>
    <fullName>Tatkal_To_Managers</fullName>
    <accessLevel>Edit</accessLevel>
    <description>Tatkal (expedited) applications need manager oversight to hit the SLA.</description>
    <sharedTo>
        <group>PSK_Managers</group>
    </sharedTo>
    <criteriaItems>
        <field>Tatkal__c</field>
        <operation>equals</operation>
        <value>true</value>
    </criteriaItems>
</sharingCriteriaRules>
```

That one is straightforward: any application with `Tatkal__c = true` becomes Edit-accessible to the `PSK_Managers` group, on top of whatever the owner already has. But two real platform limitations shaped how the rest of this rule set had to be built, and they're worth knowing cold because they trip up experienced admins, not just beginners.

**Criteria-based sharing cannot read a formula field.** There's a `High_Risk_To_Verification` rule that shares any application scoring over 70 on `Risk_Score__c` (a plain number field) with the verification team — that one works fine because `Risk_Score__c` is a real stored field, not a formula. If it had instead needed to key off a derived flag, the rule simply could not have referenced it; the criteria picker on a sharing rule only offers non-formula fields.

**Criteria-based sharing cannot traverse a lookup.** This is the one that actually forced a schema change. The design wanted region-based access — an application should become editable to the group covering the region its `PSK_Office__c` sits in — but there's no way to write a criteria rule against `PSK_Office__r.Region__c`; the criteria field list only offers fields that live directly on the object being shared. `Region__c` on `Passport_Application__c` exists for exactly this reason:

<div class="code-caption">force-app/main/default/objects/Passport_Application__c/fields/Region__c.field-meta.xml</div>

```xml
<CustomField xmlns="http://soap.sforce.com/2006/04/metadata">
    <fullName>Region__c</fullName>
    <label>Region</label>
    <length>20</length>
    <description>Copy of PSK_Office__r.Region__c, populated by PassportApplicationTriggerHandler / PSK_ApplicationService.applyRegionFromOffice whenever the office is set. Not user-entered. Exists as a real field (not a formula) purely because criteria-based sharing rules cannot traverse a lookup relationship (PSK_Office__r.Region__c), so region-based sharing needs a value that lives directly on the record.</description>
    <type>Text</type>
</CustomField>
```

Notice it says *not a formula* — a formula field reading `PSK_Office__r.Region__c` would hit the exact same wall as the risk-score example above, because it would still be a formula, just one that also happens to traverse a lookup. So `Region__c` has to be a genuinely stored, plain Text field, kept in sync by Apex (`PSK_ApplicationService.applyRegionFromOffice`, covered in the next lesson) every time the office changes. Once that denormalised copy exists, six ordinary criteria rules — `North_Region_To_Region_Group`, `South_Region_To_Region_Group`, and so on — each match one region value and share to one regional group. Nothing exotic; the trick was entirely in getting a matchable field onto the record in the first place.

Stack all three mechanisms together and you get the actual behavior a Granting Officer experiences: Private OWD means they see nothing by default; the `Granting_Stage_To_Granting_Officers` criteria rule (matching `Status__c` in Granting or Printing) opens up exactly the applications currently at their stage; their permission set then governs, field by field, what they're allowed to do once they're looking at one — full edit on the application, but never the applicant's declared PII.

<div class="pull-quote">Object access says whether you can open the door. Field-level security says what you're allowed to touch once you're inside.</div>
