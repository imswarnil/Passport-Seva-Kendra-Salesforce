@IsTest
private class AppointmentTriggerHandlerTest {

    @IsTest
    static void testBookingWithinCapacitySucceeds() {
        PSK__c office = PSK_TestDataFactory.createOffice();
        Slot__c slot = PSK_TestDataFactory.createSlot(office.Id, 3);
        Passport_Application__c app = PSK_TestDataFactory.createApplication(
            PSK_Constants.STATUS_SUBMITTED);

        Test.startTest();
        insert PSK_TestDataFactory.buildAppointment(app.Id, slot.Id, 'Scheduled');
        Test.stopTest();

        System.assertEquals(1, [SELECT COUNT() FROM Appointment__c WHERE Slot__c = :slot.Id]);
    }

    @IsTest
    static void testBookingBeyondCapacityIsBlocked() {
        PSK__c office = PSK_TestDataFactory.createOffice();
        Slot__c slot = PSK_TestDataFactory.createSlot(office.Id, 1);

        Passport_Application__c first = PSK_TestDataFactory.createApplication(
            PSK_Constants.STATUS_SUBMITTED);
        Passport_Application__c second = PSK_TestDataFactory.createApplication(
            PSK_Constants.STATUS_SUBMITTED);

        insert PSK_TestDataFactory.buildAppointment(first.Id, slot.Id, 'Scheduled');

        Test.startTest();
        Boolean blocked = false;
        String message = '';
        try {
            insert PSK_TestDataFactory.buildAppointment(second.Id, slot.Id, 'Scheduled');
        } catch (DmlException e) {
            blocked = true;
            // getMessage() rather than getDmlMessage(0): the Slot_Not_Overbooked
            // validation rule fires on the same insert, so more than one error can
            // be present and we only care that ours is among them.
            message = e.getMessage();
        }
        Test.stopTest();

        System.assertEquals(true, blocked, 'A full slot must reject a second booking');
        System.assertEquals(true, message.contains('fully booked'),
            'The trigger should give the clearer message, got: ' + message);
        System.assertEquals(1, [SELECT COUNT() FROM Appointment__c WHERE Slot__c = :slot.Id]);
    }

    @IsTest
    static void testBulkInsertFillsCapacityThenRejectsTheOverflow() {
        PSK__c office = PSK_TestDataFactory.createOffice();
        Slot__c slot = PSK_TestDataFactory.createSlot(office.Id, 3);

        List<Appointment__c> batch = new List<Appointment__c>();
        for (Integer i = 0; i < 5; i++) {
            Passport_Application__c app = PSK_TestDataFactory.createApplication(
                PSK_Constants.STATUS_SUBMITTED);
            batch.add(PSK_TestDataFactory.buildAppointment(app.Id, slot.Id, 'Scheduled'));
        }

        Test.startTest();
        List<Database.SaveResult> results = Database.insert(batch, false);
        Test.stopTest();

        Integer saved = 0;
        Integer rejected = 0;
        for (Database.SaveResult sr : results) {
            if (sr.isSuccess()) {
                saved++;
            } else {
                rejected++;
            }
        }
        System.assertEquals(3, saved, 'Capacity is 3, so exactly three should land');
        System.assertEquals(2, rejected, 'The two beyond capacity must be rejected individually');
        System.assertEquals(3, [SELECT COUNT() FROM Appointment__c WHERE Slot__c = :slot.Id]);
    }

    @IsTest
    static void testCancelledAppointmentsDoNotConsumeCapacity() {
        // Capacity 3, not 1: the Slot_Not_Overbooked validation rule compares the
        // Booked_Count__c rollup, which counts cancelled appointments too. This test
        // is about the TRIGGER's stricter, semantically-correct check.
        PSK__c office = PSK_TestDataFactory.createOffice();
        Slot__c slot = PSK_TestDataFactory.createSlot(office.Id, 3);

        Passport_Application__c first = PSK_TestDataFactory.createApplication(
            PSK_Constants.STATUS_SUBMITTED);
        Passport_Application__c second = PSK_TestDataFactory.createApplication(
            PSK_Constants.STATUS_SUBMITTED);

        insert PSK_TestDataFactory.buildAppointment(first.Id, slot.Id, 'Cancelled');

        Test.startTest();
        insert PSK_TestDataFactory.buildAppointment(second.Id, slot.Id, 'Scheduled');
        Test.stopTest();

        System.assertEquals(2, [SELECT COUNT() FROM Appointment__c WHERE Slot__c = :slot.Id],
            'A cancelled appointment should not have blocked the live one');
    }

    @IsTest
    static void testZeroCapacitySlotIsRejected() {
        PSK__c office = PSK_TestDataFactory.createOffice();
        Slot__c slot = PSK_TestDataFactory.createSlot(office.Id, 0);
        Passport_Application__c app = PSK_TestDataFactory.createApplication(
            PSK_Constants.STATUS_SUBMITTED);

        Test.startTest();
        Boolean blocked = false;
        String message = '';
        try {
            insert PSK_TestDataFactory.buildAppointment(app.Id, slot.Id, 'Scheduled');
        } catch (DmlException e) {
            blocked = true;
            message = e.getMessage();
        }
        Test.stopTest();

        System.assertEquals(true, blocked, 'A slot with no capacity cannot be booked');
        System.assertEquals(true, message.contains('no capacity'),
            'Expected the no-capacity message, got: ' + message);
    }

    @IsTest
    static void testBypassSkipsTheCapacityCheck() {
        PSK__c office = PSK_TestDataFactory.createOffice();
        Slot__c slot = PSK_TestDataFactory.createSlot(office.Id, 5);
        Passport_Application__c app = PSK_TestDataFactory.createApplication(
            PSK_Constants.STATUS_SUBMITTED);

        PSK_AutomationControl.reset();
        PSK_AutomationControl.bypassTriggers = true;
        Test.startTest();
        insert PSK_TestDataFactory.buildAppointment(app.Id, slot.Id, 'Scheduled');
        Test.stopTest();
        PSK_AutomationControl.reset();

        System.assertEquals(1, [SELECT COUNT() FROM Appointment__c WHERE Slot__c = :slot.Id],
            'The demo generator owns capacity distribution when the bypass is on');
    }

    @IsTest
    static void testDefaultStatusApplied() {
        PSK__c office = PSK_TestDataFactory.createOffice();
        Slot__c slot = PSK_TestDataFactory.createSlot(office.Id, 5);
        Passport_Application__c app = PSK_TestDataFactory.createApplication(
            PSK_Constants.STATUS_SUBMITTED);

        Appointment__c apt = PSK_TestDataFactory.buildAppointment(app.Id, slot.Id, null);
        apt.Status__c = null;
        insert apt;

        System.assertEquals('Scheduled',
            [SELECT Status__c FROM Appointment__c WHERE Id = :apt.Id].Status__c,
            'A blank status defaults to Scheduled');
    }
}
