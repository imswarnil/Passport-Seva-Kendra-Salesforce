/**
 * Tests for PSK_DemoDataGenerator.
 *
 * These run the generator stage by stage rather than calling generateAll: a full
 * scale-1 run writes ~1,236 records, which is fine against a real org but wasteful
 * inside a test and close to the CPU-time limit. Each test method gets its own
 * governor limits, so the stages are split across methods.
 */
@IsTest
private class PSK_DemoDataGeneratorTest {

    private static final Pattern BOOKLET_FORMAT = Pattern.compile('^[A-PR-WY][0-9]{7}$');

    // ------------------------------------------------------- Deterministic random

    @IsTest
    static void testLcgIsDeterministic() {
        PSK_DemoDataGenerator.Lcg first = new PSK_DemoDataGenerator.Lcg(42);
        PSK_DemoDataGenerator.Lcg second = new PSK_DemoDataGenerator.Lcg(42);

        for (Integer i = 0; i < 25; i++) {
            System.assertEquals(first.nextInt(1000), second.nextInt(1000),
                'The same seed must produce the same sequence -- this is what keeps '
                + 'the upserts idempotent across runs');
        }
    }

    @IsTest
    static void testLcgDifferentSeedsDiverge() {
        PSK_DemoDataGenerator.Lcg a = new PSK_DemoDataGenerator.Lcg(1);
        PSK_DemoDataGenerator.Lcg b = new PSK_DemoDataGenerator.Lcg(2);

        Boolean diverged = false;
        for (Integer i = 0; i < 20; i++) {
            if (a.nextInt(10000) != b.nextInt(10000)) {
                diverged = true;
                break;
            }
        }
        System.assertEquals(true, diverged, 'Different seeds must produce different sequences');
    }

    @IsTest
    static void testLcgStaysInBounds() {
        PSK_DemoDataGenerator.Lcg rnd = new PSK_DemoDataGenerator.Lcg(7);
        for (Integer i = 0; i < 200; i++) {
            Integer value = rnd.nextInt(10);
            System.assertEquals(true, value >= 0 && value < 10,
                'nextInt(10) must stay in [0,10) but returned ' + value);
        }
        System.assertEquals(0, rnd.nextInt(0), 'A zero bound is safe');
        System.assertEquals(0, rnd.nextInt(null), 'A null bound is safe');

        for (Integer i = 0; i < 50; i++) {
            Integer value = rnd.between(6, 9);
            System.assertEquals(true, value >= 6 && value <= 9,
                'between(6,9) is inclusive on both ends but returned ' + value);
        }
        System.assertEquals(5, rnd.between(5, 5), 'A degenerate range returns the bound');
        System.assertEquals(5, rnd.between(5, 3), 'An inverted range returns the low bound');
        System.assertEquals(null, rnd.pick(new List<String>()), 'Picking from nothing is null');
        System.assertEquals(null, rnd.pick(null));
    }

    // ----------------------------------------------------------- Guard behaviour

    @IsTest
    static void testCleanUpRequiresTheExactToken() {
        Integer refusals = 0;
        for (String badToken : new List<String>{
            null, '', 'delete-psk-demo-data', 'DELETE-PSK-DEMO-DATA ', 'yes'
        }) {
            try {
                PSK_DemoDataGenerator.cleanUp(badToken);
                System.assert(false, 'cleanUp accepted the token "' + badToken + '"');
            } catch (PSK_DemoDataGenerator.PSK_DemoDataException e) {
                refusals++;
                System.assertEquals(true, e.getMessage().contains('DELETE-PSK-DEMO-DATA'),
                    'The error should name the required token');
            }
        }
        System.assertEquals(5, refusals, 'Every near-miss token must be refused');
    }

    @IsTest
    static void testUnknownStageIsReportedNotThrown() {
        Test.startTest();
        PSK_DemoDataGenerator.Summary sum =
            PSK_DemoDataGenerator.generateStage('not-a-stage', 1);
        Test.stopTest();

        System.assertEquals(1, sum.errors.size());
        System.assertEquals(true, sum.errors[0].contains('Unknown stage'), sum.errors[0]);
        System.assertEquals(0, sum.totalUpserted);
    }

    @IsTest
    static void testBlankStageIsRejected() {
        System.assertEquals(1, PSK_DemoDataGenerator.generateStage(null, 1).errors.size());
        System.assertEquals(1, PSK_DemoDataGenerator.generateStage('  ', 1).errors.size());
    }

    // ---------------------------------------------------------------- Idempotency

