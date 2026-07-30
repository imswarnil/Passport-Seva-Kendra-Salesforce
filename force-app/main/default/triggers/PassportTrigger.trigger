/**
 * Keeps Passport__c.External_Id__c mirroring the booklet number in Name, which
 * the External_Id_Must_Mirror_Number validation rule requires. Logic lives in
 * PassportTriggerHandler.
 */
trigger PassportTrigger on Passport__c (before insert, before update) {
    if (Trigger.isInsert) {
        PassportTriggerHandler.beforeInsert(Trigger.new);
    } else {
        PassportTriggerHandler.beforeUpdate(Trigger.new, Trigger.oldMap);
    }
}
