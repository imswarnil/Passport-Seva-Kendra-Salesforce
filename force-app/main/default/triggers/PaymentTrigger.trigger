/**
 * Payment rollup to the parent application. Logic lives in PaymentTriggerHandler.
 */
trigger PaymentTrigger on Payment__c (
    after insert, after update, after delete, after undelete
) {
    PaymentTriggerHandler.afterChange(
        Trigger.isDelete ? null : Trigger.new,
        (Trigger.isInsert || Trigger.isUndelete) ? null : Trigger.old
    );
}