    @IsTest
    static void testOfficeStageIsIdempotent() {
        Test.startTest();
        PSK_DemoDataGenerator.Summary first =
            PSK_DemoDataGenerator.generateStage('offices', 1);
        Integer afterFirst = [SELECT COUNT() FROM PSK__c WHERE Office_Code__c LIKE 'DEMO-%'];

        PSK_DemoDataGenerator.clearCaches();
        PSK_DemoDataGenerator.Summary second =
            PSK_DemoDataGenerator.generateStage('offices', 1);
        Integer afterSecond = [SELECT COUNT() FROM PSK__c WHERE Office_Code__c LIKE 'DEMO-%'];
        Test.stopTest();

        System.assertEquals(6, afterFirst, 'Six demo offices at scale 1');
        System.assertEquals(afterFirst, afterSecond,
            'A second run must UPDATE the same six offices, not add six more');
        System.assertEquals(0, first.totalFailed, String.join(first.errors, '; '));
        System.assertEquals(0, second.totalFailed, String.join(second.errors, '; '));
    }

    @IsTest
    static void testCitizenStageIsIdempotentAndHitsEveryKycValue() {
        Test.startTest();
        PSK_DemoDataGenerator.generateStage('citizens', 1);
        Integer afterFirst = [SELECT COUNT() FROM Citizen__c WHERE Citizen_Reference__c LIKE 'DEMO-%'];

        PSK_DemoDataGenerator.clearCaches();
        PSK_DemoDataGenerator.generateStage('citizens', 1);
        Integer afterSecond = [SELECT COUNT() FROM Citizen__c WHERE Citizen_Reference__c LIKE 'DEMO-%'];
        Test.stopTest();

        System.assertEquals(120, afterFirst, '120 demo citizens at scale 1');
        System.assertEquals(afterFirst, afterSecond, 'Re-running must not double the citizens');

        Set<String> kycSeen = new Set<String>();
        for (AggregateResult ar : [
            SELECT KYC_Status__c k FROM Citizen__c
            WHERE Citizen_Reference__c LIKE 'DEMO-%' GROUP BY KYC_Status__c
        ]) {
            kycSeen.add((String) ar.get('k'));
        }
        System.assertEquals(4, kycSeen.size(),
            'Round-robin assignment must exercise all four KYC values, saw ' + kycSeen);
    }

    // ----------------------------------------------------- Lifecycle correctness

    @IsTest
    static void testApplicationCohortsCoverEveryStatus() {
        Test.startTest();
        PSK_DemoDataGenerator.generateStage('offices', 1);
        PSK_DemoDataGenerator.clearCaches();
        PSK_DemoDataGenerator.generateStage('citizens', 1);
        PSK_DemoDataGenerator.clearCaches();
        PSK_DemoDataGenerator.Summary sum =
            PSK_DemoDataGenerator.generateStage('applications', 1);
        Test.stopTest();

        System.assertEquals(0, sum.totalFailed,
            'Every cohort must survive the validation rules: ' + String.join(sum.errors, ' | '));
        System.assertEquals(150, [
            SELECT COUNT() FROM Passport_Application__c WHERE External_Id__c LIKE 'DEMO-%'
        ], '150 demo applications at scale 1');

        Set<String> statuses = new Set<String>();
        for (AggregateResult ar : [
            SELECT Status__c s FROM Passport_Application__c
            WHERE External_Id__c LIKE 'DEMO-%' GROUP BY Status__c
        ]) {
            statuses.add((String) ar.get('s'));
        }
        System.assertEquals(12, statuses.size(),
            'All twelve statuses need a cohort, saw ' + statuses);

        Set<Id> recordTypes = new Set<Id>();
        for (Passport_Application__c app : [
            SELECT RecordTypeId FROM Passport_Application__c WHERE External_Id__c LIKE 'DEMO-%'
        ]) {
            recordTypes.add(app.RecordTypeId);
        }
        System.assertEquals(6, recordTypes.size(), 'All six record types should be represented');
    }

