@IsTest
private class PSK_Citizen360ControllerTest {

    @IsTest
    static void testGetProfileAssemblesEverything() {
        PSK_AutomationControl.reset();
        PSK_AutomationControl.bypassTriggers = true;

        PSK__c office = PSK_TestDataFactory.createOffice();
        Citizen__c citizen = PSK_TestDataFactory.createCitizen();

        Passport_Application__c app = PSK_TestDataFactory.buildApplication(
            PSK_Constants.STATUS_DELIVERED, PSK_Constants.RT_FRESH);
        app.Citizen__c = citizen.Id;
        app.PSK_Office__c = office.Id;
        insert app;

        Passport__c passport = PSK_TestDataFactory.createPassport(app.Id, citizen.Id);
        insert PSK_TestDataFactory.buildFamilyMember(citizen.Id, 'Father');
        insert PSK_TestDataFactory.buildRiskFlag(app.Id, 'Open');
        insert PSK_TestDataFactory.buildRiskFlag(app.Id, 'Dismissed');

        PSK_AutomationControl.reset();

        Test.startTest();
        PSK_Citizen360Controller.CitizenProfile profile =
            PSK_Citizen360Controller.getProfile(citizen.Id);
        Test.stopTest();

        System.assertEquals(citizen.Id, profile.id);
        System.assertEquals(citizen.Name, profile.name);
        System.assertEquals(1, profile.totalApplications);
        System.assertNotEquals(null, profile.applications[0].recordTypeName,
            'The record type label should be resolved for the UI');
        System.assertEquals(PSK_Constants.STATUS_DELIVERED, profile.applications[0].status);
        System.assertEquals(1, profile.passports.size());
        System.assertEquals(passport.Name, profile.passports[0].passportNumber);
        System.assertEquals(1, profile.activePassports);
        System.assertEquals(1, profile.familyMembers.size());
        System.assertEquals('Father', profile.familyMembers[0].relationship);
        System.assertEquals(1, profile.openRiskFlagCount,
            'Only Open and Under Review flags count as open; the dismissed one is excluded');

        System.assertNotEquals(null, profile.kyc);
        System.assertEquals('Verified', profile.kyc.kycStatus);
        System.assertEquals(true, profile.kyc.aadhaarVerified);
        System.assertEquals(false, profile.kyc.isBlacklisted);
        System.assertEquals('Marathi', profile.kyc.preferredLanguage);
    }

    @IsTest
    static void testGetProfileForACitizenWithNothingAttached() {
        Citizen__c citizen = PSK_TestDataFactory.createCitizen();

        Test.startTest();
        PSK_Citizen360Controller.CitizenProfile profile =
            PSK_Citizen360Controller.getProfile(citizen.Id);
        Test.stopTest();

        System.assertEquals(0, profile.totalApplications);
        System.assertEquals(0, profile.passports.size());
        System.assertEquals(0, profile.familyMembers.size());
        System.assertEquals(0, profile.openRiskFlagCount);
        System.assertEquals(0, profile.activePassports,
            'Empty collections, never nulls -- the LWC iterates them directly');
    }

    @IsTest
    static void testGetProfileWithNullIdThrows() {
        Boolean threw = false;
        try {
            PSK_Citizen360Controller.getProfile(null);
        } catch (AuraHandledException e) {
            threw = true;
        }
        System.assertEquals(true, threw);
    }

    @IsTest
    static void testGetProfileForMissingCitizenThrows() {
        Citizen__c citizen = PSK_TestDataFactory.createCitizen();
        Id deletedId = citizen.Id;
        delete citizen;

        Boolean threw = false;
        try {
            PSK_Citizen360Controller.getProfile(deletedId);
        } catch (AuraHandledException e) {
            threw = true;
        }
        System.assertEquals(true, threw);
    }

    @IsTest
    static void testMinorFlagAndAgeSurface() {
        Citizen__c minor = PSK_TestDataFactory.createCitizen(true);

        Test.startTest();
        PSK_Citizen360Controller.CitizenProfile profile =
            PSK_Citizen360Controller.getProfile(minor.Id);
        Test.stopTest();

        System.assertEquals(true, profile.isMinor, 'A ten-year-old is a minor');
        // Age__c is FLOOR((TODAY() - DOB) / 365.25), so a date exactly ten calendar
        // years back can floor to 9 depending on the leap days in between.
        System.assertEquals(true, profile.age >= 9 && profile.age <= 10,
            'Expected an age of 9 or 10 but got ' + profile.age);
    }

    @IsTest
    static void testSearch() {
        Citizen__c citizen = PSK_TestDataFactory.createCitizen();

        Test.startTest();
        List<PSK_Citizen360Controller.CitizenProfile> byName =
            PSK_Citizen360Controller.search('Test Citizen');
        List<PSK_Citizen360Controller.CitizenProfile> byMobile =
            PSK_Citizen360Controller.search(citizen.Mobile__c);
        Test.stopTest();

        System.assertEquals(true, byName.size() >= 1, 'Name search should match');
        System.assertEquals(1, byMobile.size(), 'Mobile search should match exactly one');
        System.assertEquals(citizen.Id, byMobile[0].id);
        System.assertNotEquals(null, byMobile[0].kyc, 'Search results carry a KYC summary');
    }

    @IsTest
    static void testSearchIgnoresShortTerms() {
        PSK_TestDataFactory.createCitizen();
        System.assertEquals(0, PSK_Citizen360Controller.search('a').size(),
            'A single character is too broad to search on');
        System.assertEquals(0, PSK_Citizen360Controller.search('').size());
        System.assertEquals(0, PSK_Citizen360Controller.search(null).size());
    }
}
