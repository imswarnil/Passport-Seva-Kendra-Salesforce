/**
 * 01-backfill-citizens.apex
 *
 * For every Passport_Application__c with no Citizen__c, upsert a Citizen__c from
 * the application's snapshot fields and stamp the lookup. Matching uses the same
 * natural key as PassportApplicationTriggerHandler -- lower(first + last) + date
 * of birth + mobile -- so two applications for the same person share one citizen
 * and a second run is a no-op.
 *
 * Processes up to 2,000 applications per run; re-run until it reports 0 remaining.
 *
 *   sf apex run --file scripts/apex/01-backfill-citizens.apex
 */
Integer before = [SELECT COUNT() FROM Passport_Application__c WHERE Citizen__c = NULL];
Integer stamped = PSK_DemoDataGenerator.backfillCitizens();
Integer remaining = [SELECT COUNT() FROM Passport_Application__c WHERE Citizen__c = NULL];

System.debug(LoggingLevel.ERROR, '\n=== Citizen backfill ==='
    + '\nApplications without a citizen, before: ' + before
    + '\nApplications stamped this run:          ' + stamped
    + '\nApplications without a citizen, after:  ' + remaining
    + '\nTotal Citizen__c rows now:              ' + [SELECT COUNT() FROM Citizen__c]
    + (remaining > 0
        ? '\n\nStill ' + remaining + ' to go -- run this script again.'
        : '\n\nDone.')
);
