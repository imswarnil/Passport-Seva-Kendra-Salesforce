@IsTest
private class PSK_AutomationControlTest {

    @IsTest
    static void testDefaultsAreOff() {
        PSK_AutomationControl.reset();
        System.assertEquals(false, PSK_AutomationControl.bypassTriggers,
            'Automation must be ON by default -- the bypass is opt-in');
        System.assertEquals(false, PSK_AutomationControl.isBypassed());
        System.assertEquals(false, PSK_AutomationControl.inPaymentRollup);
        System.assertEquals(0, PSK_AutomationControl.issuanceProcessed.size());
    }

    @IsTest
    static void testBypassFlag() {
        PSK_AutomationControl.reset();
        PSK_AutomationControl.bypassTriggers = true;
        System.assertEquals(true, PSK_AutomationControl.isBypassed());
        PSK_AutomationControl.reset();
        System.assertEquals(false, PSK_AutomationControl.isBypassed(),
            'reset() must clear the bypass');
    }

    @IsTest
    static void testIssuanceProcessedIsResettable() {
        PSK_AutomationControl.reset();
        Id fakeId = PSK_TestDataFactory.createApplication(PSK_Constants.STATUS_DRAFT).Id;
        PSK_AutomationControl.issuanceProcessed.add(fakeId);
        System.assertEquals(true, PSK_AutomationControl.issuanceProcessed.contains(fakeId));
        PSK_AutomationControl.reset();
        System.assertEquals(0, PSK_AutomationControl.issuanceProcessed.size());
    }

    @IsTest
    static void testBypassSuppressesApplicationAutomation() {
        PSK_AutomationControl.reset();
        PSK_AutomationControl.bypassTriggers = true;

        Passport_Application__c app = PSK_TestDataFactory.buildApplication(
            PSK_Constants.STATUS_SUBMITTED);
        app.Fee__c = null;
        insert app;

        Passport_Application__c saved = [
            SELECT Citizen__c, Fee__c, Submitted_Date__c
            FROM Passport_Application__c WHERE Id = :app.Id
        ];
        System.assertEquals(null, saved.Citizen__c,
            'With the bypass on, the trigger must not reverse-create a citizen');
        System.assertEquals(null, saved.Fee__c,
            'With the bypass on, the trigger must not compute a fee');
        System.assertEquals(null, saved.Submitted_Date__c,
            'With the bypass on, the trigger must not stamp the submitted date');

        PSK_AutomationControl.reset();
    }
}
