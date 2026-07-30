/**
 * 99-cleanup-demo-data.apex
 *
 * DESTRUCTIVE. Deletes every record this generator created, in reverse dependency
 * order -- Passport__c before Passport_Application__c, because
 * Passport__c.Application__c has deleteConstraint Restrict.
 *
 * Only records carrying the generator's marker are touched:
 *   - most objects:     External_Id__c       LIKE 'DEMO-%'
 *   - PSK__c:           Office_Code__c       LIKE 'DEMO-%'
 *   - Citizen__c:       Citizen_Reference__c LIKE 'DEMO-%'
 *   - Passport__c:      File_Number__c       LIKE 'DEMO-%'
 *                       (External_Id__c cannot carry the marker -- the
 *                       External_Id_Must_Mirror_Number rule pins it to the
 *                       booklet number)
 *   - Family_Member__c: parent citizen's Citizen_Reference__c LIKE 'DEMO-%'
 *                       (the object has no unique field of its own)
 *
 * Hand-created and inherited records are never matched. cleanUp throws unless the
 * confirmation token is exactly 'DELETE-PSK-DEMO-DATA'.
 *
 *   sf apex run --file scripts/apex/99-cleanup-demo-data.apex
 */
PSK_DemoDataGenerator.Summary result =
    PSK_DemoDataGenerator.cleanUp('DELETE-PSK-DEMO-DATA');

List<String> lines = new List<String>{
    '',
    '=== PSK demo data cleanup ===',
    'Elapsed:       ' + result.elapsedMs + ' ms',
    'Rows deleted:  ' + result.totalDeleted,
    'Failures:      ' + result.totalFailed,
    ''
};
for (String m : result.messages) {
    lines.add('  - ' + m);
}
if (!result.errors.isEmpty()) {
    lines.add('');
    lines.add('ERRORS:');
    for (String e : result.errors) {
        lines.add('  ! ' + e);
    }
}
lines.add('');
lines.add(PSK_DemoDataGenerator.storageReport());
System.debug(LoggingLevel.ERROR, String.join(lines, '\n'));
