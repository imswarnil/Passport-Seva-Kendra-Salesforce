@IsTest
private class PSK_PassportControllerTest {

    @IsTest
    static void testGetPassportBasics() {
        PSK_AutomationControl.reset();
        PSK_AutomationControl.bypassTriggers = true;
        PSK__c office = PSK_TestDataFactory.createOffice();
        Citizen__c citizen = PSK_TestDataFactory.createCitizen();
        Passport_Application__c app = PSK_TestDataFactory.buildApplication(
            PSK_Constants.STATUS_DELIVERED);
        app.Citizen__c = citizen.Id;
        app.PSK_Office__c = office.Id;
        insert app;

        Passport__c passport = PSK_TestDataFactory.buildPassport(
            app.Id, citizen.Id, PSK_Constants.PASSPORT_ACTIVE);
        passport.PSK_Office__c = office.Id;
        insert passport;
        PSK_AutomationControl.reset();

        Test.startTest();
        PSK_PassportController.PassportDetail detail =
            PSK_PassportController.getPassport(passport.Id);
        Test.stopTest();

        System.assertEquals(passport.Id, detail.id);
        System.assertEquals(passport.Name, detail.passportNumber);
        System.assertEquals(PSK_Constants.PASSPORT_ACTIVE, detail.status);
        System.assertEquals(app.Id, detail.applicationId);
        System.assertEquals(citizen.Id, detail.citizenId);
        System.assertEquals(office.Id, detail.officeId);
        System.assertEquals(office.Name, detail.officeName);
        System.assertEquals(1, detail.chainLength, 'A single booklet is a chain of one');
        System.assertEquals(true, detail.reissueChain[0].isCurrent);
    }

    @IsTest
    static void testExpiryCountdownForAHealthyBooklet() {
        Citizen__c citizen = PSK_TestDataFactory.createCitizen();
        Passport__c passport = PSK_TestDataFactory.createPassport(null, citizen.Id);

        Test.startTest();
        PSK_PassportController.PassportDetail detail =
            PSK_PassportController.getPassport(passport.Id);
        Test.stopTest();

        System.assertEquals(false, detail.isExpired);
        System.assertEquals(false, detail.isExpiringSoon,
            'A booklet issued 30 days ago on a ten-year validity is nowhere near expiry');
        System.assertEquals('success', detail.expiryVariant);
        System.assertEquals(true, detail.daysToExpiry > 3000,
            'Expected a long runway but got ' + detail.daysToExpiry);
    }

    @IsTest
    static void testExpiryCountdownForAnExpiredBooklet() {
        Citizen__c citizen = PSK_TestDataFactory.createCitizen();
        Passport__c passport = PSK_TestDataFactory.buildPassport(
            null, citizen.Id, PSK_Constants.PASSPORT_EXPIRED);
        passport.Date_of_Issue__c = Date.today().addYears(-11);
        passport.Date_of_Expiry__c = Date.today().addDays(-30);
        insert passport;

        Test.startTest();
        PSK_PassportController.PassportDetail detail =
            PSK_PassportController.getPassport(passport.Id);
        Test.stopTest();

        System.assertEquals(true, detail.isExpired);
        System.assertEquals(-30, detail.daysToExpiry);
        System.assertEquals('error', detail.expiryVariant);
        System.assertEquals(true, detail.expiryLabel.contains('Expired'), detail.expiryLabel);
    }

    @IsTest
    static void testExpiryCountdownInsideTheRenewalWindow() {
        Citizen__c citizen = PSK_TestDataFactory.createCitizen();
        Passport__c passport = PSK_TestDataFactory.buildPassport(
            null, citizen.Id, PSK_Constants.PASSPORT_ACTIVE);
        passport.Date_of_Issue__c = Date.today().addYears(-9);
        passport.Date_of_Expiry__c = Date.today().addDays(90);
        insert passport;

        Test.startTest();
        PSK_PassportController.PassportDetail detail =
            PSK_PassportController.getPassport(passport.Id);
        Test.stopTest();

        System.assertEquals(90, detail.daysToExpiry);
        System.assertEquals('warning', detail.expiryVariant,
            'Inside a year of expiry the renewal window is open');
        System.assertEquals(true, detail.isExpiringSoon);
    }

    @IsTest
    static void testExpiryCountdownWithNoExpiryDate() {
        Citizen__c citizen = PSK_TestDataFactory.createCitizen();
        Passport__c passport = PSK_TestDataFactory.buildPassport(
            null, citizen.Id, PSK_Constants.PASSPORT_SURRENDERED);
        passport.Date_of_Expiry__c = null;
        passport.Cancellation_Reason__c = 'Surrendered';
        insert passport;

        Test.startTest();
        PSK_PassportController.PassportDetail detail =
            PSK_PassportController.getPassport(passport.Id);
        Test.stopTest();

        System.assertEquals(null, detail.daysToExpiry);
        System.assertEquals('inverse', detail.expiryVariant);
        System.assertEquals(true, detail.expiryLabel.contains('No expiry date'),
            detail.expiryLabel);
    }

