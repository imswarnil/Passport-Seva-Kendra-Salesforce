/**
 * Passport booklet detail: expiry countdown plus the full reissue chain, walked
 * in both directions from the booklet in hand.
 */
public with sharing class PSK_PassportController {

    public class ChainLink {
        @AuraEnabled public Id id;
        @AuraEnabled public String passportNumber;
        @AuraEnabled public String status;
        @AuraEnabled public Date dateOfIssue;
        @AuraEnabled public Date dateOfExpiry;
        @AuraEnabled public Boolean isCurrent;
        @AuraEnabled public Integer generation;
    }

    public class PassportDetail {
        @AuraEnabled public Id id;
        @AuraEnabled public String passportNumber;
        @AuraEnabled public String holderName;
        @AuraEnabled public String status;
        @AuraEnabled public String category;
        @AuraEnabled public String bookletPages;
        @AuraEnabled public String validityYears;
        @AuraEnabled public String ecrStatus;
        @AuraEnabled public String fileNumber;
        @AuraEnabled public String placeOfIssue;
        @AuraEnabled public Date dateOfIssue;
        @AuraEnabled public Date dateOfExpiry;
        @AuraEnabled public String cancellationReason;
        @AuraEnabled public String remarks;

        @AuraEnabled public Id applicationId;
        @AuraEnabled public String applicationName;
        @AuraEnabled public Id citizenId;
        @AuraEnabled public String citizenName;
        @AuraEnabled public Id officeId;
        @AuraEnabled public String officeName;

        // Expiry countdown
        @AuraEnabled public Integer daysToExpiry;
        @AuraEnabled public Integer monthsToExpiry;
        @AuraEnabled public Boolean isExpired;
        @AuraEnabled public Boolean isExpiringSoon;
        @AuraEnabled public String expiryLabel;
        @AuraEnabled public String expiryVariant;

        // Reissue chain, oldest booklet first
        @AuraEnabled public List<ChainLink> reissueChain;
        @AuraEnabled public Integer chainLength;
    }

    @AuraEnabled(cacheable=true)
    public static PassportDetail getPassport(Id passportId) {
        if (passportId == null) {
            throw new AuraHandledException('A passport id is required.');
        }

        List<Passport__c> records = [
            SELECT Id, Name, Holder_Name__c, Status__c, Passport_Category__c, Booklet_Pages__c,
                   Validity_Years__c, ECR_Status__c, File_Number__c, Place_of_Issue__c,
                   Date_of_Issue__c, Date_of_Expiry__c, Days_To_Expiry__c, Is_Expired__c,
                   Is_Expiring_Soon__c, Cancellation_Reason__c, Remarks__c,
                   Application__c, Application__r.Name, Citizen__c, Citizen__r.Name,
                   PSK_Office__c, PSK_Office__r.Name, Previous_Passport__c
            FROM Passport__c
            WHERE Id = :passportId
            WITH USER_MODE
            LIMIT 1
        ];
        if (records.isEmpty()) {
            throw new AuraHandledException('Passport not found, or you do not have access to it.');
        }
        Passport__c p = records[0];

        PassportDetail d = new PassportDetail();
        d.id = p.Id;
        d.passportNumber = p.Name;
        d.holderName = p.Holder_Name__c;
        d.status = p.Status__c;
        d.category = p.Passport_Category__c;
        d.bookletPages = p.Booklet_Pages__c;
        d.validityYears = p.Validity_Years__c;
        d.ecrStatus = p.ECR_Status__c;
        d.fileNumber = p.File_Number__c;
        d.placeOfIssue = p.Place_of_Issue__c;
        d.dateOfIssue = p.Date_of_Issue__c;
        d.dateOfExpiry = p.Date_of_Expiry__c;
        d.cancellationReason = p.Cancellation_Reason__c;
        d.remarks = p.Remarks__c;
        d.applicationId = p.Application__c;
        d.applicationName = p.Application__r == null ? null : p.Application__r.Name;
        d.citizenId = p.Citizen__c;
        d.citizenName = p.Citizen__r == null ? null : p.Citizen__r.Name;
        d.officeId = p.PSK_Office__c;
        d.officeName = p.PSK_Office__r == null ? null : p.PSK_Office__r.Name;

        applyExpiryCountdown(d, p);
        d.reissueChain = buildChain(p);
        d.chainLength = d.reissueChain.size();
        return d;
    }

    private static void applyExpiryCountdown(PassportDetail d, Passport__c p) {
        d.isExpired = p.Is_Expired__c == true;
        d.isExpiringSoon = p.Is_Expiring_Soon__c == true;

        if (p.Date_of_Expiry__c == null) {
            d.daysToExpiry = null;
            d.monthsToExpiry = null;
            d.expiryLabel = 'No expiry date recorded';
            d.expiryVariant = 'inverse';
            return;
        }

        Integer days = Date.today().daysBetween(p.Date_of_Expiry__c);
        d.daysToExpiry = days;
        d.monthsToExpiry = Date.today().monthsBetween(p.Date_of_Expiry__c);

        if (days < 0) {
            d.expiryLabel = 'Expired ' + Math.abs(days) + ' day(s) ago';
            d.expiryVariant = 'error';
        } else if (days == 0) {
            d.expiryLabel = 'Expires today';
            d.expiryVariant = 'error';
        } else if (days <= 365) {
            d.expiryLabel = 'Expires in ' + days + ' day(s) - renewal window open';
            d.expiryVariant = 'warning';
        } else {
            d.expiryLabel = 'Valid for another ' + d.monthsToExpiry + ' month(s)';
            d.expiryVariant = 'success';
        }
    }

    /**
     * Walk backwards through Previous_Passport__c, then forwards through
     * Reissued_Passports, and return the chain oldest first.
     *
     * Bounded to 10 hops each way: the chain is a self-lookup so a data error
     * could otherwise loop forever, and each hop costs a query.
     */
    private static List<ChainLink> buildChain(Passport__c current) {
        Map<Id, Passport__c> chain = new Map<Id, Passport__c>();
        chain.put(current.Id, current);

        // Backwards
        Id cursor = current.Previous_Passport__c;
        Integer hops = 0;
        while (cursor != null && hops < 10 && !chain.containsKey(cursor)) {
            List<Passport__c> prior = [
                SELECT Id, Name, Status__c, Date_of_Issue__c, Date_of_Expiry__c, Previous_Passport__c
                FROM Passport__c
                WHERE Id = :cursor
                WITH USER_MODE
                LIMIT 1
            ];
            if (prior.isEmpty()) {
                break;
            }
            chain.put(prior[0].Id, prior[0]);
            cursor = prior[0].Previous_Passport__c;
            hops++;
        }

        // Forwards
        Set<Id> frontier = new Set<Id>{ current.Id };
        hops = 0;
        while (!frontier.isEmpty() && hops < 10) {
            List<Passport__c> next = [
                SELECT Id, Name, Status__c, Date_of_Issue__c, Date_of_Expiry__c, Previous_Passport__c
                FROM Passport__c
                WHERE Previous_Passport__c IN :frontier
                WITH USER_MODE
                LIMIT 50
            ];
            frontier = new Set<Id>();
            for (Passport__c n : next) {
                if (!chain.containsKey(n.Id)) {
                    chain.put(n.Id, n);
                    frontier.add(n.Id);
                }
            }
            hops++;
        }

        List<Passport__c> ordered = chain.values();
        // Oldest issue date first; nulls last.
        for (Integer i = 0; i < ordered.size(); i++) {
            for (Integer j = i + 1; j < ordered.size(); j++) {
                if (isBefore(ordered[j].Date_of_Issue__c, ordered[i].Date_of_Issue__c)) {
                    Passport__c tmp = ordered[i];
                    ordered[i] = ordered[j];
                    ordered[j] = tmp;
                }
            }
        }

        List<ChainLink> links = new List<ChainLink>();
        Integer generation = 1;
        for (Passport__c p : ordered) {
            ChainLink l = new ChainLink();
            l.id = p.Id;
            l.passportNumber = p.Name;
            l.status = p.Status__c;
            l.dateOfIssue = p.Date_of_Issue__c;
            l.dateOfExpiry = p.Date_of_Expiry__c;
            l.isCurrent = (p.Id == current.Id);
            l.generation = generation++;
            links.add(l);
        }
        return links;
    }

    private static Boolean isBefore(Date a, Date b) {
        if (a == null) {
            return false;
        }
        if (b == null) {
            return true;
        }
        return a < b;
    }

    /**
     * Booklets expiring inside the given horizon -- feeds the renewal outreach list.
     */
    @AuraEnabled(cacheable=true)
    public static List<ChainLink> getExpiringPassports(Integer withinDays) {
        Integer horizon = (withinDays == null || withinDays <= 0) ? 365 : Math.min(withinDays, 1095);
        Date until = Date.today().addDays(horizon);
        List<ChainLink> out = new List<ChainLink>();
        for (Passport__c p : [
            SELECT Id, Name, Status__c, Date_of_Issue__c, Date_of_Expiry__c
            FROM Passport__c
            WHERE Status__c = :PSK_Constants.PASSPORT_ACTIVE
              AND Date_of_Expiry__c != NULL
              AND Date_of_Expiry__c <= :until
            WITH USER_MODE
            ORDER BY Date_of_Expiry__c
            LIMIT 200
        ]) {
            ChainLink l = new ChainLink();
            l.id = p.Id;
            l.passportNumber = p.Name;
            l.status = p.Status__c;
            l.dateOfIssue = p.Date_of_Issue__c;
            l.dateOfExpiry = p.Date_of_Expiry__c;
            l.isCurrent = true;
            l.generation = Date.today().daysBetween(p.Date_of_Expiry__c);
            out.add(l);
        }
        return out;
    }
}
