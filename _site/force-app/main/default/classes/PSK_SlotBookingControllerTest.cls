@IsTest
private class PSK_SlotBookingControllerTest {

    @IsTest
    static void testGetOfficesReturnsActiveOnly() {
        PSK__c active = PSK_TestDataFactory.createOffice();
        PSK__c inactive = PSK_TestDataFactory.buildOffice();
        inactive.Is_Active__c = false;
        insert inactive;

        Test.startTest();
        List<PSK_SlotBookingController.OfficeOption> offices =
            PSK_SlotBookingController.getOffices();
        Test.stopTest();

        System.assertEquals(1, offices.size(), 'Only active offices are bookable');
        System.assertEquals(active.Id, offices[0].id);
        System.assertEquals(active.Office_Code__c, offices[0].officeCode);
        System.assertEquals(200, offices[0].capacityPerDay);
    }

    @IsTest
    static void testGetAvailableSlots() {
        PSK__c office = PSK_TestDataFactory.createOffice();
        Slot__c slot = PSK_TestDataFactory.createSlot(office.Id, 5);

        Test.startTest();
        List<PSK_SlotBookingController.SlotOption> slots =
            PSK_SlotBookingController.getAvailableSlots(office.Id, Date.today());
        Test.stopTest();

        System.assertEquals(1, slots.size());
        System.assertEquals(5, slots[0].capacity);
        System.assertEquals(0, slots[0].booked);
        System.assertEquals(5, slots[0].available);
        System.assertEquals(true, slots[0].isAvailable);
        System.assertEquals('10:00', slots[0].startTime, 'Times are formatted HH:mm for the UI');
        System.assertEquals(true, slots[0].label.contains('5 of 5 free'), slots[0].label);
    }

    @IsTest
    static void testGetAvailableSlotsWithNullDateScansTheNextMonth() {
        PSK__c office = PSK_TestDataFactory.createOffice();
        insert PSK_TestDataFactory.buildSlot(office.Id, Date.today().addDays(10), 5);
        insert PSK_TestDataFactory.buildSlot(office.Id, Date.today().addDays(60), 5);

        Test.startTest();
        List<PSK_SlotBookingController.SlotOption> slots =
            PSK_SlotBookingController.getAvailableSlots(office.Id, null);
        Test.stopTest();

        System.assertEquals(1, slots.size(),
            'A null date scans today through today + 30 days, so the 60-day slot is excluded');
    }

    @IsTest
    static void testGetAvailableSlotsWithNoOffice() {
        System.assertEquals(0,
            PSK_SlotBookingController.getAvailableSlots(null, Date.today()).size());
    }

    @IsTest
    static void testBookCreatesAppointment() {
        PSK__c office = PSK_TestDataFactory.createOffice();
        Slot__c slot = PSK_TestDataFactory.createSlot(office.Id, 5);
        Passport_Application__c app = PSK_TestDataFactory.createApplication(
            PSK_Constants.STATUS_SUBMITTED);

        Test.startTest();
        PSK_SlotBookingController.BookingResult result =
            PSK_SlotBookingController.book(app.Id, slot.Id);
        Test.stopTest();

        System.assertNotEquals(null, result.appointmentId);
        System.assertEquals('Scheduled', result.status);
        System.assertNotEquals(null, result.appointmentName);
        System.assertEquals(1, [SELECT COUNT() FROM Appointment__c WHERE Slot__c = :slot.Id]);
    }

    @IsTest
    static void testBookRejectsAFullSlotWithAFriendlyMessage() {
        PSK__c office = PSK_TestDataFactory.createOffice();
        Slot__c slot = PSK_TestDataFactory.createSlot(office.Id, 1);
        Passport_Application__c first = PSK_TestDataFactory.createApplication(
            PSK_Constants.STATUS_SUBMITTED);
        Passport_Application__c second = PSK_TestDataFactory.createApplication(
            PSK_Constants.STATUS_SUBMITTED);

        PSK_SlotBookingController.book(first.Id, slot.Id);

        Test.startTest();
        Boolean threw = false;
        try {
            PSK_SlotBookingController.book(second.Id, slot.Id);
        } catch (AuraHandledException e) {
            threw = true;
        }
        Test.stopTest();

        System.assertEquals(true, threw,
            'The trigger error must surface as an AuraHandledException, not a raw DmlException');
    }

    @IsTest
    static void testBookRejectsASecondLiveAppointment() {
        PSK__c office = PSK_TestDataFactory.createOffice();
        Slot__c first = PSK_TestDataFactory.createSlot(office.Id, 5);
        Slot__c second = PSK_TestDataFactory.createSlot(office.Id, 5);
        Passport_Application__c app = PSK_TestDataFactory.createApplication(
            PSK_Constants.STATUS_SUBMITTED);

        PSK_SlotBookingController.book(app.Id, first.Id);

        Test.startTest();
        Boolean threw = false;
        String message = '';
        try {
            PSK_SlotBookingController.book(app.Id, second.Id);
        } catch (AuraHandledException e) {
            threw = true;
            message = e.getMessage();
        }
        Test.stopTest();

        System.assertEquals(true, threw, 'One live appointment per application');
        System.assertEquals(true, message.contains('already has a live appointment'), message);
    }

    @IsTest
    static void testBookRejectsTerminalApplications() {
        PSK__c office = PSK_TestDataFactory.createOffice();
        Slot__c slot = PSK_TestDataFactory.createSlot(office.Id, 5);
        Passport_Application__c app = PSK_TestDataFactory.createApplication(
            PSK_Constants.STATUS_CANCELLED);

        Boolean threw = false;
        try {
            PSK_SlotBookingController.book(app.Id, slot.Id);
        } catch (AuraHandledException e) {
            threw = true;
        }
        System.assertEquals(true, threw, 'A cancelled application cannot book an appointment');
    }

    @IsTest
    static void testBookWithMissingArgumentsThrows() {
        Boolean threw = false;
        try {
            PSK_SlotBookingController.book(null, null);
        } catch (AuraHandledException e) {
            threw = true;
        }
        System.assertEquals(true, threw);
    }

    @IsTest
    static void testCancelFreesTheSlotForRebooking() {
        PSK__c office = PSK_TestDataFactory.createOffice();
        Slot__c slot = PSK_TestDataFactory.createSlot(office.Id, 5);
        Passport_Application__c app = PSK_TestDataFactory.createApplication(
            PSK_Constants.STATUS_SUBMITTED);

        PSK_SlotBookingController.BookingResult booked =
            PSK_SlotBookingController.book(app.Id, slot.Id);

        Test.startTest();
        PSK_SlotBookingController.BookingResult cancelled =
            PSK_SlotBookingController.cancel(booked.appointmentId);
        // The application should now be free to book again.
        PSK_SlotBookingController.BookingResult rebooked =
            PSK_SlotBookingController.book(app.Id, slot.Id);
        Test.stopTest();

        System.assertEquals('Cancelled', cancelled.status);
        System.assertNotEquals(null, rebooked.appointmentId,
            'Cancelling releases the one-live-appointment lock');
    }

    @IsTest
    static void testCancelWithBadIdThrows() {
        Boolean threw = false;
        try {
            PSK_SlotBookingController.cancel(null);
        } catch (AuraHandledException e) {
            threw = true;
        }
        System.assertEquals(true, threw);
    }
}
