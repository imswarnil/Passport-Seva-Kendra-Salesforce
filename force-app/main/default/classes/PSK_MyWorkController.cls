/**
 * "My Work" queue for a PSK officer: applications owned by the running user or by
 * one of the queues they are a member of, with an SLA breach flag derived from
 * SLA_Config__mdt against Stage_Entered_Date__c.
 */
public with sharing class PSK_MyWorkController {

    public class WorkItem {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public String applicantName;
        @AuraEnabled public String recordTypeName;
        @AuraEnabled public String status;
        @AuraEnabled public String paymentStatus;
        @AuraEnabled public Boolean tatkal;
        @AuraEnabled public Decimal riskScore;
        @AuraEnabled public Id ownerId;
        @AuraEnabled public String ownerName;
        @AuraEnabled public Boolean ownedByQueue;

        @AuraEnabled public DateTime stageEnteredDate;
        @AuraEnabled public Decimal hoursInStage;
        @AuraEnabled public Decimal targetHours;
        @AuraEnabled public Decimal escalationHours;
        @AuraEnabled public Boolean slaBreached;
        @AuraEnabled public Boolean slaEscalated;
        @AuraEnabled public Decimal slaPercentConsumed;
        @AuraEnabled public String slaLabel;
        @AuraEnabled public String slaVariant;
        @AuraEnabled public String ownerQueueName;
    }

    public class MyWork {
        @AuraEnabled public Id userId;
        @AuraEnabled public String userName;
        @AuraEnabled public Integer totalItems;
        @AuraEnabled public Integer breachedItems;
        @AuraEnabled public Integer escalatedItems;
        @AuraEnabled public Integer ownedByMe;
        @AuraEnabled public Integer ownedByMyQueues;
        @AuraEnabled public List<String> queueNames;
        @AuraEnabled public List<WorkItem> items;
    }

    private static final Integer MAX_ITEMS = 200;

    @AuraEnabled(cacheable=true)
    public static MyWork getMyWork() {
        MyWork w = new MyWork();
        w.userId = UserInfo.getUserId();
        w.userName = UserInfo.getName();
        w.items = new List<WorkItem>();
        w.queueNames = new List<String>();
        w.totalItems = 0;
        w.breachedItems = 0;
        w.escalatedItems = 0;
        w.ownedByMe = 0;
        w.ownedByMyQueues = 0;

        if (!Schema.sObjectType.Passport_Application__c.isAccessible()) {
            return w;
        }

        // Queues the running user belongs to, directly or via a role/group.
        Map<Id, String> queueNameById = new Map<Id, String>();
        Set<Id> myGroupIds = new Set<Id>();
        for (GroupMember gm : [
            SELECT GroupId, Group.Name, Group.Type
            FROM GroupMember
            WHERE UserOrGroupId = :UserInfo.getUserId()
        ]) {
            myGroupIds.add(gm.GroupId);
            if (gm.Group.Type == 'Queue') {
                queueNameById.put(gm.GroupId, gm.Group.Name);
            }
        }
        w.queueNames = new List<String>(queueNameById.values());
        w.queueNames.sort();

        Set<Id> ownerIds = new Set<Id>{ UserInfo.getUserId() };
        ownerIds.addAll(myGroupIds);

        List<Passport_Application__c> apps = [
            SELECT Id, Name, First_Name__c, Last_Name__c, Status__c, Payment_Status__c,
                   Tatkal__c, Risk_Score__c, Stage_Entered_Date__c, Submitted_Date__c,
                   OwnerId, Owner.Name, RecordType.Name, CreatedDate
            FROM Passport_Application__c
            WHERE OwnerId IN :ownerIds
              AND Status__c NOT IN ('Delivered', 'Rejected', 'Cancelled')
            WITH USER_MODE
            ORDER BY Stage_Entered_Date__c ASC NULLS FIRST
            LIMIT :MAX_ITEMS
        ];

        Map<String, SLA_Config__mdt> slaByKey = slaIndex();
        DateTime nowStamp = System.now();

        for (Passport_Application__c app : apps) {
            WorkItem item = new WorkItem();
            item.id = app.Id;
            item.name = app.Name;
            item.applicantName = buildName(app);
            item.recordTypeName = app.RecordType == null ? null : app.RecordType.Name;
            item.status = app.Status__c;
            item.paymentStatus = app.Payment_Status__c;
            item.tatkal = app.Tatkal__c;
            item.riskScore = app.Risk_Score__c;
            item.ownerId = app.OwnerId;
            item.ownerName = app.Owner == null ? null : app.Owner.Name;
            item.ownedByQueue = (app.OwnerId != UserInfo.getUserId());
            item.stageEnteredDate = app.Stage_Entered_Date__c;

            DateTime since = app.Stage_Entered_Date__c != null
                ? app.Stage_Entered_Date__c
                : (app.Submitted_Date__c != null ? app.Submitted_Date__c : app.CreatedDate);
            item.hoursInStage = since == null
                ? 0
                : (Decimal.valueOf(nowStamp.getTime() - since.getTime()) / 3600000).setScale(1);

            SLA_Config__mdt sla = resolveSla(slaByKey, app.Status__c, app.Tatkal__c == true);
            applySla(item, sla);

            if (item.slaBreached == true) {
                w.breachedItems++;
            }
            if (item.slaEscalated == true) {
                w.escalatedItems++;
            }
            if (item.ownedByQueue == true) {
                w.ownedByMyQueues++;
            } else {
                w.ownedByMe++;
            }
            w.items.add(item);
        }

        w.totalItems = w.items.size();
        return w;
    }

    // ---------------------------------------------------------------- SLA lookup

    private static List<SLA_Config__mdt> slaCache;

    private static List<SLA_Config__mdt> slaRows() {
        if (slaCache == null) {
            slaCache = [
                SELECT DeveloperName, Stage__c, Service_Type__c, Target_Hours__c,
                       Escalation_Hours__c, Owner_Queue_Name__c, Applies_To_Tatkal__c, Is_Active__c
                FROM SLA_Config__mdt
                WHERE Is_Active__c = true
            ];
        }
        return slaCache;
    }

    /** Test seam so SLA behaviour is testable without deploying metadata rows. */
    @TestVisible
    private static void overrideSla(List<SLA_Config__mdt> rows) {
        slaCache = rows;
    }

    /** Key: stage + '|' + ('T' for the tatkal variant, 'S' for standard). */
    private static Map<String, SLA_Config__mdt> slaIndex() {
        Map<String, SLA_Config__mdt> index = new Map<String, SLA_Config__mdt>();
        for (SLA_Config__mdt row : slaRows()) {
            if (row.Service_Type__c != null && row.Service_Type__c != 'Passport') {
                continue;
            }
            String key = row.Stage__c + '|' + (row.Applies_To_Tatkal__c == true ? 'T' : 'S');
            index.put(key, row);
        }
        return index;
    }

    private static SLA_Config__mdt resolveSla(Map<String, SLA_Config__mdt> index,
                                              String stage, Boolean tatkal) {
        if (String.isBlank(stage)) {
            return null;
        }
        if (tatkal == true && index.containsKey(stage + '|T')) {
            return index.get(stage + '|T');
        }
        return index.get(stage + '|S');
    }

    private static void applySla(WorkItem item, SLA_Config__mdt sla) {
        item.slaBreached = false;
        item.slaEscalated = false;
        item.slaPercentConsumed = 0;

        if (sla == null) {
            item.slaLabel = 'No SLA configured for this stage';
            item.slaVariant = 'inverse';
            return;
        }

        item.ownerQueueName = sla.Owner_Queue_Name__c;
        item.targetHours = sla.Target_Hours__c;
        item.escalationHours = sla.Escalation_Hours__c;

        Decimal target = sla.Target_Hours__c;
        if (target == null || target <= 0) {
            item.slaLabel = 'No target hours configured';
            item.slaVariant = 'inverse';
            return;
        }

        item.slaPercentConsumed = (item.hoursInStage / target * 100).setScale(0);
        item.slaBreached = (item.hoursInStage > target);
        if (sla.Escalation_Hours__c != null && sla.Escalation_Hours__c > 0) {
            item.slaEscalated = (item.hoursInStage > sla.Escalation_Hours__c);
        }

        if (item.slaEscalated == true) {
            item.slaLabel = 'Escalated - ' + item.hoursInStage + 'h against a '
                + sla.Escalation_Hours__c + 'h escalation threshold';
            item.slaVariant = 'error';
        } else if (item.slaBreached == true) {
            item.slaLabel = 'Breached - ' + item.hoursInStage + 'h against a ' + target + 'h target';
            item.slaVariant = 'warning';
        } else {
            item.slaLabel = item.hoursInStage + 'h of ' + target + 'h used';
            item.slaVariant = 'success';
        }
    }

    private static String buildName(Passport_Application__c app) {
        List<String> parts = new List<String>();
        if (String.isNotBlank(app.First_Name__c)) {
            parts.add(app.First_Name__c);
        }
        if (String.isNotBlank(app.Last_Name__c)) {
            parts.add(app.Last_Name__c);
        }
        return parts.isEmpty() ? '(no name)' : String.join(parts, ' ');
    }
}