    @IsTest
    static void testGrantedCohortsAreAlwaysPaid() {
        Test.startTest();
        PSK_DemoDataGenerator.generateStage('offices', 1);
        PSK_DemoDataGenerator.clearCaches();
        PSK_DemoDataGenerator.generateStage('citizens', 1);
        PSK_DemoDataGenerator.clearCaches();
        PSK_DemoDataGenerator.generateStage('applications', 1);
        Test.stopTest();

        // Cannot_Grant_With_Pending_Payment
        System.assertEquals(0, [
            SELECT COUNT() FROM Passport_Application__c
            WHERE External_Id__c LIKE 'DEMO-%'
              AND Status__c IN ('Granting', 'Printing', 'Dispatch', 'Delivered')
              AND Payment_Status__c != 'Paid'
        ], 'Granting and beyond must always carry a paid fee');

        // Minor_Needs_Guardian_Consent
        System.assertEquals(0, [
            SELECT COUNT() FROM Passport_Application__c
            WHERE External_Id__c LIKE 'DEMO-%'
              AND Applied_For_Minor__c = true
              AND Guardian_Consent__c = false
        ], 'Every minor application must carry guardian consent');

        // Require_Core_Fields_On_Submit
        System.assertEquals(0, [
            SELECT COUNT() FROM Passport_Application__c
            WHERE External_Id__c LIKE 'DEMO-%'
              AND Status__c != 'Draft'
              AND (First_Name__c = NULL OR Last_Name__c = NULL OR Date_of_Birth__c = NULL
                   OR Mobile__c = NULL OR Address_Line1__c = NULL)
        ], 'Non-draft applications must carry the core fields');

        System.assertEquals(0, [
            SELECT COUNT() FROM Passport_Application__c
            WHERE External_Id__c LIKE 'DEMO-%' AND Citizen__c = NULL
        ], 'Every demo application is linked to a citizen');
    }

    @IsTest
    static void testDiplomaticCohortUsesTheDependentPicklistBranch() {
        Test.startTest();
        PSK_DemoDataGenerator.generateStage('offices', 1);
        PSK_DemoDataGenerator.clearCaches();
        PSK_DemoDataGenerator.generateStage('citizens', 1);
        PSK_DemoDataGenerator.clearCaches();
        PSK_DemoDataGenerator.generateStage('applications', 1);
        Test.stopTest();

        Id diplomaticRt = PSK_ApplicationService.applicationRecordTypeId(
            PSK_Constants.RT_DIPLOMATIC_OFFICIAL);
        List<Passport_Application__c> apps = [
            SELECT Passport_Category__c, Clearance_Level__c
            FROM Passport_Application__c
            WHERE External_Id__c LIKE 'DEMO-%' AND RecordTypeId = :diplomaticRt
        ];
        System.assertEquals(true, apps.size() > 0, 'The diplomatic cohort should exist');

        for (Passport_Application__c app : apps) {
            System.assertEquals(true,
                app.Passport_Category__c == 'Diplomatic' || app.Passport_Category__c == 'Official',
                'A diplomatic/official application must not be Ordinary');
            System.assertNotEquals(null, app.Clearance_Level__c,
                'A clearance level is required for this cohort');
            System.assertEquals(true,
                PSK_Constants.CLEARANCE_BY_CATEGORY
                    .get(app.Passport_Category__c).contains(app.Clearance_Level__c),
                app.Clearance_Level__c + ' is not a valid clearance for '
                + app.Passport_Category__c + ' -- Clearance_Level__c is a dependent picklist');
        }
    }

    @IsTest
    static void testSlotsRespectCapacityAfterAppointments() {
        Test.startTest();
        PSK_DemoDataGenerator.generateStage('offices', 1);
        PSK_DemoDataGenerator.clearCaches();
        PSK_DemoDataGenerator.generateStage('slots', 1);
        PSK_DemoDataGenerator.clearCaches();
        PSK_DemoDataGenerator.generateStage('citizens', 1);
        PSK_DemoDataGenerator.clearCaches();
        PSK_DemoDataGenerator.generateStage('applications', 1);
        PSK_DemoDataGenerator.clearCaches();
        PSK_DemoDataGenerator.Summary sum =
            PSK_DemoDataGenerator.generateStage('appointments', 1);
        Test.stopTest();

        System.assertEquals(0, sum.totalFailed,
            'Appointments must be spread so no slot overbooks: ' + String.join(sum.errors, ' | '));
        System.assertEquals(60, [SELECT COUNT() FROM Slot__c WHERE External_Id__c LIKE 'DEMO-%']);

        for (Slot__c slot : [
            SELECT Capacity__c, Booked_Count__c FROM Slot__c WHERE External_Id__c LIKE 'DEMO-%'
        ]) {
            System.assertEquals(true, slot.Booked_Count__c <= slot.Capacity__c,
                'A slot booked ' + slot.Booked_Count__c + ' times has capacity '
                + slot.Capacity__c + ' -- Slot_Not_Overbooked would reject this');
        }
    }

