/**
 * Status-transition actions surfaced as quick-action buttons on the
 * Passport Application record page sidebar (pskApplicationSidebar LWC).
 */
public with sharing class PSK_ApplicationActionsController {

    public class ActionResult {
        @AuraEnabled public String newStatus;
        @AuraEnabled public String message;
    }

    private static final Map<String, String> NEXT_STATUS = new Map<String, String>{
        'Draft' => 'Submitted',
        'Submitted' => 'Payment Pending',
        'Payment Pending' => 'Paid',
        'Paid' => 'Document Verification',
        'Document Verification' => 'Police Verification',
        'Police Verification' => 'Granting',
        'Granting' => 'Printing',
        'Printing' => 'Dispatch',
        'Dispatch' => 'Delivered'
    };

    @AuraEnabled
    public static ActionResult advance(Id applicationId) {
        Passport_Application__c app = [
            SELECT Id, Status__c, Payment_Status__c, Police_Verification_Type__c
            FROM Passport_Application__c
            WHERE Id = :applicationId
            WITH SECURITY_ENFORCED
            LIMIT 1
        ];

        String current = app.Status__c;
        if (!NEXT_STATUS.containsKey(current)) {
            throw new AuraHandledException('No further quick action available from status "' + current + '".');
        }
        String next = NEXT_STATUS.get(current);

        if (current == 'Draft') {
            app.Submitted_Date__c = System.now();
        }
        if (current == 'Payment Pending') {
            app.Payment_Status__c = 'Paid';
        }
        if (current == 'Document Verification') {
            app.Documents_Verified__c = true;
            insert new Police_Verification__c(
                Passport_Application__c = applicationId,
                Status__c = 'Referred',
                PV_Type__c = String.isBlank(app.Police_Verification_Type__c) ? 'Post-PV' : app.Police_Verification_Type__c,
                Referred_Date__c = Date.today()
            );
        }
        if (current == 'Police Verification') {
            List<Police_Verification__c> pvs = [
                SELECT Id, Status__c, Report_Received_Date__c
                FROM Police_Verification__c
                WHERE Passport_Application__c = :applicationId
                ORDER BY CreatedDate DESC
                LIMIT 1
            ];
            if (!pvs.isEmpty()) {
                pvs[0].Status__c = 'Cleared';
                pvs[0].Report_Received_Date__c = Date.today();
                update pvs[0];
            }
        }
        if (next == 'Granting') {
            app.Payment_Status__c = 'Paid';
            app.Granted_Date__c = System.now();
        }

        app.Status__c = next;
        app.Stage_Entered_Date__c = System.now();
        update app;

        ActionResult result = new ActionResult();
        result.newStatus = next;
        result.message = 'Application moved to ' + next + '.';
        return result;
    }

    @AuraEnabled
    public static ActionResult reject(Id applicationId) {
        Passport_Application__c app = [
            SELECT Id, Status__c
            FROM Passport_Application__c
            WHERE Id = :applicationId
            WITH SECURITY_ENFORCED
            LIMIT 1
        ];
        if (app.Status__c == 'Delivered' || app.Status__c == 'Rejected' || app.Status__c == 'Cancelled') {
            throw new AuraHandledException('Cannot reject an application in status "' + app.Status__c + '".');
        }
        app.Status__c = 'Rejected';
        app.Stage_Entered_Date__c = System.now();
        update app;

        ActionResult result = new ActionResult();
        result.newStatus = 'Rejected';
        result.message = 'Application rejected.';
        return result;
    }
}
