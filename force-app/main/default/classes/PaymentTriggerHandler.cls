/**
 * Handler for PaymentTrigger.
 *
 * Rolls the total of SUCCESSFUL Payment__c records up to the parent application
 * and derives Payment_Status__c:
 *   collected >= Fee__c   -> Paid
 *   collected > 0         -> Pending
 *   nothing collected, but a payment exists and every one of them failed -> Failed
 *   only refunds          -> Refunded
 *   otherwise             -> Not Paid
 *
 * A rollup summary field cannot express that, hence the trigger. Never changes
 * Status__c, so the PRIORVALUE-based backward-move validation rule is untouched.
 */
public with sharing class PaymentTriggerHandler {

    public static void afterChange(List<Payment__c> newList, List<Payment__c> oldList) {
        if (PSK_AutomationControl.isBypassed() || PSK_AutomationControl.inPaymentRollup) {
            return;
        }
        Set<Id> appIds = new Set<Id>();
        if (newList != null) {
            for (Payment__c p : newList) {
                if (p.Passport_Application__c != null) {
                    appIds.add(p.Passport_Application__c);
                }
            }
        }
        if (oldList != null) {
            for (Payment__c p : oldList) {
                if (p.Passport_Application__c != null) {
                    appIds.add(p.Passport_Application__c);
                }
            }
        }
        recalculate(appIds);
    }

    /**
     * Recompute payment state for the given applications. Public so the demo
     * generator and admin scripts can reconcile after a bulk load.
     */
    public static void recalculate(Set<Id> applicationIds) {
        if (applicationIds == null || applicationIds.isEmpty()) {
            return;
        }

        Map<Id, Decimal> collected = new Map<Id, Decimal>();
        Map<Id, Decimal> refunded = new Map<Id, Decimal>();
        Map<Id, Integer> counts = new Map<Id, Integer>();
        Map<Id, Integer> failures = new Map<Id, Integer>();

        for (Id appId : applicationIds) {
            collected.put(appId, 0);
            refunded.put(appId, 0);
            counts.put(appId, 0);
            failures.put(appId, 0);
        }

        for (Payment__c p : [
            SELECT Id, Passport_Application__c, Status__c, Amount__c, Payment_Date__c, Payment_Mode__c
            FROM Payment__c
            WHERE Passport_Application__c IN :applicationIds
        ]) {
            Id appId = p.Passport_Application__c;
            Decimal amount = p.Amount__c == null ? 0 : p.Amount__c;
            counts.put(appId, counts.get(appId) + 1);
            if (p.Status__c == PSK_Constants.PAYMENT_SUCCESS) {
                collected.put(appId, collected.get(appId) + amount);
            } else if (p.Status__c == PSK_Constants.PAYMENT_REFUNDED) {
                refunded.put(appId, refunded.get(appId) + amount);
            } else if (p.Status__c == PSK_Constants.PAYMENT_FAILED) {
                failures.put(appId, failures.get(appId) + 1);
            }
        }

        List<Passport_Application__c> toUpdate = new List<Passport_Application__c>();
        for (Passport_Application__c app : [
            SELECT Id, Fee__c, Payment_Status__c, Status__c, Payment_Date__c
            FROM Passport_Application__c
            WHERE Id IN :applicationIds
        ]) {
            Decimal paid = collected.get(app.Id);
            Decimal fee = (app.Fee__c == null || app.Fee__c <= 0) ? null : app.Fee__c;
            Integer total = counts.get(app.Id);

            String derived;
            if (paid > 0 && (fee == null || paid >= fee)) {
                derived = PSK_Constants.PAY_PAID;
            } else if (paid > 0) {
                derived = PSK_Constants.PAY_PENDING;
            } else if (refunded.get(app.Id) > 0) {
                derived = PSK_Constants.PAY_REFUNDED;
            } else if (total > 0 && failures.get(app.Id) == total) {
                derived = PSK_Constants.PAY_FAILED;
            } else if (total > 0) {
                derived = PSK_Constants.PAY_PENDING;
            } else {
                derived = PSK_Constants.PAY_NOT_PAID;
            }

            // Never downgrade an application that has already been granted --
            // Cannot_Grant_With_Pending_Payment would reject the update.
            if (PSK_Constants.REQUIRES_PAID.contains(app.Status__c)) {
                derived = PSK_Constants.PAY_PAID;
            }

            Boolean changed = (app.Payment_Status__c != derived);
            if (derived == PSK_Constants.PAY_PAID && app.Payment_Date__c == null) {
                app.Payment_Date__c = System.now();
                changed = true;
            }
            if (changed) {
                app.Payment_Status__c = derived;
                toUpdate.add(app);
            }
        }

        if (toUpdate.isEmpty()) {
            return;
        }

        Boolean prior = PSK_AutomationControl.inPaymentRollup;
        PSK_AutomationControl.inPaymentRollup = true;
        try {
            // Partial success: one bad parent (for example one failing a
            // concurrently-added validation rule) must not block the rest.
            Database.update(toUpdate, false);
        } finally {
            PSK_AutomationControl.inPaymentRollup = prior;
        }
    }
}
