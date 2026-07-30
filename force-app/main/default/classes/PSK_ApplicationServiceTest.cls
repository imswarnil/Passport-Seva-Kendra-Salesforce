@IsTest
private class PSK_ApplicationServiceTest {

    private static final Pattern BOOKLET_FORMAT = Pattern.compile('^[A-PR-WY][0-9]{7}$');

    // ------------------------------------------------------------ Record types

    @IsTest
    static void testRecordTypeHelpers() {
        Map<String, Id> ids = PSK_ApplicationService.applicationRecordTypeIds();
        System.assertEquals(6, ids.size(), 'Six application record types are expected');

        Id freshId = PSK_ApplicationService.applicationRecordTypeId(PSK_Constants.RT_FRESH);
        System.assertNotEquals(null, freshId);
        System.assertEquals(PSK_Constants.RT_FRESH,
            PSK_ApplicationService.applicationRecordTypeName(freshId),
            'Name lookup must round-trip the id lookup');

        System.assertEquals(null, PSK_ApplicationService.applicationRecordTypeName(null));
        System.assertEquals(null, PSK_ApplicationService.applicationRecordTypeId(null));
        System.assertNotEquals(null, PSK_ApplicationService.passportRecordTypeId(
            PSK_Constants.PASSPORT_RT_ORDINARY));
        System.assertEquals(null, PSK_ApplicationService.passportRecordTypeId(null));
    }

    @IsTest
    static void testEffectiveApplicationType() {
        Passport_Application__c noRt = PSK_TestDataFactory.buildApplication(
            PSK_Constants.STATUS_DRAFT);
        System.assertEquals(PSK_Constants.RT_FRESH,
            PSK_ApplicationService.effectiveApplicationType(noRt),
            'No record type falls back to Fresh');

        noRt.Tatkal__c = true;
        System.assertEquals(PSK_Constants.RT_TATKAL,
            PSK_ApplicationService.effectiveApplicationType(noRt),
            'The Tatkal checkbox wins when there is no record type');

        Passport_Application__c minor = PSK_TestDataFactory.buildApplication(
            PSK_Constants.STATUS_DRAFT, PSK_Constants.RT_MINOR);
        System.assertEquals(PSK_Constants.RT_MINOR,
            PSK_ApplicationService.effectiveApplicationType(minor));
    }

    // -------------------------------------------------------------------- Fees

    @IsTest
    static void testResolveFeeExactMatch() {
        PSK_ApplicationService.overrideFeeMatrix(PSK_TestDataFactory.feeMatrixRows());

        PSK_ApplicationService.FeeBreakdown fb = PSK_ApplicationService.resolveFee(
            PSK_Constants.RT_FRESH, 36, 10, false);

        System.assertEquals(true, fb.matched, 'An exact matrix row exists for Fresh/36/10');
        System.assertEquals(1500, fb.baseFee);
        System.assertEquals(0, fb.tatkalSurcharge, 'Not a tatkal application');
        System.assertEquals(1500, fb.totalFee);
    }

    @IsTest
    static void testResolveFeeAddsTatkalSurcharge() {
        PSK_ApplicationService.overrideFeeMatrix(PSK_TestDataFactory.feeMatrixRows());

        PSK_ApplicationService.FeeBreakdown fb = PSK_ApplicationService.resolveFee(
            PSK_Constants.RT_TATKAL, 36, 10, true);

        System.assertEquals(1500, fb.baseFee);
        System.assertEquals(2000, fb.tatkalSurcharge);
        System.assertEquals(3500, fb.totalFee, 'Base plus the tatkal surcharge');
    }

    @IsTest
    static void testResolveFeeWidensWhenNoExactRow() {
        PSK_ApplicationService.overrideFeeMatrix(PSK_TestDataFactory.feeMatrixRows());

        // No Minor/60/5 row exists, so it should widen to the Minor/36/5 row and add
        // the larger-booklet surcharge rather than returning nothing.
        PSK_ApplicationService.FeeBreakdown fb = PSK_ApplicationService.resolveFee(
            PSK_Constants.RT_MINOR, 60, 5, false);

        System.assertEquals(false, fb.matched, 'No exact row for a 60-page minor booklet');
        System.assertEquals(1000, fb.baseFee, 'Falls back to the Minor row that does exist');
        System.assertEquals(500, fb.additionalBookletFee,
            'A 60-page booklet priced off a 36-page row picks up the booklet surcharge');
        System.assertEquals(1500, fb.totalFee);
    }

