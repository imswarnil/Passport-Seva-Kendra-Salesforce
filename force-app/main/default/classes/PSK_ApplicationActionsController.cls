/**
 * Status-transition actions surfaced as quick-action buttons on the
 * Passport Application record page sidebar (pskApplicationSidebar LWC).
 */
public with sharing class PSK_ApplicationActionsController {

    public class ActionResult {
        @AuraEnabled public String newStatus;
        @AuraEnabled public String message;
    }

    /** What the sidebar needs to render the action buttons in the right state. */
    public class AvailableActions {
        @AuraEnabled public String currentStatus;
        @AuraEnabled public String nextStatus;
        @AuraEnabled public Boolean canAdvance;
        @AuraEnabled public Boolean canReject;
        @AuraEnabled public Boolean isTerminal;
        @AuraEnabled public String advanceLabel;
        @AuraEnabled public String blockedReason;
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
            SELECT Id, Status__c, Payment_Status__c, Police_Verification_Type__c,
                   City__c, District__c
            FROM Passport_Application__c
            WHERE Id = :applicationId
            WITH SECURITY_ENFORCED
            LIMIT 1
        ];

        String current = app.Status__c;
        if (!NEXT_STATUS.containsKey(current)) {
            // Delivered / Rejected / Cancelled are the ends of the line: the
            // application is finished, and No_Backward_Move_Once_Delivered would
            // reject any attempt to move a Delivered record anyway. Anything else
            // reaching here is an unrecognised status.
            throw PSK_ApplicationService.auraError(terminalMessage(current));
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
            // Referred_Requires_Station_And_Date: any verification past
            // 'Not Initiated' must name the station it was referred to, so the
            // record is stamped with the jurisdiction taken from the application's
            // own address rather than left blank for the officer to fill in.
            insert new Police_Verification__c(
                Passport_Application__c = applicationId,
                Status__c = 'Referred',
                PV_Type__c = String.isBlank(app.Police_Verification_Type__c) ? 'Post-PV' : app.Police_Verification_Type__c,
                Police_Station__c = policeStationFor(app),
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

    /**
     * Reject without recording a reason. Original signature, preserved for the
     * existing pskApplicationSidebar LWC and PSK_ApplicationActionsControllerTest.
     * Delegates so there is only one implementation.
     */
    @AuraEnabled
    public static ActionResult reject(Id applicationId) {
        return rejectWithReason(applicationId, null);
    }

    /**
     * Reject an application and record why. The reason is logged as an Objection__c
     * so it shows up on the application timeline rather than vanishing.
     *
     * NOTE ON NAMING: this is deliberately NOT an overload of reject(Id).
     * Salesforce does not permit overloaded @AuraEnabled methods -- the framework
     * indexes Apex actions by bare method name, and a class containing
     * @AuraEnabled reject(Id) plus reject(Id, String) fails to compile. Since
     * reject(Id) must keep its exact signature, the reason-carrying entry point
     * needs a distinct name. Call rejectWithReason from LWC.
     */
    @AuraEnabled
    public static ActionResult rejectWithReason(Id applicationId, String reason) {
        Passport_Application__c app = [
            SELECT Id, Status__c
            FROM Passport_Application__c
            WHERE Id = :applicationId
            WITH SECURITY_ENFORCED
            LIMIT 1
        ];
        if (app.Status__c == 'Delivered' || app.Status__c == 'Rejected' || app.Status__c == 'Cancelled') {
            throw PSK_ApplicationService.auraError('Cannot reject an application in status "' + app.Status__c + '".');
        }
        app.Status__c = 'Rejected';
        app.Stage_Entered_Date__c = System.now();
        update app;

        String trimmedReason = String.isBlank(reason) ? null : reason.trim();
        if (trimmedReason != null && Schema.sObjectType.Objection__c.isCreateable()) {
            // Best effort: a rejection must not fail because the audit trail could not
            // be written.
            Database.insert(
                new Objection__c(
                    Passport_Application__c = applicationId,
                    Objection_Type__c = 'Other',
                    Status__c = 'Escalated',
                    Raised_Date__c = Date.today(),
                    Description__c = trimmedReason.left(32000),
                    Resolution_Notes__c = 'Application rejected by ' + UserInfo.getName() + '.',
                    External_Id__c = 'REJ-' + applicationId
                ),
                false
            );
        }

        ActionResult result = new ActionResult();
        result.newStatus = 'Rejected';
        result.message = trimmedReason == null
            ? 'Application rejected.'
            : 'Application rejected: ' + trimmedReason;
        return result;
    }

    /**
     * Cancel an application at the applicant's request. Distinct from reject,
     * which is a departmental decision.
     */
    @AuraEnabled
    public static ActionResult cancel(Id applicationId, String reason) {
        Passport_Application__c app = [
            SELECT Id, Status__c
            FROM Passport_Application__c
            WHERE Id = :applicationId
            WITH SECURITY_ENFORCED
            LIMIT 1
        ];
        if (app.Status__c == 'Delivered' || app.Status__c == 'Rejected' || app.Status__c == 'Cancelled') {
            throw PSK_ApplicationService.auraError('Cannot cancel an application in status "' + app.Status__c + '".');
        }
        app.Status__c = 'Cancelled';
        app.Stage_Entered_Date__c = System.now();
        update app;

        ActionResult result = new ActionResult();
        result.newStatus = 'Cancelled';
        result.message = String.isBlank(reason)
            ? 'Application cancelled.'
            : 'Application cancelled: ' + reason.trim();
        return result;
    }

    /**
     * Read-only view of which actions apply right now, so the LWC does not have to
     * duplicate the lifecycle map.
     */
    @AuraEnabled(cacheable=true)
    public static AvailableActions getAvailableActions(Id applicationId) {
        AvailableActions a = new AvailableActions();
        if (applicationId == null) {
            a.canAdvance = false;
            a.canReject = false;
            a.isTerminal = false;
            a.blockedReason = 'No application selected.';
            return a;
        }

        List<Passport_Application__c> apps = [
            SELECT Id, Status__c, Payment_Status__c
            FROM Passport_Application__c
            WHERE Id = :applicationId
            WITH USER_MODE
            LIMIT 1
        ];
        if (apps.isEmpty()) {
            a.canAdvance = false;
            a.canReject = false;
            a.isTerminal = false;
            a.blockedReason = 'Application not found.';
            return a;
        }

        String current = apps[0].Status__c;
        a.currentStatus = current;
        a.isTerminal = PSK_Constants.TERMINAL_STATUSES.contains(current);
        a.nextStatus = NEXT_STATUS.get(current);
        a.canAdvance = (a.nextStatus != null);
        a.canReject = !a.isTerminal;
        a.advanceLabel = a.nextStatus == null ? null : 'Move to ' + a.nextStatus;
        if (!a.canAdvance) {
            a.blockedReason = terminalMessage(current);
        }
        return a;
    }

    /**
     * The station a verification is referred to. Police_Station__c is Text(120)
     * and required from 'Referred' onwards by Referred_Requires_Station_And_Date;
     * the applicant's own locality is the right default, and an officer can
     * correct it on the record.
     */
    private static String policeStationFor(Passport_Application__c app) {
        String locality = String.isNotBlank(app.City__c)
            ? app.City__c
            : (String.isNotBlank(app.District__c) ? app.District__c : null);
        String station = String.isBlank(locality)
            ? 'Local Police Station'
            : locality + ' City Police Station';
        return station.length() > 120 ? station.left(120) : station;
    }

    private static String terminalMessage(String current) {
        if (current == PSK_Constants.STATUS_DELIVERED) {
            return 'This application is complete - the passport has been delivered. '
                + 'Start a re-issue application to make further changes.';
        }
        if (current == PSK_Constants.STATUS_REJECTED) {
            return 'This application was rejected and cannot be advanced.';
        }
        if (current == PSK_Constants.STATUS_CANCELLED) {
            return 'This application was cancelled and cannot be advanced.';
        }
        return 'No further quick action available from status "' + current + '".';
    }
}
