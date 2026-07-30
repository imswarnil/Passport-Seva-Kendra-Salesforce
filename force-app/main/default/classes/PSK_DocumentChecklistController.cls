/**
 * Document checklist panel for the Passport Application record page.
 */
public with sharing class PSK_DocumentChecklistController {

    public class ChecklistItem {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public String documentType;
        @AuraEnabled public String status;
        @AuraEnabled public Date receivedDate;
        @AuraEnabled public Date verifiedDate;
        @AuraEnabled public String rejectionReason;
        @AuraEnabled public String notes;
    }

    public class SeedResult {
        @AuraEnabled public Integer created;
        @AuraEnabled public Integer skipped;
        @AuraEnabled public String recordTypeName;
        @AuraEnabled public String message;
        @AuraEnabled public List<ChecklistItem> items;
    }

    @AuraEnabled(cacheable=true)
    public static List<ChecklistItem> getItems(Id applicationId) {
        List<ChecklistItem> out = new List<ChecklistItem>();
        if (applicationId == null) {
            return out;
        }
        for (Document_Checklist_Item__c d : [
            SELECT Id, Name, Document_Type__c, Status__c, Received_Date__c,
                   Verified_Date__c, Rejection_Reason__c, Notes__c
            FROM Document_Checklist_Item__c
            WHERE Passport_Application__c = :applicationId
            WITH USER_MODE
            ORDER BY Document_Type__c, Name
            LIMIT 200
        ]) {
            out.add(toWrapper(d));
        }
        return out;
    }

    /**
     * Move a single checklist item to a new status, stamping the matching date.
     */
    @AuraEnabled
    public static ChecklistItem setStatus(Id itemId, String status) {
        if (itemId == null) {
            throw new AuraHandledException('A checklist item id is required.');
        }
        if (String.isBlank(status)) {
            throw new AuraHandledException('A status is required.');
        }
        Set<String> allowed = new Set<String>(PSK_Constants.DOCUMENT_STATUSES);
        if (!allowed.contains(status)) {
            throw new AuraHandledException(
                '"' + status + '" is not a valid document status. Expected one of: '
                + String.join(PSK_Constants.DOCUMENT_STATUSES, ', ') + '.'
            );
        }

        List<Document_Checklist_Item__c> items = [
            SELECT Id, Name, Document_Type__c, Status__c, Received_Date__c,
                   Verified_Date__c, Rejection_Reason__c, Notes__c
            FROM Document_Checklist_Item__c
            WHERE Id = :itemId
            WITH USER_MODE
            LIMIT 1
        ];
        if (items.isEmpty()) {
            throw new AuraHandledException('Checklist item not found, or you do not have access to it.');
        }

        Document_Checklist_Item__c item = items[0];
        item.Status__c = status;
        if (status == PSK_Constants.DOC_RECEIVED && item.Received_Date__c == null) {
            item.Received_Date__c = Date.today();
        }
        if (status == PSK_Constants.DOC_VERIFIED) {
            if (item.Received_Date__c == null) {
                item.Received_Date__c = Date.today();
            }
            item.Verified_Date__c = Date.today();
            item.Rejection_Reason__c = null;
        }
        if (status == PSK_Constants.DOC_REQUIRED) {
            item.Received_Date__c = null;
            item.Verified_Date__c = null;
            item.Rejection_Reason__c = null;
        }

        try {
            update item;
        } catch (DmlException e) {
            throw new AuraHandledException(e.getDmlMessage(0));
        }
        return toWrapper(item);
    }

    /**
     * Create the standard required documents for the application's record type.
     * Skips document types that are already on the checklist, so it is safe to
     * press twice.
     */
    @AuraEnabled
    public static SeedResult seedFromTemplate(Id applicationId) {
        if (applicationId == null) {
            throw new AuraHandledException('An application id is required.');
        }
        if (!Schema.sObjectType.Document_Checklist_Item__c.isCreateable()) {
            throw new AuraHandledException('You do not have permission to create checklist items.');
        }

        List<Passport_Application__c> apps = [
            SELECT Id, RecordTypeId, Status__c
            FROM Passport_Application__c
            WHERE Id = :applicationId
            WITH USER_MODE
            LIMIT 1
        ];
        if (apps.isEmpty()) {
            throw new AuraHandledException('Application not found, or you do not have access to it.');
        }

        String rtName = PSK_ApplicationService.applicationRecordTypeName(apps[0].RecordTypeId);
        List<String> template = PSK_ApplicationService.checklistTemplate(rtName);

        Set<String> already = new Set<String>();
        for (Document_Checklist_Item__c existing : [
            SELECT Document_Type__c
            FROM Document_Checklist_Item__c
            WHERE Passport_Application__c = :applicationId
            WITH USER_MODE
        ]) {
            already.add(existing.Document_Type__c);
        }

        List<Document_Checklist_Item__c> toInsert = new List<Document_Checklist_Item__c>();
        Integer skipped = 0;
        for (String docType : template) {
            if (already.contains(docType)) {
                skipped++;
                continue;
            }
            toInsert.add(new Document_Checklist_Item__c(
                Passport_Application__c = applicationId,
                Document_Type__c = docType,
                Status__c = PSK_Constants.DOC_REQUIRED,
                // External_Id__c is Text(40): 'DCI-' (4) + a 18-character id + '-'
                // leaves 17, so the document type is truncated to 15. The first 15
                // characters are still distinct across all seven document types.
                External_Id__c = 'DCI-' + applicationId + '-'
                    + docType.replaceAll('[^A-Za-z0-9]', '').left(15)
            ));
        }

        SeedResult r = new SeedResult();
        r.recordTypeName = String.isBlank(rtName) ? 'Unassigned' : rtName;
        r.skipped = skipped;
        r.created = 0;

        if (!toInsert.isEmpty()) {
            try {
                insert toInsert;
                r.created = toInsert.size();
            } catch (DmlException e) {
                throw new AuraHandledException(e.getDmlMessage(0));
            }
        }

        r.items = getItems(applicationId);
        r.message = r.created + ' document(s) added'
            + (skipped > 0 ? ', ' + skipped + ' already present' : '') + '.';
        return r;
    }

    private static ChecklistItem toWrapper(Document_Checklist_Item__c d) {
        ChecklistItem w = new ChecklistItem();
        w.id = d.Id;
        w.name = d.Name;
        w.documentType = d.Document_Type__c;
        w.status = d.Status__c;
        w.receivedDate = d.Received_Date__c;
        w.verifiedDate = d.Verified_Date__c;
        w.rejectionReason = d.Rejection_Reason__c;
        w.notes = d.Notes__c;
        return w;
    }
}
