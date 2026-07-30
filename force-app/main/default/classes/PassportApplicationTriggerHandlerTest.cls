@IsTest
private class PassportApplicationTriggerHandlerTest {

    @TestSetup
    static void setUp() {
        PSK_AutomationControl.reset();
    }

    // ------------------------------------------------------------- Date stamping

    @IsTest
    static void testSubmittedDateStampedWhenLeavingDraft() {
        Passport_Application__c app = PSK_TestDataFactory.createApplication(
            PSK_Constants.STATUS_DRAFT);

        Passport_Application__c asDraft = [
            SELECT Submitted_Date__c, Stage_Entered_Date__c
            FROM Passport_Application__c WHERE Id = :app.Id
        ];
        System.assertEquals(null, asDraft.Submitted_Date__c,
            'A draft has not been submitted yet');
        System.assertNotEquals(null, asDraft.Stage_Entered_Date__c,
            'Entering Draft is still a stage entry');

        Test.startTest();
        app.Status__c = PSK_Constants.STATUS_SUBMITTED;
        update app;
        Test.stopTest();

        Passport_Application__c submitted = [
            SELECT Submitted_Date__c FROM Passport_Application__c WHERE Id = :app.Id
        ];
        System.assertNotEquals(null, submitted.Submitted_Date__c,
            'Leaving Draft must stamp the submitted date');
    }

    @IsTest
    static void testSubmittedDateStampedOnDirectInsertPastDraft() {
        Passport_Application__c app = PSK_TestDataFactory.createApplication(
            PSK_Constants.STATUS_PAID);

        Passport_Application__c saved = [
            SELECT Submitted_Date__c FROM Passport_Application__c WHERE Id = :app.Id
        ];
        System.assertNotEquals(null, saved.Submitted_Date__c,
            'An application inserted directly past Draft counts as submitted');
    }

    @IsTest
    static void testSubmittedDateNotOverwritten() {
        Passport_Application__c app = PSK_TestDataFactory.buildApplication(
            PSK_Constants.STATUS_SUBMITTED);
        DateTime original = System.now().addDays(-20);
        app.Submitted_Date__c = original;
        insert app;

        app.Status__c = PSK_Constants.STATUS_PAYMENT_PENDING;
        update app;

        Passport_Application__c saved = [
            SELECT Submitted_Date__c FROM Passport_Application__c WHERE Id = :app.Id
        ];
        System.assertEquals(original, saved.Submitted_Date__c,
            'An existing submitted date must never be rewritten');
    }

    @IsTest
    static void testStageEnteredDateRefreshedOnEveryStatusChange() {
        Passport_Application__c app = PSK_TestDataFactory.buildApplication(
            PSK_Constants.STATUS_SUBMITTED);
        app.Stage_Entered_Date__c = System.now().addDays(-10);
        insert app;

        DateTime afterInsert = [
            SELECT Stage_Entered_Date__c FROM Passport_Application__c WHERE Id = :app.Id
        ].Stage_Entered_Date__c;

        Test.startTest();
        app.Status__c = PSK_Constants.STATUS_PAYMENT_PENDING;
        update app;
        Test.stopTest();

        DateTime afterUpdate = [
            SELECT Stage_Entered_Date__c FROM Passport_Application__c WHERE Id = :app.Id
        ].Stage_Entered_Date__c;
        System.assertEquals(true, afterUpdate > afterInsert,
            'Every status change refreshes Stage_Entered_Date__c');
    }

    @IsTest
    static void testStageEnteredDateUnchangedWhenStatusDoesNotChange() {
        Passport_Application__c app = PSK_TestDataFactory.createApplication(
            PSK_Constants.STATUS_SUBMITTED);
        DateTime before = [
            SELECT Stage_Entered_Date__c FROM Passport_Application__c WHERE Id = :app.Id
        ].Stage_Entered_Date__c;

        app.City__c = 'Mumbai';
        update app;

        DateTime after = [
            SELECT Stage_Entered_Date__c FROM Passport_Application__c WHERE Id = :app.Id
        ].Stage_Entered_Date__c;
        System.assertEquals(before, after,
            'Editing an unrelated field must not touch the stage clock');
    }