    @IsTest
    static void testPassportsSatisfyTheirValidationRules() {
        Test.startTest();
        PSK_DemoDataGenerator.generateStage('offices', 1);
        PSK_DemoDataGenerator.clearCaches();
        PSK_DemoDataGenerator.generateStage('citizens', 1);
        PSK_DemoDataGenerator.clearCaches();
        PSK_DemoDataGenerator.generateStage('applications', 1);
        PSK_DemoDataGenerator.clearCaches();
        PSK_DemoDataGenerator.Summary sum =
            PSK_DemoDataGenerator.generateStage('passports', 1);
        Test.stopTest();

        System.assertEquals(0, sum.totalFailed, String.join(sum.errors, ' | '));

        List<Passport__c> passports = [
            SELECT Name, External_Id__c, Status__c, Date_of_Issue__c, Date_of_Expiry__c,
                   Previous_Passport__c
            FROM Passport__c WHERE File_Number__c LIKE 'DEMO-%'
        ];
        System.assertEquals(70, passports.size(), '70 demo booklets at scale 1');

        Integer chained = 0;
        for (Passport__c p : passports) {
            System.assertEquals(p.Name, p.External_Id__c,
                'External_Id_Must_Mirror_Number requires External_Id__c == Name');
            System.assertEquals(true, BOOKLET_FORMAT.matcher(p.Name).matches(),
                p.Name + ' must satisfy Passport_Number_Format ^[A-PR-WY][0-9]{7}$');
            if (p.Status__c == PSK_Constants.PASSPORT_ACTIVE) {
                System.assertNotEquals(null, p.Date_of_Issue__c,
                    'Active_Requires_Issue_And_Expiry_Dates');
                System.assertNotEquals(null, p.Date_of_Expiry__c,
                    'Active_Requires_Issue_And_Expiry_Dates');
            }
            if (p.Previous_Passport__c != null) {
                chained++;
            }
        }
        System.assertEquals(true, chained > 0,
            'Some booklets should be linked into a reissue chain for the passport LWC');
    }

    // ------------------------------------------------------------------- Cleanup

    @IsTest
    static void testCleanUpRemovesOnlyDemoRecords() {
        // A hand-created office that must survive the cleanup.
        PSK__c keeper = PSK_TestDataFactory.createOffice();

        Test.startTest();
        PSK_DemoDataGenerator.generateStage('offices', 1);
        PSK_DemoDataGenerator.clearCaches();
        PSK_DemoDataGenerator.generateStage('citizens', 1);
        PSK_DemoDataGenerator.clearCaches();

        PSK_DemoDataGenerator.Summary wipe =
            PSK_DemoDataGenerator.cleanUp('DELETE-PSK-DEMO-DATA');
        Test.stopTest();

        System.assertEquals(true, wipe.totalDeleted >= 126,
            'Six offices and 120 citizens should have gone, deleted ' + wipe.totalDeleted);
        System.assertEquals(0, [SELECT COUNT() FROM PSK__c WHERE Office_Code__c LIKE 'DEMO-%']);
        System.assertEquals(0, [
            SELECT COUNT() FROM Citizen__c WHERE Citizen_Reference__c LIKE 'DEMO-%'
        ]);
        System.assertEquals(1, [SELECT COUNT() FROM PSK__c WHERE Id = :keeper.Id],
            'A hand-created office must never be touched');
    }

    // ------------------------------------------------------------------ Backfill

    @IsTest
    static void testBackfillCitizens() {
        // Insert applications with no citizen by bypassing the reverse-create.
        PSK_AutomationControl.reset();
        PSK_AutomationControl.bypassTriggers = true;
        List<Passport_Application__c> apps = new List<Passport_Application__c>();
        for (Integer i = 0; i < 5; i++) {
            apps.add(PSK_TestDataFactory.buildApplication(PSK_Constants.STATUS_SUBMITTED));
        }
        // Two applications for the SAME person must end up sharing one citizen.
        Passport_Application__c twin = apps[0].clone(false, true, false, false);
        twin.External_Id__c = 'TEST-APP-TWIN';
        apps.add(twin);
        insert apps;
        PSK_AutomationControl.reset();

        System.assertEquals(6, [
            SELECT COUNT() FROM Passport_Application__c WHERE Citizen__c = NULL
        ], 'Precondition: six orphaned applications');

        Test.startTest();
        Integer stamped = PSK_DemoDataGenerator.backfillCitizens();
        Test.stopTest();

        System.assertEquals(6, stamped, 'All six applications should be stamped');
        System.assertEquals(0, [
            SELECT COUNT() FROM Passport_Application__c WHERE Citizen__c = NULL
        ]);
        System.assertEquals(5, [SELECT COUNT() FROM Citizen__c],
            'Five distinct people, so five citizens -- the twin shares one');
    }

