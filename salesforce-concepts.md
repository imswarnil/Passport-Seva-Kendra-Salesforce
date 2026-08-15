---
layout: default
title: "Salesforce Concepts Curriculum"
description: "A learn-by-building curriculum covering all core Salesforce concepts, CRM Analytics, n8n integration and UI patterns, taught against the Passport Seva Kendra (PSK) build."
nav_order: 1
permalink: /salesforce-concepts/
tags: [salesforce, curriculum, apex, lwc, flow, crm-analytics, n8n, psk]
---

# Salesforce Concepts Curriculum — Learn by Building Passport Seva Kendra (PSK)

> **Purpose of this file.** This is a *curriculum + prompt*. It defines every core Salesforce concept — **what it is, why it exists, how to use it** — and pairs each with a **simple example** grounded in the PSK build (`Passport_Application__c` and friends). Feed it to Claude / Claude Code as the teaching contract for building PSK the right way, in the right order, with tests.
>
> The concept definitions here are **canonical and general** — they describe Salesforce, not PSK. The PSK lines are only *illustrations* of how a concept lands in this specific app. Learn the concept first; the example is the anchor, not the definition.

---

## 0. Prompt to Claude — How to Use This Curriculum

> Paste or reference this section when you want Claude/Claude Code to teach or build using this file.

**Your role.** You are a Salesforce mentor-engineer. You teach a concept, then apply it to the PSK build, then make me prove it with a task and a test. You never skip the "why."

**The teaching loop.** For every concept I ask about (or every concept in a phase), respond in this exact shape:

1. **What it is** — one or two plain sentences.
2. **Why it exists** — the problem it solves; what breaks without it.
3. **How to use it** — the mechanics (where in Setup, or the code/CLI shape).
4. **PSK example** — one concrete, small application in this app.
5. **Try it** — a single actionable task on the PSK org.
6. **Test it** — how to verify it works (assertion, UAT step, or Apex/LWC test).

**Sequencing.** Follow the phase order in this file (Phase 0 → 16). Do not teach automation before the data model, or code before security. Respect PSK's deploy order: **global value sets → objects → layouts → security → code → app shell.**

**Build guardrails (non-negotiable).**
- **Configure before you code.** Reach for Flow/validation/declarative first; use Apex only when declarative can't do the job.
- **Bulkify everything.** No SOQL/DML inside loops, ever.
- **Never delete metadata or data without asking me first.**
- **Deploy incrementally**, confirming each step compiles and tests pass before the next.
- **PII discipline.** Never store an Aadhaar *number*. Only `Aadhaar_Verified__c` (checkbox) and `Aadhaar_Token__c` (opaque token). OWD **Private** on anything holding personal data.
- **Snapshot vs derive.** A declaration (name/DOB/address on the application at submission) is *snapshotted* onto `Passport_Application__c`; a fact already fixed elsewhere (booklet pages, delivery address label) is *derived* via formula. Know which one a field is before you create it.
- **Tests are part of "done."** Nothing is complete until it has a passing test and (for Apex) ≥75% coverage with meaningful assertions.

**CLI you may use.**
```bash
sf project retrieve start --manifest manifest/package.xml
sf project deploy start --source-dir force-app
sf apex run test --test-level RunLocalTests --code-coverage
```

**Definition of done for any deliverable:** deployed to `psk-dev`, covered by a test, demonstrated in a one-line walkthrough, and free of stored raw PII.

---

## Concept Entry Template (the format every concept below follows)

**`Concept`** — **What:** … **Why:** … **How:** … **PSK:** …

Deep-dive phases (CRM Analytics, n8n, UI, Testing) expand beyond this line format.

---

# PHASE 0 — Orientation & Environment

**Multi-tenancy** — **What:** one shared infrastructure serves many customers ("orgs"). **Why:** it's why governor limits and the metadata architecture exist. **How:** you never manage servers; you configure metadata. **PSK:** your `psk-dev` Developer Edition is one tenant among millions.

**Metadata-driven platform** — **What:** your customizations (objects, fields, code, layouts) are metadata the runtime interprets. **Why:** lets Salesforce upgrade three times a year without breaking your app. **How:** everything is retrievable/deployable as XML source. **PSK:** all sixteen objects live as `*.object-meta.xml` under `force-app/main/default/`.

**Governor limits** — **What:** per-transaction caps (SOQL, DML, CPU, heap, callouts). **Why:** protect the shared tenant from any one org's runaway code. **How:** design in bulk; measure with debug logs. **PSK:** `PSK_ApplicationActionsController.advance()` must mint booklet + print + dispatch in *one* bulk-safe transaction.

**Editions & licenses** — **What:** editions (Developer/Enterprise/Unlimited) and user/permission-set licenses gate features and objects. **Why:** they decide what a user can even touch. **How:** check under Company Information / user record. **PSK:** the seven personas map to permission sets, all within a Developer Edition's feature envelope.

**My Domain** — **What:** your unique org subdomain. **Why:** required for Lightning, LWC, SSO, and a future Experience Cloud portal. **How:** Setup → My Domain. **PSK:** prerequisite for the not-yet-built citizen self-service site.

**Environments (Sandbox / Scratch / Dev Edition / Playground)** — **What:** disposable or long-lived orgs for build/test. **Why:** never build directly in production. **How:** Dev Hub for scratch orgs; refresh sandboxes from prod. **PSK:** this build uses a Developer Edition (`psk-dev`) as the working org.

