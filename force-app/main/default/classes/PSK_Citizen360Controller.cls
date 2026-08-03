/**
 * Citizen 360 view: everything the org knows about one citizen, in a single call.
 */
public with sharing class PSK_Citizen360Controller {

    public class ApplicationSummary {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public String recordTypeName;
        @AuraEnabled public String status;
        @AuraEnabled public String paymentStatus;
        @AuraEnabled public Decimal fee;
        @AuraEnabled public Boolean tatkal;
        @AuraEnabled public Decimal riskScore;
        @AuraEnabled public DateTime submittedDate;
        @AuraEnabled public DateTime createdDate;
    }

    public class PassportSummary {
        @AuraEnabled public Id id;
        @AuraEnabled public String passportNumber;
        @AuraEnabled public String status;
        @AuraEnabled public String category;
        @AuraEnabled public Date dateOfIssue;
        @AuraEnabled public Date dateOfExpiry;
        @AuraEnabled public Decimal daysToExpiry;
        @AuraEnabled public Boolean isExpired;
        @AuraEnabled public Boolean isExpiringSoon;
        @AuraEnabled public String placeOfIssue;
    }

    public class FamilyMemberSummary {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public String displayName;
        @AuraEnabled public String relationship;
        @AuraEnabled public Boolean isGuardian;
        @AuraEnabled public Date dateOfBirth;
        @AuraEnabled public String mobile;
        @AuraEnabled public Id relatedCitizenId;
    }

    public class RiskFlagSummary {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public String flagType;
        @AuraEnabled public String severity;
        @AuraEnabled public String status;
        @AuraEnabled public Date flaggedDate;
        @AuraEnabled public Id applicationId;
        @AuraEnabled public String applicationName;
    }

    public class KycState {
        @AuraEnabled public String kycStatus;
        @AuraEnabled public Boolean aadhaarVerified;
        @AuraEnabled public Boolean notificationConsent;
        @AuraEnabled public DateTime consentTimestamp;
        @AuraEnabled public Boolean isBlacklisted;
        @AuraEnabled public String blacklistReason;
        @AuraEnabled public String preferredLanguage;
    }

    public class CitizenProfile {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public String citizenReference;
        @AuraEnabled public Date dateOfBirth;
        @AuraEnabled public Decimal age;
        @AuraEnabled public Boolean isMinor;
        @AuraEnabled public String gender;
        @AuraEnabled public String mobile;
        @AuraEnabled public String email;
        @AuraEnabled public String city;
        @AuraEnabled public String state;
        @AuraEnabled public String pincode;
        @AuraEnabled public Id accountId;
        @AuraEnabled public String accountName;
        @AuraEnabled public KycState kyc;
        @AuraEnabled public List<ApplicationSummary> applications;
        @AuraEnabled public List<PassportSummary> passports;
        @AuraEnabled public List<FamilyMemberSummary> familyMembers;
        @AuraEnabled public List<RiskFlagSummary> openRiskFlags;
        @AuraEnabled public Integer totalApplications;
        @AuraEnabled public Integer activePassports;
        @AuraEnabled public Integer openRiskFlagCount;
    }

    @AuraEnabled(cacheable=true)
    public static CitizenProfile getProfile(Id citizenId) {
        if (citizenId == null) {
            throw PSK_ApplicationService.auraError('A citizen id is required.');
        }

        List<Citizen__c> citizens = [
            SELECT Id, Name, Citizen_Reference__c, Date_of_Birth__c, Age__c, Is_Minor__c,
                   Gender__c, Mobile__c, Email__c, City__c, State__c, Pincode__c,
                   KYC_Status__c, Aadhaar_Verified__c, Notification_Consent__c,
                   Consent_Timestamp__c, Is_Blacklisted__c, Blacklist_Reason__c,
                   Preferred_Language__c, Account__c, Account__r.Name
            FROM Citizen__c
            WHERE Id = :citizenId
            WITH USER_MODE
            LIMIT 1
        ];
        if (citizens.isEmpty()) {
            throw PSK_ApplicationService.auraError('Citizen not found, or you do not have access to it.');
        }
        Citizen__c c = citizens[0];

        CitizenProfile p = new CitizenProfile();
        p.id = c.Id;
        p.name = c.Name;
        p.citizenReference = c.Citizen_Reference__c;
        p.dateOfBirth = c.Date_of_Birth__c;
        p.age = c.Age__c;
        p.isMinor = c.Is_Minor__c;
        p.gender = c.Gender__c;
        p.mobile = c.Mobile__c;
        p.email = c.Email__c;
        p.city = c.City__c;
        p.state = c.State__c;
        p.pincode = c.Pincode__c;
        p.accountId = c.Account__c;
        p.accountName = c.Account__r == null ? null : c.Account__r.Name;

        KycState k = new KycState();
        k.kycStatus = c.KYC_Status__c;
        k.aadhaarVerified = c.Aadhaar_Verified__c;
        k.notificationConsent = c.Notification_Consent__c;
        k.consentTimestamp = c.Consent_Timestamp__c;
        k.isBlacklisted = c.Is_Blacklisted__c;
        k.blacklistReason = c.Blacklist_Reason__c;
        k.preferredLanguage = c.Preferred_Language__c;
        p.kyc = k;

        // ---------------------------------------------------------- Applications
        p.applications = new List<ApplicationSummary>();
        Set<Id> applicationIds = new Set<Id>();
        if (Schema.sObjectType.Passport_Application__c.isAccessible()) {
            for (Passport_Application__c app : [
                SELECT Id, Name, Status__c, Payment_Status__c, Fee__c, Tatkal__c, Risk_Score__c,
                       Submitted_Date__c, CreatedDate, RecordType.Name
                FROM Passport_Application__c
                WHERE Citizen__c = :citizenId
                WITH USER_MODE
                ORDER BY CreatedDate DESC
                LIMIT 100
            ]) {
                ApplicationSummary a = new ApplicationSummary();
                a.id = app.Id;
                a.name = app.Name;
                a.recordTypeName = app.RecordType == null ? null : app.RecordType.Name;
                a.status = app.Status__c;
                a.paymentStatus = app.Payment_Status__c;
                a.fee = app.Fee__c;
                a.tatkal = app.Tatkal__c;
                a.riskScore = app.Risk_Score__c;
                a.submittedDate = app.Submitted_Date__c;
                a.createdDate = app.CreatedDate;
                p.applications.add(a);
                applicationIds.add(app.Id);
            }
        }
        p.totalApplications = p.applications.size();

        // ------------------------------------------------------------- Passports
        p.passports = new List<PassportSummary>();
        p.activePassports = 0;
        if (Schema.sObjectType.Passport__c.isAccessible()) {
            for (Passport__c pp : [
                SELECT Id, Name, Status__c, Passport_Category__c, Date_of_Issue__c,
                       Date_of_Expiry__c, Days_To_Expiry__c, Is_Expired__c,
                       Is_Expiring_Soon__c, Place_of_Issue__c
                FROM Passport__c
                WHERE Citizen__c = :citizenId
                WITH USER_MODE
                ORDER BY Date_of_Issue__c DESC NULLS LAST
                LIMIT 50
            ]) {
                PassportSummary s = new PassportSummary();
                s.id = pp.Id;
                s.passportNumber = pp.Name;
                s.status = pp.Status__c;
                s.category = pp.Passport_Category__c;
                s.dateOfIssue = pp.Date_of_Issue__c;
                s.dateOfExpiry = pp.Date_of_Expiry__c;
                s.daysToExpiry = pp.Days_To_Expiry__c;
                s.isExpired = pp.Is_Expired__c;
                s.isExpiringSoon = pp.Is_Expiring_Soon__c;
                s.placeOfIssue = pp.Place_of_Issue__c;
                p.passports.add(s);
                if (pp.Status__c == PSK_Constants.PASSPORT_ACTIVE) {
                    p.activePassports++;
                }
            }
        }

        // -------------------------------------------------------- Family members
        p.familyMembers = new List<FamilyMemberSummary>();
        if (Schema.sObjectType.Family_Member__c.isAccessible()) {
            for (Family_Member__c fm : [
                SELECT Id, Name, Display_Name__c, Member_Name__c, Relationship__c,
                       Is_Guardian__c, Member_Date_of_Birth__c, Member_Mobile__c,
                       Related_Citizen__c
                FROM Family_Member__c
                WHERE Citizen__c = :citizenId
                WITH USER_MODE
                ORDER BY Relationship__c
                LIMIT 50
            ]) {
                FamilyMemberSummary f = new FamilyMemberSummary();
                f.id = fm.Id;
                f.name = fm.Name;
                f.displayName = String.isBlank(fm.Display_Name__c)
                    ? fm.Member_Name__c : fm.Display_Name__c;
                f.relationship = fm.Relationship__c;
                f.isGuardian = fm.Is_Guardian__c;
                f.dateOfBirth = fm.Member_Date_of_Birth__c;
                f.mobile = fm.Member_Mobile__c;
                f.relatedCitizenId = fm.Related_Citizen__c;
                p.familyMembers.add(f);
            }
        }

        // ------------------------------------------------------- Open risk flags
        p.openRiskFlags = new List<RiskFlagSummary>();
        if (!applicationIds.isEmpty() && Schema.sObjectType.Risk_Flag__c.isAccessible()) {
            for (Risk_Flag__c rf : [
                SELECT Id, Name, Flag_Type__c, Severity__c, Status__c, Flagged_Date__c,
                       Passport_Application__c, Passport_Application__r.Name
                FROM Risk_Flag__c
                WHERE Passport_Application__c IN :applicationIds
                  AND Status__c IN ('Open', 'Under Review')
                WITH USER_MODE
                ORDER BY Flagged_Date__c DESC NULLS LAST
                LIMIT 100
            ]) {
                RiskFlagSummary r = new RiskFlagSummary();
                r.id = rf.Id;
                r.name = rf.Name;
                r.flagType = rf.Flag_Type__c;
                r.severity = rf.Severity__c;
                r.status = rf.Status__c;
                r.flaggedDate = rf.Flagged_Date__c;
                r.applicationId = rf.Passport_Application__c;
                r.applicationName = rf.Passport_Application__r == null
                    ? null : rf.Passport_Application__r.Name;
                p.openRiskFlags.add(r);
            }
        }
        p.openRiskFlagCount = p.openRiskFlags.size();

        return p;
    }

    /**
     * Type-ahead search used by the Citizen 360 lookup.
     */
    @AuraEnabled(cacheable=true)
    public static List<CitizenProfile> search(String term) {
        List<CitizenProfile> out = new List<CitizenProfile>();
        if (String.isBlank(term) || term.trim().length() < 2) {
            return out;
        }
        String term2 = '%' + term.trim() + '%';
        for (Citizen__c c : [
            SELECT Id, Name, Citizen_Reference__c, Mobile__c, City__c, State__c,
                   KYC_Status__c, Date_of_Birth__c
            FROM Citizen__c
            WHERE Name LIKE :term2 OR Mobile__c LIKE :term2 OR Citizen_Reference__c LIKE :term2
            WITH USER_MODE
            ORDER BY Name
            LIMIT 25
        ]) {
            CitizenProfile p = new CitizenProfile();
            p.id = c.Id;
            p.name = c.Name;
            p.citizenReference = c.Citizen_Reference__c;
            p.mobile = c.Mobile__c;
            p.city = c.City__c;
            p.state = c.State__c;
            p.dateOfBirth = c.Date_of_Birth__c;
            KycState k = new KycState();
            k.kycStatus = c.KYC_Status__c;
            p.kyc = k;
            out.add(p);
        }
        return out;
    }
}