    @IsTest
    static void testBackfillCitizensIsANoOpWhenNothingIsOrphaned() {
        PSK_TestDataFactory.createApplication(PSK_Constants.STATUS_DRAFT);

        Test.startTest();
        Integer stamped = PSK_DemoDataGenerator.backfillCitizens();
        Test.stopTest();

        System.assertEquals(0, stamped,
            'The trigger already linked a citizen, so there is nothing to back-fill');
    }

    // ------------------------------------------------------------------ Reporting

    @IsTest
    static void testStorageReport() {
        PSK_DemoDataGenerator.generateStage('offices', 1);

        Test.startTest();
        String report = PSK_DemoDataGenerator.storageReport();
        Test.stopTest();

        System.assertNotEquals(null, report);
        System.assertEquals(true, report.contains('PSK storage report'), report);
        System.assertEquals(true, report.contains('Passport_Application__c'), report);
        System.assertEquals(true, report.contains('PSK objects total'), report);
        System.assertEquals(true, report.contains('Account'),
            'The shared Account count should be visible for storage planning');
    }

    @IsTest
    static void testStorageReportFromUI() {
        System.assertNotEquals(null, PSK_DemoDataGenerator.storageReportFromUI());
    }

    @IsTest
    static void testRunFromUIReturnsJson() {
        Test.startTest();
        String json = PSK_DemoDataGenerator.runFromUI(1);
        Test.stopTest();

        System.assertNotEquals(null, json);
        Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(json);
        System.assertEquals('generateAll', parsed.get('action'));
        System.assertEquals(1, parsed.get('scale'));
        System.assertNotEquals(null, parsed.get('counts'));
    }

    @IsTest
    static void testScaleIsNormalised() {
        // Scale is floored at 1 and capped at 5 so a Developer Edition org cannot be
        // asked for 50,000 records by accident.
        System.assertEquals(1, PSK_DemoDataGenerator.generateStage('offices', null).scale);
        PSK_DemoDataGenerator.clearCaches();
        System.assertEquals(1, PSK_DemoDataGenerator.generateStage('offices', 0).scale);
        PSK_DemoDataGenerator.clearCaches();
        System.assertEquals(1, PSK_DemoDataGenerator.generateStage('offices', -7).scale);
        PSK_DemoDataGenerator.clearCaches();
        System.assertEquals(5, PSK_DemoDataGenerator.generateStage('offices', 99).scale,
            'The scale is capped at 5');
    }

    @IsTest
    static void testStagesListMatchesTheDispatcher() {
        System.assertEquals(16, PSK_DemoDataGenerator.STAGES.size(),
            'Sixteen objects, sixteen stages');
        System.assertEquals('offices', PSK_DemoDataGenerator.STAGES[0],
            'Offices come first: everything else depends on them');
        System.assertEquals(true, PSK_DemoDataGenerator.STAGES.indexOf('citizens')
            < PSK_DemoDataGenerator.STAGES.indexOf('applications'),
            'Citizens must exist before applications can link to them');
        System.assertEquals(true, PSK_DemoDataGenerator.STAGES.indexOf('applications')
            < PSK_DemoDataGenerator.STAGES.indexOf('passports'),
            'Passports hang off applications');
    }

    @IsTest
    static void testStageWithMissingPrerequisitesReportsAnError() {
        // No offices or citizens exist, so the applications stage cannot proceed.
        Test.startTest();
        PSK_DemoDataGenerator.Summary sum =
            PSK_DemoDataGenerator.generateStage('applications', 1);
        Test.stopTest();

        System.assertEquals(0, sum.totalUpserted);
        System.assertEquals(true, sum.totalFailed > 0,
            'A missing prerequisite must be surfaced, not silently skipped');
        System.assertEquals(true, sum.errors[0].contains('earlier stages'), sum.errors[0]);
    }

    @IsTest
    static void testBypassIsRestoredAfterAStage() {
        PSK_AutomationControl.reset();
        System.assertEquals(false, PSK_AutomationControl.bypassTriggers);

        Test.startTest();
        PSK_DemoDataGenerator.generateStage('offices', 1);
        Test.stopTest();

        System.assertEquals(false, PSK_AutomationControl.bypassTriggers,
            'The generator must restore the bypass flag, or every later DML in the '
            + 'transaction silently loses its automation');
    }
}