    @IsTest
    static void testResolveFeeWithNoMatrixAtAll() {
        PSK_ApplicationService.overrideFeeMatrix(new List<Fee_Matrix__mdt>());

        PSK_ApplicationService.FeeBreakdown fb = PSK_ApplicationService.resolveFee(
            PSK_Constants.RT_DIPLOMATIC_OFFICIAL, 36, 10, false);

        System.assertEquals(false, fb.matched);
        System.assertEquals(1500, fb.totalFee,
            'An empty matrix still yields a safe default rather than null');
        System.assertEquals(null, fb.matrixRecord);
    }

    @IsTest
    static void testBookletPagesAndValidityDefaults() {
        Passport_Application__c app = PSK_TestDataFactory.buildApplication(
            PSK_Constants.STATUS_DRAFT);
        app.Booklet_Pages__c = null;
        app.Validity_Years__c = null;
        System.assertEquals(36, PSK_ApplicationService.bookletPagesOf(app),
            'Blank booklet pages default to 36');
        System.assertEquals(10, PSK_ApplicationService.validityYearsOf(app),
            'Blank validity defaults to 10 years for an adult');

        app.Applied_For_Minor__c = true;
        System.assertEquals(5, PSK_ApplicationService.validityYearsOf(app),
            'A minor booklet defaults to 5 years');

        app.Validity_Years__c = '10';
        System.assertEquals(10, PSK_ApplicationService.validityYearsOf(app),
            'An explicit value always wins over the default');
    }

    @IsTest
    static void testApplyFeesOnlyWhenBlankOrDriversChanged() {
        PSK_ApplicationService.overrideFeeMatrix(PSK_TestDataFactory.feeMatrixRows());

        Passport_Application__c app = PSK_TestDataFactory.buildApplication(
            PSK_Constants.STATUS_DRAFT);
        app.Fee__c = null;
        PSK_ApplicationService.applyFees(new List<Passport_Application__c>{ app }, null);
        System.assertEquals(1500, app.Fee__c, 'A blank fee is always computed');

        // A manual override must survive an unrelated edit.
        app.Id = fakeId(Passport_Application__c.SObjectType, 1);
        app.Fee__c = 9999;
        Passport_Application__c prior = app.clone(true, true, true, true);
        PSK_ApplicationService.applyFees(
            new List<Passport_Application__c>{ app },
            new Map<Id, Passport_Application__c>{ app.Id => prior }
        );
        System.assertEquals(9999, app.Fee__c,
            'Nothing changed, so the manual fee override must be left alone');

        // Changing a driving field forces a recompute.
        app.Booklet_Pages__c = '60';
        PSK_ApplicationService.applyFees(
            new List<Passport_Application__c>{ app },
            new Map<Id, Passport_Application__c>{ app.Id => prior }
        );
        System.assertEquals(2000, app.Fee__c,
            'Changing the booklet size must recompute the fee');
    }

    // --------------------------------------------------------- Booklet numbers

    @IsTest
    static void testBookletNumberFormatAndDeterminism() {
        String first = PSK_ApplicationService.generateBookletNumber('SEED-A');
        String again = PSK_ApplicationService.generateBookletNumber('SEED-A');
        String other = PSK_ApplicationService.generateBookletNumber('SEED-B');

        System.assertEquals(first, again,
            'The same seed must always produce the same booklet number -- this is what '
            + 'makes the generator and the trigger idempotent');
        System.assertNotEquals(first, other, 'Different seeds should differ');
        System.assertEquals(8, first.length());
        System.assertEquals(true, BOOKLET_FORMAT.matcher(first).matches(),
            'Passport_Number_Format requires ^[A-PR-WY][0-9]{7}$ but got ' + first);
    }

    @IsTest
    static void testBookletNumberAvoidsExcludedLetters() {
        Set<String> excluded = new Set<String>{ 'I', 'O', 'Q', 'X', 'Z' };
        for (Integer i = 0; i < 60; i++) {
            String number = PSK_ApplicationService.generateBookletNumber('SEED-' + i);
            System.assertEquals(true, BOOKLET_FORMAT.matcher(number).matches(),
                number + ' must match the passport number format');
            System.assertEquals(false, excluded.contains(number.substring(0, 1)),
                number + ' starts with an excluded letter');
        }
    }

