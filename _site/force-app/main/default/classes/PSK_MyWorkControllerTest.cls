@IsTest
private class PSK_MyWorkControllerTest {

    @IsTest
    static void testMyWorkListsRecordsIOwn() {
        PSK_MyWorkController.overrideSla(PSK_TestDataFactory.slaRows());
        Passport_Application__c app = PSK_TestDataFactory.createApplication(
            PSK_Constants.STATUS_SUBMITTED);

        Test.startTest();
        PSK_MyWorkController.MyWork work = PSK_MyWorkController.getMyWork();
        Test.stopTest();

        System.assertEquals(UserInfo.getUserId(), work.userId);
        System.assertEquals(1, work.totalItems);
        System.assertEquals(1, work.ownedByMe);
        System.assertEquals(0, work.ownedByMyQueues);
        System.assertEquals(app.Id, work.items[0].id);
        System.assertEquals(true, work.items[0].applicantName.startsWith('Aarav '),
            'The applicant name is composed from first and last name, got '
            + work.items[0].applicantName);
        System.assertEquals(false, work.items[0].ownedByQueue);
    }

    @IsTest
    static void testTerminalRecordsAreExcluded() {
        PSK_MyWorkController.overrideSla(PSK_TestDataFactory.slaRows());
        PSK_TestDataFactory.createApplication(PSK_Constants.STATUS_SUBMITTED);
        PSK_TestDataFactory.createApplication(PSK_Constants.STATUS_DELIVERED);
        PSK_TestDataFactory.createApplication(PSK_Constants.STATUS_REJECTED);
        PSK_TestDataFactory.createApplication(PSK_Constants.STATUS_CANCELLED);

        Test.startTest();
        PSK_MyWorkController.MyWork work = PSK_MyWorkController.getMyWork();
        Test.stopTest();

        System.assertEquals(1, work.totalItems,
            'Delivered, Rejected and Cancelled applications are finished work');
    }

    @IsTest
    static void testSlaWithinTarget() {
        PSK_MyWorkController.overrideSla(PSK_TestDataFactory.slaRows());
        Passport_Application__c app = PSK_TestDataFactory.buildApplication(
            PSK_Constants.STATUS_SUBMITTED);
        app.Stage_Entered_Date__c = System.now().addHours(-2);
        insert app;

        Test.startTest();
        PSK_MyWorkController.MyWork work = PSK_MyWorkController.getMyWork();
        Test.stopTest();

        PSK_MyWorkController.WorkItem item = work.items[0];
        System.assertEquals(24, item.targetHours, 'The Submitted stage targets 24 hours');
        System.assertEquals(false, item.slaBreached, 'Two hours in is well inside target');
        System.assertEquals(false, item.slaEscalated);
        System.assertEquals('success', item.slaVariant);
        System.assertEquals(0, work.breachedItems);
        System.assertEquals(true, item.hoursInStage >= 1.9 && item.hoursInStage <= 2.2,
            'Expected roughly two hours in stage, got ' + item.hoursInStage);
    }

    @IsTest
    static void testSlaBreached() {
        PSK_MyWorkController.overrideSla(PSK_TestDataFactory.slaRows());
        Passport_Application__c app = PSK_TestDataFactory.buildApplication(
            PSK_Constants.STATUS_SUBMITTED);
        app.Stage_Entered_Date__c = System.now().addHours(-30);
        insert app;

        Test.startTest();
        PSK_MyWorkController.MyWork work = PSK_MyWorkController.getMyWork();
        Test.stopTest();

        PSK_MyWorkController.WorkItem item = work.items[0];
        System.assertEquals(true, item.slaBreached, '30 hours against a 24-hour target');
        System.assertEquals(false, item.slaEscalated, 'Not yet past the 48-hour escalation');
        System.assertEquals('warning', item.slaVariant);
        System.assertEquals(1, work.breachedItems);
        System.assertEquals(0, work.escalatedItems);
    }

    @IsTest
    static void testSlaEscalated() {
        PSK_MyWorkController.overrideSla(PSK_TestDataFactory.slaRows());
        Passport_Application__c app = PSK_TestDataFactory.buildApplication(
            PSK_Constants.STATUS_SUBMITTED);
        app.Stage_Entered_Date__c = System.now().addHours(-100);
        insert app;

        Test.startTest();
        PSK_MyWorkController.MyWork work = PSK_MyWorkController.getMyWork();
        Test.stopTest();

        PSK_MyWorkController.WorkItem item = work.items[0];
        System.assertEquals(true, item.slaBreached);
        System.assertEquals(true, item.slaEscalated, '100 hours is past the 48-hour escalation');
        System.assertEquals('error', item.slaVariant);
        System.assertEquals(1, work.escalatedItems);
        System.assertEquals(true, item.slaLabel.contains('Escalated'), item.slaLabel);
    }