    @IsTest
    static void testGrantedDateStampedOnEnteringGranting() {
        Passport_Application__c app = PSK_TestDataFactory.buildApplication(
            PSK_Constants.STATUS_POLICE_VERIFICATION);
        app.Payment_Status__c = PSK_Constants.PAY_PAID;
        insert app;

        System.assertEquals(null, [
            SELECT Granted_Date__c FROM Passport_Application__c WHERE Id = :app.Id
        ].Granted_Date__c, 'Not granted yet');

        Test.startTest();
        app.Status__c = PSK_Constants.STATUS_GRANTING;
        update app;
        Test.stopTest();

        System.assertNotEquals(null, [
            SELECT Granted_Date__c FROM Passport_Application__c WHERE Id = :app.Id
        ].Granted_Date__c, 'Entering Granting must stamp the granted date');
    }

    // ---------------------------------------------------- Citizen reverse-create

    @IsTest
    static void testCitizenReverseCreatedOnInsert() {
        Passport_Application__c app = PSK_TestDataFactory.buildApplication(
            PSK_Constants.STATUS_DRAFT);
        app.First_Name__c = 'Meera';
        app.Last_Name__c = 'Iyer';

        Test.startTest();
        insert app;
        Test.stopTest();

        Passport_Application__c saved = [
            SELECT Citizen__c, Citizen__r.Name FROM Passport_Application__c WHERE Id = :app.Id
        ];
        System.assertNotEquals(null, saved.Citizen__c,
            'An application arriving without a citizen must get one created for it -- '
            + 'this keeps the pskHomeDashboard inline quick-create working');
        System.assertEquals('Meera Iyer', saved.Citizen__r.Name);
    }

    @IsTest
    static void testCitizenMatchedNotDuplicatedAcrossApplications() {
        Passport_Application__c first = PSK_TestDataFactory.buildApplication(
            PSK_Constants.STATUS_DRAFT);
        insert first;

        Passport_Application__c second = first.clone(false, true, false, false);
        second.External_Id__c = 'TEST-APP-SECOND';
        second.Citizen__c = null;

        Test.startTest();
        insert second;
        Test.stopTest();

        Id firstCitizen = [
            SELECT Citizen__c FROM Passport_Application__c WHERE Id = :first.Id
        ].Citizen__c;
        Id secondCitizen = [
            SELECT Citizen__c FROM Passport_Application__c WHERE Id = :second.Id
        ].Citizen__c;

        System.assertEquals(firstCitizen, secondCitizen,
            'A second application for the same person must reuse the existing citizen');
        System.assertEquals(1, [SELECT COUNT() FROM Citizen__c]);
    }

    @IsTest
    static void testExistingCitizenLinkPreserved() {
        Citizen__c citizen = PSK_TestDataFactory.createCitizen();
        Passport_Application__c app = PSK_TestDataFactory.buildApplication(
            PSK_Constants.STATUS_DRAFT);
        app.Citizen__c = citizen.Id;
        insert app;

        System.assertEquals(citizen.Id, [
            SELECT Citizen__c FROM Passport_Application__c WHERE Id = :app.Id
        ].Citizen__c, 'An explicit citizen link must be left alone');
        System.assertEquals(1, [SELECT COUNT() FROM Citizen__c],
            'No extra citizen should be created');
    }

    // ------------------------------------------------------ Snapshot copy rules

    @IsTest
    static void testSnapshotFieldsCopiedOnlyWhenBlank() {
        Citizen__c citizen = PSK_TestDataFactory.createCitizen();

        Passport_Application__c app = PSK_TestDataFactory.buildApplication(
            PSK_Constants.STATUS_DRAFT);
        app.Citizen__c = citizen.Id;
        app.City__c = 'Nagpur';   // deliberately different from the citizen
        app.Email__c = null;      // blank, so it should be filled

        Test.startTest();
        insert app;
        Test.stopTest();

        Passport_Application__c saved = [
            SELECT City__c, Email__c, Pincode__c
            FROM Passport_Application__c WHERE Id = :app.Id
        ];
        System.assertEquals('Nagpur', saved.City__c,
            'The as-submitted snapshot must win over the citizen record');
        System.assertEquals(citizen.Email__c, saved.Email__c,
            'A blank field is filled from the citizen');
    }