    @IsTest
    static void testBookletNumberHandlesBlankSeed() {
        String number = PSK_ApplicationService.generateBookletNumber(null);
        System.assertEquals(true, BOOKLET_FORMAT.matcher(number).matches(),
            'A null seed must still produce a valid booklet number');
    }

    // -------------------------------------------------------- Citizen handling

    @IsTest
    static void testCitizenKeyIsCaseAndFormatInsensitive() {
        Date dob = Date.newInstance(1990, 1, 1);
        String a = PSK_ApplicationService.citizenKey('Rahul', 'Verma', dob, '9000090000');
        String b = PSK_ApplicationService.citizenKey('  rahul ', 'VERMA', dob, '90000-90000');
        System.assertEquals(a, b,
            'Case, surrounding whitespace and phone punctuation must not change the key');

        String c = PSK_ApplicationService.citizenKey('Rahul', 'Verma', dob, '9000090001');
        System.assertNotEquals(a, c, 'A different mobile is a different person');
        System.assertNotEquals(null, PSK_ApplicationService.citizenKey(null, null, null, null));
    }

    @IsTest
    static void testEnsureCitizensCreatesAndReuses() {
        Passport_Application__c one = PSK_TestDataFactory.buildApplication(
            PSK_Constants.STATUS_DRAFT);
        Passport_Application__c two = one.clone(false, true, false, false);
        two.External_Id__c = 'TEST-APP-CLONE';

        Test.startTest();
        PSK_ApplicationService.ensureCitizens(new List<Passport_Application__c>{ one, two });
        Test.stopTest();

        System.assertNotEquals(null, one.Citizen__c, 'A citizen should have been created');
        System.assertEquals(one.Citizen__c, two.Citizen__c,
            'Two applications for the same person must share one citizen record');
        System.assertEquals(1, [SELECT COUNT() FROM Citizen__c],
            'Exactly one citizen, not two');
    }

    @IsTest
    static void testEnsureCitizensSkipsIncompleteRecords() {
        Passport_Application__c noName = PSK_TestDataFactory.buildApplication(
            PSK_Constants.STATUS_DRAFT);
        noName.First_Name__c = null;

        Citizen__c existing = PSK_TestDataFactory.createCitizen();
        Passport_Application__c alreadyLinked = PSK_TestDataFactory.buildApplication(
            PSK_Constants.STATUS_DRAFT);
        alreadyLinked.Citizen__c = existing.Id;

        Integer before = [SELECT COUNT() FROM Citizen__c];
        PSK_ApplicationService.ensureCitizens(
            new List<Passport_Application__c>{ noName, alreadyLinked });

        System.assertEquals(before, [SELECT COUNT() FROM Citizen__c],
            'No citizen should be created for an unnamed or already-linked application');
        System.assertEquals(null, noName.Citizen__c);
        System.assertEquals(existing.Id, alreadyLinked.Citizen__c,
            'An existing link must never be overwritten');
    }

    @IsTest
    static void testCopyFromCitizenOnlyFillsBlanks() {
        Citizen__c citizen = PSK_TestDataFactory.createCitizen();

        Passport_Application__c app = PSK_TestDataFactory.buildApplication(
            PSK_Constants.STATUS_DRAFT);
        app.Citizen__c = citizen.Id;
        // Deliberately keep an as-submitted value that differs from the citizen.
        app.City__c = 'Nagpur';
        app.Mobile__c = '9111111111';
        app.Gender__c = null;
        app.Email__c = null;

        PSK_ApplicationService.copyFromCitizenWhenBlank(
            new List<Passport_Application__c>{ app });

        System.assertEquals('Nagpur', app.City__c,
            'A populated snapshot field must never be overwritten by the citizen');
        System.assertEquals('9111111111', app.Mobile__c,
            'The as-submitted mobile is the snapshot and must survive');
        System.assertEquals(citizen.Gender__c, app.Gender__c,
            'A blank field is filled from the citizen');
        System.assertEquals(citizen.Email__c, app.Email__c);
        System.assertEquals(true, app.Aadhaar_Verified__c,
            'Aadhaar verification propagates from the citizen');
    }