**SFDX source format & Salesforce CLI (`sf`)** — **What:** metadata represented as version-controllable source, driven from the command line. **Why:** enables Git, CI/CD, and repeatable deploys. **How:** `sf project retrieve/deploy start`. **PSK:** source API version 67.0; deploy with `--source-dir force-app`.

**Release cycle** — **What:** three seasonal releases/year (Spring, Summer, Winter). **Why:** predictable, auto-applied upgrades. **How:** read release notes, test in a pre-release org. **PSK:** new Flow/Agentforce features arrive here without you upgrading anything.

**Setup & Object Manager** — **What:** the admin console. **Why:** single place to configure declaratively. **How:** gear icon → Setup. **PSK:** where you'll define record types, validation rules, and sharing rules.

---

# PHASE 1 — Data Model & Schema

**Standard vs custom objects (`__c`)** — **What:** built-in vs objects you create. **Why:** model your domain. **How:** Object Manager → New Custom Object. **PSK:** `Passport_Application__c` (custom root), `User` (standard).

**Fields & field types** — **What:** typed columns (Text, Number, Date, Picklist, Formula, Lookup, Master-Detail…). **Why:** type governs storage, validation, reporting. **How:** Object Manager → Fields. **PSK:** `Date_of_Birth__c` (Date), `Risk_Score__c` (Number 0–100), `Status__c` (Picklist).

**Record IDs (15 vs 18 char)** — **What:** 15-char case-sensitive vs 18-char case-safe IDs. **Why:** integrations/formulas break if you mix them. **How:** APIs return 18; UI shows 15. **PSK:** external ID on `Passport__c` mirrors the booklet number, not the record ID.

**Record types** — **What:** variants of one object with different picklist values, layouts, processes. **Why:** avoid forking the schema per variant. **How:** Object Manager → Record Types + assign via permission sets. **PSK:** six on `Passport_Application__c` (Fresh, Re-Issue, Tatkal, Lost/Damaged, Minor, Diplomatic/Official) — they *subset* picklists, they don't create new objects.

**Relationships** — **What:** Lookup (loose), Master-Detail (tight: cascade delete, owner inheritance, roll-ups), Hierarchical (User only). **Why:** connect records and control ownership/sharing. **How:** create as a relationship field. **PSK:** `Payment__c` is M-D → application (`ControlledByParent`); `Police_Verification__c` is a *lookup* so a verification report survives independently.

**Junction object (many-to-many)** — **What:** an object with two master-detail relationships. **Why:** model M:N. **How:** two M-D fields. **PSK:** `Appointment__c` joins `Slot__c` and the application.

**Formula fields** — **What:** read-only, runtime-computed, can reach up relationships. **Why:** derive facts without storing/duplicating them. **How:** field type = Formula. **PSK:** `Dispatch__c.Delivery_Address__c` is a formula over the application address so a courier label can't drift.

**Roll-up summary fields** — **What:** SUM/COUNT/MIN/MAX of child records onto a parent (master-detail only). **Why:** aggregate without code. **How:** field type = Roll-Up Summary. **PSK:** count of open `Objection__c` on an application.

**Picklists & Global Value Sets** — **What:** restricted value lists; global sets are reused across fields. **Why:** consistent, restricted vocabulary. **How:** create a Global Value Set, reference it. **PSK:** 13 global value sets; record types subset them.

**Field dependencies** — **What:** controlling → dependent picklist filtering. **Why:** stop invalid combinations. **How:** Fields → Field Dependencies. **PSK:** application category could filter which `Police_Verification_Type__c` values are valid.

**Custom Metadata Types (`__mdt`)** — **What:** deployable, packageable config *records*. **Why:** keep business config out of code; ship it with the app. **How:** define type + records; query in Apex. **PSK:** `Fee_Matrix__mdt` (10 records) and `SLA_Config__mdt` (26 records) drive pricing and SLA targets declaratively.

**Custom Settings** — **What:** cached config at org/user level. **Why:** fast runtime config without SOQL cost. **How:** hierarchy or list custom setting. **PSK:** could hold a global "Tatkal premium multiplier" toggle.

**Schema Builder** — **What:** visual ERD/design tool. **Why:** see and shape relationships at a glance. **How:** Setup → Schema Builder. **PSK:** view the 16-object model rooted at the application.

**Big Objects / External Objects** — **What:** billions-of-rows archive storage / live external data. **Why:** scale history or avoid copying external data. **How:** Big Object definition / Salesforce Connect. **PSK:** archived, delivered applications older than N years could move to a Big Object.

---

# PHASE 2 — Data Management & Quality

**Data Import Wizard vs Data Loader** — **What:** UI import (small, dedupe-aware) vs bulk tool/CLI (millions, all objects). **Why:** load data at the right scale. **How:** Setup → Data Import Wizard, or Data Loader. **PSK:** seed `PSK__c` offices via the wizard; bulk citizens via Data Loader.

**External IDs & upsert** — **What:** a field that matches an outside key so you insert-or-update in one call. **Why:** idempotent integrations. **How:** mark field External ID + unique; upsert on it. **PSK:** `Notification_Log__c.Provider_Message_Id__c` as a Twilio idempotency key.

