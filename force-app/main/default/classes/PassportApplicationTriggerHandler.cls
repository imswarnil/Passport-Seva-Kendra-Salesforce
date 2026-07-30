/**
 * Handler for PassportApplicationTrigger.
 *
 * Responsibilities
 *  - stamp Submitted_Date__c / Stage_Entered_Date__c / Granted_Date__c
 *  - copy snapshot fields from the linked Citizen__c, but ONLY when blank, so the
 *    as-submitted snapshot is never overwritten by later citizen edits
 *  - reverse-create or match a Citizen__c when an application arrives without one
 *    (this is what keeps the pskHomeDashboard inline quick-create working)
 *  - compute Fee__c from Fee_Matrix__mdt
 *  - create Passport__c + Print_Job__c on entering Printing, Dispatch__c on
 *    entering Dispatch -- idempotently
 *
 * Everything short-circuits on PSK_AutomationControl.bypassTriggers so the demo
 * data generator can own child records deterministically.
 */
public with sharing class PassportApplicationTriggerHandler {

    // ------------------------------------------------------------ Before insert

    public static void beforeInsert(List<Passport_Application__c> newList) {
        if (PSK_AutomationControl.isBypassed()) {
            return;
        }
        PSK_ApplicationService.ensureCitizens(newList);
        PSK_ApplicationService.copyFromCitizenWhenBlank(newList);
        stampDates(newList, null);
        PSK_ApplicationService.applyFees(newList, null);
        applyDefaults(newList);
    }

    // ------------------------------------------------------------ Before update

    public static void beforeUpdate(List<Passport_Application__c> newList,
                                    Map<Id, Passport_Application__c> oldMap) {
        if (PSK_AutomationControl.isBypassed()) {
            return;
        }
        PSK_ApplicationService.copyFromCitizenWhenBlank(newList);
        stampDates(newList, oldMap);
        PSK_ApplicationService.applyFees(newList, oldMap);
        applyDefaults(newList);
    }

    // ------------------------------------------------------------- After insert

    public static void afterInsert(List<Passport_Application__c> newList) {
        if (PSK_AutomationControl.isBypassed()) {
            return;
        }
        handleFulfilment(newList, null);
    }

    // ------------------------------------------------------------- After update

    public static void afterUpdate(List<Passport_Application__c> newList,
                                   Map<Id, Passport_Application__c> oldMap) {
        if (PSK_AutomationControl.isBypassed() || PSK_AutomationControl.inPaymentRollup) {
            return;
        }
        handleFulfilment(newList, oldMap);
    }

    // ------------------------------------------------------------------ Internals

    /**
     * Submitted_Date__c is stamped the first time the record leaves Draft.
     * Stage_Entered_Date__c is refreshed on every status change.
     * Granted_Date__c is stamped when the record enters Granting.
     */
    @TestVisible
    private static void stampDates(List<Passport_Application__c> newList,
                                   Map<Id, Passport_Application__c> oldMap) {
        DateTime nowStamp = System.now();
        for (Passport_Application__c app : newList) {
            String priorStatus = null;
            if (oldMap != null && app.Id != null && oldMap.containsKey(app.Id)) {
                priorStatus = oldMap.get(app.Id).Status__c;
            }
            Boolean isInsert = (oldMap == null);
            Boolean statusChanged = (priorStatus != app.Status__c);

            if (isInsert) {
                // An insert is not a transition FROM anything, so an explicitly
                // supplied stage clock (a data load, a backdated migration) is
                // respected. Only fill the gap.
                if (app.Stage_Entered_Date__c == null) {
                    app.Stage_Entered_Date__c = nowStamp;
                }
            } else if (statusChanged) {
                app.Stage_Entered_Date__c = nowStamp;
            }

            Boolean leftDraft = app.Status__c != PSK_Constants.STATUS_DRAFT
                && (priorStatus == null || priorStatus == PSK_Constants.STATUS_DRAFT);
            if (leftDraft && app.Submitted_Date__c == null) {
                app.Submitted_Date__c = nowStamp;
            }

            Boolean enteringGranting = app.Status__c == PSK_Constants.STATUS_GRANTING
                && priorStatus != PSK_Constants.STATUS_GRANTING;
            if (enteringGranting && app.Granted_Date__c == null) {
                app.Granted_Date__c = nowStamp;
            }
            // Anything at or beyond Granting must carry a granted date for reporting.
            if (app.Granted_Date__c == null
                    && PSK_Constants.isAtOrBeyond(app.Status__c, PSK_Constants.STATUS_GRANTING)) {
                app.Granted_Date__c = nowStamp;
            }
        }
    }

    /**
     * Defensive defaults so records survive the validation rules on the object.
     * Never flips a value the user explicitly set.
     */
    @TestVisible
    private static void applyDefaults(List<Passport_Application__c> newList) {
        for (Passport_Application__c app : newList) {
            if (String.isBlank(app.Status__c)) {
                app.Status__c = PSK_Constants.STATUS_DRAFT;
            }
            if (String.isBlank(app.Payment_Status__c)) {
                app.Payment_Status__c = PSK_Constants.PAY_NOT_PAID;
            }
            if (String.isBlank(app.Country__c)) {
                app.Country__c = 'India';
            }
            // Cannot_Grant_With_Pending_Payment: Granting and beyond require Paid.
            if (PSK_Constants.REQUIRES_PAID.contains(app.Status__c)
                    && app.Payment_Status__c != PSK_Constants.PAY_PAID) {
                app.Payment_Status__c = PSK_Constants.PAY_PAID;
            }
            if (app.Payment_Status__c == PSK_Constants.PAY_PAID && app.Payment_Date__c == null) {
                app.Payment_Date__c = System.now();
            }
            if (app.Status__c == PSK_Constants.STATUS_DOC_VERIFICATION
                    || PSK_Constants.isAtOrBeyond(app.Status__c, PSK_Constants.STATUS_POLICE_VERIFICATION)) {
                if (app.Documents_Verified__c != true
                        && PSK_Constants.isAtOrBeyond(app.Status__c, PSK_Constants.STATUS_POLICE_VERIFICATION)) {
                    app.Documents_Verified__c = true;
                }
            }
        }
    }

    /**
     * Create the downstream fulfilment artefacts when an application enters
     * Printing or Dispatch. Both branches are idempotent; PSK_ApplicationService
     * checks for existing children before inserting.
     */
    private static void handleFulfilment(List<Passport_Application__c> newList,
                                         Map<Id, Passport_Application__c> oldMap) {
        Set<Id> enteringPrinting = new Set<Id>();
        Set<Id> enteringDispatch = new Set<Id>();

        for (Passport_Application__c app : newList) {
            String priorStatus = (oldMap != null && oldMap.containsKey(app.Id))
                ? oldMap.get(app.Id).Status__c : null;
            if (app.Status__c == priorStatus) {
                continue;
            }
            if (app.Status__c == PSK_Constants.STATUS_PRINTING) {
                enteringPrinting.add(app.Id);
            } else if (app.Status__c == PSK_Constants.STATUS_DISPATCH) {
                // Dispatch implies the booklet exists -- back-fill if the record
                // skipped straight past Printing.
                enteringPrinting.add(app.Id);
                enteringDispatch.add(app.Id);
            }
        }

        // The issuance guard applies to booklet creation ONLY. A record that was
        // issued earlier in this same transaction still needs its dispatch when it
        // moves on to Dispatch, so this must not short-circuit enteringDispatch.
        enteringPrinting.removeAll(PSK_AutomationControl.issuanceProcessed);

        if (!enteringPrinting.isEmpty()) {
            PSK_ApplicationService.issuePassports(enteringPrinting);
            PSK_AutomationControl.issuanceProcessed.addAll(enteringPrinting);
        }
        if (!enteringDispatch.isEmpty()) {
            PSK_ApplicationService.createDispatches(enteringDispatch);
        }
    }
}
