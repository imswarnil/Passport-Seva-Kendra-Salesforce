@IsTest
private class PSK_HomeControllerTest {

    @TestSetup
    static void setup() {
        Map<String, Schema.RecordTypeInfo> rtByName = Schema.SObjectType.Passport_Application__c.getRecordTypeInfosByDeveloperName();
        Id freshRtId = rtByName.get('Fresh')?.getRecordTypeId();
        Id tatkalRtId = rtByName.get('Tatkal')?.getRecordTypeId();

        List<Passport_Application__c> apps = new List<Passport_Application__c>();
        apps.add(new Passport_Application__c(
            RecordTypeId = freshRtId,
            First_Name__c = 'Asha', Last_Name__c = 'Rao', Status__c = 'Draft',
            Payment_Status__c = 'Not Paid'
        ));
        apps.add(new Passport_Application__c(
            RecordTypeId = freshRtId,
            First_Name__c = 'Bhavesh', Last_Name__c = 'Shah', Status__c = 'Submitted',
            Date_of_Birth__c = Date.newInstance(1990, 5, 12), Mobile__c = '9876543210',
            Address_Line1__c = '12 MG Road', Payment_Status__c = 'Pending',
            Submitted_Date__c = System.now(), Tatkal__c = true
        ));
        apps.add(new Passport_Application__c(
            RecordTypeId = tatkalRtId,
            First_Name__c = 'Chitra', Last_Name__c = 'Iyer', Status__c = 'Delivered',
            Date_of_Birth__c = Date.newInstance(1985, 8, 20), Mobile__c = '9123456780',
            Address_Line1__c = '45 Park Street', Payment_Status__c = 'Paid',
            Granted_Date__c = System.now()
        ));
        insert apps;
    }

    @IsTest
    static void testGetHomeStatsUnfiltered() {
        Test.startTest();
        PSK_HomeController.HomeStats stats = PSK_HomeController.getHomeStats(null);
        Test.stopTest();

        System.assertEquals(3, stats.totalApplications, 'Expected 3 seeded applications');
        System.assertEquals(1, stats.draftCount, 'Expected 1 draft application');
        System.assertEquals(1, stats.submittedTodayCount, 'Expected 1 application submitted today');
        System.assertEquals(2, stats.paymentPendingCount, 'Expected 2 payment pending applications (Not Paid + Pending)');
        System.assertEquals(1, stats.grantedThisMonthCount, 'Expected 1 application granted this month');
        System.assertEquals(1, stats.tatkalCount, 'Expected 1 tatkal application');
        System.assert(!stats.statusBreakdown.isEmpty(), 'Expected status breakdown to be populated');
    }

    @IsTest
    static void testGetHomeStatsFilteredByRecordType() {
        Id freshRtId = Schema.SObjectType.Passport_Application__c.getRecordTypeInfosByDeveloperName().get('Fresh')?.getRecordTypeId();

        Test.startTest();
        PSK_HomeController.HomeStats stats = PSK_HomeController.getHomeStats(freshRtId);
        Test.stopTest();

        System.assertEquals(2, stats.totalApplications, 'Expected only the 2 Fresh record-type applications');
    }

    @IsTest
    static void testGetRecentApplications() {
        Test.startTest();
        List<Passport_Application__c> recent = PSK_HomeController.getRecentApplications(2, null);
        List<Passport_Application__c> defaulted = PSK_HomeController.getRecentApplications(null, null);
        Test.stopTest();

        System.assertEquals(2, recent.size(), 'Expected limit to be respected');
        System.assertEquals(3, defaulted.size(), 'Expected default limit to return all seeded records');
    }

    @IsTest
    static void testGetRecordTypeOptions() {
        Test.startTest();
        List<PSK_HomeController.RecordTypeOption> options = PSK_HomeController.getRecordTypeOptions();
        Test.stopTest();

        System.assert(!options.isEmpty(), 'Expected at least the "All Record Types" option');
        System.assertEquals('All Record Types', options[0].label);
        System.assertEquals('', options[0].value);
    }

    @IsTest
    static void testGetRecordTypeSummary() {
        Test.startTest();
        List<PSK_HomeController.StatusCount> summary = PSK_HomeController.getRecordTypeSummary();
        Test.stopTest();

        System.assert(!summary.isEmpty(), 'Expected record type summary to be populated');
    }
}