**Matching & duplicate rules** — **What:** define "sameness" and block/warn on duplicates. **Why:** keep the golden identity clean. **How:** Setup → Matching/Duplicate Rules. **PSK:** stop two `Citizen__c` records for the same person.

**Validation rules** — **What:** block a save that fails a boolean condition. **Why:** structural gates, not policy reminders. **How:** Object Manager → Validation Rules. **PSK:** `Cannot_Grant_With_Pending_Payment` and `Require_Core_Fields_On_Submit` (fires only once Status leaves Draft).

**Field History Tracking** — **What:** log old/new values on selected fields. **Why:** tamper-resistant audit trail. **How:** enable per object, ≤20 fields. **PSK:** enabled on `Passport_Application__c` so the Auditor persona has a real timeline.

**Data vs file storage** — **What:** records vs attachments counted separately. **Why:** budgeting and limits. **How:** monitor under Company Information. **PSK:** scanned documents (files) vs application records (data).

**Demo/seed data** — **What:** scripted test records. **Why:** demoable without hand-building scenarios. **How:** Apex seeding class or Data Loader. **PSK:** `PSK_DemoDataGenerator` populates all sixteen objects.

**DPDP / PII minimisation** — **What:** store the least personal data necessary. **Why:** legal + ethical obligation. **How:** tokenize, checkbox-verify, restrict FLS. **PSK:** never store Aadhaar number; only verified-flag + opaque token.

---

# PHASE 3 — Security, Access & Sharing

> Mental split: **profiles/permission sets = what you can *do*; OWD/roles/sharing = which records you can *see*.**

**Profiles** — **What:** baseline permissions (CRUD, FLS, apps/tabs, login). **Why:** every user needs a floor. **How:** keep minimal, layer with permission sets. **PSK:** a lean base profile; personas differ via permission sets.

**Permission sets** — **What:** additive grants layered on the profile. **Why:** grant extra access without cloning profiles. **How:** assign per user. **PSK:** `PSK_Officer`, `PSK_Document_Verification_Officer`, `PSK_Granting_Officer`, etc.

**Permission set groups & muting** — **What:** bundle sets; mute removes specific perms inside a group. **Why:** compose personas cleanly. **How:** PSG + optional muting set. **PSK:** the seven persona PSGs (in flight).

