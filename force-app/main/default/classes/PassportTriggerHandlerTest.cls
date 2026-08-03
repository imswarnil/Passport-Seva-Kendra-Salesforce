@IsTest
private class PassportTriggerHandlerTest {

    private static final Pattern BOOKLET_FORMAT = Pattern.compile('^[A-PR-WY][0-9]{7}$');

    @IsTest
    static void testExternalIdMirroredOnInsertWhenLeftBlank() {
        // The External_Id_Must_Mirror_Number validation rule fails on a BLANK
        // External_Id__c as well as a mismatched one, so a hand-created passport
        // would be rejected without this trigger.
        Citizen__c citizen = PSK_TestDataFactory.createCitizen();
        Passport__c passport = PSK_TestDataFactory.buildPassport(
            null, citizen.Id, PSK_Constants.PASSPORT_ACTIVE);
        String bookletNo = passport.Name;
        passport.External_Id__c = null;

        Test.startTest();
        insert passport;
        Test.stopTest();

        System.assertEquals(bookletNo,
            [SELECT External_Id__c FROM Passport__c WHERE Id = :passport.Id].External_Id__c,
            'The trigger must mirror Name into External_Id__c');
    }

    @IsTest
    static void testExternalIdCorrectedWhenMismatched() {
        Citizen__c citizen = PSK_TestDataFactory.createCitizen();
        Passport__c passport = PSK_TestDataFactory.buildPassport(
            null, citizen.Id, PSK_Constants.PASSPORT_ACTIVE);
        passport.External_Id__c = 'SOMETHING-ELSE';

        Test.startTest();
        insert passport;
        Test.stopTest();

        System.assertEquals(passport.Name,
            [SELECT External_Id__c FROM Passport__c WHERE Id = :passport.Id].External_Id__c,
            'A mismatched external id must be corrected, not rejected');
    }

    @IsTest
    static void testExternalIdFollowsARenumber() {
        Citizen__c citizen = PSK_TestDataFactory.createCitizen();
        Passport__c passport = PSK_TestDataFactory.createPassport(null, citizen.Id);

        String renumbered = PSK_ApplicationService.generateBookletNumber('RENUMBERED-SEED');
        System.assertNotEquals(passport.Name, renumbered, 'Precondition: a different bookletNo');

        Test.startTest();
        passport.Name = renumbered;
        update passport;
        Test.stopTest();

        System.assertEquals(renumbered,
            [SELECT External_Id__c FROM Passport__c WHERE Id = :passport.Id].External_Id__c,
            'Changing the booklet bookletNo must carry the external id with it');
    }

    @IsTest
    static void testActivePassportGetsDefaultDates() {
        Citizen__c citizen = PSK_TestDataFactory.createCitizen();
        Passport__c passport = PSK_TestDataFactory.buildPassport(
            null, citizen.Id, PSK_Constants.PASSPORT_ACTIVE);
        passport.Date_of_Issue__c = null;
        passport.Date_of_Expiry__c = null;

        Test.startTest();
        insert passport;
        Test.stopTest();

        Passport__c saved = [
            SELECT Date_of_Issue__c, Date_of_Expiry__c FROM Passport__c WHERE Id = :passport.Id
        ];
        System.assertEquals(Date.today(), saved.Date_of_Issue__c,
            'Active_Requires_Issue_And_Expiry_Dates needs an issue date');
        System.assertEquals(Date.today().addYears(10), saved.Date_of_Expiry__c,
            'A standard adult booklet runs ten years');
    }

    @IsTest
    static void testNonActivePassportKeepsBlankDates() {
        Citizen__c citizen = PSK_TestDataFactory.createCitizen();
        Passport__c passport = PSK_TestDataFactory.buildPassport(
            null, citizen.Id, PSK_Constants.PASSPORT_CANCELLED);
        passport.Date_of_Expiry__c = null;
        passport.Cancellation_Reason__c = 'Revoked';

        Test.startTest();
        insert passport;
        Test.stopTest();

        System.assertEquals(null,
            [SELECT Date_of_Expiry__c FROM Passport__c WHERE Id = :passport.Id].Date_of_Expiry__c,
            'Only Active booklets need the dates back-filled');
    }

    @IsTest
    static void testMirrorStillRunsUnderBypass() {
        // The mirror is a data-integrity invariant, not business automation, so it
        // must hold even when the demo generator disables the rest of the triggers.
        Citizen__c citizen = PSK_TestDataFactory.createCitizen();
        Passport__c passport = PSK_TestDataFactory.buildPassport(
            null, citizen.Id, PSK_Constants.PASSPORT_ACTIVE);
        passport.External_Id__c = null;

        PSK_AutomationControl.reset();
        PSK_AutomationControl.bypassTriggers = true;
        Test.startTest();
        insert passport;
        Test.stopTest();
        PSK_AutomationControl.reset();

        System.assertEquals(passport.Name,
            [SELECT External_Id__c FROM Passport__c WHERE Id = :passport.Id].External_Id__c,
            'The External_Id__c mirror must never be bypassed');
    }

    @IsTest
    static void testBulkInsertMirrors() {
        Citizen__c citizen = PSK_TestDataFactory.createCitizen();
        List<Passport__c> passports = new List<Passport__c>();
        for (Integer i = 0; i < 30; i++) {
            Passport__c p = PSK_TestDataFactory.buildPassport(
                null, citizen.Id, PSK_Constants.PASSPORT_ACTIVE);
            p.External_Id__c = null;
            passports.add(p);
        }

        Test.startTest();
        insert passports;
        Test.stopTest();

        for (Passport__c p : [
            SELECT Name, External_Id__c FROM Passport__c WHERE Id IN :passports
        ]) {
            System.assertEquals(p.Name, p.External_Id__c,
                'Every row in a bulk insert must be mirrored');
            System.assertEquals(true, BOOKLET_FORMAT.matcher(p.Name).matches(),
                p.Name + ' must satisfy Passport_Number_Format');
        }
    }
}
