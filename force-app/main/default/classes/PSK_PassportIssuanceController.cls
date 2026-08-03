/**
 * "Issue Passport" action for the Passport Application record page.
 *
 * Delegates to PSK_ApplicationService so this produces exactly the same
 * Passport__c + Print_Job__c pair as the automatic issuance that fires when an
 * application enters Printing. Calling it twice is safe -- the second call
 * returns the existing booklet with created = false.
 */
public with sharing class PSK_PassportIssuanceController {

    @AuraEnabled
    public static PSK_ApplicationService.IssuanceResult issue(Id applicationId) {
        if (applicationId == null) {
            throw PSK_ApplicationService.auraError('An application id is required.');
        }

        List<Passport_Application__c> apps = [
            SELECT Id, Name, Status__c, Payment_Status__c, First_Name__c, Last_Name__c,
                   Citizen__c, PSK_Office__c, Passport_Category__c
            FROM Passport_Application__c
            WHERE Id = :applicationId
            WITH USER_MODE
            LIMIT 1
        ];
        if (apps.isEmpty()) {
            throw PSK_ApplicationService.auraError('Application not found, or you do not have access to it.');
        }
        Passport_Application__c app = apps[0];

        if (!Schema.sObjectType.Passport__c.isCreateable()) {
            throw PSK_ApplicationService.auraError('You do not have permission to create passports.');
        }
        if (app.Status__c == PSK_Constants.STATUS_REJECTED
                || app.Status__c == PSK_Constants.STATUS_CANCELLED) {
            throw PSK_ApplicationService.auraError(
                'A passport cannot be issued for an application in status "' + app.Status__c + '".'
            );
        }
        if (app.Payment_Status__c != PSK_Constants.PAY_PAID) {
            throw PSK_ApplicationService.auraError(
                'The application fee must be fully paid before a passport can be issued.'
            );
        }
        if (!PSK_Constants.isAtOrBeyond(app.Status__c, PSK_Constants.STATUS_GRANTING)) {
            throw PSK_ApplicationService.auraError(
                'The application must reach Granting before a passport can be issued. Current status: '
                + app.Status__c + '.'
            );
        }

        Map<Id, PSK_ApplicationService.IssuanceResult> results =
            PSK_ApplicationService.issuePassports(new Set<Id>{ applicationId });

        PSK_ApplicationService.IssuanceResult result = results.get(applicationId);
        if (result == null) {
            throw PSK_ApplicationService.auraError('Passport issuance did not return a result.');
        }
        if (result.passportId == null) {
            throw PSK_ApplicationService.auraError(
                String.isBlank(result.message) ? 'Passport issuance failed.' : result.message
            );
        }

        // Mark it handled so a subsequent status change to Printing in the same
        // transaction does not attempt a duplicate.
        PSK_AutomationControl.issuanceProcessed.add(applicationId);
        return result;
    }

    /**
     * Read-only companion so the LWC can render the button in the right state
     * without attempting the action.
     */
    @AuraEnabled(cacheable=true)
    public static IssuanceEligibility checkEligibility(Id applicationId) {
        IssuanceEligibility e = new IssuanceEligibility();
        e.eligible = false;
        if (applicationId == null) {
            e.reason = 'No application selected.';
            return e;
        }

        List<Passport_Application__c> apps = [
            SELECT Id, Status__c, Payment_Status__c
            FROM Passport_Application__c
            WHERE Id = :applicationId
            WITH USER_MODE
            LIMIT 1
        ];
        if (apps.isEmpty()) {
            e.reason = 'Application not found.';
            return e;
        }

        Integer existing = [
            SELECT COUNT() FROM Passport__c WHERE Application__c = :applicationId WITH USER_MODE
        ];
        if (existing > 0) {
            e.alreadyIssued = true;
            e.reason = 'A passport has already been issued for this application.';
            return e;
        }

        Passport_Application__c app = apps[0];
        if (app.Payment_Status__c != PSK_Constants.PAY_PAID) {
            e.reason = 'The application fee is not fully paid.';
            return e;
        }
        if (!PSK_Constants.isAtOrBeyond(app.Status__c, PSK_Constants.STATUS_GRANTING)) {
            e.reason = 'The application has not reached Granting yet.';
            return e;
        }
        e.eligible = true;
        e.reason = 'Ready to issue.';
        return e;
    }

    public class IssuanceEligibility {
        @AuraEnabled public Boolean eligible;
        @AuraEnabled public Boolean alreadyIssued = false;
        @AuraEnabled public String reason;
    }
}