**Roles & role hierarchy** — **What:** record-visibility roll-up (managers see subordinates' records). **Why:** vertical visibility. **How:** Setup → Roles. **PSK:** 11 roles rooted at `CEO_and_Admins`; RPO sits above office managers.

**Org-Wide Defaults (OWD)** — **What:** baseline record access per object. **Why:** start restrictive, open up deliberately. **How:** Sharing Settings. **PSK:** **Private** on every object holding personal data.

**Sharing rules (owner/criteria-based)** — **What:** open access beyond OWD by ownership or field criteria. **Why:** route records to the right group automatically. **How:** Sharing Settings → Sharing Rules. **PSK:** `Tatkal_To_Managers`, `Diplomatic_To_RPO`, `Adverse_To_Managers`, `Open_High_Severity_To_Managers`, `High_Risk_To_Verification`.

**Manual & Apex managed sharing** — **What:** per-record grants by user/admin, or programmatic `__Share` rows. **Why:** cases rules can't express. **How:** Share button / Apex. **PSK:** reserved for edge cases the criteria rules miss.

**CRUD & FLS** — **What:** object-level Create/Read/Edit/Delete and per-field visibility. **Why:** the first two gates on any access. **How:** set on profile/permission set. **PSK:** Front Office is create/read-only on `Payment__c`; Aadhaar token is read-not-edit for everyone.

**Queues & public groups** — **What:** shared ownership buckets / reusable member collections. **Why:** "who owns this now" = queue membership, not a drawer. **How:** Setup → Queues / Public Groups. **PSK:** six queues (`Document_Verification`, `Police_Verification`, `Granting`, `Printing_And_Dispatch`, `Objections`, `Risk_Review`).

**Custom permissions** — **What:** declarative feature flags checked in flows/rules/Apex. **Why:** gate features without hard-coding roles. **How:** create + check `FeatureManagement`/`$Permission`. **PSK:** a "Can override SLA" custom permission for managers.

**Login security & MFA / Shield** — **What:** IP ranges, login hours, MFA, encryption, event monitoring. **Why:** protect access and data at rest. **How:** Session Settings / Shield. **PSK:** MFA on; Shield-style field audit is conceptually the Auditor's backstop.

---

# PHASE 4 — UI & Layouts

**Page layouts** — **What:** classic field/section/related-list arrangement. **Why:** still drives related lists and some mobile. **How:** Object Manager → Page Layouts. **PSK:** per-record-type layouts (five newest objects in flight).

**Lightning record pages & App Builder** — **What:** drag-and-drop record UI with visibility rules. **Why:** modern, component-based pages. **How:** Lightning App Builder. **PSK:** application record page hosting the checklist LWC and Path.

**Dynamic Forms & Dynamic Actions** — **What:** field-level placement + conditional buttons. **Why:** show the right fields/actions to the right user/state. **How:** toggle on the Lightning page. **PSK:** hide granting actions until Status = Granting.

**Compact layouts** — **What:** key fields in highlights/mobile/hover. **Why:** fast at-a-glance context. **How:** Object Manager → Compact Layouts. **PSK:** ARN + applicant name + status on the application highlights panel.

**List views** — **What:** saved filterable tables with inline edit and mass actions. **Why:** work a queue without a report. **How:** list view builder. **PSK:** "My open verifications" for Document Verification Officer.

**Path** — **What:** guided stage bar with key fields + guidance per step. **Why:** make current lifecycle position unambiguous. **How:** Setup → Path. **PSK:** `Passport_Application_Path` (Fresh record type today; others pending).

**Apps, tabs, quick actions, utility bar** — **What:** navigation bundles, object tabs, one-click record actions, persistent footer. **Why:** shape each persona's workspace. **How:** App Manager / Object actions. **PSK:** `Application_Management_Console` app, 17 tabs, actions like **Collect Payment**, **Mark Verified**.

**SLDS & field sets** — **What:** design tokens/CSS + reorderable field groups for code. **Why:** consistent styling, layout-driven components. **How:** SLDS classes / Field Sets. **PSK:** LWCs styled with SLDS; a field set feeding a dynamic form component.

---

# PHASE 5 — Declarative Automation

**Order of Execution (save order)** — **What:** the exact sequence of validations, triggers, flows, rules, commit. **Why:** prevents "why did my value get overwritten" and recursion bugs. **How:** learn the canonical list. **PSK:** know that `Require_Core_Fields_On_Submit` (validation) runs before after-save flows.

**Flow Builder & flow types** — **What:** no-code automation: Screen, Record-Triggered (before/after save), Scheduled, Autolaunched, Platform-Event. **Why:** the strategic replacement for Workflow/Process Builder. **How:** Setup → Flows. **PSK:** a record-triggered flow generates `Document_Checklist_Item__c` rows on submit.

**Flow elements & resources** — **What:** Decision, Loop, Get/Create/Update/Delete, Assignment; variables/collections/formulas. **Why:** express logic visually and in bulk. **How:** drag elements; loop collections, don't DML per record. **PSK:** loop the checklist template to create items in bulk.

**Subflows & Flow Orchestrator** — **What:** reusable flows / multi-user orchestrated processes. **Why:** modularity and human-in-the-loop sequences. **How:** call subflow / build orchestration. **PSK:** a reusable "send notification" subflow.

**Validation rules** — (see Phase 2) declarative save-time gates. **PSK:** `No_Backward_Move_Once_Delivered`.

**Approval processes** — **What:** multi-step submit/approve routing with actions. **Why:** documented, role-appropriate sign-off. **How:** Setup → Approval Processes. **PSK:** `Diplomatic_Official_Grant_Approval` routes to the `RPO_Approvals` queue and blocks Printing until approved.

**Assignment / escalation / auto-response rules** — **What:** route or escalate Cases/Leads; auto-reply. **Why:** hands-off routing and SLA enforcement. **How:** Setup rules. **PSK:** conceptually mirrored by queue routing; escalation logic driven by `SLA_Config__mdt`.

**Email alerts, outbound messages, scheduled paths** — **What:** templated emails, SOAP messages, delayed actions. **Why:** notify and defer. **How:** flow/automation actions. **PSK:** a scheduled path to warn when a stage nears its SLA target.

---

# PHASE 6 — Apex & Backend

**Apex fundamentals** — **What:** Java-like, cloud-hosted, transactional language. **Why:** logic declarative tools can't express. **How:** classes, triggers, tests. **PSK:** the `PSK_*` service/controller classes.

**Triggers & context variables** — **What:** code on DML events; `Trigger.new/old/newMap/oldMap`, `isBefore/isAfter`. **Why:** react to record changes. **How:** one trigger per object. **PSK:** application trigger delegates to a handler that mints downstream records.

**Trigger handler pattern** — **What:** one trigger → handler class. **Why:** testable, ordered, logic-free triggers. **How:** dispatch by context. **PSK:** `PSK_ApplicationTriggerHandler` (service layer, in flight).

**SOQL / SOSL / DML** — **What:** query / full-text search / data manipulation. **Why:** read and write records. **How:** bulk lists, bind variables, never in loops. **PSK:** query `Fee_Matrix__mdt` once, price in memory.

**Bulkification & collections** — **What:** handle 1 or 200 records equally with List/Set/Map. **Why:** the #1 Apex discipline; avoids limit errors. **How:** map lookups, loop collections. **PSK:** `advance()` processes many applications in one call.

**Asynchronous Apex** — **What:** `@future`, Queueable, Batch, Scheduled, Continuation. **Why:** offload heavy or callout work. **How:** pick by volume/chaining/callout needs. **PSK:** a Queueable posts notification callouts to n8n off the transaction.

**Custom Metadata in Apex** — **What:** query `__mdt` config at runtime. **Why:** behavior driven by config, not literals. **How:** SOQL on the type. **PSK:** `PSK_FeeService` reads `Fee_Matrix__mdt`.

**Invocable methods** — **What:** `@InvocableMethod` Apex callable from Flow. **Why:** give flows a code capability. **How:** annotate. **PSK:** an invocable "calculate risk score" called from a record-triggered flow.

**Sharing keywords & security enforcement** — **What:** `with/without/inherited sharing`; `WITH USER_MODE`, `stripInaccessible`. **Why:** respect record and field security in code. **How:** declare on classes/queries. **PSK:** service classes run `with sharing`; token field respected via FLS.

**Named credentials & callouts** — **What:** secure endpoint+auth referenced by `Http` callouts. **Why:** no hard-coded secrets. **How:** Named Credential + `callout:` URL. **PSK:** callout to n8n's webhook via a named credential.

---

# PHASE 7 — Frontend (Visualforce / Aura / LWC / React)

**Visualforce** — **What:** original `<apex:>` markup + Apex controllers. **Why:** PDFs, email templates, legacy pages. **How:** VF page + controller. **PSK:** a printable application summary PDF.

**Aura components** — **What:** first Lightning framework. **Why:** legacy gaps LWC can't yet fill. **How:** `.cmp` + controller/helper. **PSK:** avoid unless required; prefer LWC.

**Lightning Web Components (LWC)** — **What:** modern, standards-based framework (HTML template + JS class + meta XML). **Why:** faster, simpler, the default. **How:** `sf` scaffolds a component. **PSK:** four LWCs including `pskHomeDashboard`.

**Lightning Data Service (LDS)** — **What:** read/write records without Apex; caching + FLS handled. **Why:** less code, shared record state. **How:** `lightning-record-form`, `uiRecordApi`. **PSK:** edit application fields without a controller.

**Wire vs imperative Apex** — **What:** `@wire` (reactive, cached) vs manual imperative calls. **Why:** getting server data into a component two ways. **How:** `@AuraEnabled(cacheable=true)` for wire. **PSK:** `pskHomeDashboard` wires stage counts from `PSK_HomeController`.

**Events & Lightning Message Service** — **What:** `CustomEvent` (child→parent), `@api` (parent→child), LMS (cross-DOM/framework). **Why:** component communication. **How:** dispatch/handle events or a message channel. **PSK:** checklist LWC emits an event when all items verified.

**Static resources & React** — **What:** host JS/CSS/zips; use React via bundles in LWC or external apps over REST/GraphQL. **Why:** no native React core framework — LWC is the native model. **How:** upload static resource / call APIs. **PSK:** a chart library as a static resource inside a dashboard LWC.

**Custom labels** — **What:** reusable, translatable text. **Why:** no hard-coded strings; future Hindi support. **How:** Setup → Custom Labels. **PSK:** all LWC UI strings as labels, ready for `Preferred_Language__c`.

---

# PHASE 8 — Integration & Events

**REST / SOAP / Bulk / GraphQL APIs** — **What:** JSON CRUD / XML enterprise / async high-volume / flexible field selection. **Why:** get data in and out. **How:** standard endpoints. **PSK:** an external agency reads verification status via REST.

**Metadata & Tooling APIs** — **What:** deploy/retrieve metadata / dev-metadata access. **Why:** power CI/CD and IDEs. **How:** used by the CLI. **PSK:** your `sf deploy` uses Metadata API under the hood.

**Platform Events / Change Data Capture / Pub-Sub / Streaming** — **What:** event-driven publish/subscribe and record-change events. **Why:** decouple systems, react in near-real-time. **How:** define event, publish, subscribe (flow/Apex/external). **PSK:** publish a `Notification_Requested__e` platform event that n8n subscribes to.

**Apex REST / callouts / named credentials / external services** — (see Phase 6) inbound endpoints, outbound calls, secured auth, OpenAPI import. **PSK:** the notification bridge to n8n.

**Salesforce Connect** — **What:** external data as External Objects, live. **Why:** avoid copying external systems. **How:** OData/Apex adapter. **PSK:** conceptually, a live feed of courier tracking.

**Integration patterns** — **What:** request-reply, fire-and-forget, batch sync, remote call-in, UI update from data change. **Why:** choose the right shape per use case. **How:** match pattern to latency/volume. **PSK:** notification send = fire-and-forget to n8n.

---

# PHASE 9 — Identity & Authentication

**OAuth 2.0 flows** — **What:** Web Server, JWT Bearer, Client Credentials, Device, Refresh. **Why:** secure machine and user auth. **How:** connected app + flow. **PSK:** JWT flow for n8n's server-to-server calls into Salesforce.

**Connected apps** — **What:** register an external app with scopes/policies. **Why:** control and audit external access. **How:** Setup → App Manager. **PSK:** the "PSK n8n Bridge" connected app.

**SSO (SAML/OIDC), Auth Providers, JIT** — **What:** federated login and auto-provisioning. **Why:** one identity, less admin. **How:** configure IdP/SP. **PSK:** future citizen portal social/OIDC login.

---

# PHASE 10 — Service, Cases & Routing

**Cases & channels** — **What:** the service object + Web/Email-to-Case intake. **Why:** structured request handling. **How:** enable channels + Case object. **PSK:** the application *is* PSK's "case-like" root; the concepts transfer directly.

**Queues & Omni-Channel** — **What:** shared buckets + real-time skills/capacity routing. **Why:** route work to the right available person. **How:** Omni setup + presence/routing configs. **PSK:** queues today; Omni-Channel is the upgrade path for live desk routing.

**Escalation, entitlements & milestones** — **What:** SLA timing and escalation. **Why:** enforce turnaround (esp. Tatkal). **How:** business hours + milestones. **PSK:** `SLA_Config__mdt` targets per stage, normal vs Tatkal.

**Knowledge, macros, quick text, console** — **What:** articles, one-click actions, snippets, multi-tab workspace. **Why:** agent productivity + consistency. **How:** enable + author. **PSK:** a Knowledge article on "documents required for Re-Issue."

---

# PHASE 11 — Reporting & CRM Analytics (Deep Dive)

## 11a. Standard Reports & Dashboards

**Report types** — **What:** define which objects+fields a report can use (with primary/related object relationships). **Why:** you can't report on what no report type exposes. **How:** Setup → Report Types (custom ones for custom objects). **PSK:** a custom report type "Applications with Police Verifications."

**Report formats** — **What:** Tabular, Summary, Matrix, Joined. **Why:** shape data for the question. **How:** report builder. **PSK:** Summary report of applications grouped by `Status__c`.

**Groupings, filters, buckets, cross filters, summary formulas** — **What:** organize, segment, categorize, and calculate. **Why:** turn rows into insight. **How:** builder controls. **PSK:** bucket risk scores into Low/Medium/High; cross-filter "applications without a payment."

**Dashboards & dynamic dashboards** — **What:** visual summaries from source reports; running-user controls whose data shows. **Why:** at-a-glance office health. **How:** dashboard builder + running user. **PSK:** office-level dashboard of stage counts and SLA breaches (the standard-reporting version of what `pskHomeDashboard` does in code).

**Reporting snapshots & subscriptions** — **What:** capture report results over time; schedule delivery. **Why:** trend analysis + push. **How:** Analytic Snapshot + subscribe. **PSK:** daily snapshot of open applications per stage to trend backlog.

## 11b. CRM Analytics (formerly Tableau CRM / Einstein Analytics)

> CRM Analytics is a separate analytics platform layered on Salesforce for large-scale, multi-source, interactive exploration — beyond what standard reports do.

**CRM Analytics app** — **What:** a container for datasets, dashboards, and lenses. **Why:** package related analytics together. **How:** Analytics Studio → create app. **PSK:** a "PSK Operations" analytics app.

**Datasets** — **What:** optimized, columnar copies of data for fast querying. **Why:** interactive speed over millions of rows; blend sources. **How:** ingest via connectors/CSV. **PSK:** an `Applications` dataset combining application + payment + police verification fields.

**Data Prep (Recipes) & Dataflows** — **What:** visual ETL that builds datasets (join, transform, aggregate, compute). **Why:** shape and blend data before analysis. **How:** Data Manager → Recipe. **PSK:** a recipe joining applications to `SLA_Config__mdt` to compute an `SLA_Breached` flag per record.

**Lenses** — **What:** an ad-hoc exploration of one dataset. **Why:** quick "slice and dice" without building a dashboard. **How:** click into a dataset. **PSK:** explore applications by office and status.

**CRM Analytics dashboards & widgets** — **What:** interactive dashboards built from steps (queries) and widgets (charts, tables, toggles, filters, number widgets). **Why:** faceted, drillable, cross-filtered analytics. **How:** dashboard designer. **PSK:** a dashboard where clicking an office filters every chart (stage mix, average days-in-stage, breach rate).

**Steps & bindings** — **What:** a *step* is a saved query; *bindings* let one widget's selection drive another's query (faceting/interaction). **Why:** true interactivity beyond static charts. **How:** widget faceting or manual binding expressions. **PSK:** selecting "Tatkal" in a toggle re-queries the SLA-breach chart to Tatkal only.

**SAQL & SQL** — **What:** the query languages behind steps (SAQL = Salesforce Analytics Query Language; SQL also supported). **Why:** custom queries beyond the point-and-click builder. **How:** edit step query. **PSK:** a SAQL step computing 90th-percentile days-to-grant per office.

**Security predicates & sharing inheritance** — **What:** row-level security on datasets via a predicate expression, optionally inheriting Salesforce sharing. **Why:** an analyst should only see rows they're allowed to. **How:** set predicate on the dataset. **PSK:** predicate limiting each office manager to their own office's applications.

**Einstein Discovery** — **What:** automated predictive/prescriptive modelling with plain-language "stories." **Why:** find drivers and predict outcomes without hand-coding models. **How:** point it at a dataset + target variable. **PSK:** predict which applications are likely to breach SLA, and *why* (top factors: stage, office, Tatkal flag).

**Embedding in Lightning** — **What:** drop a CRM Analytics dashboard onto a record/home page. **Why:** analytics in the flow of work. **How:** App Builder Analytics component. **PSK:** embed the office dashboard on the RPO's home page (the managerial view PERSONAS describes).

---

# PHASE 12 — AI Layer (Agentforce / Einstein / Data Cloud)

**Data Cloud** — **What:** real-time, zero-copy platform unifying data into profiles. **Why:** grounds AI with trusted, current data (RAG). **How:** ingest + harmonize + activate. **PSK:** unify citizen + application signals to ground an agent.

**Prompt Builder** — **What:** declarative studio for reusable, grounded AI prompt templates. **Why:** the governed path from "AI idea" to production feature. **How:** author + ground + test template. **PSK:** a "summarise this application's history for an officer" prompt template.

**Agentforce & Agent Builder** — **What:** platform for autonomous AI agents that reason and act using Flows/Apex/prompts. **Why:** move from answering to *doing*. **How:** low-code Agent Builder. **PSK:** an internal agent that drafts an objection letter listing exactly which checklist items failed.

**Einstein Trust Layer** — **What:** AI governance: PII masking, zero data retention, toxicity filtering. **Why:** safe use of external LLMs on sensitive data. **How:** automatic on Agentforce/Prompt Builder. **PSK:** ensures Aadhaar-adjacent data is masked before any LLM call.

**Einstein (predictive)** — **What:** scoring/prediction/next-best-action. **Why:** proactive signals. **How:** enable + configure. **PSK:** predictive risk scoring feeding `Risk_Score__c`.

---

# PHASE 13 — n8n Integration (Deep Dive)

> **What n8n is.** n8n is an open-source workflow-automation tool (a self-hostable "iPaaS"). You build visual workflows of *nodes* — a trigger node starts the flow, action nodes call APIs (Salesforce, Twilio, HTTP, databases). **Why use it here:** it keeps notification/orchestration logic *outside* Salesforce, dodges Apex callout/governor limits for fan-out messaging, and lets you add channels (SMS, WhatsApp, email) without redeploying the org.

## The PSK notification bridge — end to end

**The shape:** *Salesforce event → n8n webhook → n8n calls Twilio → n8n writes the result back to Salesforce.*

**1. Trigger the send from Salesforce.** Two clean options:
- **Platform Event (preferred, decoupled):** a record-triggered Flow publishes `Notification_Requested__e` with fields (application Id, mobile, template, stage). n8n subscribes via the Pub/Sub API. **Why:** fire-and-forget, no callout in the transaction.
- **Named-credential callout:** a Flow/Queueable calls n8n's webhook URL via a Named Credential. **Why:** simplest to stand up; still keeps secrets out of code.

**2. n8n webhook node receives it.** The Webhook trigger node exposes an HTTPS URL; incoming JSON becomes the workflow's input. **PSK:** payload = `{ applicationId, mobile, stage, templateKey }`.

**3. n8n Twilio node sends the SMS.** Configure Twilio credentials once in n8n; map the message body from a template. **PSK:** "Your application {{ARN}} has entered Police Verification."

**4. Idempotency.** Twilio returns a message SID; write it back to `Notification_Log__c.Provider_Message_Id__c` (an External ID). **Why:** re-running the workflow upserts on that key instead of double-sending. **PSK:** exactly the field the build already reserves for this.

**5. Write back to Salesforce.** n8n's Salesforce node (authenticated via a Connected App / OAuth JWT) upserts the `Notification_Log__c` row with status = Sent/Failed + the SID. **Why:** the Auditor persona can later confirm the citizen was actually informed.

**6. Error handling & retries.** Use n8n's error workflow / retry-on-fail so a Twilio hiccup doesn't silently drop a notification; on final failure, write status = Failed so it's visible in Salesforce. **Why:** no silent gaps — the exact frustration PSK's design targets.

**7. Security.** n8n holds Twilio + Salesforce credentials in its own credential store; Salesforce holds only the n8n webhook URL (in a Named Credential). No secrets in metadata. **Why:** least privilege on both sides.

**Concepts exercised:** Platform Events / Pub-Sub API, Named Credentials, Connected App + OAuth JWT, External ID + upsert, idempotency, fire-and-forget integration pattern, error/retry design.

---

# PHASE 14 — UI Use Cases (Practical Patterns)

Simple, concrete UI patterns and where each fits in PSK. Each says **when to use it** and gives a **PSK example**.

**Screen Flow intake wizard** — **When:** multi-step guided data entry. **PSK:** a "New Application" screen flow that walks Front Office through applicant → address → documents, creating the `Passport_Application__c` at the end. *Why over a raw layout:* enforces order and gates required fields conversationally.

**Record page + Path + Dynamic Actions** — **When:** a record with a clear lifecycle. **PSK:** the application page shows the Path stage bar, and **Advance**/**Grant** buttons appear only in the right status via Dynamic Actions.

**Dashboard LWC (wire + cacheable Apex)** — **When:** aggregate KPIs on home/app pages. **PSK:** `pskHomeDashboard` wires stage counts + SLA breaches from `PSK_HomeController`; the manager's landing page. *Why LWC over a report:* custom layout, cross-object counts, click-through.

**Related-list-driven checklist LWC** — **When:** manage many child rows inline. **PSK:** a checklist component over `Document_Checklist_Item__c` with **Mark Received / Mark Verified** buttons, emitting an event when all items pass.

**List views as work queues** — **When:** an officer works a stream of records. **PSK:** "Open in my queue" list view with inline edit for the Document Verification desk.

**Quick actions / global actions** — **When:** one-click create/update from a record or anywhere. **PSK:** **Collect Payment**, **New Objection**, **Mark Cleared** — the verbs each persona actually uses.

**Utility bar widget** — **When:** always-available tool across tabs. **PSK:** a "recent applications" utility for fast switching.

**Printable Visualforce PDF** — **When:** a formatted document artifact. **PSK:** an application acknowledgement slip as a VF-rendered PDF.

**Embedded CRM Analytics dashboard** — **When:** rich interactive analytics in context. **PSK:** office performance dashboard embedded on the RPO home page.

---

# PHASE 15 — Testing & Quality

> Nothing ships without a test. This phase is a first-class deliverable, not a cleanup step.

**Apex test classes** — **What:** `@isTest` classes exercising your code. **Why:** required to deploy (≥75% org coverage) and to prove behavior. **How:** arrange → act → assert. **PSK:** `PSK_ApplicationActionsControllerTest` drives an application Draft→Delivered and asserts exactly one booklet/print/dispatch is minted.

**Meaningful assertions** — **What:** `Assert.areEqual(...)` on real outcomes, not just running code. **Why:** coverage without assertions proves nothing. **PSK:** assert the booklet number matches the Indian format and the external ID mirrors it.

**Test data factory** — **What:** a reusable class that builds test records. **Why:** DRY, consistent setup; `@isTest(SeeAllData=false)` isolates from org data. **PSK:** a factory creating an application + citizen + fee-eligible setup.

**`Test.startTest()/stopTest()`** — **What:** reset limits mid-test and force async to run. **Why:** test governor-limit behavior and Queueable/Batch. **PSK:** wrap `advance()` to assert the async notification enqueues.

**Mocking callouts (`HttpCalloutMock`, `Test.setMock`)** — **What:** simulate external responses. **Why:** you can't call n8n/Twilio from a test. **PSK:** mock the n8n webhook response when testing the notification callout.

**Flow testing** — **What:** built-in Flow tests (given record → assert outcome). **Why:** cover declarative logic too. **PSK:** a Flow test that a submitted application generates the correct checklist items.

**LWC Jest tests** — **What:** `sfdx-lwc-jest` unit tests for components. **Why:** verify rendering and events without a browser. **PSK:** assert the checklist LWC fires its "all verified" event.

**UAT walkthrough** — **What:** scripted end-to-end persona test. **Why:** proves the *system*, not just the units. **PSK:** the Draft→Delivered walkthrough each persona's actions in sequence (mirrors the readiness report's UAT checklist).

**Run + measure.** `sf apex run test --test-level RunLocalTests --code-coverage`. **PSK target:** keep the 188/188 green and coverage in place across the automation layer.

---

# PHASE 16 — DevOps & Deployment

**Sandboxes / scratch orgs / Dev Hub** — **What:** build/test environments. **Why:** never build in prod. **PSK:** `psk-dev` today; scratch orgs for future feature branches.

**Source format & Git** — **What:** metadata as version-controlled source. **Why:** history, review, rollback. **PSK:** `force-app/main/default/` in Git.

**CLI deploy / retrieve** — **What:** move metadata via `sf`. **Why:** repeatable, scriptable. **PSK:** `sf project deploy start --source-dir force-app`.

**Change Sets / Unlocked Packages / DevOps Center** — **What:** declarative migration / modular packaging / Git-backed release UI. **Why:** structured promotion across orgs. **PSK:** unlocked package is the natural next step for modular release.

**Incremental deploy sequence (PSK rule)** — **What:** value sets → objects → layouts → security → code → app shell. **Why:** each layer depends on the previous; deploy order prevents dependency failures. **PSK:** the project's standing deploy convention.

---

# Curriculum Roadmap (Phase → Concepts → PSK Deliverable → Test)

| Phase | Core concepts | PSK deliverable | How it's tested |
|---|---|---|---|
| 0 Orientation | multi-tenancy, limits, CLI, SFDX | retrieve the org, confirm deploy works | successful `retrieve` + `deploy` |
| 1 Data model | objects, fields, record types, relationships, `__mdt` | the 16-object model + Fee/SLA metadata | schema deploys; records visible |
| 2 Data mgmt | validation, external IDs, field history, PII | validation rules + seed data | validation blocks bad saves |
| 3 Security | profiles, permission sets, OWD, sharing rules, queues | 7 personas + 9 sharing rules + 6 queues | persona access matrix (UAT) |
| 4 UI/layouts | record pages, Path, dynamic actions | app shell, tabs, Path | manual smoke test |
| 5 Automation | Flow, validation, approvals | checklist flow + Diplomatic approval | Flow test |
| 6 Apex | triggers, bulkification, async, `__mdt` in Apex | `PSK_*` service/controller layer | Apex tests ≥75% |
| 7 Frontend | LWC, LDS, wire, events | 4 LWCs incl. home dashboard | Jest tests |
| 8 Integration | platform events, callouts, named creds | notification bridge scaffolding | mocked callout tests |
| 9 Identity | OAuth, connected apps | n8n bridge connected app | JWT auth handshake |
| 10 Service/routing | queues, Omni, SLA/milestones | queue routing + SLA config | routing UAT |
| 11 Reporting + CRM Analytics | report types, datasets, recipes, dashboards, SAQL | SLA-breach + risk analytics | dashboard renders; predicate scoped |
| 12 AI | Data Cloud, Prompt Builder, Agentforce | objection-draft prompt template | prompt grounding review |
| 13 n8n | webhook, Twilio, idempotency, retries | end-to-end SMS on stage change | send + write-back verified |
| 14 UI use cases | screen flow, dashboard LWC, quick actions | intake wizard + checklist LWC | Jest + Flow tests |
| 15 Testing | Apex/Flow/Jest tests, mocking, UAT | full test suite | `RunLocalTests` green |
| 16 DevOps | source format, Git, deploy order, packaging | incremental deploy pipeline | clean deploy from scratch |

---

# Guardrails Recap (read before every build step)

1. **Configure before you code.**
2. **Bulkify everything** — no SOQL/DML in loops.
3. **Never delete metadata/data without asking.**
4. **Deploy incrementally**, verifying each layer.
5. **PII:** never store Aadhaar number; OWD Private on personal data.
6. **Snapshot a declaration, derive a fact** — pick correctly per field.
7. **Done = deployed + tested + demonstrated + PII-safe.**

> Teach the concept. Apply it to PSK. Prove it with a test. Then move to the next phase.