/**
 * All Passport_Application__c automation. Logic lives in
 * PassportApplicationTriggerHandler -- keep this file a pure dispatcher.
 */
trigger PassportApplicationTrigger on Passport_Application__c (
    before insert, before update, after insert, after update
) {
    if (Trigger.isBefore) {
        if (Trigger.isInsert) {
            PassportApplicationTriggerHandler.beforeInsert(Trigger.new);
        } else if (Trigger.isUpdate) {
            PassportApplicationTriggerHandler.beforeUpdate(Trigger.new, Trigger.oldMap);
        }
    } else {
        if (Trigger.isInsert) {
            PassportApplicationTriggerHandler.afterInsert(Trigger.new);
        } else if (Trigger.isUpdate) {
            PassportApplicationTriggerHandler.afterUpdate(Trigger.new, Trigger.oldMap);
        }
    }
}
