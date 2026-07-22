/**
 * Data provider for the Passport Application Home dashboard (pskHomeDashboard LWC).
 */
public with sharing class PSK_HomeController {

    public class StatusCount {
        @AuraEnabled public String status;
        @AuraEnabled public Integer count;
        public StatusCount(String status, Integer count) {
            this.status = status;
            this.count = count;
        }
    }

    public class RecordTypeOption {
        @AuraEnabled public String label;
        @AuraEnabled public String value;
        public RecordTypeOption(String label, String value) {
            this.label = label;
            this.value = value;
        }
    }

    public class HomeStats {
        @AuraEnabled public Integer totalApplications;
        @AuraEnabled public Integer draftCount;
        @AuraEnabled public Integer submittedTodayCount;
        @AuraEnabled public Integer paymentPendingCount;
        @AuraEnabled public Integer grantedThisMonthCount;
        @AuraEnabled public Integer tatkalCount;
        @AuraEnabled public List<StatusCount> statusBreakdown;
        @AuraEnabled public Integer openRiskFlags;
        @AuraEnabled public Integer pendingPoliceVerifications;
        @AuraEnabled public Integer documentsAwaitingVerification;
        @AuraEnabled public Integer upcomingAppointments;
    }

    @AuraEnabled(cacheable=true)
    public static List<RecordTypeOption> getRecordTypeOptions() {
        List<RecordTypeOption> options = new List<RecordTypeOption>{ new RecordTypeOption('All Record Types', '') };
        for (Schema.RecordTypeInfo rti : Passport_Application__c.SObjectType.getDescribe().getRecordTypeInfos()) {
            if (rti.isAvailable() && !rti.isMaster()) {
                options.add(new RecordTypeOption(rti.getName(), rti.getRecordTypeId()));
            }
        }
        return options;
    }

    @AuraEnabled(cacheable=true)
    public static HomeStats getHomeStats(Id recordTypeId) {
        if (!Schema.sObjectType.Passport_Application__c.isAccessible()) {
            throw new AuraHandledException('Insufficient access to Passport Application.');
        }

        HomeStats stats = new HomeStats();
        Date todayDate = Date.today();
        Date monthStart = Date.newInstance(todayDate.year(), todayDate.month(), 1);
        String rtFilter = recordTypeId == null ? '' : ' AND RecordTypeId = :recordTypeId';

        stats.statusBreakdown = new List<StatusCount>();
        Integer total = 0;
        for (AggregateResult ar : (List<AggregateResult>) Database.queryWithBinds(
            'SELECT Status__c status, COUNT(Id) total FROM Passport_Application__c WHERE Id != null' + rtFilter + ' GROUP BY Status__c ORDER BY Status__c',
            new Map<String, Object>{ 'recordTypeId' => recordTypeId },
            AccessLevel.USER_MODE
        )) {
            Integer c = (Integer) ar.get('total');
            stats.statusBreakdown.add(new StatusCount((String) ar.get('status'), c));
            total += c;
        }
        stats.totalApplications = total;

        stats.draftCount = Database.countQueryWithBinds(
            'SELECT COUNT() FROM Passport_Application__c WHERE Status__c = \'Draft\'' + rtFilter,
            new Map<String, Object>{ 'recordTypeId' => recordTypeId },
            AccessLevel.USER_MODE
        );
        stats.submittedTodayCount = Database.countQueryWithBinds(
            'SELECT COUNT() FROM Passport_Application__c WHERE Submitted_Date__c = TODAY' + rtFilter,
            new Map<String, Object>{ 'recordTypeId' => recordTypeId },
            AccessLevel.USER_MODE
        );
        stats.paymentPendingCount = Database.countQueryWithBinds(
            'SELECT COUNT() FROM Passport_Application__c WHERE Payment_Status__c IN (\'Not Paid\', \'Pending\')' + rtFilter,
            new Map<String, Object>{ 'recordTypeId' => recordTypeId },
            AccessLevel.USER_MODE
        );
        stats.grantedThisMonthCount = Database.countQueryWithBinds(
            'SELECT COUNT() FROM Passport_Application__c WHERE Granted_Date__c >= :monthStart AND Granted_Date__c <= :todayDate' + rtFilter,
            new Map<String, Object>{ 'monthStart' => monthStart, 'todayDate' => todayDate, 'recordTypeId' => recordTypeId },
            AccessLevel.USER_MODE
        );
        stats.tatkalCount = Database.countQueryWithBinds(
            'SELECT COUNT() FROM Passport_Application__c WHERE Tatkal__c = true' + rtFilter,
            new Map<String, Object>{ 'recordTypeId' => recordTypeId },
            AccessLevel.USER_MODE
        );

        stats.openRiskFlags = Schema.sObjectType.Risk_Flag__c.isAccessible()
            ? [SELECT COUNT() FROM Risk_Flag__c WHERE Status__c = 'Open']
            : 0;

        stats.pendingPoliceVerifications = Schema.sObjectType.Police_Verification__c.isAccessible()
            ? [SELECT COUNT() FROM Police_Verification__c WHERE Status__c IN ('Referred', 'In Progress')]
            : 0;

        stats.documentsAwaitingVerification = Schema.sObjectType.Document_Checklist_Item__c.isAccessible()
            ? [SELECT COUNT() FROM Document_Checklist_Item__c WHERE Status__c IN ('Required', 'Received')]
            : 0;

        stats.upcomingAppointments = Schema.sObjectType.Appointment__c.isAccessible()
            ? [SELECT COUNT() FROM Appointment__c WHERE Status__c = 'Scheduled']
            : 0;

        return stats;
    }

    @AuraEnabled(cacheable=true)
    public static List<StatusCount> getRecordTypeSummary() {
        List<StatusCount> summary = new List<StatusCount>();
        for (AggregateResult ar : [
            SELECT RecordType.Name rtName, COUNT(Id) total
            FROM Passport_Application__c
            GROUP BY RecordType.Name
            ORDER BY RecordType.Name
        ]) {
            String rtName = (String) ar.get('rtName');
            summary.add(new StatusCount(String.isBlank(rtName) ? 'Unassigned' : rtName, (Integer) ar.get('total')));
        }
        return summary;
    }

    @AuraEnabled(cacheable=true)
    public static List<Passport_Application__c> getRecentApplications(Integer recordLimit, Id recordTypeId) {
        if (!Schema.sObjectType.Passport_Application__c.isAccessible()) {
            throw new AuraHandledException('Insufficient access to Passport Application.');
        }
        Integer safeLimit = (recordLimit == null || recordLimit <= 0 || recordLimit > 50) ? 10 : recordLimit;
        String rtFilter = recordTypeId == null ? '' : ' WHERE RecordTypeId = :recordTypeId';

        return (List<Passport_Application__c>) Database.queryWithBinds(
            'SELECT Id, Name, First_Name__c, Last_Name__c, Status__c, Passport_Category__c, ' +
            'Payment_Status__c, Risk_Score__c, Tatkal__c, CreatedDate ' +
            'FROM Passport_Application__c' + rtFilter + ' ORDER BY CreatedDate DESC LIMIT :safeLimit',
            new Map<String, Object>{ 'recordTypeId' => recordTypeId, 'safeLimit' => safeLimit },
            AccessLevel.USER_MODE
        );
    }
}
