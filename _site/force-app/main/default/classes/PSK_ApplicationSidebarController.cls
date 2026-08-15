/**
 * Data provider for the Passport Application record page sidebar (pskApplicationSidebar LWC).
 */
public with sharing class PSK_ApplicationSidebarController {

    public class SidebarData {
        @AuraEnabled public Integer documentsTotal;
        @AuraEnabled public Integer documentsVerified;
        @AuraEnabled public Integer documentsRejected;
        @AuraEnabled public String paymentStatus;
        @AuraEnabled public Decimal paymentAmount;
        @AuraEnabled public String policeVerificationStatus;
        @AuraEnabled public String policeVerificationType;
        @AuraEnabled public Integer openRiskFlags;
        @AuraEnabled public Integer totalRiskFlags;
    }

    @AuraEnabled(cacheable=true)
    public static SidebarData getSidebarData(Id applicationId) {
        SidebarData data = new SidebarData();
        data.documentsTotal = 0;
        data.documentsVerified = 0;
        data.documentsRejected = 0;
        data.openRiskFlags = 0;
        data.totalRiskFlags = 0;

        if (applicationId == null) {
            return data;
        }

        if (Schema.sObjectType.Document_Checklist_Item__c.isAccessible()) {
            for (AggregateResult ar : [
                SELECT Status__c status, COUNT(Id) total
                FROM Document_Checklist_Item__c
                WHERE Passport_Application__c = :applicationId
                GROUP BY Status__c
            ]) {
                Integer c = (Integer) ar.get('total');
                String status = (String) ar.get('status');
                data.documentsTotal += c;
                if (status == 'Verified') {
                    data.documentsVerified += c;
                } else if (status == 'Rejected') {
                    data.documentsRejected += c;
                }
            }
        }

        if (Schema.sObjectType.Payment__c.isAccessible()) {
            List<Payment__c> payments = [
                SELECT Status__c, Amount__c
                FROM Payment__c
                WHERE Passport_Application__c = :applicationId
                ORDER BY Payment_Date__c DESC NULLS LAST
                LIMIT 1
            ];
            if (!payments.isEmpty()) {
                data.paymentStatus = payments[0].Status__c;
                data.paymentAmount = payments[0].Amount__c;
            }
        }

        if (Schema.sObjectType.Police_Verification__c.isAccessible()) {
            List<Police_Verification__c> pvs = [
                SELECT Status__c, PV_Type__c
                FROM Police_Verification__c
                WHERE Passport_Application__c = :applicationId
                ORDER BY CreatedDate DESC
                LIMIT 1
            ];
            if (!pvs.isEmpty()) {
                data.policeVerificationStatus = pvs[0].Status__c;
                data.policeVerificationType = pvs[0].PV_Type__c;
            }
        }

        if (Schema.sObjectType.Risk_Flag__c.isAccessible()) {
            for (AggregateResult ar : [
                SELECT Status__c status, COUNT(Id) total
                FROM Risk_Flag__c
                WHERE Passport_Application__c = :applicationId
                GROUP BY Status__c
            ]) {
                Integer c = (Integer) ar.get('total');
                data.totalRiskFlags += c;
                if ((String) ar.get('status') == 'Open') {
                    data.openRiskFlags += c;
                }
            }
        }

        return data;
    }
}
