/**
 * 03-verify-counts.apex
 *
 * Read-only. Run after 02-generate-demo-data.apex to confirm the data set looks
 * right: row counts, the status / record-type / payment spread on applications,
 * and the Passport__c invariants the validation rules depend on.
 *
 *   sf apex run --file scripts/apex/03-verify-counts.apex
 */
List<String> lines = new List<String>{ '', PSK_DemoDataGenerator.storageReport(), '' };

lines.add('=== Passport_Application__c by status (demo only) ===');
Set<String> seenStatuses = new Set<String>();
for (AggregateResult ar : [
    SELECT Status__c s, COUNT(Id) c
    FROM Passport_Application__c
    WHERE External_Id__c LIKE 'DEMO-%'
    GROUP BY Status__c
    ORDER BY Status__c
]) {
    seenStatuses.add((String) ar.get('s'));
    lines.add('  ' + String.valueOf(ar.get('s')).rightPad(26) + ar.get('c'));
}
for (String expected : PSK_Constants.ALL_STATUSES) {
    if (!seenStatuses.contains(expected)) {
        lines.add('  !! MISSING cohort for status: ' + expected);
    }
}

lines.add('');
lines.add('=== Passport_Application__c by record type (demo only) ===');
for (AggregateResult ar : [
    SELECT RecordType.Name rt, COUNT(Id) c
    FROM Passport_Application__c
    WHERE External_Id__c LIKE 'DEMO-%'
    GROUP BY RecordType.Name
    ORDER BY RecordType.Name
]) {
    lines.add('  ' + String.valueOf(ar.get('rt')).rightPad(26) + ar.get('c'));
}

lines.add('');
lines.add('=== Payment_Status__c spread (demo only) ===');
for (AggregateResult ar : [
    SELECT Payment_Status__c p, COUNT(Id) c
    FROM Passport_Application__c
    WHERE External_Id__c LIKE 'DEMO-%'
    GROUP BY Payment_Status__c
    ORDER BY Payment_Status__c
]) {
    lines.add('  ' + String.valueOf(ar.get('p')).rightPad(26) + ar.get('c'));
}

lines.add('');
lines.add('=== Passport__c integrity ===');
Integer mirrorBreaks = 0;
Integer formatBreaks = 0;
Integer activeMissingDates = 0;
Pattern bookletFormat = Pattern.compile('^[A-PR-WY][0-9]{7}$');
for (Passport__c p : [
    SELECT Name, External_Id__c, Status__c, Date_of_Issue__c, Date_of_Expiry__c
    FROM Passport__c
    WHERE File_Number__c LIKE 'DEMO-%'
    LIMIT 5000
]) {
    if (p.External_Id__c != p.Name) {
        mirrorBreaks++;
    }
    if (p.Name == null || !bookletFormat.matcher(p.Name).matches()) {
        formatBreaks++;
    }
    if (p.Status__c == 'Active' && (p.Date_of_Issue__c == null || p.Date_of_Expiry__c == null)) {
        activeMissingDates++;
    }
}
lines.add('  External_Id__c != Name:            ' + mirrorBreaks + '   (must be 0)');
lines.add('  Name failing ^[A-PR-WY][0-9]{7}$:  ' + formatBreaks + '   (must be 0)');
lines.add('  Active without issue/expiry dates: ' + activeMissingDates + '   (must be 0)');
lines.add('  Passports in a reissue chain:      ' + [
    SELECT COUNT() FROM Passport__c
    WHERE Previous_Passport__c != NULL AND File_Number__c LIKE 'DEMO-%'
]);

lines.add('');
lines.add('=== Slot capacity sanity ===');
Integer overbooked = 0;
for (Slot__c s : [
    SELECT Capacity__c, Booked_Count__c
    FROM Slot__c
    WHERE External_Id__c LIKE 'DEMO-%'
    LIMIT 5000
]) {
    if (s.Capacity__c != null && s.Booked_Count__c > s.Capacity__c) {
        overbooked++;
    }
}
lines.add('  Overbooked slots:                  ' + overbooked + '   (must be 0)');

lines.add('');
lines.add('=== Orphan check ===');
lines.add('  Applications with no citizen:      '
    + [SELECT COUNT() FROM Passport_Application__c WHERE Citizen__c = NULL]);

System.debug(LoggingLevel.ERROR, String.join(lines, '\n'));
