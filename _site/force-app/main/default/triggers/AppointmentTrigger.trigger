/**
 * Race-safe slot capacity enforcement. Logic lives in AppointmentTriggerHandler.
 */
trigger AppointmentTrigger on Appointment__c (before insert) {
    AppointmentTriggerHandler.beforeInsert(Trigger.new);
}
