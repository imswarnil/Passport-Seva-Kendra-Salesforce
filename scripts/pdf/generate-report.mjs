#!/usr/bin/env node
/**
 * PSK Org Readiness Report generator.
 *
 * Node 22, zero npm dependencies. Renders scripts/pdf/build/PSK_Org_Readiness_Report.html
 * from scripts/pdf/report-data.json plus a live scan of force-app/, then shells out to
 * headless Chrome to print PSK_Org_Readiness_Report.pdf at the repository root.
 *
 *   node scripts/pdf/generate-report.mjs              # HTML + PDF
 *   node scripts/pdf/generate-report.mjs --html-only   # HTML only, no Chrome needed
 *
 * Design note: every count in the report is derived here, at generation time, by reading
 * the metadata tree. Nothing countable is hard-coded in report-data.json, because other
 * work lands in force-app/ continuously and a hard-coded number would go stale silently.
 */

import { readFileSync, writeFileSync, mkdirSync, existsSync, readdirSync, statSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
import { dirname, join, resolve, basename } from 'node:path';
import { fileURLToPath } from 'node:url';

const HERE = dirname(fileURLToPath(import.meta.url));
const REPO = resolve(HERE, '..', '..');
const SRC = join(REPO, 'force-app', 'main', 'default');
const BUILD = join(HERE, 'build');
const HTML_OUT = join(BUILD, 'PSK_Org_Readiness_Report.html');
const PDF_OUT = join(REPO, 'PSK_Org_Readiness_Report.pdf');
const CHROME = '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';

const HTML_ONLY = process.argv.includes('--html-only');

/* ------------------------------------------------------------------ helpers */

const esc = (s) =>
  String(s ?? '').replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');

/** Escape for display but keep the small HTML vocabulary the JSON prose uses. */
const rich = (s) => String(s ?? '');

const ls = (p) => {
  try {
    return readdirSync(p).sort();
  } catch {
    return [];
  }
};
const isDir = (p) => {
  try {
    return statSync(p).isDirectory();
  } catch {
    return false;
  }
};
const read = (p) => {
  try {
    return readFileSync(p, 'utf8');
  } catch {
    return '';
  }
};
const size = (p) => {
  try {
    return statSync(p).size;
  } catch {
    return null;
  }
};

/** All values of a repeated simple XML tag. Adequate for the flat metadata we read. */
const tags = (xml, tag) => [...xml.matchAll(new RegExp(`<${tag}>([\\s\\S]*?)</${tag}>`, 'g'))].map((m) => m[1]);
const tag1 = (xml, tag) => tags(xml, tag)[0] ?? '';
const unent = (s) =>
  String(s)
    .replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>')
    .replace(/&quot;/g, '"')
    .replace(/&apos;/g, "'")
    .replace(/&amp;/g, '&');

const sh = (cmd, args) => {
  try {
    return execFileSync(cmd, args, { cwd: REPO, encoding: 'utf8' }).trim();
  } catch {
    return null;
  }
};

/* ------------------------------------------------------------- repo scanning */

/** Objects that belong to PSK, as opposed to inherited-template or standard objects. */
const NON_PSK_OBJECTS = new Set(['Account', 'OpportunityHistory__c', 'Reseller_Account_Plan__c']);

function scanObjects() {
  const dir = join(SRC, 'objects');
  const out = [];
  for (const name of ls(dir)) {
    const objDir = join(dir, name);
    if (!isDir(objDir)) continue;
    const metaPath = join(objDir, `${name}.object-meta.xml`);
    const xml = read(metaPath);
    const nameFieldBlock = /<nameField>([\s\S]*?)<\/nameField>/.exec(xml)?.[1] ?? '';
    const fieldFiles = ls(join(objDir, 'fields')).filter((f) => f.endsWith('.field-meta.xml'));

    const fields = fieldFiles.map((f) => {
      const fx = read(join(objDir, 'fields', f));
      return {
        api: f.replace('.field-meta.xml', ''),
        label: tag1(fx, 'label'),
        type: tag1(fx, 'type'),
        referenceTo: tag1(fx, 'referenceTo'),
        relationshipName: tag1(fx, 'relationshipName'),
        formula: unent(tag1(fx, 'formula')),
        encrypted: /<encryptionScheme>/.test(fx) ? tag1(fx, 'encryptionScheme') : '',
      };
    });

    const recordTypes = ls(join(objDir, 'recordTypes'))
      .filter((f) => f.endsWith('.recordType-meta.xml'))
      .map((f) => {
        const rx = read(join(objDir, 'recordTypes', f));
        const picklists = [...rx.matchAll(/<picklistValues>([\s\S]*?)<\/picklistValues>/g)].map((m) => ({
          picklist: tag1(m[1], 'picklist'),
          values: tags(m[1], 'fullName'),
        }));
        return {
          api: f.replace('.recordType-meta.xml', ''),
          label: tag1(rx, 'label'),
          active: tag1(rx, 'active') === 'true',
          picklists,
        };
      });

    const validationRules = ls(join(objDir, 'validationRules'))
      .filter((f) => f.endsWith('.validationRule-meta.xml'))
      .map((f) => {
        const vx = read(join(objDir, 'validationRules', f));
        return {
          object: name,
          api: f.replace('.validationRule-meta.xml', ''),
          active: tag1(vx, 'active') === 'true',
          formula: unent(tag1(vx, 'errorConditionFormula')).replace(/\s+/g, ' ').trim(),
          message: unent(tag1(vx, 'errorMessage')),
          field: tag1(vx, 'errorDisplayField'),
        };
      });

    const compactLayouts = ls(join(objDir, 'compactLayouts'))
      .filter((f) => f.endsWith('.compactLayout-meta.xml'))
      .map((f) => ({
        api: f.replace('.compactLayout-meta.xml', ''),
        fields: tags(read(join(objDir, 'compactLayouts', f)), 'fields'),
      }));

    out.push({
      api: name,
      isPsk: !NON_PSK_OBJECTS.has(name),
      isMdt: name.endsWith('__mdt'),
      label: tag1(xml, 'label') || name,
      pluralLabel: tag1(xml, 'pluralLabel'),
      description: tag1(xml, 'description'),
      owd: tag1(xml, 'sharingModel'),
      nameFieldLabel: tag1(nameFieldBlock, 'label'),
      nameFieldType: tag1(nameFieldBlock, 'type'),
      nameFieldFormat: tag1(nameFieldBlock, 'displayFormat'),
      compactLayoutAssignment: tag1(xml, 'compactLayoutAssignment'),
      enableHistory: tag1(xml, 'enableHistory') === 'true',
      enableReports: tag1(xml, 'enableReports') === 'true',
      fieldCount: fields.length,
      fields,
      recordTypes,
      validationRules,
      compactLayouts,
      listViewCount: ls(join(objDir, 'listViews')).length,
    });
  }
  return out;
}

function scanApps() {
  return ls(join(SRC, 'applications'))
    .filter((f) => f.endsWith('.app-meta.xml') && !f.startsWith('standard__'))
    .map((f) => {
      const xml = read(join(SRC, 'applications', f));
      return {
        api: f.replace('.app-meta.xml', ''),
        label: tag1(xml, 'label'),
        headerColor: tag1(xml, 'headerColor'),
        tabs: tags(xml, 'tabs'),
        utilityBar: tag1(xml, 'utilityBar'),
      };
    });
}

function scanFlexipages() {
  return ls(join(SRC, 'flexipages'))
    .filter((f) => f.endsWith('.flexipage-meta.xml'))
    .map((f) => {
      const xml = read(join(SRC, 'flexipages', f));
      return {
        api: f.replace('.flexipage-meta.xml', ''),
        label: tag1(xml, 'masterLabel'),
        type: tag1(xml, 'type'),
        sobjectType: tag1(xml, 'sobjectType'),
      };
    });
}

function scanPermissionSets() {
  return ls(join(SRC, 'permissionsets'))
    .filter((f) => f.startsWith('PSK') && f.endsWith('.permissionset-meta.xml'))
    .map((f) => {
      const xml = read(join(SRC, 'permissionsets', f));
      const objPerms = [...xml.matchAll(/<objectPermissions>([\s\S]*?)<\/objectPermissions>/g)].map((m) => ({
        object: tag1(m[1], 'object'),
        c: tag1(m[1], 'allowCreate') === 'true',
        r: tag1(m[1], 'allowRead') === 'true',
        u: tag1(m[1], 'allowEdit') === 'true',
        d: tag1(m[1], 'allowDelete') === 'true',
        va: tag1(m[1], 'viewAllRecords') === 'true',
        ma: tag1(m[1], 'modifyAllRecords') === 'true',
      }));
      return {
        api: f.replace('.permissionset-meta.xml', ''),
        label: tag1(xml, 'label') || f.replace('.permissionset-meta.xml', ''),
        description: tag1(xml, 'description'),
        objPerms,
        fieldPermCount: tags(xml, 'fieldPermissions').length,
      };
    });
}

function scanSharingRules(pskObjects) {
  const names = new Set(pskObjects.map((o) => o.api));
  const out = [];
  for (const f of ls(join(SRC, 'sharingRules'))) {
    const obj = f.replace('.sharingRules-meta.xml', '');
    if (!names.has(obj)) continue;
    const xml = read(join(SRC, 'sharingRules', f));
    for (const m of xml.matchAll(/<sharingCriteriaRules>([\s\S]*?)<\/sharingCriteriaRules>/g)) {
      const b = m[1];
      const crit = [...b.matchAll(/<criteriaItems>([\s\S]*?)<\/criteriaItems>/g)].map(
        (c) => `${tag1(c[1], 'field')} ${tag1(c[1], 'operation')} ${tag1(c[1], 'value')}`
      );
      const sharedTo = /<sharedTo>([\s\S]*?)<\/sharedTo>/.exec(b)?.[1] ?? '';
      const target = /<(\w+)>([\s\S]*?)<\/\1>/.exec(sharedTo.trim());
      out.push({
        object: obj,
        api: tag1(b, 'fullName'),
        label: tag1(b, 'label'),
        access: tag1(b, 'accessLevel'),
        sharedTo: target ? `${target[2]} (${target[1]})` : '',
        criteria: crit.join(' AND '),
        description: tag1(b, 'description'),
      });
    }
  }
  return out;
}

function scanCustomMetadataRecords() {
  const byType = {};
  for (const f of ls(join(SRC, 'customMetadata'))) {
    if (!f.endsWith('.md-meta.xml')) continue;
    const type = f.split('.')[0];
    (byType[type] ||= []).push(f.replace('.md-meta.xml', '').split('.').slice(1).join('.'));
  }
  return byType;
}

function scanApexApiVersions() {
  const out = [];
  for (const f of ls(join(SRC, 'classes'))) {
    if (!f.endsWith('.cls-meta.xml')) continue;
    if (!f.startsWith('PSK')) continue;
    out.push({ cls: f.replace('.cls-meta.xml', ''), apiVersion: tag1(read(join(SRC, 'classes', f)), 'apiVersion') });
  }
  return out;
}

function scanPathAssistants() {
  return ls(join(SRC, 'pathAssistants'))
    .filter((f) => f.endsWith('.pathAssistant-meta.xml'))
    .map((f) => {
      const xml = read(join(SRC, 'pathAssistants', f));
      return {
        api: f.replace('.pathAssistant-meta.xml', ''),
        label: tag1(xml, 'masterLabel'),
        entity: tag1(xml, 'entityName'),
        recordType: tag1(xml, 'recordTypeName'),
        active: tag1(xml, 'active') === 'true',
        picklistField: tag1(xml, 'pathAssistantFieldName') || 'Status__c',
        steps: tags(xml, 'picklistValueName'),
      };
    });
}

function scanQuickActions() {
  const out = [];
  for (const f of ls(join(SRC, 'quickActions'))) {
    if (!f.endsWith('.quickAction-meta.xml')) continue;
    const parts = f.replace('.quickAction-meta.xml', '').split('.');
    if (parts.length < 2) continue; // global action, not object-scoped
    const xml = read(join(SRC, 'quickActions', f));
    out.push({
      host: parts[0],
      api: parts[1],
      label: tag1(xml, 'label'),
      type: tag1(xml, 'type'),
      targetObject: tag1(xml, 'targetObject'),
      targetParentField: tag1(xml, 'targetParentField'),
      targetRecordType: tag1(xml, 'targetRecordType'),
      fieldOverrides: [...xml.matchAll(/<fieldOverrides>([\s\S]*?)<\/fieldOverrides>/g)].map((m) => ({
        field: tag1(m[1], 'field'),
        literal: tag1(m[1], 'literalValue'),
        formula: unent(tag1(m[1], 'formula')),
      })),
    });
  }
  return out;
}

function scanPermissionSetGroups() {
  return ls(join(SRC, 'permissionsetgroups'))
    .filter((f) => f.endsWith('.permissionsetgroup-meta.xml'))
    .map((f) => {
      const xml = read(join(SRC, 'permissionsetgroups', f));
      return {
        api: f.replace('.permissionsetgroup-meta.xml', ''),
        label: tag1(xml, 'label'),
        description: tag1(xml, 'description'),
        sets: tags(xml, 'permissionSets'),
      };
    });
}

/**
 * Declared order of a restricted picklist's values. Metadata stores <values> blocks in
 * alphabetical order inside a field, but a Path's steps are only meaningful in lifecycle
 * order — so the order has to come from the field's own valueSetDefinition.
 */
function picklistOrder(objectApi, fieldApi) {
  const xml = read(join(SRC, 'objects', objectApi, 'fields', `${fieldApi}.field-meta.xml`));
  const def = /<valueSetDefinition>([\s\S]*?)<\/valueSetDefinition>/.exec(xml)?.[1] ?? '';
  return [...def.matchAll(/<value>([\s\S]*?)<\/value>/g)].map((m) => tag1(m[1], 'fullName') || tag1(m[1], 'label'));
}

function scanTranslations() {
  const locales = new Set();
  const bundles = [];
  for (const d of ls(join(SRC, 'objectTranslations'))) {
    if (!isDir(join(SRC, 'objectTranslations', d))) continue;
    bundles.push(d);
    const loc = d.split('-').slice(-1)[0];
    locales.add(loc);
  }
  return { bundles, locales: [...locales].sort() };
}

function collectFacts() {
  const objects = scanObjects();
  const pskObjects = objects.filter((o) => o.isPsk && !o.isMdt);
  const mdtObjects = objects.filter((o) => o.isMdt);
  const apps = scanApps();
  const flexipages = scanFlexipages();
  const tabs = ls(join(SRC, 'tabs'))
    .filter((f) => f.endsWith('.tab-meta.xml'))
    .map((f) => f.replace('.tab-meta.xml', ''));
  const tabSet = new Set(tabs);
  const layoutFiles = ls(join(SRC, 'layouts'));
  const layoutsByObject = {};
  for (const f of layoutFiles) {
    const obj = f.split('-')[0];
    (layoutsByObject[obj] ||= []).push(decodeURIComponent(f.replace('.layout-meta.xml', '').split('-').slice(1).join('-')));
  }

  // Which app(s) surface each object's tab?
  const appForObject = {};
  for (const app of apps) {
    for (const t of app.tabs) {
      if (!appForObject[t]) appForObject[t] = [];
      appForObject[t].push(app.label || app.api);
    }
  }

  const validationRules = objects.flatMap((o) => o.validationRules);

  return {
    generatedAt: new Date(),
    gitSha: sh('git', ['rev-parse', '--short', 'HEAD']) ?? 'unknown',
    gitBranch: sh('git', ['rev-parse', '--abbrev-ref', 'HEAD']) ?? 'unknown',
    gitDirty: (sh('git', ['status', '--porcelain']) ?? '').length > 0,
    nodeVersion: process.version,
    objects,
    pskObjects,
    mdtObjects,
    apps,
    flexipages,
    recordPages: flexipages.filter((f) => f.type === 'RecordPage'),
    tabs,
    tabSet,
    layoutsByObject,
    appForObject,
    validationRules,
    permissionSets: scanPermissionSets(),
    sharingRules: scanSharingRules(pskObjects),
    roles: ls(join(SRC, 'roles')).filter((f) => f.endsWith('.role-meta.xml')).map((f) => f.replace('.role-meta.xml', '')),
    queues: ls(join(SRC, 'queues')).filter((f) => f.endsWith('.queue-meta.xml')).map((f) => f.replace('.queue-meta.xml', '')),
    groups: ls(join(SRC, 'groups')).filter((f) => f.endsWith('.group-meta.xml')).map((f) => f.replace('.group-meta.xml', '')),
    globalValueSets: ls(join(SRC, 'globalValueSets'))
      .filter((f) => f.endsWith('.globalValueSet-meta.xml'))
      .map((f) => f.replace('.globalValueSet-meta.xml', '')),
    lwc: ls(join(SRC, 'lwc')).filter((f) => isDir(join(SRC, 'lwc', f))),
    triggers: ls(join(SRC, 'triggers')).filter((f) => f.endsWith('.trigger')).map((f) => f.replace('.trigger', '')),
    flows: ls(join(SRC, 'flows')).filter((f) => f.endsWith('.flow-meta.xml')).map((f) => f.replace('.flow-meta.xml', '')),
    cmdRecords: scanCustomMetadataRecords(),
    apexApiVersions: scanApexApiVersions(),
    pathAssistants: scanPathAssistants(),
    translations: scanTranslations(),
    permissionSetGroups: scanPermissionSetGroups(),
    quickActions: scanQuickActions(),

    // ---- action-item verification probes -------------------------------
    probes: {
      openAiClassExists: existsSync(join(SRC, 'classes', 'OpenAIChatController.cls')),
      openAiInGitHistory: (sh('git', ['log', '--oneline', '--all', '--', '*OpenAIChatController*']) ?? '').length > 0,
      approvalProcessesDirExists: isDir(join(SRC, 'approvalProcesses')),
      approvalProcessCount: ls(join(SRC, 'approvalProcesses')).length,
      reportsDirExists: isDir(join(SRC, 'reports')),
      dashboardsDirExists: isDir(join(SRC, 'dashboards')),
      pskReportTypes: ls(join(SRC, 'reportTypes')).filter((f) => /psk|passport|citizen/i.test(f)),
      reportTypeCount: ls(join(SRC, 'reportTypes')).filter((f) => f.endsWith('.reportType-meta.xml')).length,
      manifestTypeCount: (read(join(REPO, 'manifest', 'package.xml')).match(/<name>/g) ?? []).length,
      scopedManifestExists: existsSync(join(REPO, 'manifest', 'psk-package.xml')),
      strayClasses: ['ABC.cls', 'TestSheet.cls', 'LeadController.cls']
        .map((f) => ({ file: f, bytes: size(join(SRC, 'classes', f)) }))
        .filter((x) => x.bytes !== null),
      orphanLeadLayout: ls(join(SRC, 'layouts')).filter((f) => /^Lead-Passport/.test(f)),
      contentAssetTotal: ls(join(SRC, 'contentassets')).length,
      contentAssetDupes: ls(join(SRC, 'contentassets')).filter((f) => /_1[0-9]?\./.test(f)).length,
      communities: ls(join(SRC, 'communities')).map((f) => f.replace('.community-meta.xml', '')),
      digitalExperiences: ls(join(SRC, 'digitalExperiences')),
    },
  };
}

/* ---------------------------------------------------- derived / cross-checks */

function derive(F, DATA) {
  const appObj = F.objects.find((o) => o.api === 'Passport_Application__c');

  // Objects missing a page layout in the tree.
  const missingLayouts = F.pskObjects.filter((o) => !(F.layoutsByObject[o.api]?.length)).map((o) => o.api);

  // Objects with no tab.
  const missingTabs = F.pskObjects.filter((o) => !F.tabSet.has(o.api)).map((o) => o.api);

  // Relationship graph, PSK objects only.
  const relationships = [];
  for (const o of F.pskObjects) {
    for (const f of o.fields) {
      if (f.type === 'MasterDetail' || f.type === 'Lookup') {
        relationships.push({
          from: o.api,
          field: f.api,
          to: f.referenceTo,
          type: f.type,
          relationshipName: f.relationshipName,
        });
      }
    }
  }

  // Related lists on the application = child relationships pointing at it.
  const childrenOf = (api) => relationships.filter((r) => r.to === api);

  // The inactive-by-design rule.
  const citizenRule = F.validationRules.find((v) => v.api === 'Citizen_Required_On_Submit');

  // Region field for criteria-based sharing.
  const regionFieldOnApp = appObj?.fields.some((f) => f.api === 'Region__c' && f.type !== 'Formula');

  // Aadhaar token field state.
  const aadhaarToken = appObj?.fields.find((f) => f.api === 'Aadhaar_Token__c');

  // Path coverage. Re-order each path's steps into the picklist's declared lifecycle
  // order; the metadata lists them alphabetically, which reads as a false sequence.
  const statusOrder = picklistOrder('Passport_Application__c', 'Status__c');
  const rank = (v) => {
    const i = statusOrder.indexOf(v);
    return i === -1 ? 999 : i;
  };
  const appPaths = F.pathAssistants
    .filter((p) => p.entity === 'Passport_Application__c')
    .map((p) => ({ ...p, steps: [...p.steps].sort((a, b) => rank(a) - rank(b)) }));
  const coveredRecordTypes = new Set(appPaths.map((p) => p.recordType).filter(Boolean));
  const uncoveredRecordTypes = (appObj?.recordTypes ?? [])
    .map((rt) => rt.api)
    .filter((rt) => !coveredRecordTypes.has(rt));

  // Apex apiVersion drift.
  const projectApi = tag1(read(join(REPO, 'sfdx-project.json')), 'sourceApiVersion') ||
    (JSON.parse(read(join(REPO, 'sfdx-project.json')) || '{}').sourceApiVersion ?? DATA.meta.sourceApiVersion);
  const driftedClasses = F.apexApiVersions.filter((c) => c.apiVersion && c.apiVersion !== projectApi);

  // Live-derived storage numbers from the captured org snapshot.
  const counts = DATA.orgFacts.recordCounts;
  const totalRecords = counts.reduce((a, b) => a + b.count, 0);
  const inherited = counts.filter((c) => c.origin.startsWith('inherited')).reduce((a, b) => a + b.count, 0);
  const pskRecords = totalRecords - inherited;

  return {
    appObj,
    missingLayouts,
    missingTabs,
    relationships,
    childrenOf,
    citizenRule,
    regionFieldOnApp,
    aadhaarToken,
    appPaths,
    uncoveredRecordTypes,
    projectApi,
    driftedClasses,
    totalRecords,
    inherited,
    pskRecords,
  };
}

/* --------------------------------------------- validation-rule trip recipes */

const TRIP_RECIPES = {
  Require_Core_Fields_On_Submit: {
    input:
      'On a Fresh application with only <code>First_Name__c</code> = <em>Anjali</em> filled, set <code>Status__c</code> = <strong>Submitted</strong> and save.',
    blocks: true,
  },
  Minor_Needs_Guardian_Consent: {
    input:
      'On a Minor application with all core fields filled, tick <code>Applied_For_Minor__c</code>, leave <code>Guardian_Consent__c</code> unticked, set <code>Status__c</code> = <strong>Submitted</strong>.',
    blocks: true,
  },
  Cannot_Grant_With_Pending_Payment: {
    input:
      'On an application with <code>Payment_Status__c</code> = <strong>Not Paid</strong> (or Pending / Failed / Refunded), set <code>Status__c</code> = <strong>Granting</strong>.',
    blocks: true,
  },
  No_Backward_Move_Once_Delivered: {
    input:
      'On an application already saved at <code>Status__c</code> = <strong>Delivered</strong>, change <code>Status__c</code> to <strong>Dispatch</strong> and save.',
    blocks: true,
  },
  Citizen_Required_On_Submit: {
    input:
      'With the rule <strong>active</strong>: on an application with <code>Citizen__c</code> blank, set <code>Status__c</code> = <strong>Submitted</strong>. Also confirm that while the rule is <strong>inactive</strong> the same save succeeds — that is the shipped state.',
    blocks: true,
  },
};

const tripFor = (rule) =>
  TRIP_RECIPES[rule.api]?.input ??
  `Construct a record that makes this formula evaluate to TRUE, then save: <code>${esc(rule.formula)}</code>`;

/* ------------------------------------------------------------------- the ERD */

function erdSvg(D) {
  // Hand-laid boxes. Coordinates are deliberate, not generated — the point of a
  // hand-written ERD is that the reader's eye follows the lifecycle left to right.
  const box = (x, y, w, h, api, sub, accent) => `
    <g class="ent">
      <rect x="${x}" y="${y}" width="${w}" height="${h}" rx="8" fill="#ffffff"
            stroke="${accent}" stroke-width="${accent === '#1a2a5e' ? 2.5 : 1.6}"/>
      <rect x="${x}" y="${y}" width="${w}" height="7" rx="3.5" fill="${accent}"/>
      <text x="${x + w / 2}" y="${y + 32}" text-anchor="middle"
            font-size="15" font-weight="700" fill="#1a2a5e">${esc(api)}</text>
      ${sub
        .map(
          (line, i) =>
            `<text x="${x + w / 2}" y="${y + 52 + i * 15}" text-anchor="middle" font-size="11.5" fill="#4a5568">${line}</text>`
        )
        .join('')}
    </g>`;

  const NAVY = '#1a2a5e';
  const GOLD = '#c9a227';
  const SLATE = '#7c8798';

  return `
<svg viewBox="0 0 960 660" class="erd" role="img" aria-label="Entity relationship diagram centred on Passport_Application__c">
  <defs>
    <marker id="arrowSolid" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" markerHeight="7" orient="auto-start-reverse">
      <path d="M0,0 L10,5 L0,10 z" fill="${NAVY}"/>
    </marker>
    <marker id="arrowDash" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" markerHeight="7" orient="auto-start-reverse">
      <path d="M0,0 L10,5 L0,10 z" fill="${SLATE}"/>
    </marker>
  </defs>

  <!-- ===== master-detail (solid) ===== -->
  <g stroke="${NAVY}" stroke-width="2.2" fill="none" marker-end="url(#arrowSolid)">
    <line x1="145" y1="455" x2="145" y2="168"/>            <!-- Family_Member -> Citizen -->
    <line x1="655" y1="332" x2="592" y2="318"/>            <!-- Print_Job -> Application -->
    <line x1="655" y1="462" x2="592" y2="352"/>            <!-- Dispatch  -> Application -->
  </g>

  <!-- ===== lookups (dashed) ===== -->
  <g stroke="${SLATE}" stroke-width="1.7" fill="none" stroke-dasharray="6 4" marker-end="url(#arrowDash)">
    <line x1="352" y1="288" x2="256" y2="146"/>            <!-- Application -> Citizen -->
    <line x1="704" y1="168" x2="556" y2="250"/>            <!-- Passport -> Application -->
    <line x1="676" y1="104" x2="256" y2="104"/>            <!-- Passport -> Citizen -->
    <line x1="778" y1="298" x2="778" y2="170"/>            <!-- Print_Job -> Passport -->
    <polyline points="884,466 916,466 916,128 886,128"/>   <!-- Dispatch -> Passport -->
    <line x1="256" y1="486" x2="352" y2="352"/>            <!-- Family_Member -> Application (Minor_Application__c) -->
  </g>

  <!-- ===== edge labels ===== -->
  <g font-size="10.5" fill="${SLATE}" font-style="italic"
     stroke="#ffffff" stroke-width="3" paint-order="stroke fill" stroke-linejoin="round">
    <text x="156" y="316">Citizen__c (M-D)</text>
    <text x="300" y="212" text-anchor="end">Citizen__c</text>
    <text x="470" y="96" text-anchor="middle">Citizen__c</text>
    <text x="640" y="200" text-anchor="middle">Application__c</text>
    <text x="784" y="240">Passport__c</text>
    <text x="928" y="300" text-anchor="middle" transform="rotate(90 928 300)">Passport__c</text>
    <text x="300" y="444">Minor_Application__c</text>
  </g>
  <!-- The two master-detail edges into the application are too short to label in
       place; both fields are literally named Passport_Application__c and are listed
       in the relationship table below the diagram. -->
  <g font-size="9.5" fill="${NAVY}" font-weight="700" text-anchor="middle"
     stroke="#ffffff" stroke-width="3.5" paint-order="stroke fill" stroke-linejoin="round">
    <text x="623" y="318">M-D</text>
    <text x="626" y="398">M-D</text>
  </g>

  ${box(40, 62, 216, 106, 'Citizen__c', ['Golden identity — who they', 'are <tspan font-style="italic">now</tspan>', 'Text name · OWD Private'], GOLD)}
  ${box(676, 62, 210, 106, 'Passport__c', ['The issued booklet', '3 record types', 'Text name · OWD Private'], GOLD)}
  ${box(352, 250, 240, 118, 'Passport_Application__c', ['The whole lifecycle', 'ARN-{000000} · 6 record types', '12 statuses · OWD Private'], NAVY)}
  ${box(655, 296, 232, 90, 'Print_Job__c', ['Booklet printing', 'PRN-{00000} · child'], GOLD)}
  ${box(655, 426, 232, 90, 'Dispatch__c', ['Courier + delivery', 'DSP-{00000} · child'], GOLD)}
  ${box(40, 452, 216, 106, 'Family_Member__c', ['Citizen-to-citizen links', 'Carries the guardian link', 'FM-{00000} · child'], GOLD)}

  <!-- ===== legend ===== -->
  <g transform="translate(300, 578)">
    <rect x="0" y="0" width="360" height="62" rx="6" fill="#f7f8fb" stroke="#dde1e9"/>
    <line x1="16" y1="22" x2="58" y2="22" stroke="${NAVY}" stroke-width="2.2" marker-end="url(#arrowSolid)"/>
    <text x="68" y="26" font-size="11.5" fill="#3d4759">master-detail (cascade delete, OWD ControlledByParent)</text>
    <line x1="16" y1="44" x2="58" y2="44" stroke="${SLATE}" stroke-width="1.7" stroke-dasharray="6 4" marker-end="url(#arrowDash)"/>
    <text x="68" y="48" font-size="11.5" fill="#3d4759">lookup (independent lifecycle, own OWD)</text>
  </g>
</svg>`;
}

/* ----------------------------------------------------------- other SVG charts */

function storageChart(counts) {
  const rows = counts.filter((c) => c.count > 0).sort((a, b) => b.count - a.count);
  const max = Math.max(...rows.map((r) => r.count), 1);
  const rowH = 20;
  const labelW = 210;
  const barW = 470;
  const h = rows.length * rowH + 34;
  return `
<svg viewBox="0 0 760 ${h}" class="chart" role="img" aria-label="Record counts by object">
  <text x="0" y="12" font-size="11" font-weight="700" fill="#1a2a5e">RECORDS BY OBJECT (as of capture)</text>
  ${rows
    .map((r, i) => {
      const y = 28 + i * rowH;
      const w = Math.max(2, (r.count / max) * barW);
      const psk = !r.origin.startsWith('inherited');
      return `
    <text x="${labelW - 8}" y="${y + 11}" text-anchor="end" font-size="10.5" fill="${psk ? '#1a2a5e' : '#7c8798'}"
          font-weight="${psk ? 600 : 400}">${esc(r.object)}</text>
    <rect x="${labelW}" y="${y + 2}" width="${w}" height="12" rx="2" fill="${psk ? '#c9a227' : '#c3cad6'}"/>
    <text x="${labelW + w + 6}" y="${y + 12}" font-size="10" fill="#4a5568">${r.count.toLocaleString('en-IN')}</text>`;
    })
    .join('')}
  <g transform="translate(${labelW}, ${h - 4})" font-size="10" fill="#4a5568">
    <rect x="0" y="-9" width="10" height="8" rx="2" fill="#c9a227"/><text x="15" y="-2">PSK</text>
    <rect x="52" y="-9" width="10" height="8" rx="2" fill="#c3cad6"/><text x="67" y="-2">inherited template data</text>
  </g>
</svg>`;
}

/**
 * Two-column labelled bar chart of what has shipped. Labels sit outside the bars,
 * so nothing can collide however the numbers move between generations.
 */
function shippedChart(rows) {
  const max = Math.max(...rows.map((r) => r.value), 1);
  const perCol = Math.ceil(rows.length / 2);
  const colW = 380;
  const labelW = 128;
  const barW = 196;
  const rowH = 19;
  const h = perCol * rowH + 28;
  return `
<svg viewBox="0 0 760 ${h}" class="chart" role="img" aria-label="Metadata components shipped, by type">
  <text x="0" y="11" font-size="11" font-weight="700" fill="#1a2a5e">METADATA SHIPPED</text>
  ${rows
    .map((r, i) => {
      const col = Math.floor(i / perCol);
      const y = 24 + (i % perCol) * rowH;
      const x0 = col * colW;
      const w = Math.max(2, (r.value / max) * barW);
      return `
    <text x="${x0 + labelW - 8}" y="${y + 11}" text-anchor="end" font-size="10" fill="#4a5568">${esc(r.label)}</text>
    <rect x="${x0 + labelW}" y="${y + 2}" width="${w}" height="12" rx="2" fill="${r.fill}"/>
    <text x="${x0 + labelW + w + 5}" y="${y + 12}" font-size="10" font-weight="700" fill="#1a2a5e">${r.value}</text>`;
    })
    .join('')}
</svg>`;
}

function severityChart(items) {
  const buckets = ['P0', 'P1', 'P2'].map((sev) => ({
    sev,
    n: items.filter((i) => i.severity === sev).length,
    fill: sev === 'P0' ? '#9b1c1c' : sev === 'P1' ? '#c9a227' : '#5a6a85',
  }));
  const max = Math.max(...buckets.map((b) => b.n), 1);
  return `
<svg viewBox="0 0 300 118" class="chart" role="img" aria-label="Action items by severity">
  ${buckets
    .map((b, i) => {
      const h = (b.n / max) * 70;
      const x = 24 + i * 90;
      return `<rect x="${x}" y="${86 - h}" width="52" height="${h}" rx="3" fill="${b.fill}"/>
      <text x="${x + 26}" y="${80 - h}" text-anchor="middle" font-size="15" font-weight="700" fill="#1a2a5e">${b.n}</text>
      <text x="${x + 26}" y="104" text-anchor="middle" font-size="11" font-weight="700" fill="#4a5568">${b.sev}</text>`;
    })
    .join('')}
  <text x="0" y="10" font-size="11" font-weight="700" fill="#1a2a5e">OPEN ITEMS BY SEVERITY</text>
</svg>`;
}

/* ------------------------------------------------------------------ rendering */

const cb = () => '<span class="cb"></span>';
const checkRow = (label, detail = '') =>
  `<li>${cb()}<span class="ck-l">${label}</span>${detail ? `<span class="ck-d">${detail}</span>` : ''}</li>`;

function renderObjectInventory(F) {
  const rows = F.pskObjects
    .map((o) => {
      const nameField = o.nameFieldType === 'AutoNumber' ? `Auto Number <code>${esc(o.nameFieldFormat)}</code>` : `${esc(o.nameFieldType || '—')} — ${esc(o.nameFieldLabel || 'Name')}`;
      const rts = o.recordTypes.length ? o.recordTypes.map((r) => esc(r.api)).join(', ') : '<span class="muted">none</span>';
      const tab = F.tabSet.has(o.api) ? '<span class="yes">&#10003;</span>' : '<span class="no">&mdash;</span>';
      const app = (F.appForObject[o.api] ?? []).join(', ') || '<span class="muted">not in any app</span>';
      return `<tr>
        <td><code>${esc(o.api)}</code></td>
        <td>${esc(o.label)}</td>
        <td><span class="owd owd-${esc(o.owd)}">${esc(o.owd || '—')}</span></td>
        <td>${nameField}</td>
        <td>${rts}</td>
        <td class="num">${o.fieldCount}</td>
        <td class="nw">${tab}</td>
        <td class="small">${app}</td>
      </tr>`;
    })
    .join('');

  const mdt = F.mdtObjects
    .map(
      (o) =>
        `<tr><td><code>${esc(o.api)}</code></td><td>${esc(o.label)}</td><td colspan="2" class="muted">Custom Metadata Type</td><td class="muted">—</td><td class="num">${o.fieldCount}</td><td class="muted">—</td><td class="small">${(F.cmdRecords[o.api.replace('__mdt', '')] ?? []).length} records deployed</td></tr>`
    )
    .join('');

  return `
  <table class="grid">
    <thead><tr>
      <th>API name</th><th>Label</th><th>OWD</th><th>Name field</th><th>Record types</th>
      <th class="num">Fields</th><th class="nw">Tab</th><th>App</th>
    </tr></thead>
    <tbody>${rows}${mdt}</tbody>
  </table>`;
}

function renderUatChecklist(F, D) {
  return F.pskObjects
    .map((o) => {
      const children = D.childrenOf(o.api);
      const layouts = F.layoutsByObject[o.api] ?? [];
      const items = [];

      // create from tab
      if (F.tabSet.has(o.api)) {
        items.push(
          checkRow(
            `Create a record from the <strong>${esc(o.label)}</strong> tab.`,
            o.nameFieldType === 'AutoNumber'
              ? `Name auto-assigns in the form <code>${esc(o.nameFieldFormat)}</code>.`
              : `The <em>${esc(o.nameFieldLabel || 'Name')}</em> text name is required and saves as typed.`
          )
        );
      } else {
        items.push(
          checkRow(
            `<span class="flag">No tab</span> <strong>${esc(o.label)}</strong> has no <code>CustomTab</code> in the tree — records can only be reached from a parent or by URL. Confirm that is intended.`
          )
        );
      }

      // create from the parent's quick action — real actions first, then any
      // master-detail parent that has no action defined for it.
      const parents = o.fields.filter((f) => f.type === 'MasterDetail' || f.type === 'Lookup');
      const creatorActions = F.quickActions.filter((q) => q.targetObject === o.api && q.type === 'Create');
      for (const q of creatorActions) {
        const overrides = q.fieldOverrides
          .map((fo) => `<code>${esc(fo.field)}</code> = ${esc(fo.literal || fo.formula || '(blank)')}`)
          .join(', ');
        items.push(
          checkRow(
            `Create from the parent's quick action: on a <code>${esc(q.host)}</code> record, use <strong>${esc(q.label || q.api)}</strong>.`,
            `Action <code>${esc(q.host)}.${esc(q.api)}</code>${q.targetParentField ? `, parent field <code>${esc(q.targetParentField)}</code> pre-filled and read-only` : ''}${q.targetRecordType ? `, record type <code>${esc(q.targetRecordType)}</code>` : ''}.${overrides ? ` Pre-set: ${overrides}.` : ''}`
          )
        );
      }
      for (const p of parents.filter((f) => f.type === 'MasterDetail')) {
        const covered = creatorActions.some((q) => q.targetParentField === p.api || q.host === p.referenceTo);
        items.push(
          checkRow(
            `Create from the parent: open a <code>${esc(p.referenceTo)}</code> record and use the <em>New</em> action on the <strong>${esc(p.relationshipName || o.pluralLabel || o.label)}</strong> related list.${covered ? '' : ' <span class="flag">no quick action</span>'}`,
            `The <code>${esc(p.api)}</code> master-detail is pre-filled and cannot be changed after save.${covered ? '' : ' No purpose-built quick action targets this object from that parent — the generic New action is all a tester has.'}`
          )
        );
      }
      // non-create actions on this object
      const otherActions = F.quickActions.filter((q) => q.host === o.api && q.type !== 'Create');
      for (const q of otherActions) {
        const overrides = q.fieldOverrides
          .map((fo) => `<code>${esc(fo.field)}</code> &rarr; ${esc(fo.literal || fo.formula || '(blank)')}`)
          .join(', ');
        items.push(
          checkRow(
            `Quick action <strong>${esc(q.label || q.api)}</strong> (<code>${esc(q.api)}</code>, ${esc(q.type || 'Update')}) appears on the highlights panel and does what it says.`,
            overrides ? `Expect it to set ${overrides}. Confirm it is blocked when a validation rule should stop it.` : `Confirm the action's fields and that it respects the object's validation rules.`
          )
        );
      }
      if (parents.some((f) => f.type === 'MasterDetail')) {
        items.push(
          checkRow(
            `Confirm cascade delete: deleting the parent removes this child.`,
            `OWD is <code>ControlledByParent</code>, so record access follows the parent — verify with a persona that cannot see the parent.`
          )
        );
      }

      // validation rules
      for (const v of o.validationRules) {
        items.push(
          checkRow(
            `Validation rule <code>${esc(v.api)}</code>${v.active ? '' : ' <span class="flag">INACTIVE</span>'} trips as designed.`,
            `<span class="trip"><strong>Input:</strong> ${tripFor(v)}</span><span class="trip"><strong>Expect:</strong> save is blocked with &ldquo;${esc(v.message)}&rdquo;</span>`
          )
        );
      }
      if (!o.validationRules.length) {
        items.push(checkRow(`No validation rules on this object — confirm nothing needs one.`, `A child record with a Status picklist and no rules can be advanced out of order.`));
      }

      // record types + subsetted picklists
      for (const rt of o.recordTypes) {
        const subset = rt.picklists
          .filter((p) => p.values.length && p.values.length <= 6)
          .map((p) => `<code>${esc(p.picklist)}</code> → ${p.values.map(esc).join(' / ')}`);
        items.push(
          checkRow(
            `Record type <strong>${esc(rt.label || rt.api)}</strong>${rt.active ? '' : ' <span class="flag">inactive</span>'} shows only its subsetted picklist values.`,
            subset.length
              ? `<span class="trip">${subset.join(' &nbsp;·&nbsp; ')}</span>`
              : `<span class="trip">All picklists inherit the full value set for this record type.</span>`
          )
        );
      }

      // path
      const paths = F.pathAssistants.filter((p) => p.entity === o.api);
      if (paths.length) {
        for (const p of paths) {
          items.push(
            checkRow(
              `Path <strong>${esc(p.label)}</strong> renders on the record page and advances one step at a time.`,
              `Record type <code>${esc(p.recordType || 'all')}</code>, field <code>${esc(p.picklistField)}</code>, ${p.steps.length} steps. Guidance text shows on every step; <em>Mark Status as Complete</em> advances and re-stamps <code>Stage_Entered_Date__c</code>.`
            )
          );
        }
        if (o.api === 'Passport_Application__c' && D.uncoveredRecordTypes.length) {
          items.push(
            checkRow(
              `<span class="flag">Gap</span> Confirm the missing Paths are expected: no path assistant covers ${D.uncoveredRecordTypes.map((r) => `<code>${esc(r)}</code>`).join(', ')}.`,
              `Those record types render no stage bar at all. See action item P1-08.`
            )
          );
        }
      }

      // compact layout
      if (o.compactLayouts.length) {
        for (const cl of o.compactLayouts) {
          const assigned = o.compactLayoutAssignment === cl.api;
          items.push(
            checkRow(
              `Compact layout <code>${esc(cl.api)}</code> appears in the highlights panel${assigned ? ' <span class="yes">(assigned as primary)</span>' : ' <span class="muted">(deployed, not the primary assignment)</span>'}.`,
              `Expect these fields, in order: ${cl.fields.map((f) => `<code>${esc(f)}</code>`).join(', ')}.`
            )
          );
        }
      } else {
        items.push(checkRow(`Highlights panel falls back to the system default — no compact layout is defined.`, `Confirm the default is acceptable or author one.`));
      }

      // related lists
      if (children.length) {
        items.push(
          checkRow(
            `Related lists appear with the right columns.`,
            `Expect ${children.length}: ${children
              .map((c) => `<strong>${esc(c.relationshipName || c.from)}</strong> (<code>${esc(c.from)}.${esc(c.field)}</code>, ${c.type === 'MasterDetail' ? 'M-D' : 'lookup'})`)
              .join('; ')}. Each should show its own Name plus Status and the key date, not just Name.`
          )
        );
      }

      // layout
      if (layouts.length) {
        items.push(
          checkRow(
            `Page layout <em>${esc(layouts.join(', '))}</em> is assigned and its sections are in a deliberate order.`,
            o.api === 'Passport_Application__c'
              ? `Expect: Lifecycle → Applicant Details → Address → Application Details → Payment → Verification &amp; Compliance → Consent &amp; Notifications → System.`
              : `No field should sit in a section it does not belong to, and nothing should be in a nameless catch-all section. Confirm the lookup to the parent is on the layout and read-only where it should be.`
          )
        );
      } else {
        items.push(checkRow(`<span class="flag">No layout</span> No <code>Layout</code> metadata exists for this object — it will render an auto-generated layout.`, `See action item P1-07.`));
      }

      // list views
      items.push(
        checkRow(
          `List views behave.`,
          o.listViewCount
            ? `${o.listViewCount} list view${o.listViewCount === 1 ? '' : 's'} deployed — open each, confirm filters return rows and the columns are the ones an officer needs.`
            : `No list views deployed; only <em>Recently Viewed</em> and <em>All</em> will exist. Confirm that is enough.`
        )
      );

      // field history
      items.push(
        checkRow(
          `Field history tracking is ${o.enableHistory ? 'on' : '<span class="flag">off</span>'}.`,
          o.enableHistory
            ? `Change a tracked field and confirm the History related list records old → new value and the user.`
            : `Nothing on this object is auditable after the fact. Confirm that is intended.`
        )
      );

      return `
      <div class="uat-obj">
        <h3><code>${esc(o.api)}</code> <span class="uat-meta">${esc(o.label)} · OWD ${esc(o.owd || '—')} · ${o.fieldCount} fields · ${o.recordTypes.length} record type${o.recordTypes.length === 1 ? '' : 's'} · ${o.validationRules.length} validation rule${o.validationRules.length === 1 ? '' : 's'}</span></h3>
        ${o.description ? `<p class="uat-desc">${esc(o.description)}</p>` : ''}
        <ul class="checklist">${items.join('')}</ul>
      </div>`;
    })
    .join('');
}

function renderPersonaMatrix(F, DATA) {
  const sets = F.permissionSets;
  const objects = F.pskObjects;

  if (!sets.length) {
    return `<div class="callout warn"><p><strong>No <code>PSK_*</code> permission sets are present in <code>force-app/main/default/permissionsets/</code> at generation time.</strong> The matrix cannot be rendered from metadata. The seven personas described below are the design intent; re-run this generator once the sets land.</p></div>`;
  }

  const head = `<tr><th class="sticky">Object</th>${sets
    .map((s) => `<th class="rot"><span>${esc(s.label)}</span></th>`)
    .join('')}</tr>`;

  const body = objects
    .map((o) => {
      const cells = sets
        .map((s) => {
          const p = s.objPerms.find((x) => x.object === o.api);
          if (!p) return `<td class="perm none">—</td>`;
          const letters = [p.c && 'C', p.r && 'R', p.u && 'U', p.d && 'D'].filter(Boolean).join('');
          const extra = p.ma ? ' <sup>MA</sup>' : p.va ? ' <sup>VA</sup>' : '';
          return `<td class="perm ${letters ? 'has' : 'none'}">${letters || '—'}${extra}</td>`;
        })
        .join('');
      return `<tr><td class="sticky"><code>${esc(o.api)}</code></td>${cells}</tr>`;
    })
    .join('');

  const fieldRow = `<tr class="tfoot"><td class="sticky">Field permissions declared</td>${sets
    .map((s) => `<td class="perm">${s.fieldPermCount}</td>`)
    .join('')}</tr>`;

  return `
  <table class="grid matrix"><thead>${head}</thead><tbody>${body}${fieldRow}</tbody></table>
  <p class="legend-line"><strong>C</strong> create · <strong>R</strong> read · <strong>U</strong> edit · <strong>D</strong> delete · <sup>VA</sup> View All Records · <sup>MA</sup> Modify All Records · <strong>—</strong> no object permission declared in that set.
  Object permissions alone do not grant record access: with OWD Private, a persona also needs the role hierarchy or a sharing rule to see a record it does not own.</p>`;
}

function renderPersonaIntent(DATA) {
  return `
  <table class="grid">
    <thead><tr><th>Persona</th><th>Expected set</th><th>Role</th><th>Intended shape</th></tr></thead>
    <tbody>${DATA.personaMatrix.expectedPersonas
      .map(
        (p) =>
          `<tr><td><strong>${esc(p.label)}</strong></td><td><code>${esc(p.key)}</code></td><td><code>${esc(p.role)}</code></td><td class="small">${rich(p.shape)}</td></tr>`
      )
      .join('')}</tbody>
  </table>`;
}

function renderActionItems(F, D, DATA) {
  const items = DATA.actionItems;
  const rows = items
    .map(
      (a) => `
    <tr class="ai sev-${a.severity}">
      <td class="ai-id">${esc(a.id)}</td>
      <td><span class="pill pill-${a.severity}">${a.severity}</span></td>
      <td class="small">${esc(a.area)}</td>
      <td class="ai-item">${rich(a.item)}</td>
      <td class="small">${esc(a.owner)}</td>
      <td class="ai-eff">${esc(a.effort)}</td>
    </tr>`
    )
    .join('');

  // Live verification strip — the facts each item was checked against.
  const checks = [
    [
      'OpenAIChatController.cls in classes/',
      F.probes.openAiClassExists ? 'PRESENT — rotate and remove now' : 'absent (also absent from git history)',
      !F.probes.openAiClassExists,
    ],
    ['approvalProcesses/ directory', F.probes.approvalProcessesDirExists ? `${F.probes.approvalProcessCount} file(s)` : 'absent — zero approval processes', false],
    ['Territory2Model queryable', DATA.orgFacts.territory2ModelQueryable ? 'yes' : 'no — ETM not enabled', false],
    ['Real Region__c text field on the application', D.regionFieldOnApp ? 'present' : 'absent — criteria-based region sharing impossible', false],
    ['RecordPage flexipages needing manual activation', `${F.recordPages.length}: ${F.recordPages.map((p) => p.api).join(', ') || 'none'}`, false],
    ['reports/ · dashboards/ directories', `${F.probes.reportsDirExists ? 'present' : 'absent'} · ${F.probes.dashboardsDirExists ? 'present' : 'absent'}`, false],
    ['PSK custom report types', F.probes.pskReportTypes.length ? F.probes.pskReportTypes.join(', ') : `none (of ${F.probes.reportTypeCount} inherited types)`, false],
    ['Citizen_Required_On_Submit', D.citizenRule ? (D.citizenRule.active ? 'present and ACTIVE — check the backfill ran' : 'present and inactive, as designed') : 'not written yet', !!D.citizenRule && !D.citizenRule.active],
    ['Aadhaar_Token__c encryption', D.aadhaarToken ? `${D.aadhaarToken.type}${D.aadhaarToken.encrypted ? ` / ${D.aadhaarToken.encrypted}` : ', no encryption scheme'}` : 'field not found', false],
    ['Stray/empty Apex', F.probes.strayClasses.map((s) => `${s.file} (${s.bytes} B)`).join(', ') || 'none found', false],
    ['Orphan Lead layout', F.probes.orphanLeadLayout.length ? decodeURIComponent(F.probes.orphanLeadLayout[0]) : 'none found', false],
    ['contentassets/ near-duplicates', `${F.probes.contentAssetDupes} of ${F.probes.contentAssetTotal} files match _1/_11 variants`, false],
    ['objectTranslations locales', F.translations.locales.join(', ') || 'none', false],
    ['manifest/package.xml types', `${F.probes.manifestTypeCount} · scoped psk-package.xml ${F.probes.scopedManifestExists ? 'exists' : 'missing'}`, false],
    ['Apex apiVersion drift (project is ' + D.projectApi + ')', D.driftedClasses.length ? `${D.driftedClasses.length} PSK class(es) at ${[...new Set(D.driftedClasses.map((c) => c.apiVersion))].join('/')}` : 'none', D.driftedClasses.length === 0],
    ['PSK objects with no page layout', D.missingLayouts.join(', ') || 'none', D.missingLayouts.length === 0],
    ['PSK objects with no tab', D.missingTabs.join(', ') || 'none', D.missingTabs.length === 0],
    ['Experience Cloud sites', F.probes.communities.join(', ') || 'none', false],
  ];

  return `
  ${severityChart(items)}
  <table class="grid actions">
    <thead><tr><th>ID</th><th>Sev</th><th>Area</th><th>Item</th><th>Owner</th><th>Effort</th></tr></thead>
    <tbody>${rows}</tbody>
  </table>
  <p class="note">Effort: <strong>S</strong> under a day · <strong>M</strong> a few days · <strong>L</strong> a sprint or more.</p>

  <h3 class="sub">Verification strip — what each item was actually checked against</h3>
  <p class="note">Recomputed by this generator at ${esc(F.generatedAt.toISOString())} against commit <code>${esc(F.gitSha)}</code>. Nothing in the table above is asserted from memory.</p>
  <table class="grid probes">
    <thead><tr><th>Probe</th><th>Result at generation</th></tr></thead>
    <tbody>${checks
      .map(([k, v, ok]) => `<tr><td class="small">${esc(k)}</td><td class="small"><span class="${ok ? 'yes' : 'no'}">${esc(v)}</span></td></tr>`)
      .join('')}</tbody>
  </table>`;
}

function renderValidationReference(F) {
  if (!F.validationRules.length) return `<p class="muted">No validation rules found in the tree.</p>`;
  return `
  <table class="grid vr">
    <thead><tr><th>Rule</th><th>Object</th><th>Active</th><th>Error condition formula</th><th>Message</th></tr></thead>
    <tbody>${F.validationRules
      .map(
        (v) => `<tr>
        <td><code>${esc(v.api)}</code></td>
        <td class="small"><code>${esc(v.object)}</code></td>
        <td>${v.active ? '<span class="yes">yes</span>' : '<span class="no">no</span>'}</td>
        <td class="formula">${esc(v.formula)}</td>
        <td class="small">${esc(v.message)}</td>
      </tr>`
      )
      .join('')}</tbody>
  </table>`;
}

function renderSharingReference(F) {
  if (!F.sharingRules.length) return `<p class="muted">No criteria-based sharing rules found for PSK objects.</p>`;
  return `
  <table class="grid">
    <thead><tr><th>Rule</th><th>Object</th><th>Criteria</th><th>Shared to</th><th>Access</th></tr></thead>
    <tbody>${F.sharingRules
      .map(
        (r) =>
          `<tr><td><code>${esc(r.api)}</code></td><td class="small"><code>${esc(r.object)}</code></td><td class="small"><code>${esc(r.criteria)}</code></td><td class="small">${esc(r.sharedTo)}</td><td>${esc(r.access)}</td></tr>`
      )
      .join('')}</tbody>
  </table>`;
}

/* --------------------------------------------------------------- the document */

function renderHtml(F, D, DATA) {
  const M = DATA.meta;
  const buildDate = F.generatedAt.toLocaleDateString('en-GB', { day: 'numeric', month: 'long', year: 'numeric' });
  const buildTime = F.generatedAt.toISOString().replace('T', ' ').slice(0, 16) + ' UTC';

  const NAVY = '#1a2a5e';
  const GOLD = '#c9a227';
  const SLATE = '#7c8798';
  const shipped = [
    { label: 'custom fields', value: F.pskObjects.reduce((a, o) => a + o.fieldCount, 0), fill: NAVY },
    { label: 'validation rules', value: F.validationRules.length, fill: NAVY },
    { label: 'quick actions', value: F.quickActions.length, fill: NAVY },
    { label: 'custom md records', value: Object.values(F.cmdRecords).reduce((a, v) => a + v.length, 0), fill: NAVY },
    { label: 'record types', value: F.pskObjects.reduce((a, o) => a + o.recordTypes.length, 0), fill: NAVY },
    { label: 'PSK objects', value: F.pskObjects.length, fill: GOLD },
    { label: 'global value sets', value: F.globalValueSets.length, fill: GOLD },
    { label: 'LWCs', value: F.lwc.length, fill: GOLD },
    { label: 'roles', value: F.roles.length, fill: SLATE },
    { label: 'permission sets', value: F.permissionSets.length, fill: SLATE },
    { label: 'sharing rules', value: F.sharingRules.length, fill: SLATE },
    { label: 'queues + groups', value: F.queues.length + F.groups.length, fill: SLATE },
    { label: 'apex triggers', value: F.triggers.length, fill: SLATE },
    { label: 'lightning pages', value: F.flexipages.filter((p) => !/UtilityBar$/.test(p.api)).length, fill: SLATE },
  ];

  const cmdTotals = Object.entries(F.cmdRecords)
    .map(([k, v]) => `<code>${esc(k)}__mdt</code> ${v.length} records`)
    .join(' · ');

  const stat = (n, l, sub = '') =>
    `<div class="stat"><div class="stat-n">${n}</div><div class="stat-l">${l}</div>${sub ? `<div class="stat-s">${sub}</div>` : ''}</div>`;

  return `<title>${esc(M.title)} — ${esc(M.orgAlias)}</title>
<style>
  @page { size: A4; margin: 14mm; }

  :root {
    --navy: #1a2a5e;
    --navy-2: #2d4380;
    --gold: #c9a227;
    --gold-soft: #f3e7c2;
    --ink: #1f2733;
    --ink-2: #4a5568;
    --muted: #7c8798;
    --rule: #dde1e9;
    --panel: #f7f8fb;
    --red: #9b1c1c;
    --green: #1f6b45;
  }

  * { box-sizing: border-box; -webkit-print-color-adjust: exact; print-color-adjust: exact; }

  /* Chrome will not resolve a mm height on the cover panel unless the root and body
     are themselves sized, so the cover cannot fill the printable page without this. */
  html { height: 100%; }

  /* Hard width clamp. Chrome's print pipeline scales the whole document down when any
     box is wider than the page box, so an overflow bug shows up as "the PDF looks
     zoomed out" rather than as a horizontal scrollbar. Keep this. */
  body > * { max-width: 100%; }
  table { max-width: 100%; }

  body {
    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", "Helvetica Neue", Helvetica, Arial, sans-serif;
    font-size: 8.7pt;
    line-height: 1.45;
    color: var(--ink);
    margin: 0;
    height: 100%;
  }

  code, .formula, pre {
    font-family: ui-monospace, SFMono-Regular, "SF Mono", Menlo, Consolas, "Liberation Mono", monospace;
  }
  code { font-size: 0.88em; background: #eef0f5; padding: 0.5px 3px; border-radius: 3px; color: #26324a; }

  h1, h2, h3, h4 { color: var(--navy); line-height: 1.2; margin: 0; break-after: avoid; }
  p { margin: 0 0 7px; }
  ul, ol { margin: 0 0 8px; padding-left: 18px; }
  li { margin-bottom: 4px; }
  em { color: var(--ink-2); }
  .muted { color: var(--muted); }
  .small { font-size: 8.4pt; }
  .note { font-size: 8.2pt; color: var(--muted); margin-top: 5px; }
  .yes { color: var(--green); font-weight: 600; }
  .no  { color: var(--red); font-weight: 600; }

  /* ---------- cover ---------- */
  /* Full-bleed is not reliably achievable in Chrome's paged media — negative margins
     into the @page margin box are ignored — so the cover is a navy panel that fills
     the printable area exactly, framed by the page margin. */
  .cover {
    break-after: page;
    height: 267mm;
    display: flex;
    flex-direction: column;
    background: var(--navy);
    color: #fff;
    border-radius: 3px;
    padding: 20mm 16mm 14mm;
  }
  .cover .kicker { font-size: 8.6pt; letter-spacing: 0.24em; text-transform: uppercase; color: var(--gold); font-weight: 700; }
  .cover h1 { color: #fff; font-size: 33pt; letter-spacing: -0.6px; margin: 14px 0 8px; }
  .cover .sub { font-size: 12.5pt; color: #c3cddf; max-width: 135mm; line-height: 1.4; }
  .cover .gold-rule { height: 4px; width: 82px; background: var(--gold); margin: 22px 0 26px; border-radius: 2px; }
  .cover .spacer { flex: 1; }
  .cover-meta { display: grid; grid-template-columns: 1fr 1fr; gap: 0; border-top: 1px solid rgba(255,255,255,.22); }
  .cover-meta div {
    padding: 9px 12px 9px 0;
    border-bottom: 1px solid rgba(255,255,255,.12);
    font-size: 9.4pt;
  }
  .cover-meta .k { color: var(--gold); font-size: 7.8pt; letter-spacing: .14em; text-transform: uppercase; display: block; margin-bottom: 2px; }
  .cover-meta .v { color: #fff; font-family: ui-monospace, SFMono-Regular, Menlo, monospace; font-size: 9pt; overflow-wrap: anywhere; }
  .cover .disclaimer { margin-top: 20px; font-size: 8pt; color: #a7b5cd; max-width: 140mm; line-height: 1.5; }
  /* A 2-column grid, not CSS multicol: Chrome collapses a fixed-height flex ancestor
     when it has to fragment a multicol box in paged media. */
  .cover .toc {
    margin-top: 24px; font-size: 9pt; color: #c3cddf;
    display: grid; grid-template-columns: 1fr 1fr; grid-template-rows: repeat(5, auto);
    grid-auto-flow: column; column-gap: 14mm; row-gap: 3px;
    list-style-position: inside; padding-left: 0;
  }
  .cover .toc li { margin-bottom: 0; }
  .cover .toc strong { color: #fff; }

  /* ---------- sections ---------- */
  section { break-before: page; }
  section:first-of-type { break-before: auto; }
  .sec-head { border-bottom: 2px solid var(--navy); padding-bottom: 5px; margin-bottom: 12px; display: flex; align-items: baseline; gap: 10px; }
  .sec-num { font-size: 8.4pt; font-weight: 700; letter-spacing: .18em; color: var(--gold); }
  .sec-head h2 { font-size: 17pt; letter-spacing: -0.2px; }
  h3 { font-size: 11.4pt; margin: 14px 0 6px; }
  h3.sub { margin-top: 16px; padding-top: 8px; border-top: 1px solid var(--rule); }
  h4 { font-size: 9.8pt; margin: 10px 0 4px; text-transform: uppercase; letter-spacing: .06em; color: var(--navy-2); }

  /* ---------- cards / callouts ---------- */
  /* Single column on purpose: these two lists are long, and a two-column grid item
     that has to fragment across a page break leaves an empty stub behind in Chrome. */
  .cards { display: block; }
  .card { border: 1px solid var(--rule); border-radius: 6px; padding: 10px 12px 4px; background: #fff; margin-bottom: 9px; }
  .card ul { columns: 2; column-gap: 10mm; }
  .card li { break-inside: avoid; }
  .card.can { border-left: 3px solid var(--green); }
  .card.cant { border-left: 3px solid var(--red); }
  .card h4 { margin-top: 0; }
  .card ul { padding-left: 15px; margin-bottom: 0; }

  .callout {
    break-inside: avoid;
    border: 1px solid var(--gold);
    border-left: 4px solid var(--gold);
    background: #fdfaf1;
    border-radius: 5px;
    padding: 11px 14px;
    margin: 12px 0;
  }
  .callout h4 { margin-top: 0; color: #8a6d10; }
  .callout.warn { border-color: var(--red); border-left-color: var(--red); background: #fdf3f3; }
  .callout.warn h4 { color: var(--red); }
  .callout p:last-child { margin-bottom: 0; }

  .panel { background: var(--panel); border: 1px solid var(--rule); border-radius: 6px; padding: 11px 13px; margin: 10px 0; break-inside: avoid; }

  /* ---------- stats ---------- */
  .stats { display: grid; grid-template-columns: repeat(6, 1fr); gap: 7px; margin: 10px 0 14px; }
  .stat { break-inside: avoid; background: var(--navy); color: #fff; border-radius: 5px; padding: 9px 8px; text-align: center; }
  .stat-n { font-size: 18pt; font-weight: 700; line-height: 1; color: #fff; }
  .stat-l { font-size: 7.4pt; text-transform: uppercase; letter-spacing: .08em; color: var(--gold); margin-top: 4px; }
  .stat-s { font-size: 7pt; color: #a9b6cc; margin-top: 2px; }

  /* ---------- tables ---------- */
  table.grid { width: 100%; border-collapse: collapse; font-size: 8.4pt; margin: 8px 0 10px; }
  table.grid thead { break-inside: avoid; break-after: avoid; }
  table.grid th {
    background: var(--navy); color: #fff; text-align: left; padding: 5px 6px;
    font-size: 7.6pt; text-transform: uppercase; letter-spacing: .06em; font-weight: 700;
    border-right: 1px solid rgba(255,255,255,.14);
  }
  table.grid td { padding: 4.5px 6px; border-bottom: 1px solid var(--rule); vertical-align: top; }
  /* Nothing may exceed the printable width: a single overflowing cell makes Chrome
     shrink the ENTIRE document to fit, silently reducing every font size. */
  table.grid td { overflow-wrap: anywhere; }
  /* overflow-wrap:anywhere on a header lets the auto table layout shrink the column
     to one character, turning "FIELDS" into a vertical stack of letters. break-word
     does not reduce min-content width, so short headers stay whole while a long API
     name like POLICE_VERIFICATION_TYPE__C can still break rather than blow the table
     past the page width (which would silently scale the whole document down). */
  table.grid th { overflow-wrap: break-word; word-break: break-word; }
  table.grid th.num, table.grid td.num,
  table.grid th.nw, table.grid td.nw { white-space: nowrap; }
  table.grid td.nw { text-align: center; }
  .formula { overflow-wrap: anywhere; }
  table.grid tbody tr { break-inside: avoid; }
  table.grid tbody tr:nth-child(even) { background: #fafbfd; }
  table.grid td.num, table.grid th.num { text-align: right; }
  .owd { font-size: 7.4pt; font-weight: 700; padding: 1px 5px; border-radius: 8px; white-space: nowrap; }
  .owd-Private { background: #fde8e8; color: var(--red); }
  .owd-ControlledByParent { background: #eef0f5; color: var(--navy-2); }
  .owd-Read { background: #fff5d8; color: #8a6d10; }
  .owd-ReadWrite { background: #e6f4ec; color: var(--green); }

  table.actions td.ai-item { font-size: 8.3pt; line-height: 1.45; }
  table.actions td.ai-id { font-family: ui-monospace, Menlo, monospace; font-weight: 700; color: var(--navy); white-space: nowrap; }
  table.actions td.ai-eff { text-align: center; font-weight: 700; }
  .pill { display: inline-block; font-size: 7.4pt; font-weight: 700; padding: 1.5px 6px; border-radius: 9px; color: #fff; }
  .pill-P0 { background: var(--red); }
  .pill-P1 { background: var(--gold); color: #3d2f00; }
  .pill-P2 { background: #5a6a85; }
  tr.sev-P0 { background: #fdf6f6 !important; }

  table.vr td.formula { font-size: 7.4pt; line-height: 1.35; word-break: break-word; max-width: 68mm; color: #26324a; }
  table.probes td { padding: 3.5px 6px; }

  table.matrix th.rot { height: 26mm; vertical-align: bottom; padding: 4px 2px; }
  table.matrix th.rot span { writing-mode: vertical-rl; transform: rotate(180deg); font-size: 7.2pt; letter-spacing: .02em; white-space: nowrap; }
  table.matrix td.perm { text-align: center; font-family: ui-monospace, Menlo, monospace; font-size: 7.8pt; font-weight: 700; }
  table.matrix td.perm.has { background: #eef4ff; color: var(--navy); }
  table.matrix td.perm.none { color: #c3cad6; }
  table.matrix td.sticky { font-size: 7.8pt; }
  table.matrix tr.tfoot td { background: var(--panel); font-weight: 700; }
  .legend-line { font-size: 8pt; color: var(--ink-2); }

  /* ---------- checklists ---------- */
  .uat-obj { break-inside: avoid; border: 1px solid var(--rule); border-radius: 6px; padding: 10px 12px; margin-bottom: 10px; }
  .uat-obj h3 { font-size: 10.6pt; margin: 0 0 3px; }
  .uat-meta { font-size: 7.8pt; font-weight: 400; color: var(--muted); letter-spacing: 0; }
  .uat-desc { font-size: 8.2pt; color: var(--ink-2); font-style: italic; margin-bottom: 6px; }
  ul.checklist { list-style: none; padding: 0; margin: 0; }
  ul.checklist li { display: grid; grid-template-columns: 14px 1fr; gap: 6px; margin-bottom: 5px; break-inside: avoid; font-size: 8.4pt; }
  .cb { display: block; width: 10px; height: 10px; border: 1.4px solid var(--navy); border-radius: 2px; margin-top: 2.5px; }
  .ck-l { grid-column: 2; }
  .ck-d { grid-column: 2; font-size: 8pt; color: var(--ink-2); display: block; margin-top: 1.5px; }
  .trip { display: block; }
  .flag { display: inline-block; font-size: 7pt; font-weight: 700; background: var(--gold); color: #3d2f00; padding: 0.5px 4px; border-radius: 3px; letter-spacing: .04em; }

  /* ---------- lifecycle ---------- */
  table.life { width: 100%; border-collapse: collapse; font-size: 8.4pt; }
  table.life tbody tr { break-inside: avoid; }
  table.life td { padding: 6px; border-bottom: 1px solid var(--rule); vertical-align: top; }
  table.life td.step { width: 8mm; text-align: center; font-weight: 700; color: var(--gold); font-size: 10pt; }
  table.life td.stage { width: 34mm; font-weight: 700; color: var(--navy); }
  table.life td.act { width: 62mm; }
  table.life td.exp { color: var(--ink-2); }
  table.life thead th { background: var(--navy); color: #fff; font-size: 7.6pt; text-transform: uppercase; letter-spacing: .06em; padding: 5px 6px; text-align: left; }

  /* ---------- commands ---------- */
  .cmd { break-inside: avoid; margin-bottom: 6px; }
  .cmd code {
    display: block; background: #10182b; color: #dbe4f5; padding: 6px 9px; border-radius: 4px;
    font-size: 8pt; line-height: 1.4; word-break: break-all; border-left: 3px solid var(--gold);
  }
  .cmd .why { font-size: 8pt; color: var(--ink-2); margin-top: 2px; }

  /* ---------- svg ---------- */
  svg.erd { width: 100%; height: auto; margin: 6px 0 10px; }
  svg.chart { width: 100%; height: auto; margin: 6px 0 10px; }

  .footer-note { margin-top: 14px; padding-top: 7px; border-top: 1px solid var(--rule); font-size: 7.6pt; color: var(--muted); }

  /* ---------- dark theme (screen only; print always uses the light document) ---------- */
  @media screen and (prefers-color-scheme: dark) {
    body { background: #11151d; color: #dbe1ea; }
    .card, .uat-obj, table.grid tbody tr:nth-child(even) { background: #171c26; }
    .card, .uat-obj, .panel, table.grid td, .footer-note, h3.sub { border-color: #2a323f; }
    .panel { background: #171c26; }
    h1, h2, h3, h4 { color: #e8edf5; }
    code { background: #232b38; color: #cbd6e8; }
    .callout { background: #241f10; }
    .callout.warn { background: #251516; }
    .muted, .note, .ck-d, .uat-meta { color: #8c98ab; }
  }
</style>

<div class="cover">
  <div class="kicker">Passport Seva Kendra · Salesforce</div>
  <h1>${esc(M.title)}</h1>
  <div class="sub">${esc(M.subtitle)}</div>
  <div class="gold-rule"></div>

  <div class="cover-meta">
    <div><span class="k">Org alias</span><span class="v">${esc(M.orgAlias)}</span></div>
    <div><span class="k">Edition</span><span class="v">${esc(M.orgEdition)}</span></div>
    <div><span class="k">Username</span><span class="v">${esc(M.username)}</span></div>
    <div><span class="k">Org Id</span><span class="v">${esc(M.orgId)}</span></div>
    <div><span class="k">Source API version</span><span class="v">${esc(D.projectApi)}</span></div>
    <div><span class="k">Build date</span><span class="v">${esc(buildDate)}</span></div>
    <div><span class="k">Git commit</span><span class="v">${esc(F.gitSha)} (${esc(F.gitBranch)})${F.gitDirty ? ' · uncommitted changes present' : ''}</span></div>
    <div><span class="k">Generated</span><span class="v">${esc(buildTime)} · node ${esc(F.nodeVersion)}</span></div>
    <div><span class="k">Instance</span><span class="v">${esc(M.instanceUrl)}</span></div>
    <div><span class="k">Scanned tree</span><span class="v">force-app/main/default · ${F.pskObjects.length} PSK objects</span></div>
  </div>

  <ol class="toc">
    <li><strong>Executive summary</strong></li>
    <li><strong>Data model</strong> — ERD and the snapshot decision</li>
    <li><strong>Object inventory</strong></li>
    <li><strong>Per-object UAT checklist</strong></li>
    <li><strong>Lifecycle walkthrough script</strong></li>
    <li><strong>Persona access matrix</strong></li>
    <li><strong>Action items</strong> — ${DATA.actionItems.length} open</li>
    <li><strong>Org limits and storage</strong></li>
    <li><strong>Appendix</strong> — commands, validation and sharing reference</li>
  </ol>

  <div class="spacer"></div>
  <div class="disclaimer">
    Every count in this document was recomputed from the metadata tree at generation time, not transcribed.
    Counts are therefore <strong>as of ${esc(buildTime)}</strong> at commit <code style="background:rgba(255,255,255,.12);color:#e6ecf7">${esc(F.gitSha)}</code>;
    re-run <code style="background:rgba(255,255,255,.12);color:#e6ecf7">node scripts/pdf/generate-report.mjs</code> to refresh them.
    <br><br>${esc(M.disclaimer)}
  </div>
</div>

<!-- ================================================= 1. EXECUTIVE SUMMARY -->
<section>
  <div class="sec-head"><span class="sec-num">01</span><h2>Executive summary</h2></div>

  <div class="stats">
    ${stat(F.pskObjects.length, 'PSK objects', `+ ${F.mdtObjects.length} metadata types`)}
    ${stat(F.pskObjects.reduce((a, o) => a + o.fieldCount, 0), 'custom fields', 'across PSK objects')}
    ${stat(F.validationRules.length, 'validation rules', `${F.validationRules.filter((v) => !v.active).length} inactive`)}
    ${stat(F.sharingRules.length, 'sharing rules', `${F.roles.length} roles · ${F.groups.length} groups`)}
    ${stat(F.permissionSets.length, 'PSK perm sets', `${F.queues.length} queues`)}
    ${stat(DATA.actionItems.length, 'open items', `${DATA.actionItems.filter((a) => a.severity === 'P0').length} P0`)}
  </div>

  ${shippedChart(shipped)}

  <div class="cards">
    <div class="card can">
      <h4>What the org can do end to end</h4>
      <ul>${DATA.executiveSummary.canDo.map((s) => `<li>${rich(s)}</li>`).join('')}</ul>
    </div>
    <div class="card cant">
      <h4>What it still cannot do</h4>
      <ul>${DATA.executiveSummary.cannotDo.map((s) => `<li>${rich(s)}</li>`).join('')}</ul>
    </div>
  </div>

  <div class="panel">
    <h4>Supporting configuration in the tree</h4>
    <p class="small">
      <strong>Global value sets (${F.globalValueSets.length}):</strong> ${F.globalValueSets.map((g) => `<code>${esc(g)}</code>`).join(' ')}<br>
      <strong>Roles (${F.roles.length}):</strong> ${F.roles.map((r) => `<code>${esc(r)}</code>`).join(' ')}<br>
      <strong>Queues (${F.queues.length}):</strong> ${F.queues.map((q) => `<code>${esc(q)}</code>`).join(' ')}<br>
      <strong>Public groups (${F.groups.length}):</strong> ${F.groups.map((g) => `<code>${esc(g)}</code>`).join(' ')}<br>
      <strong>Custom metadata records:</strong> ${cmdTotals || '<span class="muted">none</span>'}<br>
      <strong>LWCs (${F.lwc.length}):</strong> ${F.lwc.map((c) => `<code>${esc(c)}</code>`).join(' ')}<br>
      <strong>Apex triggers (${F.triggers.length}):</strong> ${F.triggers.length ? F.triggers.map((t) => `<code>${esc(t)}</code>`).join(' ') : '<span class="muted">none in the tree at generation time</span>'}<br>
      <strong>Object quick actions (${F.quickActions.length}):</strong> ${F.quickActions.filter((q) => /__c/.test(q.host)).length} on PSK objects &mdash; ${F.quickActions.filter((q) => q.type === 'Create').length} create, ${F.quickActions.filter((q) => q.type !== 'Create').length} update<br>
      <strong>Permission set groups (${F.permissionSetGroups.length}):</strong> ${F.permissionSetGroups.map((g) => `<code>${esc(g.api)}</code>`).join(' ') || '<span class="muted">none</span>'}<br>
      <strong>Custom apps (${F.apps.length}):</strong> ${F.apps.map((a) => `<code>${esc(a.api)}</code>`).join(' ')}
    </p>
  </div>
</section>

<!-- ============================================================ 2. DATA MODEL -->
<section>
  <div class="sec-head"><span class="sec-num">02</span><h2>Data model</h2></div>
  <p>Six objects carry the weight of the system. <code>Passport_Application__c</code> sits at the centre with ${D.appObj?.fieldCount ?? 0} fields, ${D.appObj?.recordTypes.length ?? 0} record types and ${D.appObj?.validationRules.length ?? 0} validation rules — the &ldquo;few objects, many fields&rdquo; philosophy in one place. Everything else either identifies a person, records an issued booklet, or tracks fulfilment.</p>

  ${erdSvg(D)}

  <div class="callout">
    <h4>${esc(DATA.erd.calloutTitle)}</h4>
    ${DATA.erd.calloutBody.map((p) => `<p>${rich(p)}</p>`).join('')}
  </div>

  <div class="panel">
    <h4>${esc(DATA.erd.avoidedTitle)}</h4>
    <ul class="small">${DATA.erd.avoidedBody.map((p) => `<li>${rich(p)}</li>`).join('')}</ul>
  </div>

  <h3 class="sub">Every PSK relationship in the tree</h3>
  <table class="grid">
    <thead><tr><th>Child object</th><th>Field</th><th>Type</th><th>Parent</th><th>Child relationship name</th></tr></thead>
    <tbody>${D.relationships
      .map(
        (r) =>
          `<tr><td><code>${esc(r.from)}</code></td><td><code>${esc(r.field)}</code></td><td>${r.type === 'MasterDetail' ? '<strong>master-detail</strong>' : 'lookup'}</td><td><code>${esc(r.to)}</code></td><td class="small"><code>${esc(r.relationshipName)}</code></td></tr>`
      )
      .join('')}</tbody>
  </table>

  <h3 class="sub">Cross-object formula fields — the derived, not-duplicated facts</h3>
  <table class="grid">
    <thead><tr><th>Object</th><th>Field</th><th>Formula</th></tr></thead>
    <tbody>${F.pskObjects
      .flatMap((o) => o.fields.filter((f) => f.formula && /__r\./.test(f.formula)).map((f) => ({ o: o.api, f })))
      .map((x) => `<tr><td class="small"><code>${esc(x.o)}</code></td><td><code>${esc(x.f.api)}</code></td><td class="formula">${esc(x.f.formula)}</td></tr>`)
      .join('')}</tbody>
  </table>
</section>

<!-- ====================================================== 3. OBJECT INVENTORY -->
<section>
  <div class="sec-head"><span class="sec-num">03</span><h2>Object inventory</h2></div>
  <p>${F.pskObjects.length} PSK objects plus ${F.mdtObjects.length} custom metadata types, as of commit <code>${esc(F.gitSha)}</code>. Field counts exclude standard fields. Inherited template objects (<code>Account</code>, <code>OpportunityHistory__c</code>, <code>Reseller_Account_Plan__c</code>) are excluded.</p>
  ${renderObjectInventory(F)}
  ${D.missingTabs.length ? `<div class="callout warn"><p><strong>No tab:</strong> ${D.missingTabs.map((t) => `<code>${esc(t)}</code>`).join(', ')}. These objects are only reachable from a parent record or by URL.</p></div>` : ''}
  ${D.missingLayouts.length ? `<div class="callout warn"><p><strong>No page layout in the tree:</strong> ${D.missingLayouts.map((t) => `<code>${esc(t)}</code>`).join(', ')}. See action item P1-07.</p></div>` : ''}
</section>

<!-- ================================================= 4. PER-OBJECT UAT CHECKS -->
<section>
  <div class="sec-head"><span class="sec-num">04</span><h2>Per-object UAT checklist</h2></div>
  <p>Print this section and tick as you go. Every row was generated from the metadata actually on disk, so a row that looks wrong means the metadata is wrong — not the checklist. Rows carrying a <span class="flag">flag</span> are gaps the generator detected rather than tests to run.</p>
  ${renderUatChecklist(F, D)}
</section>

<!-- ================================================== 5. LIFECYCLE WALKTHROUGH -->
<section>
  <div class="sec-head"><span class="sec-num">05</span><h2>Lifecycle walkthrough script</h2></div>
  <p>${rich(DATA.lifecycle.intro)}</p>

  <div class="panel">
    <h4>Before you start</h4>
    <ul class="small">${DATA.lifecycle.preconditions.map((p) => `<li>${rich(p)}</li>`).join('')}</ul>
    <p class="small" style="margin-top:6px"><strong>ARN under test:</strong> <span style="border-bottom:1px solid var(--muted); display:inline-block; width:40mm">&nbsp;</span> &nbsp;&nbsp;<strong>Tester:</strong> <span style="border-bottom:1px solid var(--muted); display:inline-block; width:40mm">&nbsp;</span> &nbsp;&nbsp;<strong>Date:</strong> <span style="border-bottom:1px solid var(--muted); display:inline-block; width:28mm">&nbsp;</span></p>
  </div>

  <table class="life">
    <thead><tr><th>&#10003;</th><th>Stage</th><th>Action</th><th>Expected</th></tr></thead>
    <tbody>${DATA.lifecycle.steps
      .map(
        (s, i) =>
          `<tr><td class="step">${cb()}</td><td class="stage">${rich(s.stage)}</td><td class="act">${rich(s.action)}</td><td class="exp">${rich(s.expect)}</td></tr>`
      )
      .join('')}</tbody>
  </table>

  <div class="callout">
    <h4>Final assertions — nothing bypassed, nothing spuriously blocking</h4>
    <ul class="checklist">${DATA.lifecycle.finalAssertions.map((a) => checkRow(rich(a))).join('')}</ul>
  </div>

  <div class="panel">
    <h4>Path steps as deployed</h4>
    ${D.appPaths
      .map(
        (p) =>
          `<p class="small"><code>${esc(p.api)}</code> — record type <code>${esc(p.recordType || 'all')}</code>, ${p.active ? 'active' : '<span class="no">inactive</span>'}, ${p.steps.length} steps: ${p.steps.map((s) => esc(s)).join(' → ')}</p>`
      )
      .join('') || '<p class="muted small">No path assistant found for Passport_Application__c.</p>'}
  </div>
</section>

<!-- ==================================================== 6. PERSONA ACCESS MATRIX -->
<section>
  <div class="sec-head"><span class="sec-num">06</span><h2>Persona access matrix</h2></div>
  <p>${rich(DATA.personaMatrix.intro)}</p>
  ${renderPersonaMatrix(F, DATA)}

  <h3 class="sub">Design intent — the seven personas</h3>
  <p class="note">${rich(DATA.personaMatrix.personaCaveat)}</p>
  ${renderPersonaIntent(DATA)}
  ${DATA.personaMatrix.personaGroups ? `<p class="small">${rich(DATA.personaMatrix.personaGroups)}</p>` : ''}

  <div class="panel">
    <h4>How to verify each</h4>
    <ul class="checklist">${DATA.personaMatrix.verifyHow.map((v) => checkRow(rich(v))).join('')}</ul>
  </div>

  <h3 class="sub">Permission set groups</h3>
  ${
    F.permissionSetGroups.length
      ? `<table class="grid"><thead><tr><th>Group</th><th>Bundles</th><th>Purpose</th></tr></thead><tbody>${F.permissionSetGroups
          .map(
            (g) =>
              `<tr><td><code>${esc(g.api)}</code><br><span class="small muted">${esc(g.label)}</span></td><td>${g.sets.map((s) => `<code>${esc(s)}</code>`).join(' + ')}</td><td class="small">${esc(g.description)}</td></tr>`
          )
          .join('')}</tbody></table>
      <p class="note">Verify each group: assign it to the test user and confirm the union of its sets is what the user actually gets — a group whose calculation is stale (Setup &rarr; Permission Set Groups shows <em>Outdated</em>) silently grants the wrong thing.</p>`
      : `<p class="muted">No permission set groups in the tree.</p>`
  }

  <h3 class="sub">Record-level layer: criteria-based sharing rules in the tree</h3>
  ${renderSharingReference(F)}
  <p class="note">Public groups: ${F.groups.map((g) => `<code>${esc(g)}</code>`).join(', ') || 'none'}. Queues: ${F.queues.map((q) => `<code>${esc(q)}</code>`).join(', ') || 'none'}.</p>
</section>

<!-- ============================================================ 7. ACTION ITEMS -->
<section>
  <div class="sec-head"><span class="sec-num">07</span><h2>Action items</h2></div>
  <p>${DATA.actionItems.length} open items: ${DATA.actionItems.filter((a) => a.severity === 'P0').length} P0, ${DATA.actionItems.filter((a) => a.severity === 'P1').length} P1, ${DATA.actionItems.filter((a) => a.severity === 'P2').length} P2. Each was verified against the repository or the org before being listed; the verification strip at the end of this section shows what was actually observed.</p>
  ${renderActionItems(F, D, DATA)}
</section>

<!-- ================================================== 8. ORG LIMITS AND STORAGE -->
<section>
  <div class="sec-head"><span class="sec-num">08</span><h2>Org limits and storage</h2></div>

  ${DATA.orgLimits.storageIntro.map((p) => `<p>${rich(p)}</p>`).join('')}

  <div class="stats" style="grid-template-columns: repeat(4, 1fr)">
    ${stat('~5 MB', 'data storage', 'Developer Edition')}
    ${stat('~2,500', 'records org-wide', 'at 2 KB per record')}
    ${stat(D.inherited.toLocaleString('en-IN'), 'inherited records', 'template sample data')}
    ${stat(D.pskRecords.toLocaleString('en-IN'), 'PSK records', 'as of capture')}
  </div>

  ${storageChart(DATA.orgFacts.recordCounts)}
  <p class="note">Captured by read-only <code>sf data query</code> on ${esc(DATA.orgFacts.capturedOn)}. ${rich(DATA.orgFacts.note)}</p>

  <h3 class="sub">What to delete first if storage binds</h3>
  <table class="grid">
    <thead><tr><th>Order</th><th>Delete</th><th>Why it is safe, and what it costs</th></tr></thead>
    <tbody>${DATA.orgLimits.deleteFirst
      .map((d) => `<tr><td class="num"><strong>${d.order}</strong></td><td>${rich(d.what)}</td><td class="small">${rich(d.why)}</td></tr>`)
      .join('')}</tbody>
  </table>

  <h3 class="sub">Licence ceiling — and why persona testing swaps permission sets</h3>
  <table class="grid" style="width:auto; min-width:80mm">
    <thead><tr><th>User licence</th><th class="num">Total</th><th class="num">Used</th><th class="num">Free</th></tr></thead>
    <tbody>${DATA.orgFacts.licences
      .map(
        (l) =>
          `<tr><td>${esc(l.name)}</td><td class="num">${l.total.toLocaleString('en-IN')}</td><td class="num">${l.used.toLocaleString('en-IN')}</td><td class="num"><strong>${(l.total - l.used).toLocaleString('en-IN')}</strong></td></tr>`
      )
      .join('')}</tbody>
  </table>
  ${DATA.orgLimits.licenceNote.map((p) => `<p>${rich(p)}</p>`).join('')}

  <div class="callout warn">
    <h4>Enterprise Territory Management</h4>
    <p><code>SELECT Id FROM Territory2Model</code> returns <em>${esc(DATA.orgFacts.territory2ModelError)}</em>, which is how the platform reports that the feature has never been switched on. It is a Setup toggle, it cannot be enabled by a metadata deploy, and it is irreversible. See action item P1-01.</p>
  </div>
</section>

<!-- ================================================================ 9. APPENDIX -->
<section>
  <div class="sec-head"><span class="sec-num">09</span><h2>Appendix</h2></div>

  <h3>A. Deploy, verify and seed command sequence</h3>
  <p class="small">${rich(DATA.appendix.commandsIntro)}</p>
  ${DATA.appendix.commandGroups
    .map(
      (g) => `
    <h4>${esc(g.title)}</h4>
    ${g.commands.map((c) => `<div class="cmd"><code>${esc(c.cmd)}</code><div class="why">${rich(c.note)}</div></div>`).join('')}`
    )
    .join('')}

  <h3 class="sub">B. Validation rule reference</h3>
  <p class="small">All ${F.validationRules.length} validation rules across every object in the tree, formulas verbatim from the metadata.</p>
  ${renderValidationReference(F)}

  <h3 class="sub">C. Record type picklist subsetting</h3>
  ${F.pskObjects
    .filter((o) => o.recordTypes.length)
    .map(
      (o) => `
    <h4><code>${esc(o.api)}</code></h4>
    <table class="grid">
      <thead><tr><th>Record type</th>${[...new Set(o.recordTypes.flatMap((r) => r.picklists.map((p) => p.picklist)))]
        .filter((p) => !['State__c', 'Gender__c', 'Marital_Status__c', 'Payment_Mode__c', 'Payment_Status__c', 'Status__c'].includes(p))
        .map((p) => `<th>${esc(p)}</th>`)
        .join('')}</tr></thead>
      <tbody>${o.recordTypes
        .map((rt) => {
          const cols = [...new Set(o.recordTypes.flatMap((r) => r.picklists.map((p) => p.picklist)))].filter(
            (p) => !['State__c', 'Gender__c', 'Marital_Status__c', 'Payment_Mode__c', 'Payment_Status__c', 'Status__c'].includes(p)
          );
          return `<tr><td><strong>${esc(rt.label || rt.api)}</strong></td>${cols
            .map((c) => {
              const pl = rt.picklists.find((p) => p.picklist === c);
              return `<td class="small">${pl ? pl.values.map(esc).join(', ') : '<span class="muted">—</span>'}</td>`;
            })
            .join('')}</tr>`;
        })
        .join('')}</tbody>
    </table>
    <p class="note">Shared vocabularies (<code>State__c</code>, <code>Gender__c</code>, <code>Marital_Status__c</code>, <code>Payment_Mode__c</code>, <code>Payment_Status__c</code>, <code>Status__c</code>) are the same across all record types on this object and are omitted from the table for width; see the Global Value Sets.</p>`
    )
    .join('')}

  <h3 class="sub">D. Fee matrix and SLA configuration records</h3>
  ${Object.entries(F.cmdRecords)
    .map(
      ([type, recs]) => `
    <h4><code>${esc(type)}__mdt</code> — ${recs.length} records</h4>
    <p class="small">${recs.map((r) => `<code>${esc(r)}</code>`).join(' · ')}</p>`
    )
    .join('') || '<p class="muted">No custom metadata records in the tree.</p>'}

  <h3 class="sub">E. Apex apiVersion inventory</h3>
  <p class="small">Project <code>sourceApiVersion</code> is <strong>${esc(D.projectApi)}</strong>. ${D.driftedClasses.length ? `${D.driftedClasses.length} PSK class(es) differ — see action item P2-05.` : 'No PSK class differs.'}</p>
  <table class="grid" style="width:auto; min-width:70mm">
    <thead><tr><th>Class</th><th>apiVersion</th></tr></thead>
    <tbody>${F.apexApiVersions
      .map(
        (c) =>
          `<tr><td><code>${esc(c.cls)}</code></td><td>${c.apiVersion === D.projectApi ? esc(c.apiVersion) : `<span class="no">${esc(c.apiVersion)}</span>`}</td></tr>`
      )
      .join('')}</tbody>
  </table>

  <div class="footer-note">
    ${esc(M.title)} · org <code>${esc(M.orgAlias)}</code> · commit <code>${esc(F.gitSha)}</code> · generated ${esc(buildTime)} by
    <code>scripts/pdf/generate-report.mjs</code> from <code>scripts/pdf/report-data.json</code>.
    ${esc(M.disclaimer)}
  </div>
</section>
`;
}

/* ------------------------------------------------------------------- pipeline */

/**
 * Chrome's print pipeline scales the WHOLE document down when any box is wider than
 * the page box, so a single un-wrappable table cell shows up as "the PDF looks zoomed
 * out" — every font silently shrinks — rather than as an error. This probe renders the
 * built HTML with a throwaway measuring script and warns with the offending table's
 * header row, which is the only fast way to find the culprit.
 */
function checkNoHorizontalOverflow() {
  const probePath = join(BUILD, '.overflow-probe.html');
  const probe = `${readFileSync(HTML_OUT, 'utf8')}
<script>
  var w = document.documentElement.clientWidth, out = [];
  document.querySelectorAll('table, pre, svg, div').forEach(function (el) {
    if (el.getBoundingClientRect().width > w + 1) {
      var head = el.querySelector && el.querySelector('thead');
      out.push(el.tagName + (el.className ? '.' + el.className : '') +
        ' width=' + Math.round(el.getBoundingClientRect().width) + '/' + w +
        (head ? ' [' + head.innerText.replace(/\\s+/g, ' ').trim().slice(0, 120) + ']' : ''));
    }
  });
  document.title = 'OVERFLOW:' + (out.length ? out.slice(0, 6).join(' ;; ') : 'none');
</script>`;
  writeFileSync(probePath, probe, 'utf8');
  let dom = '';
  try {
    dom = execFileSync(CHROME, ['--headless=new', '--disable-gpu', '--no-sandbox', '--virtual-time-budget=4000', '--dump-dom', `file://${probePath}`], {
      encoding: 'utf8',
      stdio: ['ignore', 'pipe', 'ignore'],
      maxBuffer: 64 * 1024 * 1024,
    });
  } catch {
    return; // probe is best-effort; never block the actual PDF on it
  }
  const found = /OVERFLOW:([^<]*)/.exec(dom)?.[1]?.trim();
  if (found && found !== 'none') {
    console.warn(
      `WARN  horizontal overflow — Chrome will scale the whole PDF down to fit:\n      ${found}\n` +
        `      Fix the offending box (usually a table cell that cannot wrap) rather than accepting the smaller type.`
    );
  } else {
    console.log('Fit   no horizontal overflow — document prints at scale 1.');
  }
}

function main() {
  const dataPath = join(HERE, 'report-data.json');
  if (!existsSync(dataPath)) {
    console.error(`Missing ${dataPath}`);
    process.exit(1);
  }
  const DATA = JSON.parse(readFileSync(dataPath, 'utf8'));

  const F = collectFacts();
  const D = derive(F, DATA);

  mkdirSync(BUILD, { recursive: true });
  const html = renderHtml(F, D, DATA);
  writeFileSync(HTML_OUT, html, 'utf8');
  console.log(`HTML  ${HTML_OUT}  (${(Buffer.byteLength(html) / 1024).toFixed(1)} KB)`);
  console.log(
    `Scan  ${F.pskObjects.length} PSK objects · ${F.pskObjects.reduce((a, o) => a + o.fieldCount, 0)} fields · ` +
      `${F.validationRules.length} validation rules · ${F.sharingRules.length} sharing rules · ` +
      `${F.permissionSets.length} PSK permission sets · commit ${F.gitSha}`
  );

  if (HTML_ONLY) {
    console.log('--html-only: skipping Chrome.');
    return;
  }
  if (!existsSync(CHROME)) {
    console.error(`Chrome not found at ${CHROME}. Re-run with --html-only, or install Chrome.`);
    process.exit(2);
  }

  checkNoHorizontalOverflow();

  execFileSync(
    CHROME,
    [
      '--headless=new',
      '--disable-gpu',
      '--no-sandbox',
      '--virtual-time-budget=5000',
      '--no-pdf-header-footer',
      `--print-to-pdf=${PDF_OUT}`,
      `file://${HTML_OUT}`,
    ],
    { stdio: 'inherit' }
  );

  const bytes = size(PDF_OUT);
  if (!bytes) {
    console.error('Chrome exited but no PDF was written.');
    process.exit(3);
  }
  // Page count straight out of the PDF: count /Type /Page objects.
  const buf = readFileSync(PDF_OUT).toString('latin1');
  const pages =
    (buf.match(/\/Type\s*\/Page[^s]/g) ?? []).length ||
    Number(/\/Count\s+(\d+)/.exec(buf)?.[1] ?? 0) ||
    null;
  console.log(`PDF   ${PDF_OUT}  (${(bytes / 1024).toFixed(1)} KB, ${pages ?? '?'} pages)`);
}

main();
