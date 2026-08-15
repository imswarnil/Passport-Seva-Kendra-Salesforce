---
layout: default
title: How it's built
---

<div class="prose" markdown="1">

# How it's built

This is a chronological account of how Passport Seva Kendra actually got built — decisions, dead ends, and the real bugs that got found and fixed along the way. It's assembled from the project's own commit history, which reads less like a changelog and more like a build diary: most commits explain not just *what* changed but *what broke and why* before it got fixed. Where useful, this page quotes those messages directly rather than paraphrasing them into something blander.

## 1. The data model

The build starts, deliberately, with a single object: `Passport_Application__c` — 56 custom fields, 6 record types, 4 validation rules, one Status picklist carrying the whole Draft-to-Delivered lifecycle. That's the "few objects, many fields" philosophy stated in [PSK.md](https://github.com/{{ site.repository }}/blob/main/PSK.md) §1: a half-finished application is the same object in `Draft` status, not a different object.

From there the model grew outward to the rest of the catalogue — offices (`PSK__c`), appointment slots and bookings (`Slot__c`, `Appointment__c`), document checklists, objections, police verification, payments, and eventually identity (`Citizen__c`, `Family_Member__c`) and fulfilment (`Passport__c`, `Print_Job__c`, `Dispatch__c`). Two objects weren't in the original roadmap at all and got added because the model needed them: `Citizen__c`, so the applicant is a golden identity record instead of an Account, and `Family_Member__c` for citizen-to-citizen relationship links (which also carries the guardian link a minor application needs).

The one deliberate exception to "don't duplicate data" — `Passport_Application__c` stores its own name, date of birth, mobile number, and address even though it also holds a `Citizen__c` lookup — got explained at length in [Lesson 2](/lessons/02-fields-and-formulas/). The short version, from PSK.md §2.1: a passport application is a legal instrument, and if its declared fields were live formulas off the citizen record, a citizen correcting a typo years later would silently rewrite what an already-granted, already-printed application says was declared. **Snapshot a declaration, derive a fact** became the rule of thumb applied everywhere else in the model instead — `Passport__c` re-keys nothing off its application, `Dispatch__c.Delivery_Address__c` is a formula, and so on.

## 2. Security

Security followed the data model's shape rather than a generic profile-per-department setup: eleven roles rooted at `CEO_and_Admins`, nine persona permission sets (Front Office, Document Verification, Police Verification, Granting Officer, Print & Dispatch, Office Manager/RPO, Audit & Compliance, plus a Visa persona added later), six queues, and criteria-based sharing rules layered on top of a Private org-wide default everywhere personal data lives.

Two platform constraints shaped the sharing design directly, and both are documented as constraints rather than bugs, because they're not fixable — they're how Salesforce works:

> Criteria-based sharing cannot read a formula field. That is why `Expiring_To_Officers` filters on `Status__c` rather than the obvious `Is_Expiring_Soon__c`.

> Criteria-based sharing cannot traverse a lookup. So no rule can be written against `PSK_Office__r.Region__c`, and region-based access is currently unimplemented.

That second constraint sat as an open gap for most of the build (PSK.md §5.5 flagged it explicitly) until it finally got closed in the last working session — see §5 below.

PII got its own discipline: `Date_of_Birth__c`, `Mobile__c`, `Aadhaar_Verified__c`, and `Aadhaar_Token__c` are controlled by field-level security *per persona set*, independent of object access, following the DPDP-driven rule that the Aadhaar number itself is never stored — only a verification checkbox and an opaque token reference.

## 3. Automation

The automation layer — four triggers, a dozen-plus `PSK_*` service and controller classes — is where the build's most detailed incident report lives. The commit that deployed it (*"Deploy the Apex layer: 4 triggers, 12 services, demo data generator"*) took the test suite from 59% to 89% passing, and getting there surfaced problems that had nothing to do with business logic and everything to do with how Salesforce actually deploys and enforces things:

> 35 classes had no `.cls-meta.xml`, so the CLI silently skipped them and only their dependents failed. The cascading "variable does not exist" errors never named the real cause.

> `number`, `limit` and `like` are reserved identifiers in Apex.

> Field permissions had been generated before the `External_Id__c` fields were added, so those fields were invisible and USER_MODE DML failed with "fields being inaccessible." 252 → 263 field permissions.

That last one is a genuinely useful lesson on its own: a field can exist, compile, and deploy cleanly, and Apex running in `USER_MODE` will still refuse to touch it if the running user's permission set was generated before the field existed. The fix isn't a code change at all — it's regenerating field-level security.

A second pass (*"Complete the build: security, UI, seeded data, 188/188 tests green"*) took the suite the rest of the way, and fixed six more real product bugs surfaced by fixing tests properly instead of loosening assertions to make them pass:

> Every `AuraHandledException` surfaced to the user as the literal string "Script-thrown exception", because `getMessage()` returns that unless `setMessage()` is also called. All 40+ throws now route through a helper.

> `cleanUp()` guarded a mass delete with `!=` on a String, which is case-insensitive in Apex, so `"delete-psk-demo-data"` passed the check.

> Test factory external ids collided because Apex test methods run in parallel and the counter restarted per method.

That collision bug is the centerpiece of [Lesson 7](/lessons/07-testing-apex/) — it's a textbook example of a flaky test that only shows up when Salesforce happens to schedule two test methods into overlapping transactions, and the fix (a random per-transaction key prefix, `RUN`, that every generated external ID is built from) is now baked permanently into `PSK_TestDataFactory`.