    @IsTest
    static void testCopyFromCitizenNoOpWithoutCitizen() {
        Passport_Application__c app = PSK_TestDataFactory.buildApplication(
            PSK_Constants.STATUS_DRAFT);
        app.Citizen__c = null;
        app.Gender__c = null;
        PSK_ApplicationService.copyFromCitizenWhenBlank(
            new List<Passport_Application__c>{ app });
        System.assertEquals(null, app.Gender__c, 'Nothing to copy from');
    }

    @IsTest
    static void testBuildCitizenName() {
        Passport_Application__c app = PSK_TestDataFactory.buildApplication(
            PSK_Constants.STATUS_DRAFT);
        app.First_Name__c = 'Aarav';
        app.Middle_Name__c = 'Kumar';
        app.Last_Name__c = 'Sharma';
        System.assertEquals('Aarav Kumar Sharma', PSK_ApplicationService.buildCitizenName(app));

        app.First_Name__c = null;
        app.Middle_Name__c = null;
        app.Last_Name__c = null;
        System.assertEquals('Unnamed Citizen', PSK_ApplicationService.buildCitizenName(app));
    }

    // ---------------------------------------------------------------- Issuance

    @IsTest
    static void testIssuePassportsIsIdempotent() {
        PSK_AutomationControl.reset();
        PSK_AutomationControl.bypassTriggers = true;
        Passport_Application__c app = PSK_TestDataFactory.createLinkedApplication(
            PSK_Constants.STATUS_GRANTING);
        PSK_AutomationControl.reset();

        Test.startTest();
        Map<Id, PSK_ApplicationService.IssuanceResult> first =
            PSK_ApplicationService.issuePassports(new Set<Id>{ app.Id });
        Map<Id, PSK_ApplicationService.IssuanceResult> second =
            PSK_ApplicationService.issuePassports(new Set<Id>{ app.Id });
        Test.stopTest();

        System.assertEquals(true, first.get(app.Id).created, 'The first call issues a booklet');
        System.assertNotEquals(null, first.get(app.Id).passportId);
        System.assertNotEquals(null, first.get(app.Id).printJobId, 'A print job accompanies it');
        System.assertEquals(false, second.get(app.Id).created,
            'The second call must not issue a second booklet');
        System.assertEquals(first.get(app.Id).passportId, second.get(app.Id).passportId);
        System.assertEquals(1, [SELECT COUNT() FROM Passport__c WHERE Application__c = :app.Id],
            'Exactly one passport per application');
        System.assertEquals(1, [SELECT COUNT() FROM Print_Job__c WHERE Passport_Application__c = :app.Id],
            'Exactly one print job per application');
    }

    @IsTest
    static void testIssuedPassportSatisfiesValidationRules() {
        PSK_AutomationControl.reset();
        PSK_AutomationControl.bypassTriggers = true;
        Passport_Application__c app = PSK_TestDataFactory.createLinkedApplication(
            PSK_Constants.STATUS_GRANTING);
        PSK_AutomationControl.reset();

        PSK_ApplicationService.issuePassports(new Set<Id>{ app.Id });

        Passport__c passport = [
            SELECT Name, External_Id__c, Status__c, Date_of_Issue__c, Date_of_Expiry__c,
                   File_Number__c, RecordTypeId
            FROM Passport__c WHERE Application__c = :app.Id
        ];
        System.assertEquals(passport.Name, passport.External_Id__c,
            'External_Id_Must_Mirror_Number requires External_Id__c == Name');
        System.assertEquals(true, BOOKLET_FORMAT.matcher(passport.Name).matches(),
            'Passport_Number_Format requires ^[A-PR-WY][0-9]{7}$');
        System.assertEquals(PSK_Constants.PASSPORT_ACTIVE, passport.Status__c);
        System.assertNotEquals(null, passport.Date_of_Issue__c,
            'Active_Requires_Issue_And_Expiry_Dates needs an issue date');
        System.assertNotEquals(null, passport.Date_of_Expiry__c,
            'Active_Requires_Issue_And_Expiry_Dates needs an expiry date');
        System.assertEquals(Date.today().addYears(10), passport.Date_of_Expiry__c,
            'A 10-year booklet expires ten years out');
    }

