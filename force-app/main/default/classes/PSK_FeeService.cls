/**
 * Fee calculation surface for LWCs. Reads Fee_Matrix__mdt via
 * PSK_ApplicationService so a fee previewed in the UI is byte-identical to the
 * one the trigger stamps on save.
 */
public with sharing class PSK_FeeService {

    /**
     * Non-destructive: work out what the fee WOULD be, without touching the record.
     */
    @AuraEnabled(cacheable=true)
    public static PSK_ApplicationService.FeeBreakdown preview(Id applicationId) {
        Passport_Application__c app = loadApplication(applicationId);
        PSK_ApplicationService.FeeBreakdown fb = PSK_ApplicationService.resolveFee(app);
        return fb;
    }

    /**
     * Recompute Fee__c and save it. Returns the breakdown that was applied.
     */
    @AuraEnabled
    public static PSK_ApplicationService.FeeBreakdown recalculate(Id applicationId) {
        Passport_Application__c app = loadApplication(applicationId);

        if (!Schema.sObjectType.Passport_Application__c.fields.Fee__c.isUpdateable()) {
            throw new AuraHandledException('You do not have permission to update the application fee.');
        }

        PSK_ApplicationService.FeeBreakdown fb = PSK_ApplicationService.resolveFee(app);
        app.Fee__c = fb.totalFee;
        try {
            update app;
        } catch (DmlException e) {
            throw new AuraHandledException('Could not save the recalculated fee: ' + e.getDmlMessage(0));
        }
        return fb;
    }

    private static Passport_Application__c loadApplication(Id applicationId) {
        if (applicationId == null) {
            throw new AuraHandledException('An application id is required.');
        }
        List<Passport_Application__c> apps = [
            SELECT Id, RecordTypeId, Booklet_Pages__c, Validity_Years__c, Tatkal__c,
                   Applied_For_Minor__c, Fee__c, Status__c, Payment_Status__c
            FROM Passport_Application__c
            WHERE Id = :applicationId
            WITH USER_MODE
            LIMIT 1
        ];
        if (apps.isEmpty()) {
            throw new AuraHandledException('Application not found, or you do not have access to it.');
        }
        return apps[0];
    }
}
