/**
 * Handler for AppointmentTrigger.
 *
 * Enforces slot capacity in a race-safe way. A validation rule (or a check
 * against the Booked_Count__c rollup) cannot be race safe: two concurrent
 * bookings both read the same pre-booking count and both pass. Locking the
 * parent Slot__c rows with FOR UPDATE serialises concurrent transactions so the
 * second one sees the first one's appointment.
 */
public with sharing class AppointmentTriggerHandler {

    public static final String ERR_SLOT_FULL =
        'This appointment slot is already fully booked. Please pick another slot.';
    public static final String ERR_SLOT_MISSING =
        'The appointment slot could not be found or is no longer available.';
    public static final String ERR_SLOT_INACTIVE =
        'Appointments cannot be booked against a slot with no capacity configured.';

    /** Appointment statuses that do NOT consume capacity. */
    private static final Set<String> NON_CONSUMING = new Set<String>{ 'Cancelled', 'No Show' };

    public static void beforeInsert(List<Appointment__c> newList) {
        if (PSK_AutomationControl.isBypassed()) {
            return;
        }

        Map<Id, Integer> requestedPerSlot = new Map<Id, Integer>();
        for (Appointment__c apt : newList) {
            if (apt.Slot__c == null || NON_CONSUMING.contains(apt.Status__c)) {
                continue;
            }
            Integer soFar = requestedPerSlot.containsKey(apt.Slot__c) ? requestedPerSlot.get(apt.Slot__c) : 0;
            requestedPerSlot.put(apt.Slot__c, soFar + 1);
        }
        if (requestedPerSlot.isEmpty()) {
            return;
        }

        Set<Id> slotIds = requestedPerSlot.keySet();

        // Serialise concurrent bookings on the same slot.
        Map<Id, Slot__c> slots = new Map<Id, Slot__c>();
        for (Slot__c s : [
            SELECT Id, Capacity__c, Slot_Date__c
            FROM Slot__c
            WHERE Id IN :slotIds
            FOR UPDATE
        ]) {
            slots.put(s.Id, s);
        }

        // Count committed appointments rather than trusting the rollup, which is
        // not guaranteed to be current inside the same transaction.
        Map<Id, Integer> bookedPerSlot = new Map<Id, Integer>();
        for (Id slotId : slotIds) {
            bookedPerSlot.put(slotId, 0);
        }
        for (AggregateResult ar : [
            SELECT Slot__c slotId, COUNT(Id) total
            FROM Appointment__c
            WHERE Slot__c IN :slotIds AND Status__c NOT IN :NON_CONSUMING
            GROUP BY Slot__c
        ]) {
            bookedPerSlot.put((Id) ar.get('slotId'), (Integer) ar.get('total'));
        }

        // Assign capacity in list order so only the overflowing rows fail.
        Map<Id, Integer> remaining = new Map<Id, Integer>();
        for (Id slotId : slotIds) {
            Slot__c s = slots.get(slotId);
            if (s == null) {
                remaining.put(slotId, -1);
                continue;
            }
            Integer capacity = s.Capacity__c == null ? 0 : s.Capacity__c.intValue();
            remaining.put(slotId, capacity - bookedPerSlot.get(slotId));
        }

        for (Appointment__c apt : newList) {
            if (apt.Slot__c == null || NON_CONSUMING.contains(apt.Status__c)) {
                continue;
            }
            Slot__c s = slots.get(apt.Slot__c);
            if (s == null) {
                apt.addError(ERR_SLOT_MISSING);
                continue;
            }
            if (s.Capacity__c == null || s.Capacity__c <= 0) {
                apt.addError(ERR_SLOT_INACTIVE);
                continue;
            }
            Integer left = remaining.get(apt.Slot__c);
            if (left <= 0) {
                apt.addError(ERR_SLOT_FULL);
                continue;
            }
            remaining.put(apt.Slot__c, left - 1);
            if (String.isBlank(apt.Status__c)) {
                apt.Status__c = 'Scheduled';
            }
        }
    }
}
