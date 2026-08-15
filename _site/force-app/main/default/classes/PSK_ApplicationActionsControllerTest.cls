@IsTest
private class PSK_ApplicationActionsControllerTest {

    private static Passport_Application__c newApp(String status) {
        return new Passport_Application__c(
            First_Name__c = 'Rahul', Last_Name__c = 'Verma', Status__c = status,
            Date_of_Birth__c = Date.newInstance(1995, 6, 1), Mobile__c = '9000090000',
            Address_Line1__c = '1 MG Road'
        );
    }

    @IsTest
    static void testAdvanceThroughFullLifecycle() {
        Passport_Application__c app = newApp('Draft');
        insert app;

        Test.startTest();
        PSK_ApplicationActionsController.advance(app.Id); // Draft -> Submitted
        PSK_ApplicationActionsController.advance(app.Id); // Submitted -> Payment Pending
        PSK_ApplicationActionsController.advance(app.Id); // Payment Pending -> Paid
        PSK_ApplicationActionsController.advance(app.Id); // Paid -> Document Verification
        PSK_ApplicationActionsController.ActionResult toPv = PSK_ApplicationActionsController.advance(app.Id); // -> Police Verification
        Test.stopTest();

        System.assertEquals('Police Verification', toPv.newStatus, 'Expected status to advance to Police Verification');

        Passport_Application__c updated = [
            SELECT Status__c, Submitted_Date__c, Payment_Status__c, Documents_Verified__c
            FROM Passport_Application__c WHERE Id = :app.Id
        ];
        System.assertEquals('Police Verification', updated.Status__c);
        System.assertNotEquals(null, updated.Submitted_Date__c, 'Submitted date should be stamped');
        System.assertEquals('Paid', updated.Payment_Status__c);
        System.assertEquals(true, updated.Documents_Verified__c);

        List<Police_Verification__c> pvs = [SELECT Status__c FROM Police_Verification__c WHERE Passport_Application__c = :app.Id];
        System.assertEquals(1, pvs.size(), 'Expected a police verification record to be created');
        System.assertEquals('Referred', pvs[0].Status__c);
    }

    @IsTest
    static void testAdvanceClearsVerificationAndReachesGranting() {
        Passport_Application__c app = newApp('Police Verification');
        insert app;
        insert new Police_Verification__c(
            // Referred_Requires_Station_And_Date wants both the station and the date.
            Passport_Application__c = app.Id, Status__c = 'Referred', PV_Type__c = 'Post-PV',
            Police_Station__c = 'MG Road PS', Referred_Date__c = Date.today()
        );

        Test.startTest();
        PSK_ApplicationActionsController.ActionResult result = PSK_ApplicationActionsController.advance(app.Id);
        Test.stopTest();

        System.assertEquals('Granting', result.newStatus);

        Passport_Application__c updated = [SELECT Payment_Status__c, Granted_Date__c FROM Passport_Application__c WHERE Id = :app.Id];
        System.assertEquals('Paid', updated.Payment_Status__c, 'Payment must be Paid before Granting');
        System.assertNotEquals(null, updated.Granted_Date__c);

        Police_Verification__c pv = [SELECT Status__c, Report_Received_Date__c FROM Police_Verification__c WHERE Passport_Application__c = :app.Id];
        System.assertEquals('Cleared', pv.Status__c);
        System.assertNotEquals(null, pv.Report_Received_Date__c);
    }

    @IsTest
    static void testAdvanceFromTerminalStatusThrows() {
        Passport_Application__c app = newApp('Delivered');
        insert app;

        Boolean threw = false;
        try {
            PSK_ApplicationActionsController.advance(app.Id);
        } catch (AuraHandledException e) {
            threw = true;
        }
        System.assert(threw, 'Expected an exception when advancing from a terminal status');
    }

    @IsTest
    static void testReject() {
        Passport_Application__c app = newApp('Submitted');
        insert app;

        Test.startTest();
        PSK_ApplicationActionsController.ActionResult result = PSK_ApplicationActionsController.reject(app.Id);
        Test.stopTest();

        System.assertEquals('Rejected', result.newStatus);
    }

    @IsTest
    static void testRejectFromTerminalStatusThrows() {
        Passport_Application__c app = newApp('Delivered');
        insert app;

        Boolean threw = false;
        try {
            PSK_ApplicationActionsController.reject(app.Id);
        } catch (AuraHandledException e) {
            threw = true;
        }
        System.assert(threw, 'Expected an exception when rejecting a terminal status application');
    }
}