    @IsTest
    static void testReissueChainWalksBothDirections() {
        Citizen__c citizen = PSK_TestDataFactory.createCitizen();

        Passport__c oldest = PSK_TestDataFactory.buildPassport(
            null, citizen.Id, PSK_Constants.PASSPORT_REISSUED);
        oldest.Date_of_Issue__c = Date.today().addYears(-25);
        oldest.Date_of_Expiry__c = Date.today().addYears(-15);
        oldest.Cancellation_Reason__c = 'Reissued';
        insert oldest;

        Passport__c middle = PSK_TestDataFactory.buildPassport(
            null, citizen.Id, PSK_Constants.PASSPORT_REISSUED);
        middle.Date_of_Issue__c = Date.today().addYears(-15);
        middle.Date_of_Expiry__c = Date.today().addYears(-5);
        middle.Cancellation_Reason__c = 'Reissued';
        middle.Previous_Passport__c = oldest.Id;
        insert middle;

        Passport__c current = PSK_TestDataFactory.buildPassport(
            null, citizen.Id, PSK_Constants.PASSPORT_ACTIVE);
        current.Date_of_Issue__c = Date.today().addYears(-5);
        current.Date_of_Expiry__c = Date.today().addYears(5);
        current.Previous_Passport__c = middle.Id;
        insert current;

        Test.startTest();
        // Query from the MIDDLE booklet: the walk must find the older one behind it
        // and the newer one in front of it.
        PSK_PassportController.PassportDetail detail =
            PSK_PassportController.getPassport(middle.Id);
        Test.stopTest();

        System.assertEquals(3, detail.chainLength,
            'The whole chain should be visible from any booklet in it');
        System.assertEquals(oldest.Id, detail.reissueChain[0].id, 'Oldest booklet first');
        System.assertEquals(middle.Id, detail.reissueChain[1].id);
        System.assertEquals(current.Id, detail.reissueChain[2].id);
        System.assertEquals(1, detail.reissueChain[0].generation);
        System.assertEquals(3, detail.reissueChain[2].generation);
        System.assertEquals(true, detail.reissueChain[1].isCurrent,
            'The booklet we asked about is flagged as current');
        System.assertEquals(false, detail.reissueChain[0].isCurrent);
    }

    @IsTest
    static void testGetPassportWithBadIdThrows() {
        Integer thrown = 0;
        try {
            PSK_PassportController.getPassport(null);
        } catch (AuraHandledException e) {
            thrown++;
        }

        Citizen__c citizen = PSK_TestDataFactory.createCitizen();
        Passport__c passport = PSK_TestDataFactory.createPassport(null, citizen.Id);
        Id deletedId = passport.Id;
        delete passport;
        try {
            PSK_PassportController.getPassport(deletedId);
        } catch (AuraHandledException e) {
            thrown++;
        }
        System.assertEquals(2, thrown, 'Both a null and a missing passport must be reported');
    }

    @IsTest
    static void testGetExpiringPassports() {
        Citizen__c citizen = PSK_TestDataFactory.createCitizen();

        Passport__c soon = PSK_TestDataFactory.buildPassport(
            null, citizen.Id, PSK_Constants.PASSPORT_ACTIVE);
        soon.Date_of_Issue__c = Date.today().addYears(-9);
        soon.Date_of_Expiry__c = Date.today().addDays(100);
        insert soon;

        Passport__c later = PSK_TestDataFactory.buildPassport(
            null, citizen.Id, PSK_Constants.PASSPORT_ACTIVE);
        later.Date_of_Issue__c = Date.today();
        later.Date_of_Expiry__c = Date.today().addYears(9);
        insert later;

        Test.startTest();
        List<PSK_PassportController.ChainLink> expiring =
            PSK_PassportController.getExpiringPassports(365);
        List<PSK_PassportController.ChainLink> defaulted =
            PSK_PassportController.getExpiringPassports(null);
        Test.stopTest();

        System.assertEquals(1, expiring.size(),
            'Only the booklet expiring inside a year should appear');
        System.assertEquals(soon.Id, expiring[0].id);
        System.assertEquals(100, expiring[0].generation,
            'For this list, generation carries the days remaining');
        System.assertEquals(1, defaulted.size(), 'A null horizon defaults to 365 days');
    }
}
