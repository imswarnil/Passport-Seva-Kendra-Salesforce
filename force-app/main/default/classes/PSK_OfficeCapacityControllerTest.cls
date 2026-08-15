@IsTest
private class PSK_OfficeCapacityControllerTest {

    @IsTest
    static void testUtilisationHasNoGapsInTheWindow() {
        PSK__c office = PSK_TestDataFactory.createOffice();
        // Slots on only two of the fourteen days.
        insert PSK_TestDataFactory.buildSlot(office.Id, Date.today(), 10);
        insert PSK_TestDataFactory.buildSlot(office.Id, Date.today().addDays(3), 10);

        Test.startTest();
        PSK_OfficeCapacityController.OfficeUtilisation u =
            PSK_OfficeCapacityController.getUtilisation(office.Id, 14);
        Test.stopTest();

        System.assertEquals(14, u.days.size(),
            'Every day in the window must be present so the chart has no gaps');
        System.assertEquals(Date.today(), u.days[0].slotDate);
        System.assertEquals(Date.today().addDays(13), u.toDate);
        System.assertEquals(20, u.totalCapacity, 'Two slots of ten seats each');
        System.assertEquals(0, u.totalBooked);
        System.assertEquals(0, u.overallUtilisationPercent);
        System.assertEquals(1, u.days[0].slotCount);
        System.assertEquals(0, u.days[1].slotCount, 'A day with no slots reads as zero, not absent');
    }

    @IsTest
    static void testUtilisationReflectsBookings() {
        PSK__c office = PSK_TestDataFactory.createOffice();
        Slot__c slot = PSK_TestDataFactory.createSlot(office.Id, 4);
        for (Integer i = 0; i < 2; i++) {
            Passport_Application__c app = PSK_TestDataFactory.createApplication(
                PSK_Constants.STATUS_SUBMITTED);
            insert PSK_TestDataFactory.buildAppointment(app.Id, slot.Id, 'Scheduled');
        }

        Test.startTest();
        PSK_OfficeCapacityController.OfficeUtilisation u =
            PSK_OfficeCapacityController.getUtilisation(office.Id, 7);
        Test.stopTest();

        System.assertEquals(4, u.totalCapacity);
        System.assertEquals(2, u.totalBooked);
        System.assertEquals(50.0, u.overallUtilisationPercent, 'Two of four seats taken');
        System.assertEquals(2, u.days[0].available);
        System.assertEquals(false, u.days[0].isFull);
        System.assertEquals(0, u.fullDays);
    }

    @IsTest
    static void testFullDayIsFlagged() {
        PSK__c office = PSK_TestDataFactory.createOffice();
        Slot__c slot = PSK_TestDataFactory.createSlot(office.Id, 1);
        Passport_Application__c app = PSK_TestDataFactory.createApplication(
            PSK_Constants.STATUS_SUBMITTED);
        insert PSK_TestDataFactory.buildAppointment(app.Id, slot.Id, 'Scheduled');

        Test.startTest();
        PSK_OfficeCapacityController.OfficeUtilisation u =
            PSK_OfficeCapacityController.getUtilisation(office.Id, 3);
        Test.stopTest();

        System.assertEquals(true, u.days[0].isFull, 'One seat, one booking, no room left');
        System.assertEquals(0, u.days[0].available);
        System.assertEquals(1, u.fullDays);
        System.assertEquals(100.0, u.days[0].utilisationPercent);
    }

    @IsTest
    static void testHorizonDefaultsAndCaps() {
        PSK__c office = PSK_TestDataFactory.createOffice();

        Test.startTest();
        System.assertEquals(14,
            PSK_OfficeCapacityController.getUtilisation(office.Id, null).days.size(),
            'A null horizon defaults to a fortnight');
        System.assertEquals(14,
            PSK_OfficeCapacityController.getUtilisation(office.Id, 0).days.size(),
            'A zero horizon also defaults');
        System.assertEquals(90,
            PSK_OfficeCapacityController.getUtilisation(office.Id, 500).days.size(),
            'The horizon is capped at 90 days');
        Test.stopTest();
    }

    @IsTest
    static void testUtilisationWithBadOfficeThrows() {
        Integer thrown = 0;
        try {
            PSK_OfficeCapacityController.getUtilisation(null, 7);
        } catch (AuraHandledException e) {
            thrown++;
        }

        PSK__c office = PSK_TestDataFactory.createOffice();
        Id deletedId = office.Id;
        delete office;
        try {
            PSK_OfficeCapacityController.getUtilisation(deletedId, 7);
        } catch (AuraHandledException e) {
            thrown++;
        }
        System.assertEquals(2, thrown);
    }

    @IsTest
    static void testNetworkUtilisation() {
        PSK__c first = PSK_TestDataFactory.createOffice();
        PSK__c second = PSK_TestDataFactory.createOffice();
        insert PSK_TestDataFactory.buildSlot(first.Id, Date.today(), 10);
        insert PSK_TestDataFactory.buildSlot(second.Id, Date.today(), 6);

        Test.startTest();
        List<PSK_OfficeCapacityController.OfficeUtilisation> network =
            PSK_OfficeCapacityController.getNetworkUtilisation(14);
        Test.stopTest();

        System.assertEquals(2, network.size(), 'Both active offices should appear');
        Integer totalCapacity = 0;
        for (PSK_OfficeCapacityController.OfficeUtilisation u : network) {
            totalCapacity += u.totalCapacity;
            System.assertNotEquals(null, u.officeName);
        }
        System.assertEquals(16, totalCapacity, 'Ten seats plus six across the network');
    }

    @IsTest
    static void testNetworkUtilisationWithNoOffices() {
        System.assertEquals(0,
            PSK_OfficeCapacityController.getNetworkUtilisation(7).size(),
            'No offices means an empty list, not an exception');
    }
}
