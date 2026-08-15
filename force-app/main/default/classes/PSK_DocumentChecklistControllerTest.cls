@IsTest
private class PSK_DocumentChecklistControllerTest {

    @IsTest
    static void testGetItems() {
        Passport_Application__c app = PSK_TestDataFactory.createApplication(
            PSK_Constants.STATUS_DOC_VERIFICATION);
        insert new List<Document_Checklist_Item__c>{
            PSK_TestDataFactory.buildDocument(app.Id, 'Aadhaar Proof', PSK_Constants.DOC_VERIFIED),
            PSK_TestDataFactory.buildDocument(app.Id, 'Address Proof', PSK_Constants.DOC_REQUIRED)
        };

        Test.startTest();
        List<PSK_DocumentChecklistController.ChecklistItem> items =
            PSK_DocumentChecklistController.getItems(app.Id);
        Test.stopTest();

        System.assertEquals(2, items.size());
        System.assertEquals('Aadhaar Proof', items[0].documentType,
            'Items come back sorted by document type');
        System.assertNotEquals(null, items[0].name);
    }

    @IsTest
    static void testGetItemsWithNoApplication() {
        System.assertEquals(0, PSK_DocumentChecklistController.getItems(null).size());
    }

    @IsTest
    static void testSetStatusToReceivedStampsTheDate() {
        Passport_Application__c app = PSK_TestDataFactory.createApplication(
            PSK_Constants.STATUS_DOC_VERIFICATION);
        Document_Checklist_Item__c item = PSK_TestDataFactory.buildDocument(
            app.Id, 'Aadhaar Proof', PSK_Constants.DOC_REQUIRED);
        insert item;

        Test.startTest();
        PSK_DocumentChecklistController.ChecklistItem updated =
            PSK_DocumentChecklistController.setStatus(item.Id, PSK_Constants.DOC_RECEIVED);
        Test.stopTest();

        System.assertEquals(PSK_Constants.DOC_RECEIVED, updated.status);
        System.assertEquals(Date.today(), updated.receivedDate);
        System.assertEquals(null, updated.verifiedDate, 'Received is not yet verified');
    }

    @IsTest
    static void testSetStatusToVerifiedBackfillsReceivedDate() {
        Passport_Application__c app = PSK_TestDataFactory.createApplication(
            PSK_Constants.STATUS_DOC_VERIFICATION);
        Document_Checklist_Item__c item = PSK_TestDataFactory.buildDocument(
            app.Id, 'Address Proof', PSK_Constants.DOC_REQUIRED);
        insert item;

        Test.startTest();
        PSK_DocumentChecklistController.ChecklistItem updated =
            PSK_DocumentChecklistController.setStatus(item.Id, PSK_Constants.DOC_VERIFIED);
        Test.stopTest();

        System.assertEquals(Date.today(), updated.verifiedDate);
        System.assertEquals(Date.today(), updated.receivedDate,
            'A document cannot be verified without having been received');
    }

    @IsTest
    static void testSetStatusBackToRequiredClearsDates() {
        Passport_Application__c app = PSK_TestDataFactory.createApplication(
            PSK_Constants.STATUS_DOC_VERIFICATION);
        Document_Checklist_Item__c item = PSK_TestDataFactory.buildDocument(
            app.Id, 'Annexure', PSK_Constants.DOC_VERIFIED);
        item.Received_Date__c = Date.today().addDays(-5);
        item.Verified_Date__c = Date.today().addDays(-4);
        insert item;

        Test.startTest();
        PSK_DocumentChecklistController.ChecklistItem updated =
            PSK_DocumentChecklistController.setStatus(item.Id, PSK_Constants.DOC_REQUIRED);
        Test.stopTest();

        System.assertEquals(null, updated.receivedDate, 'Resetting to Required clears the dates');
        System.assertEquals(null, updated.verifiedDate);
    }

