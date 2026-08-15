@IsTest
private class PSK_FeeServiceTest {

    @IsTest
    static void testPreviewDoesNotMutateTheRecord() {
        PSK_ApplicationService.overrideFeeMatrix(PSK_TestDataFactory.feeMatrixRows());
        Passport_Application__c app = PSK_TestDataFactory.buildApplication(
            PSK_Constants.STATUS_DRAFT);
        app.Fee__c = 4242;
        insert app;

        Test.startTest();
        PSK_ApplicationService.FeeBreakdown fb = PSK_FeeService.preview(app.Id);
        Test.stopTest();

        System.assertEquals(1500, fb.totalFee, 'Fresh / 36 pages / 10 years');
        System.assertEquals(4242,
            [SELECT Fee__c FROM Passport_Application__c WHERE Id = :app.Id].Fee__c,
            'preview must be read-only');
    }

    @IsTest
    static void testRecalculateSavesTheFee() {
        PSK_ApplicationService.overrideFeeMatrix(PSK_TestDataFactory.feeMatrixRows());
        Passport_Application__c app = PSK_TestDataFactory.buildApplication(
            PSK_Constants.STATUS_DRAFT);
        app.Fee__c = 1;
        insert app;

        Test.startTest();
        PSK_ApplicationService.FeeBreakdown fb = PSK_FeeService.recalculate(app.Id);
        Test.stopTest();

        System.assertEquals(1500, fb.totalFee);
        System.assertEquals(1500,
            [SELECT Fee__c FROM Passport_Application__c WHERE Id = :app.Id].Fee__c,
            'recalculate must persist the fee');
    }

    @IsTest
    static void testTatkalRecordTypeGetsSurcharge() {
        PSK_ApplicationService.overrideFeeMatrix(PSK_TestDataFactory.feeMatrixRows());
        Passport_Application__c app = PSK_TestDataFactory.createApplication(
            PSK_Constants.STATUS_DRAFT, PSK_Constants.RT_TATKAL);

        Test.startTest();
        PSK_ApplicationService.FeeBreakdown fb = PSK_FeeService.preview(app.Id);
        Test.stopTest();

        System.assertEquals(2000, fb.tatkalSurcharge, 'A tatkal application carries the surcharge');
        System.assertEquals(3500, fb.totalFee);
    }

    @IsTest
    static void testNullApplicationIdThrows() {
        Boolean threw = false;
        try {
            PSK_FeeService.preview(null);
        } catch (AuraHandledException e) {
            threw = true;
        }
        System.assertEquals(true, threw, 'A null id must be rejected with a friendly error');
    }

    @IsTest
    static void testUnknownApplicationThrows() {
        Passport_Application__c app = PSK_TestDataFactory.createApplication(
            PSK_Constants.STATUS_DRAFT);
        Id realId = app.Id;
        delete app;

        Boolean threw = false;
        try {
            PSK_FeeService.recalculate(realId);
        } catch (AuraHandledException e) {
            threw = true;
        }
        System.assertEquals(true, threw, 'A missing application must be reported, not swallowed');
    }
}
