/**
 * 02-generate-demo-data.apex
 *
 * Generate the demo data set. IDEMPOTENT: every record carries a deterministic
 * DEMO-<OBJ>-<n> external id and is written with Database.upsert(..., false), so
 * running this twice updates the same rows rather than doubling them.
 *
 * scale = 1 produces roughly 1,236 records:
 *   6 PSK__c, 60 Slot__c, 120 Citizen__c, 60 Family_Member__c,
 *   150 Passport_Application__c, 90 Appointment__c, 250 Document_Checklist_Item__c,
 *   110 Payment__c, 30 Objection__c, 50 Police_Verification__c, 25 Risk_Flag__c,
 *   70 Passport__c, 55 Print_Job__c, 50 Dispatch__c, 90 Notification_Log__c,
 *   20 Renewal__c
 *
 * Do NOT raise the scale on a Developer Edition org without checking
 * 00-storage-check.apex first. If the whole run trips the CPU-time limit, use the
 * per-stage form at the bottom of this file instead -- each stage is its own
 * transaction with its own limits.
 *
 *   sf apex run --file scripts/apex/02-generate-demo-data.apex
 */
Integer scale = 1;

PSK_DemoDataGenerator.Summary result = PSK_DemoDataGenerator.generateAll(scale);

List<String> lines = new List<String>{
    '',
    '=== PSK demo data generation ===',
    'Action:         ' + result.action,
    'Scale:          ' + result.scale,
    'Elapsed:        ' + result.elapsedMs + ' ms',
    'Rows upserted:  ' + result.totalUpserted,
    'Rows failed:    ' + result.totalFailed,
    '',
    'Per object:'
};
for (PSK_DemoDataGenerator.ObjectCount oc : result.counts) {
    lines.add('  ' + oc.objectName.rightPad(30)
        + ' ok=' + String.valueOf(oc.created).leftPad(5)
        + '  failed=' + String.valueOf(oc.failed).leftPad(5));
}
if (!result.messages.isEmpty()) {
    lines.add('');
    lines.add('Notes:');
    for (String m : result.messages) {
        lines.add('  - ' + m);
    }
}
if (!result.errors.isEmpty()) {
    lines.add('');
    lines.add('ERRORS (first 100 captured):');
    for (String e : result.errors) {
        lines.add('  ! ' + e);
    }
}
System.debug(LoggingLevel.ERROR, String.join(lines, '\n'));

/*
 * Per-stage fallback, in dependency order. Run each as its own `sf apex run`.
 *
 *   PSK_DemoDataGenerator.generateStage('offices', 1);
 *   PSK_DemoDataGenerator.generateStage('slots', 1);
 *   PSK_DemoDataGenerator.generateStage('citizens', 1);
 *   PSK_DemoDataGenerator.generateStage('family', 1);
 *   PSK_DemoDataGenerator.generateStage('applications', 1);
 *   PSK_DemoDataGenerator.generateStage('appointments', 1);
 *   PSK_DemoDataGenerator.generateStage('documents', 1);
 *   PSK_DemoDataGenerator.generateStage('payments', 1);
 *   PSK_DemoDataGenerator.generateStage('objections', 1);
 *   PSK_DemoDataGenerator.generateStage('police', 1);
 *   PSK_DemoDataGenerator.generateStage('risk', 1);
 *   PSK_DemoDataGenerator.generateStage('passports', 1);
 *   PSK_DemoDataGenerator.generateStage('printjobs', 1);
 *   PSK_DemoDataGenerator.generateStage('dispatches', 1);
 *   PSK_DemoDataGenerator.generateStage('notifications', 1);
 *   PSK_DemoDataGenerator.generateStage('renewals', 1);
 */
