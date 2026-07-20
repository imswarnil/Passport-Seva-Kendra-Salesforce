# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

Salesforce (SFDX source-format) project for a custom **Passport Seva Kendra** app being built on a Salesforce Developer Edition org. The local tree was retrieved from the org — the org is the source of truth, and local metadata must be deployed back for changes to take effect.

**Read [PSK.md](PSK.md) first** — it is the authoritative build guide: project goal, the "few objects, many fields" design philosophy, naming/PII conventions, the 11-object roadmap, and the complete step-by-step spec for the object currently being built (`Passport_Application__c`). [README.md](README.md) is the project overview. When building PSK features, follow PSK.md's incremental deploy sequence and its "What NOT to do yet" constraints.

- Default org alias: **`psk-dev`** (already set as the project `target-org`, so `--target-org` is optional on `sf` commands).
- Source API version: **67.0** (`sfdx-project.json`). Note: individual Apex classes carry their own `apiVersion` in their `.cls-meta.xml` (many are 61.0) — retrieved as-is from the org.

## Commands

```bash
# Pull the entire org into force-app/ (rebuilds local from org)
sf project retrieve start --manifest manifest/package.xml

# Pull specific components
sf project retrieve start --metadata ApexClass:LeadController
sf project retrieve start --metadata CustomObject:Reseller_Account_Plan__c

# Deploy local changes to the org
sf project deploy start --source-dir force-app          # deploy everything
sf project deploy start --metadata ApexClass:LeadController   # deploy one class
sf project deploy start --source-dir force-app --dry-run     # validate without saving

# Run Apex tests
sf apex run test --test-level RunLocalTests --result-format human --code-coverage
sf apex run test --class-names DataManager_UtilsTest         # a single test class
sf apex run test --tests DataManager_UtilsTest.someMethod    # a single test method

# Open the org / run anonymous Apex / tail logs
sf org open
sf apex run --file script.apex
sf apex tail log
```

Test classes follow the `<ClassName>Test` naming convention (e.g. `DataManager_Utils` → `DataManager_UtilsTest`); `DataManager_TestUtils` provides shared test-data setup.

## Architecture

Everything lives under `force-app/main/default/`, split by metadata type (`classes/`, `objects/`, `layouts/`, `profiles/`, `waveTemplates/`, etc.). `manifest/package.xml` is the full-org manifest used to retrieve/rebuild — regenerate it if new metadata types are added to the org. Three types are excluded from it because the source CLI can't handle them: `ExperienceContainer`, `PlatformEventMigration`, `TagSet`.

The Apex falls into a few functional groups, most of it inherited from Salesforce templates rather than hand-written for this app:

- **DataManager_\* (largest group)** — data-loading/management utilities from the **Service Analytics (CRM Analytics/Wave) template**. `DataManager_controller` is the Visualforce controller UI; `DataManager_Opportunity`, `_Quota`, `_Activity`, `_Dataflow`, `_CleanUp` generate/refresh sample data feeding the Wave dashboards; `DataManager_Utils`/`_TestUtils` are shared helpers. These pair with the `waveTemplates/` bundles (`Service_Analytics_Flex`, `Trailhead_Template*`) and the `wave/` analytics assets. The custom objects `OpportunityHistory__c` and `Reseller_Account_Plan__c` back these datasets.
- **Site/community auth** — `SiteLoginController`, `SiteRegisterController`, `ForgotPasswordController`, `ChangePasswordController`, `MyProfilePageController` are the standard Experience Cloud (Communities) self-registration/login controllers, paired with the `Internal Zone` community and Visualforce pages under `pages/`.
- **App-specific (in progress)** — `LeadController` and `Upload_*_EM` (Einstein/data upload flow) and `OpenAIChatController` are the custom pieces being built on top; these are the ones most likely relevant to Passport Seva Kendra feature work.

There are no LWC or Aura component directories yet; UI is Visualforce pages (`pages/`) plus Lightning pages (`flexipages/`).

## Security note

`classes/OpenAIChatController.cls` contains a **hardcoded OpenAI API key** in source. Treat it as compromised: rotate the key, and move it to a Named Credential / Custom Setting / Protected Custom Metadata rather than a string literal before deploying further. Do not copy this pattern into new classes.
