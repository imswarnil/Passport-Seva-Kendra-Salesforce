@IsTest
private class PSK_ApplicationSidebarControllerTest {

    @TestSetup
    static void setup() {
        Passport_Application__c app = new Passport_Application__c(
            First_Name__c = 'Deepa', Last_Name__c = 'Nair', Status__c = 'Document Verification',
            Date_of_Birth__c = Date.newInstance(1992, 3, 15), Mobile__c = '9988776655',
            Address_Line1__c = '7 Lake View'
        );
        insert app;

        // Each child below carries the fields its own status-conditional
        // validation rule demands: Verified_Requires_Verified_Date,
        // Rejected_Requires_Rejection_Reason, Success_Requires_Reference,
        // Referred_Requires_Station_And_Date and Reviewed_Requires_Reviewer.
        insert new List<Document_Checklist_Item__c>{
            new Document_Checklist_Item__c(Passport_Application__c = app.Id, Document_Type__c = 'Address Proof', Status__c = 'Verified',
                Received_Date__c = Date.today().addDays(-3), Verified_Date__c = Date.today().addDays(-1)),
            new Document_Checklist_Item__c(Passport_Application__c = app.Id, Document_Type__c = 'Aadhaar Proof', Status__c = 'Rejected',
                Received_Date__c = Date.today().addDays(-3), Rejection_Reason__c = 'Name does not match the birth certificate.'),
            new Document_Checklist_Item__c(Passport_Application__c = app.Id, Document_Type__c = 'Date of Birth Proof', Status__c = 'Required')
        };

        insert new Payment__c(
            Passport_Application__c = app.Id, Status__c = 'Success', Amount__c = 1500,
            Payment_Date__c = System.now(), Payment_Reference__c = 'SIDEBAR-PAYREF-1'
        );

        insert new Police_Verification__c(
            Passport_Application__c = app.Id, Status__c = 'In Progress', PV_Type__c = 'Pre-PV',
            Police_Station__c = 'Lake View PS', Referred_Date__c = Date.today().addDays(-4)
        );

        insert new List<Risk_Flag__c>{
            new Risk_Flag__c(Passport_Application__c = app.Id, Flag_Type__c = 'Address Anomaly', Status__c = 'Open', Severity__c = 'Medium'),
            new Risk_Flag__c(Passport_Application__c = app.Id, Flag_Type__c = 'Duplicate Application', Status__c = 'Dismissed', Severity__c = 'Low',
                Reviewed_By__c = UserInfo.getUserId())
        };
    }

    @IsTest
    static void testGetSidebarData() {
        Passport_Application__c app = [SELECT Id FROM Passport_Application__c LIMIT 1];

        Test.startTest();
        PSK_ApplicationSidebarController.SidebarData data = PSK_ApplicationSidebarController.getSidebarData(app.Id);
        Test.stopTest();

        System.assertEquals(3, data.documentsTotal, 'Expected 3 checklist items');
        System.assertEquals(1, data.documentsVerified, 'Expected 1 verified document');
        System.assertEquals(1, data.documentsRejected, 'Expected 1 rejected document');
        System.assertEquals('Success', data.paymentStatus, 'Expected latest payment status');
        System.assertEquals(1500, data.paymentAmount, 'Expected payment amount to match');
        System.assertEquals('In Progress', data.policeVerificationStatus, 'Expected PV status');
        System.assertEquals('Pre-PV', data.policeVerificationType, 'Expected PV type');
        System.assertEquals(2, data.totalRiskFlags, 'Expected 2 risk flags');
        System.assertEquals(1, data.openRiskFlags, 'Expected 1 open risk flag');
    }

    @IsTest
    static void testGetSidebarDataNullId() {
        Test.startTest();
        PSK_ApplicationSidebarController.SidebarData data = PSK_ApplicationSidebarController.getSidebarData(null);
        Test.stopTest();

        System.assertEquals(0, data.documentsTotal, 'Expected zeroed data for null id');
        System.assertEquals(null, data.paymentStatus, 'Expected no payment status for null id');
    }
}