    @IsTest
    static void testTatkalUsesTheTighterSla() {
        PSK_MyWorkController.overrideSla(PSK_TestDataFactory.slaRows());
        Passport_Application__c app = PSK_TestDataFactory.buildApplication(
            PSK_Constants.STATUS_SUBMITTED, PSK_Constants.RT_TATKAL);
        app.Stage_Entered_Date__c = System.now().addHours(-6);
        insert app;

        Test.startTest();
        PSK_MyWorkController.MyWork work = PSK_MyWorkController.getMyWork();
        Test.stopTest();

        PSK_MyWorkController.WorkItem item = work.items[0];
        System.assertEquals(4, item.targetHours,
            'A tatkal application is held to the four-hour target, not the standard 24');
        System.assertEquals(true, item.slaBreached, 'Six hours against a four-hour target');
        System.assertEquals('Tatkal', item.ownerQueueName);
    }

    @IsTest
    static void testStageWithNoSlaConfigured() {
        // Only Submitted and Granting are configured in the test rows.
        PSK_MyWorkController.overrideSla(PSK_TestDataFactory.slaRows());
        PSK_TestDataFactory.createApplication(PSK_Constants.STATUS_DOC_VERIFICATION);

        Test.startTest();
        PSK_MyWorkController.MyWork work = PSK_MyWorkController.getMyWork();
        Test.stopTest();

        PSK_MyWorkController.WorkItem item = work.items[0];
        System.assertEquals(false, item.slaBreached,
            'With no SLA configured nothing can be in breach');
        System.assertEquals('inverse', item.slaVariant);
        System.assertEquals(true, item.slaLabel.contains('No SLA configured'), item.slaLabel);
    }

    @IsTest
    static void testNoTargetHoursConfigured() {
        PSK_MyWorkController.overrideSla(new List<SLA_Config__mdt>{
            new SLA_Config__mdt(
                DeveloperName = 'Test_NoTarget', Stage__c = PSK_Constants.STATUS_SUBMITTED,
                Service_Type__c = 'Passport', Target_Hours__c = 0,
                Owner_Queue_Name__c = 'Submitted', Applies_To_Tatkal__c = false, Is_Active__c = true
            )
        });
        PSK_TestDataFactory.createApplication(PSK_Constants.STATUS_SUBMITTED);

        Test.startTest();
        PSK_MyWorkController.MyWork work = PSK_MyWorkController.getMyWork();
        Test.stopTest();

        System.assertEquals(true, work.items[0].slaLabel.contains('No target hours'),
            work.items[0].slaLabel);
    }

    @IsTest
    static void testNonPassportSlaRowsAreIgnored() {
        PSK_MyWorkController.overrideSla(new List<SLA_Config__mdt>{
            new SLA_Config__mdt(
                DeveloperName = 'Test_Visa', Stage__c = PSK_Constants.STATUS_SUBMITTED,
                Service_Type__c = 'Visa', Target_Hours__c = 1,
                Applies_To_Tatkal__c = false, Is_Active__c = true
            )
        });
        PSK_TestDataFactory.createApplication(PSK_Constants.STATUS_SUBMITTED);

        Test.startTest();
        PSK_MyWorkController.MyWork work = PSK_MyWorkController.getMyWork();
        Test.stopTest();

        System.assertEquals(true, work.items[0].slaLabel.contains('No SLA configured'),
            'A Visa SLA row must not be applied to a passport application');
    }

    @IsTest
    static void testEmptyWorkList() {
        PSK_MyWorkController.overrideSla(PSK_TestDataFactory.slaRows());

        Test.startTest();
        PSK_MyWorkController.MyWork work = PSK_MyWorkController.getMyWork();
        Test.stopTest();

        System.assertEquals(0, work.totalItems);
        System.assertNotEquals(null, work.items, 'An empty list, never null');
        System.assertNotEquals(null, work.queueNames);
    }

    @IsTest
    static void testApplicantNameFallback() {
        PSK_MyWorkController.overrideSla(PSK_TestDataFactory.slaRows());
        // A Draft application is the only place a name may legitimately be missing:
        // Require_Core_Fields_On_Submit enforces it from Submitted onwards.
        Passport_Application__c app = PSK_TestDataFactory.buildApplication(
            PSK_Constants.STATUS_DRAFT);
        app.First_Name__c = null;
        app.Last_Name__c = null;
        insert app;

        Test.startTest();
        PSK_MyWorkController.MyWork work = PSK_MyWorkController.getMyWork();
        Test.stopTest();

        System.assertEquals('(no name)', work.items[0].applicantName,
            'A nameless draft must not render as null in the UI');
    }
}
