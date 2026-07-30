/**
 * Appointment slot picker for the Passport Application record page.
 *
 * Capacity is enforced by AppointmentTrigger (FOR UPDATE), not here -- this
 * class only surfaces the choices and translates the trigger's addError into a
 * friendly AuraHandledException.
 */
public with sharing class PSK_SlotBookingController {

    public class OfficeOption {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public String officeCode;
        @AuraEnabled public String city;
        @AuraEnabled public String state;
        @AuraEnabled public String region;
        @AuraEnabled public Integer capacityPerDay;
    }

    public class SlotOption {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public Date slotDate;
        @AuraEnabled public String startTime;
        @AuraEnabled public String endTime;
        @AuraEnabled public Integer capacity;
        @AuraEnabled public Integer booked;
        @AuraEnabled public Integer available;
        @AuraEnabled public Boolean isAvailable;
        @AuraEnabled public String label;
    }

    public class BookingResult {
        @AuraEnabled public Id appointmentId;
        @AuraEnabled public Id slotId;
        @AuraEnabled public String appointmentName;
        @AuraEnabled public String status;
        @AuraEnabled public String message;
    }

    @AuraEnabled(cacheable=true)
    public static List<OfficeOption> getOffices() {
        List<OfficeOption> options = new List<OfficeOption>();
        for (PSK__c office : [
            SELECT Id, Name, Office_Code__c, City__c, State__c, Region__c, Capacity_Per_Day__c
            FROM PSK__c
            WHERE Is_Active__c = true
            WITH USER_MODE
            ORDER BY State__c, Name
            LIMIT 200
        ]) {
            OfficeOption o = new OfficeOption();
            o.id = office.Id;
            o.name = office.Name;
            o.officeCode = office.Office_Code__c;
            o.city = office.City__c;
            o.state = office.State__c;
            o.region = office.Region__c;
            o.capacityPerDay = office.Capacity_Per_Day__c == null
                ? null : office.Capacity_Per_Day__c.intValue();
            options.add(o);
        }
        return options;
    }

    /**
     * Slots at an office on a given day. Pass a null date for "today onwards".
     */
    @AuraEnabled(cacheable=true)
    public static List<SlotOption> getAvailableSlots(Id officeId, Date d) {
        if (officeId == null) {
            return new List<SlotOption>();
        }
        Date fromDate = (d == null) ? Date.today() : d;
        Date toDate = (d == null) ? Date.today().addDays(30) : d;

        List<Slot__c> slots = [
            SELECT Id, Name, Slot_Date__c, Start_Time__c, End_Time__c, Capacity__c,
                   Booked_Count__c, Is_Available__c
            FROM Slot__c
            WHERE PSK_Office__c = :officeId
              AND Slot_Date__c >= :fromDate
              AND Slot_Date__c <= :toDate
            WITH USER_MODE
            ORDER BY Slot_Date__c, Start_Time__c
            LIMIT 500
        ];

        List<SlotOption> out = new List<SlotOption>();
        for (Slot__c s : slots) {
            SlotOption o = new SlotOption();
            o.id = s.Id;
            o.name = s.Name;
            o.slotDate = s.Slot_Date__c;
            o.startTime = formatTime(s.Start_Time__c);
            o.endTime = formatTime(s.End_Time__c);
            o.capacity = s.Capacity__c == null ? 0 : s.Capacity__c.intValue();
            o.booked = s.Booked_Count__c == null ? 0 : s.Booked_Count__c.intValue();
            o.available = o.capacity - o.booked;
            o.isAvailable = (o.available > 0);
            o.label = (s.Slot_Date__c == null ? '' : s.Slot_Date__c.format())
                + ' ' + o.startTime + '-' + o.endTime
                + ' (' + o.available + ' of ' + o.capacity + ' free)';
            out.add(o);
        }
        return out;
    }

    @AuraEnabled
    public static BookingResult book(Id applicationId, Id slotId) {
        if (applicationId == null || slotId == null) {
            throw new AuraHandledException('Both an application and a slot are required.');
        }
        if (!Schema.sObjectType.Appointment__c.isCreateable()) {
            throw new AuraHandledException('You do not have permission to book appointments.');
        }

        List<Passport_Application__c> apps = [
            SELECT Id, Name, Status__c
            FROM Passport_Application__c
            WHERE Id = :applicationId
            WITH USER_MODE
            LIMIT 1
        ];
        if (apps.isEmpty()) {
            throw new AuraHandledException('Application not found, or you do not have access to it.');
        }
        if (PSK_Constants.TERMINAL_STATUSES.contains(apps[0].Status__c)) {
            throw new AuraHandledException(
                'An appointment cannot be booked for an application in status "'
                + apps[0].Status__c + '".'
            );
        }

        // One live appointment per application.
        List<Appointment__c> live = [
            SELECT Id, Slot__c, Status__c
            FROM Appointment__c
            WHERE Passport_Application__c = :applicationId
              AND Status__c IN ('Scheduled', 'Checked In')
            WITH USER_MODE
            LIMIT 1
        ];
        if (!live.isEmpty()) {
            throw new AuraHandledException(
                'This application already has a live appointment. Cancel it before booking another.'
            );
        }

        Appointment__c apt = new Appointment__c(
            Passport_Application__c = applicationId,
            Slot__c = slotId,
            Status__c = 'Scheduled'
        );
        apt.External_Id__c = 'APT-' + applicationId + '-' + slotId;

        try {
            insert apt;
        } catch (DmlException e) {
            // The FOR UPDATE capacity check in AppointmentTriggerHandler surfaces here.
            throw new AuraHandledException(e.getDmlMessage(0));
        }

        BookingResult r = new BookingResult();
        r.appointmentId = apt.Id;
        r.slotId = slotId;
        r.status = 'Scheduled';
        List<Appointment__c> saved = [
            SELECT Name FROM Appointment__c WHERE Id = :apt.Id WITH USER_MODE LIMIT 1
        ];
        r.appointmentName = saved.isEmpty() ? null : saved[0].Name;
        r.message = 'Appointment booked.';
        return r;
    }

    /** Release a slot so the applicant can rebook. */
    @AuraEnabled
    public static BookingResult cancel(Id appointmentId) {
        if (appointmentId == null) {
            throw new AuraHandledException('An appointment id is required.');
        }
        List<Appointment__c> apts = [
            SELECT Id, Name, Slot__c, Status__c
            FROM Appointment__c
            WHERE Id = :appointmentId
            WITH USER_MODE
            LIMIT 1
        ];
        if (apts.isEmpty()) {
            throw new AuraHandledException('Appointment not found, or you do not have access to it.');
        }
        Appointment__c apt = apts[0];
        apt.Status__c = 'Cancelled';
        try {
            update apt;
        } catch (DmlException e) {
            throw new AuraHandledException(e.getDmlMessage(0));
        }

        BookingResult r = new BookingResult();
        r.appointmentId = apt.Id;
        r.appointmentName = apt.Name;
        r.slotId = apt.Slot__c;
        r.status = 'Cancelled';
        r.message = 'Appointment cancelled.';
        return r;
    }

    private static String formatTime(Time t) {
        if (t == null) {
            return '--:--';
        }
        return String.valueOf(t.hour()).leftPad(2, '0') + ':'
            + String.valueOf(t.minute()).leftPad(2, '0');
    }
}