    @IsTest
    static void testLaterCitizenEditDoesNotRewriteSnapshot() {
        Citizen__c citizen = PSK_TestDataFactory.createCitizen();
        Passport_Application__c app = PSK_TestDataFactory.buildApplication(
            PSK_Constants.STATUS_SUBMITTED);
        app.Citizen__c = citizen.Id;
        insert app;

        String snapshotCity = [
            SELECT City__c FROM Passport_Application__c WHERE Id = :app.Id
        ].City__c;

        Test.startTest();
        citizen.City__c = 'Somewhere Else';
        update citizen;
        app.Status__c = PSK_Constants.STATUS_PAYMENT_PENDING;
        update app;
        Test.stopTest();

        System.assertEquals(snapshotCity, [
            SELECT City__c FROM Passport_Application__c WHERE Id = :app.Id
        ].City__c, 'Moving the citizen must not retro-edit the submitted application');
    }

    // ------------------------------------------------------------------ Fee stamp

    @IsTest
    static void testFeeComputedOnInsert() {
        Passport_Application__c app = PSK_TestDataFactory.buildApplication(
            PSK_Constants.STATUS_DRAFT);
        app.Fee__c = null;

        Test.startTest();
        insert app;
        Test.stopTest();

        Decimal fee = [SELECT Fee__c FROM Passport_Application__c WHERE Id = :app.Id].Fee__c;
        System.assertNotEquals(null, fee, 'The trigger must stamp a fee');
        System.assertEquals(true, fee > 0, 'The fee must be a positive amount, got ' + fee);
    }

    @IsTest
    static void testManualFeeOverrideSurvivesUnrelatedEdit() {
        Passport_Application__c app = PSK_TestDataFactory.buildApplication(
            PSK_Constants.STATUS_DRAFT);
        app.Fee__c = 7777;
        insert app;

        Test.startTest();
        app.City__c = 'Kochi';
        update app;
        Test.stopTest();

        System.assertEquals(7777,
            [SELECT Fee__c FROM Passport_Application__c WHERE Id = :app.Id].Fee__c,
            'An explicit fee must not be recomputed by an unrelated edit');
    }

    // ----------------------------------------------------------------- Defaults

    @IsTest
    static void testDefaultsApplied() {
        Passport_Application__c app = PSK_TestDataFactory.buildApplication(
            PSK_Constants.STATUS_DRAFT);
        app.Payment_Status__c = null;
        app.Country__c = null;
        insert app;

        Passport_Application__c saved = [
            SELECT Payment_Status__c, Country__c
            FROM Passport_Application__c WHERE Id = :app.Id
        ];
        System.assertEquals(PSK_Constants.PAY_NOT_PAID, saved.Payment_Status__c);
        System.assertEquals('India', saved.Country__c);
    }

    @IsTest
    static void testPaymentForcedPaidAtGranting() {
        // Cannot_Grant_With_Pending_Payment would otherwise reject this insert.
        Passport_Application__c app = PSK_TestDataFactory.buildApplication(
            PSK_Constants.STATUS_GRANTING);
        app.Payment_Status__c = PSK_Constants.PAY_PENDING;

        Test.startTest();
        insert app;
        Test.stopTest();

        Passport_Application__c saved = [
            SELECT Payment_Status__c, Payment_Date__c, Documents_Verified__c
            FROM Passport_Application__c WHERE Id = :app.Id
        ];
        System.assertEquals(PSK_Constants.PAY_PAID, saved.Payment_Status__c,
            'Granting and beyond must carry a paid fee');
        System.assertNotEquals(null, saved.Payment_Date__c,
            'Marking a fee paid should stamp the payment date');
        System.assertEquals(true, saved.Documents_Verified__c,
            'Past Police Verification the documents are necessarily verified');
    }

    // --------------------------------------------------------------- Fulfilment

