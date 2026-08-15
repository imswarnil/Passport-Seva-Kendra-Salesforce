@IsTest
private class PSK_PassportIssuanceControllerTest {

    private static Passport_Application__c grantedApplication() {
        PSK_AutomationControl.reset();
        PSK_AutomationControl.bypassTriggers = true;
        Passport_Application__c app = PSK_TestDataFactory.createLinkedApplication(
            PSK_Constants.STATUS_GRANTING);
        PSK_AutomationControl.reset();
        return app;
    }

    @IsTest
    static void testIssueCreatesPassportAndPrintJob() {
        Passport_Application__c app = grantedApplication();

        Test.startTest();
        PSK_ApplicationService.IssuanceResult result =
            PSK_PassportIssuanceController.issue(app.Id);
        Test.stopTest();

        System.assertEquals(true, result.created);
        System.assertNotEquals(null, result.passportId);
        System.assertNotEquals(null, result.printJobId);
        System.assertNotEquals(null, result.passportNumber);
        System.assertEquals(Date.today(), result.dateOfIssue);
        System.assertEquals(1, [SELECT COUNT() FROM Passport__c WHERE Application__c = :app.Id]);
    }

    @IsTest
    static void testIssueTwiceReturnsTheExistingBooklet() {
        Passport_Application__c app = grantedApplication();

        Test.startTest();
        PSK_ApplicationService.IssuanceResult first =
            PSK_PassportIssuanceController.issue(app.Id);
        PSK_ApplicationService.IssuanceResult second =
            PSK_PassportIssuanceController.issue(app.Id);
        Test.stopTest();

        System.assertEquals(false, second.created,
            'The second press of the button must not mint a second booklet');
        System.assertEquals(first.passportId, second.passportId);
        System.assertEquals(1, [SELECT COUNT() FROM Passport__c WHERE Application__c = :app.Id]);
    }

    @IsTest
    static void testIssueBlockedBeforeGranting() {
        PSK_AutomationControl.reset();
        PSK_AutomationControl.bypassTriggers = true;
        Passport_Application__c app = PSK_TestDataFactory.buildApplication(
            PSK_Constants.STATUS_DOC_VERIFICATION);
        app.Payment_Status__c = PSK_Constants.PAY_PAID;
        app.Citizen__c = PSK_TestDataFactory.createCitizen().Id;
        insert app;
        PSK_AutomationControl.reset();

        Boolean threw = false;
        String message = '';
        try {
            PSK_PassportIssuanceController.issue(app.Id);
        } catch (AuraHandledException e) {
            threw = true;
            message = e.getMessage();
        }
        System.assertEquals(true, threw, 'Issuance before Granting must be refused');
        System.assertEquals(0, [SELECT COUNT() FROM Passport__c WHERE Application__c = :app.Id]);
    }

    @IsTest
    static void testIssueBlockedWithUnpaidFee() {
        PSK_AutomationControl.reset();
        PSK_AutomationControl.bypassTriggers = true;
        Passport_Application__c app = PSK_TestDataFactory.buildApplication(
            PSK_Constants.STATUS_POLICE_VERIFICATION);
        app.Payment_Status__c = PSK_Constants.PAY_PENDING;
        app.Citizen__c = PSK_TestDataFactory.createCitizen().Id;
        insert app;
        PSK_AutomationControl.reset();

        Boolean threw = false;
        try {
            PSK_PassportIssuanceController.issue(app.Id);
        } catch (AuraHandledException e) {
            threw = true;
        }
        System.assertEquals(true, threw, 'An unpaid fee must block issuance');
    }

    @IsTest
    static void testIssueBlockedOnRejectedApplication() {
        PSK_AutomationControl.reset();
        PSK_AutomationControl.bypassTriggers = true;
        Passport_Application__c app = PSK_TestDataFactory.buildApplication(
            PSK_Constants.STATUS_REJECTED);
        app.Payment_Status__c = PSK_Constants.PAY_PAID;
        app.Citizen__c = PSK_TestDataFactory.createCitizen().Id;
        insert app;
        PSK_AutomationControl.reset();

        Boolean threw = false;
        try {
            PSK_PassportIssuanceController.issue(app.Id);
        } catch (AuraHandledException e) {
            threw = true;
        }
        System.assertEquals(true, threw, 'A rejected application never gets a booklet');
    }

    @IsTest
    static void testIssueWithNullIdThrows() {
        Boolean threw = false;
        try {
            PSK_PassportIssuanceController.issue(null);
        } catch (AuraHandledException e) {
            threw = true;
        }
        System.assertEquals(true, threw);
    }

    @IsTest
    static void testCheckEligibility() {
        Passport_Application__c ready = grantedApplication();

        PSK_PassportIssuanceController.IssuanceEligibility eligible =
            PSK_PassportIssuanceController.checkEligibility(ready.Id);
        System.assertEquals(true, eligible.eligible, eligible.reason);
        System.assertEquals(false, eligible.alreadyIssued);

        PSK_PassportIssuanceController.issue(ready.Id);
        PSK_PassportIssuanceController.IssuanceEligibility afterIssue =
            PSK_PassportIssuanceController.checkEligibility(ready.Id);
        System.assertEquals(false, afterIssue.eligible);
        System.assertEquals(true, afterIssue.alreadyIssued,
            'Once issued, the button should report the booklet already exists');
    }

    @IsTest
    static void testCheckEligibilityEdgeCases() {
        PSK_PassportIssuanceController.IssuanceEligibility noId =
            PSK_PassportIssuanceController.checkEligibility(null);
        System.assertEquals(false, noId.eligible);
        System.assertNotEquals(null, noId.reason);

        PSK_AutomationControl.reset();
        PSK_AutomationControl.bypassTriggers = true;
        Passport_Application__c unpaid = PSK_TestDataFactory.buildApplication(
            PSK_Constants.STATUS_SUBMITTED);
        unpaid.Payment_Status__c = PSK_Constants.PAY_PENDING;
        unpaid.Citizen__c = PSK_TestDataFactory.createCitizen().Id;
        insert unpaid;
        PSK_AutomationControl.reset();

        PSK_PassportIssuanceController.IssuanceEligibility notPaid =
            PSK_PassportIssuanceController.checkEligibility(unpaid.Id);
        System.assertEquals(false, notPaid.eligible);
        System.assertEquals(true, notPaid.reason.contains('not fully paid'), notPaid.reason);
    }
}