Later in the build, a follow-up session added the pieces that turn "an object with fields" into "a system that runs itself": `PSK_ApplicationService.routeOwnership()` auto-assigns `OwnerId` to the matching queue the instant `Status__c` transitions into a new stage — no assignment rules to maintain — and `seedChecklistItems()` auto-generates the required-document checklist the moment an application leaves Draft. A real Approval Process, `Diplomatic_Official_Grant_Approval`, was added to gate sensitive grants behind sign-off, though its first version routed to a hardcoded admin user rather than a role — a limitation that got fixed properly two sessions later (§5).

## 4. UI

The UI layer is Lightning-native throughout — no classic page layouts anywhere in this build, FlexiPages exclusively. The `Application Management Console` app carries the navy `#1A2A5E` branded header defined in its `app-meta.xml`, 17+ tabs (one per object), and a home dashboard (`pskHomeDashboard`) backed by real Apex rather than a static Lightning page. `pskApplicationSidebar` gives every record page a per-record context panel — citizen, documents, police verification, and payments at a glance — and `pskRiskMeter` renders `Risk_Score__c` as a visual gauge rather than a bare number.

Some of the UI work turned into its own debugging story. Deploying 45 quick actions and rebuilding every layout ran into two non-obvious platform quirks noted directly in the commit history: `force:relatedListSingleContainer` rejects a `relatedListId` in this org's API version, so those fall back to `relatedListContainer`; and FlexiPage component identifiers have to be unique *per page*, not per region — a mistake that looks like a harmless duplicate ID until the deploy rejects it outright.

One limitation stayed honest rather than getting worked around: per-record-type Lightning page activation isn't reliably expressible in FlexiPage metadata, so after every deploy that touches a record page, someone has to open Lightning App Builder by hand and assign it per record type. PSK.md documents this as a manual step rather than pretending it's automated.

## 5. Closing the gaps

The most recent working session (*"Close the remaining gaps: region sharing, reports, visa department, split personas"*) is where several long-standing, explicitly-tracked gaps in PSK.md finally got closed in one pass:

- **Region-based sharing.** Since criteria-based sharing can't traverse a lookup, the fix wasn't a smarter sharing rule — it was a real `Region__c` text field on `Passport_Application__c`, denormalized from `PSK_Office__r.Region__c` by trigger, paired with six new `PSK_Region_*` public groups and six matching sharing rules. A field that duplicates data on purpose, again, because the platform constraint made the "obvious" formula-field approach impossible.
- **First reporting layer.** Zero reports existed for any PSK object before this session. It shipped two custom report types and five reports (Applications by Stage, Tatkal In Progress, High Risk, Pending Police Verifications, Granted This Month) plus an operations dashboard — and hit a genuinely obscure metadata quirk along the way: *"Custom-object report types need a `__c` suffix and `$` field separators at the metadata layer that don't appear in the source file names — non-obvious, cost real iteration to find."* A follow-up commit fixed the dashboard itself, discovering that a row-limited tabular report can't back a Table or Metric tile — Salesforce requires a Dashboard Settings row limit for any tabular report used that way, and even after adding one, Table/Metric tiles still rejected it. The dashboard ships with the two components that render reliably, and the other two reports stay one click away instead of broken inline.
- **The visa department MVP.** `Visa_Application__c` — the object whose role, group, and value set had sat waiting since early in the build — finally shipped: 26 fields and two validation rules, modelled as fields on one object rather than spinning up `Country__c`/`Sponsor__c`, consistent with the project's own design philosophy. Deliberately scoped without Apex automation yet, so it's a real object in the model without pretending the automation layer is further along than it is.
- **Persona correctness audit.** Document Verification and Police Verification had been incorrectly sharing one permission set despite being distinct personas in the original design — split into `PSK_Document_Verification_Officer` and `PSK_Verification_Officer`. PII field-level security drift across four permission sets got corrected so Granting and Verification officers can no longer edit the applicant's declared PII, matching "cannot edit the applicant declaration" in the original spec.
- **Approval routing, for real this time.** The placeholder admin-user approver got replaced: role-based approver assignment isn't valid in `ApprovalStep` metadata (`NextOwnerType` has no `role` enum value), so approvals now route to a new `RPO_Approvals` queue whose members are the Regional Passport Officer role and subordinates.

The session ended at 234/235 local tests passing — the one failure being the same pre-existing, unrelated Trailhead template test documented from the start as out of scope.

## 6. This site

The site you're reading is the last piece, and it's meta on purpose: it exists to teach what got learned building everything above, using the actual code and metadata as the material rather than invented examples. It reuses the org's own navy `#1A2A5E` / gold `#C9A227` palette (see the [design language page](/design/)) so the teaching material visibly belongs to the same project as the build it's teaching. It was originally scaffolded as a `jekyll/` directory and later renamed to `salesforce-passport/` and rewritten around that actual purpose — "teaching Salesforce concepts through one real build instead of disconnected tutorials," as the commit that did the rename put it — with deploy automated via GitHub Actions.

Building the site surfaced its own small lessons, consistent with everything above: an accidentally-committed `_site/` build directory had to be removed and `.gitignore` hardened against it recurring, and the showcase stats on the homepage (object counts, permission set counts, test counts) needed a deliberate update pass to stay honest as the underlying build kept growing — the same discipline PSK.md itself applies to its own status tables.

</div>
