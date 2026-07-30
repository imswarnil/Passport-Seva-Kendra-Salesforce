/**
 * Handler for PassportTrigger.
 *
 * Passport__c.Name IS the passport booklet number, and Salesforce cannot enforce
 * uniqueness on the standard Name field. External_Id__c therefore mirrors Name
 * and carries the unique constraint, and the validation rule
 * Passport__c/External_Id_Must_Mirror_Number enforces the mirroring:
 *
 *     AND(NOT(ISBLANK(Name)), External_Id__c <> Name)
 *
 * Note the rule also fails on a BLANK External_Id__c. Validation rules evaluate
 * AFTER before-triggers, so keeping the mirror in sync here turns that rule into
 * a harmless backstop and means a user creating a passport by hand in the UI
 * never has to know the field exists.
 */
public with sharing class PassportTriggerHandler {

    public static void beforeInsert(List<Passport__c> newList) {
        mirrorExternalId(newList);
        defaultDates(newList);
    }

    public static void beforeUpdate(List<Passport__c> newList, Map<Id, Passport__c> oldMap) {
        mirrorExternalId(newList);
        defaultDates(newList);
    }

    /**
     * Keep External_Id__c === Name. Deliberately NOT guarded by
     * PSK_AutomationControl.bypassTriggers: the mirror is a data-integrity
     * invariant backed by a validation rule, not business automation, so it must
     * hold even when the demo generator disables the rest of the automation.
     */
    @TestVisible
    private static void mirrorExternalId(List<Passport__c> records) {
        for (Passport__c p : records) {
            if (String.isNotBlank(p.Name) && p.External_Id__c != p.Name) {
                p.External_Id__c = p.Name;
            }
        }
    }

    /**
     * Passport__c/Active_Requires_Issue_And_Expiry_Dates requires both dates on
     * an Active booklet. Fill in sensible values rather than letting a
     * hand-created record fail.
     */
    @TestVisible
    private static void defaultDates(List<Passport__c> records) {
        if (PSK_AutomationControl.isBypassed()) {
            return;
        }
        for (Passport__c p : records) {
            if (p.Status__c != PSK_Constants.PASSPORT_ACTIVE) {
                continue;
            }
            if (p.Date_of_Issue__c == null) {
                p.Date_of_Issue__c = Date.today();
            }
            if (p.Date_of_Expiry__c == null) {
                // Validity_Years__c on Passport__c is a formula off the parent
                // application, so it is not readable in a before trigger. Ten
                // years is the standard adult booklet.
                p.Date_of_Expiry__c = p.Date_of_Issue__c.addYears(10);
            }
        }
    }
}