    @IsTest
    static void testIssuePassportsWithEmptyInput() {
        System.assertEquals(0,
            PSK_ApplicationService.issuePassports(new Set<Id>()).size());
        System.assertEquals(0, PSK_ApplicationService.issuePassports(null).size());
    }

    @IsTest
    static void testIssuePassportsLinksPreviousBooklet() {
        PSK_AutomationControl.reset();
        PSK_AutomationControl.bypassTriggers = true;
        Citizen__c citizen = PSK_TestDataFactory.createCitizen();
        Passport__c older = PSK_TestDataFactory.createPassport(null, citizen.Id);

        Passport_Application__c app = PSK_TestDataFactory.buildApplication(
            PSK_Constants.STATUS_GRANTING, PSK_Constants.RT_RE_ISSUE);
        app.Citizen__c = citizen.Id;
        app.Previous_Passport_No__c = older.Name;
        insert app;
        PSK_AutomationControl.reset();

        PSK_ApplicationService.issuePassports(new Set<Id>{ app.Id });

        Passport__c issued = [
            SELECT Previous_Passport__c FROM Passport__c WHERE Application__c = :app.Id
        ];
        System.assertEquals(older.Id, issued.Previous_Passport__c,
            'The reissue chain should link back to the previous booklet number');
    }

    @IsTest
    static void testCreateDispatchesIsIdempotent() {
        PSK_AutomationControl.reset();
        PSK_AutomationControl.bypassTriggers = true;
        Passport_Application__c app = PSK_TestDataFactory.createLinkedApplication(
            PSK_Constants.STATUS_DISPATCH);
        PSK_AutomationControl.reset();

        Test.startTest();
        Integer firstRun = PSK_ApplicationService.createDispatches(new Set<Id>{ app.Id });
        Integer secondRun = PSK_ApplicationService.createDispatches(new Set<Id>{ app.Id });
        Test.stopTest();

        System.assertEquals(1, firstRun);
        System.assertEquals(0, secondRun, 'A second call must not create a duplicate dispatch');
        System.assertEquals(1, [SELECT COUNT() FROM Dispatch__c WHERE Passport_Application__c = :app.Id]);
        System.assertEquals(0, PSK_ApplicationService.createDispatches(new Set<Id>()));
        System.assertEquals(0, PSK_ApplicationService.createDispatches(null));
    }

    // ------------------------------------------------------- Checklist template

    @IsTest
    static void testChecklistTemplatePerRecordType() {
        System.assertEquals(4,
            PSK_ApplicationService.checklistTemplate(PSK_Constants.RT_MINOR).size());
        System.assertEquals(5,
            PSK_ApplicationService.checklistTemplate(PSK_Constants.RT_TATKAL).size());
        System.assertEquals(3,
            PSK_ApplicationService.checklistTemplate(PSK_Constants.RT_RE_ISSUE).size());
        System.assertEquals(4,
            PSK_ApplicationService.checklistTemplate(PSK_Constants.RT_LOST_DAMAGED).size());
        System.assertEquals(4,
            PSK_ApplicationService.checklistTemplate(PSK_Constants.RT_DIPLOMATIC_OFFICIAL).size());
        System.assertEquals(3,
            PSK_ApplicationService.checklistTemplate(PSK_Constants.RT_FRESH).size());
        System.assertEquals(3, PSK_ApplicationService.checklistTemplate(null).size(),
            'An unmapped record type falls back to the Fresh template');

        for (String docType : PSK_ApplicationService.checklistTemplate(PSK_Constants.RT_TATKAL)) {
            System.assertEquals(true,
                new Set<String>(PSK_Constants.DOCUMENT_TYPES).contains(docType),
                docType + ' must be a real Document_Type__c picklist value');
        }
    }

    // ------------------------------------------------------------------ Helpers

    private static Integer fakeIdCounter = 1;

    private static Id fakeId(Schema.SObjectType sot, Integer seed) {
        String suffix = String.valueOf(fakeIdCounter++ + seed);
        return Id.valueOf(sot.getDescribe().getKeyPrefix()
            + '0'.repeat(12 - suffix.length()) + suffix);
    }
}
