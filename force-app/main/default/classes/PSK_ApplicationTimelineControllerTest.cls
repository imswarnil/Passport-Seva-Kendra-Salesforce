@IsTest
private class PSK_ApplicationTimelineControllerTest {

    @IsTest
    static void testTimelineMergesEveryChildObject() {
        PSK_AutomationControl.reset();
        PSK_AutomationControl.bypassTriggers = true;

        PSK__c office = PSK_TestDataFactory.createOffice();
        Slot__c slot = PSK_TestDataFactory.createSlot(office.Id, 5);
        Citizen__c citizen = PSK_TestDataFactory.createCitizen();

        Passport_Application__c app = PSK_TestDataFactory.buildApplication(
            PSK_Constants.STATUS_DELIVERED);
        app.Citizen__c = citizen.Id;
        app.PSK_Office__c = office.Id;
        app.Submitted_Date__c = System.now().addDays(-20);
        app.Granted_Date__c = System.now().addDays(-5);
        insert app;

        Passport__c passport = PSK_TestDataFactory.createPassport(app.Id, citizen.Id);

        insert PSK_TestDataFactory.buildAppointment(app.Id, slot.Id, 'Completed');
        insert PSK_TestDataFactory.buildPayment(app.Id, 1500, PSK_Constants.PAYMENT_SUCCESS);
        insert PSK_TestDataFactory.buildDocument(
            app.Id, 'Aadhaar Proof', PSK_Constants.DOC_VERIFIED);
        insert PSK_TestDataFactory.buildPoliceVerification(app.Id, 'Cleared');
        insert PSK_TestDataFactory.buildObjection(app.Id, 'Resolved');
        insert PSK_TestDataFactory.buildNotification(app.Id, 'Sent');
        insert PSK_TestDataFactory.buildPrintJob(app.Id, passport.Id, 'Printed');
        insert PSK_TestDataFactory.buildDispatch(app.Id, passport.Id, 'Delivered');

        PSK_AutomationControl.reset();

        Test.startTest();
        List<PSK_ApplicationTimelineController.TimelineEntry> timeline =
            PSK_ApplicationTimelineController.getTimeline(app.Id);
        Test.stopTest();

        Set<String> types = new Set<String>();
        for (PSK_ApplicationTimelineController.TimelineEntry e : timeline) {
            types.add(e.type);
            System.assertNotEquals(null, e.title, 'Every entry needs a title');
            System.assertNotEquals(null, e.icon, 'Every entry needs an icon for the LWC');
        }

        System.assertEquals(true, types.contains('Application'));
        System.assertEquals(true, types.contains('Appointment'));
        System.assertEquals(true, types.contains('Payment'));
        System.assertEquals(true, types.contains('Document'));
        System.assertEquals(true, types.contains('Police Verification'));
        System.assertEquals(true, types.contains('Objection'));
        System.assertEquals(true, types.contains('Notification'));
        System.assertEquals(true, types.contains('Print Job'));
        System.assertEquals(true, types.contains('Dispatch'));
        System.assertEquals(9, types.size(), 'All nine entry types should be represented');
    }

    @IsTest
    static void testTimelineIsSortedNewestFirst() {
        Passport_Application__c app = PSK_TestDataFactory.createApplication(
            PSK_Constants.STATUS_SUBMITTED);

        Test.startTest();
        List<PSK_ApplicationTimelineController.TimelineEntry> timeline =
            PSK_ApplicationTimelineController.getTimeline(app.Id);
        Test.stopTest();

        System.assertEquals(true, timeline.size() >= 2,
            'Creation and submission should both appear');
        for (Integer i = 1; i < timeline.size(); i++) {
            DateTime earlier = timeline[i].timestamp;
            DateTime later = timeline[i - 1].timestamp;
            if (earlier == null || later == null) {
                continue;
            }
            System.assertEquals(true, later >= earlier,
                'Entries must run newest first, but position ' + i + ' broke the order');
        }
    }

    @IsTest
    static void testTimelineForUnknownApplication() {
        System.assertEquals(0,
            PSK_ApplicationTimelineController.getTimeline(null).size(),
            'A null id yields an empty timeline rather than an exception');

        Passport_Application__c app = PSK_TestDataFactory.createApplication(
            PSK_Constants.STATUS_DRAFT);
        Id deletedId = app.Id;
        delete app;
        System.assertEquals(0,
            PSK_ApplicationTimelineController.getTimeline(deletedId).size());
    }

    @IsTest
    static void testTimelineVariantsFlagProblems() {
        PSK_AutomationControl.reset();
        PSK_AutomationControl.bypassTriggers = true;
        Passport_Application__c app = PSK_TestDataFactory.createApplication(
            PSK_Constants.STATUS_DOC_VERIFICATION);
        insert PSK_TestDataFactory.buildDocument(
            app.Id, 'Affidavit', PSK_Constants.DOC_REJECTED);
        insert PSK_TestDataFactory.buildPoliceVerification(app.Id, 'Adverse');
        PSK_AutomationControl.reset();

        Test.startTest();
        List<PSK_ApplicationTimelineController.TimelineEntry> timeline =
            PSK_ApplicationTimelineController.getTimeline(app.Id);
        Test.stopTest();

        Integer errors = 0;
        for (PSK_ApplicationTimelineController.TimelineEntry e : timeline) {
            if (e.variant == 'error') {
                errors++;
            }
        }
        System.assertEquals(2, errors,
            'A rejected document and an adverse verification should both read as errors');
    }
}