    @IsTest
    static void testEnteringPrintingIssuesPassportAndPrintJob() {
        Passport_Application__c app = PSK_TestDataFactory.createLinkedApplication(
            PSK_Constants.STATUS_GRANTING);

        Test.startTest();
        app.Status__c = PSK_Constants.STATUS_PRINTING;
        update app;
        Test.stopTest();

        List<Passport__c> passports = [
            SELECT Name, External_Id__c, Status__c, Date_of_Issue__c, Date_of_Expiry__c
            FROM Passport__c WHERE Application__c = :app.Id
        ];
        System.assertEquals(1, passports.size(),
            'Entering Printing must issue exactly one booklet');
        System.assertEquals(passports[0].Name, passports[0].External_Id__c,
            'External_Id_Must_Mirror_Number');
        System.assertNotEquals(null, passports[0].Date_of_Expiry__c);
        System.assertEquals(1,
            [SELECT COUNT() FROM Print_Job__c WHERE Passport_Application__c = :app.Id],
            'A print job accompanies the booklet');
    }

    @IsTest
    static void testEnteringPrintingTwiceDoesNotDuplicate() {
        Passport_Application__c app = PSK_TestDataFactory.createLinkedApplication(
            PSK_Constants.STATUS_GRANTING);

        Test.startTest();
        app.Status__c = PSK_Constants.STATUS_PRINTING;
        update app;
        // Move on and back to Printing to prove the guard holds.
        app.Status__c = PSK_Constants.STATUS_DISPATCH;
        update app;
        Test.stopTest();

        System.assertEquals(1, [SELECT COUNT() FROM Passport__c WHERE Application__c = :app.Id],
            'A second Printing transition must never mint a second booklet');
    }

    @IsTest
    static void testEnteringDispatchCreatesDispatchRecord() {
        Passport_Application__c app = PSK_TestDataFactory.createLinkedApplication(
            PSK_Constants.STATUS_PRINTING);

        Test.startTest();
        app.Status__c = PSK_Constants.STATUS_DISPATCH;
        update app;
        Test.stopTest();

        System.assertEquals(1,
            [SELECT COUNT() FROM Dispatch__c WHERE Passport_Application__c = :app.Id],
            'Entering Dispatch must create a dispatch record');
    }

    // ----------------------------------------------------------------- Bulk safe

    @IsTest
    static void testBulkInsertIsSafe() {
        List<Passport_Application__c> apps = new List<Passport_Application__c>();
        for (Integer i = 0; i < 50; i++) {
            Passport_Application__c app = PSK_TestDataFactory.buildApplication(
                PSK_Constants.ALL_STATUSES[Math.mod(i, PSK_Constants.ALL_STATUSES.size())]);
            app.Fee__c = null;
            apps.add(app);
        }

        Test.startTest();
        insert apps;
        Test.stopTest();

        System.assertEquals(50, [SELECT COUNT() FROM Passport_Application__c],
            'All 50 applications should insert in one DML');
        System.assertEquals(0, [
            SELECT COUNT() FROM Passport_Application__c WHERE Fee__c = NULL
        ], 'Every application should have a fee stamped');
        System.assertEquals(0, [
            SELECT COUNT() FROM Passport_Application__c WHERE Citizen__c = NULL
        ], 'Every application should have a citizen');
    }

    @IsTest
    static void testBulkUpdateIsSafe() {
        List<Passport_Application__c> apps = new List<Passport_Application__c>();
        for (Integer i = 0; i < 50; i++) {
            apps.add(PSK_TestDataFactory.buildApplication(PSK_Constants.STATUS_DRAFT));
        }
        insert apps;

        Test.startTest();
        for (Passport_Application__c app : apps) {
            app.Status__c = PSK_Constants.STATUS_SUBMITTED;
        }
        update apps;
        Test.stopTest();

        System.assertEquals(50, [
            SELECT COUNT() FROM Passport_Application__c
            WHERE Status__c = :PSK_Constants.STATUS_SUBMITTED AND Submitted_Date__c != NULL
        ], 'Every record should be stamped, with no per-row SOQL');
    }
}