    @IsTest
    static void testSetStatusRejectsAnInvalidValue() {
        Passport_Application__c app = PSK_TestDataFactory.createApplication(
            PSK_Constants.STATUS_DOC_VERIFICATION);
        Document_Checklist_Item__c item = PSK_TestDataFactory.buildDocument(app.Id, null, null);
        insert item;

        Boolean threw = false;
        String message = '';
        try {
            PSK_DocumentChecklistController.setStatus(item.Id, 'Shredded');
        } catch (AuraHandledException e) {
            threw = true;
            message = e.getMessage();
        }
        System.assertEquals(true, threw, 'An unknown status must be rejected');
        System.assertEquals(true, message.contains('not a valid document status'), message);
    }

    @IsTest
    static void testSetStatusWithMissingArgumentsThrows() {
        Integer thrown = 0;
        try {
            PSK_DocumentChecklistController.setStatus(null, PSK_Constants.DOC_VERIFIED);
        } catch (AuraHandledException e) {
            thrown++;
        }
        Passport_Application__c app = PSK_TestDataFactory.createApplication(
            PSK_Constants.STATUS_DRAFT);
        Document_Checklist_Item__c item = PSK_TestDataFactory.buildDocument(app.Id, null, null);
        insert item;
        try {
            PSK_DocumentChecklistController.setStatus(item.Id, '  ');
        } catch (AuraHandledException e) {
            thrown++;
        }
        System.assertEquals(2, thrown, 'Both a null id and a blank status must be rejected');
    }

    @IsTest
    static void testSeedFromTemplateForFresh() {
        Passport_Application__c app = PSK_TestDataFactory.createApplication(
            PSK_Constants.STATUS_SUBMITTED, PSK_Constants.RT_FRESH);

        Test.startTest();
        PSK_DocumentChecklistController.SeedResult result =
            PSK_DocumentChecklistController.seedFromTemplate(app.Id);
        Test.stopTest();

        System.assertEquals(3, result.created, 'The Fresh template has three documents');
        System.assertEquals(0, result.skipped);
        System.assertEquals(PSK_Constants.RT_FRESH, result.recordTypeName);
        System.assertEquals(3, result.items.size());
        for (PSK_DocumentChecklistController.ChecklistItem item : result.items) {
            System.assertEquals(PSK_Constants.DOC_REQUIRED, item.status,
                'Seeded documents start as Required');
        }
    }

    @IsTest
    static void testSeedFromTemplateForTatkalIsLonger() {
        Passport_Application__c app = PSK_TestDataFactory.createApplication(
            PSK_Constants.STATUS_SUBMITTED, PSK_Constants.RT_TATKAL);

        Test.startTest();
        PSK_DocumentChecklistController.SeedResult result =
            PSK_DocumentChecklistController.seedFromTemplate(app.Id);
        Test.stopTest();

        System.assertEquals(5, result.created,
            'Tatkal needs an affidavit and an annexure on top of the basics');
    }

    @IsTest
    static void testSeedFromTemplateIsIdempotent() {
        Passport_Application__c app = PSK_TestDataFactory.createApplication(
            PSK_Constants.STATUS_SUBMITTED, PSK_Constants.RT_MINOR);

        Test.startTest();
        PSK_DocumentChecklistController.SeedResult first =
            PSK_DocumentChecklistController.seedFromTemplate(app.Id);
        PSK_DocumentChecklistController.SeedResult second =
            PSK_DocumentChecklistController.seedFromTemplate(app.Id);
        Test.stopTest();

        System.assertEquals(4, first.created, 'The Minor template has four documents');
        System.assertEquals(0, second.created,
            'Pressing seed twice must not duplicate the checklist');
        System.assertEquals(4, second.skipped);
        System.assertEquals(4, [
            SELECT COUNT() FROM Document_Checklist_Item__c WHERE Passport_Application__c = :app.Id
        ]);
    }

    @IsTest
    static void testSeedFromTemplateWithNullIdThrows() {
        Boolean threw = false;
        try {
            PSK_DocumentChecklistController.seedFromTemplate(null);
        } catch (AuraHandledException e) {
            threw = true;
        }
        System.assertEquals(true, threw);
    }
}
