/**
 * Shared domain logic for Passport_Application__c.
 *
 * Both PassportApplicationTriggerHandler and the @AuraEnabled controllers
 * (PSK_FeeService, PSK_PassportIssuanceController) delegate here so that a fee
 * calculated by a button matches a fee calculated by the trigger, and a passport
 * issued from the UI is identical to one issued by the status transition.
 *
 * Queries in this class run in SYSTEM mode on purpose: it is invoked from
 * trigger context where the running user may legitimately lack read access to a
 * sibling record that still has to be kept consistent. The @AuraEnabled entry
 * points that call in are responsible for their own user-mode access checks.
 */
public with sharing class PSK_ApplicationService {

    /**
     * Build an AuraHandledException that actually carries its message.
     *
     * `new AuraHandledException(msg)` sets only the field the LWC error handler
     * reads; getMessage() still returns the literal 'Script-thrown exception'.
     * That makes the exception useless in Apex tests and in any log, so
     * setMessage() is called too. Every @AuraEnabled entry point in this app
     * raises its errors through here.
     */
    public static AuraHandledException auraError(String message) {
        String text = String.isBlank(message) ? 'The operation could not be completed.' : message;
        AuraHandledException e = new AuraHandledException(text);
        e.setMessage(text);
        return e;
    }

    // ------------------------------------------------------------------ Wrappers

    public class FeeBreakdown {
        @AuraEnabled public String applicationType;
        @AuraEnabled public Decimal bookletPages;
        @AuraEnabled public Decimal validityYears;
        @AuraEnabled public Boolean tatkal;
        @AuraEnabled public Decimal baseFee;
        @AuraEnabled public Decimal tatkalSurcharge;
        @AuraEnabled public Decimal additionalBookletFee;
        @AuraEnabled public Decimal totalFee;
        @AuraEnabled public String matrixRecord;
        @AuraEnabled public Boolean matched;

        public FeeBreakdown() {
            this.baseFee = 0;
            this.tatkalSurcharge = 0;
            this.additionalBookletFee = 0;
            this.totalFee = 0;
            this.matched = false;
        }
    }

    public class IssuanceResult {
        @AuraEnabled public Id applicationId;
        @AuraEnabled public Id passportId;
        @AuraEnabled public String passportNumber;
        @AuraEnabled public Id printJobId;
        @AuraEnabled public Date dateOfIssue;
        @AuraEnabled public Date dateOfExpiry;
        @AuraEnabled public Boolean created;
        @AuraEnabled public String message;
    }

    // ------------------------------------------------------- Record type helpers

    private static Map<Id, String> appRtNameById;
    private static Map<String, Id> appRtIdByName;

    private static void loadApplicationRecordTypes() {
        if (appRtNameById != null) {
            return;
        }
        appRtNameById = new Map<Id, String>();
        appRtIdByName = new Map<String, Id>();
        for (Schema.RecordTypeInfo rti :
                Passport_Application__c.SObjectType.getDescribe().getRecordTypeInfos()) {
            if (rti.isMaster()) {
                continue;
            }
            appRtNameById.put(rti.getRecordTypeId(), rti.getDeveloperName());
            appRtIdByName.put(rti.getDeveloperName(), rti.getRecordTypeId());
        }
    }

    /** Developer name of a Passport_Application__c record type, or null. */
    public static String applicationRecordTypeName(Id recordTypeId) {
        loadApplicationRecordTypes();
        return recordTypeId == null ? null : appRtNameById.get(recordTypeId);
    }

    public static Id applicationRecordTypeId(String developerName) {
        loadApplicationRecordTypes();
        return developerName == null ? null : appRtIdByName.get(developerName);
    }

    public static Map<String, Id> applicationRecordTypeIds() {
        loadApplicationRecordTypes();
        return appRtIdByName.clone();
    }

    private static Map<String, Id> passportRtIdByName;

    public static Id passportRecordTypeId(String developerName) {
        if (passportRtIdByName == null) {
            passportRtIdByName = new Map<String, Id>();
            for (Schema.RecordTypeInfo rti : Passport__c.SObjectType.getDescribe().getRecordTypeInfos()) {
                if (!rti.isMaster()) {
                    passportRtIdByName.put(rti.getDeveloperName(), rti.getRecordTypeId());
                }
            }
        }
        return developerName == null ? null : passportRtIdByName.get(developerName);
    }

    /**
     * Effective "application type" used to look up Fee_Matrix__mdt. Falls back to
     * Tatkal when the checkbox is on but the record type is not the Tatkal one,
     * and to Fresh when there is no record type at all.
     */
    public static String effectiveApplicationType(Passport_Application__c app) {
        String rtName = applicationRecordTypeName(app.RecordTypeId);
        if (String.isBlank(rtName)) {
            rtName = app.Tatkal__c == true ? PSK_Constants.RT_TATKAL : PSK_Constants.RT_FRESH;
        }
        return rtName;
    }

    // ------------------------------------------------------------ Fee resolution

    private static List<Fee_Matrix__mdt> feeMatrixCache;

    private static List<Fee_Matrix__mdt> feeMatrix() {
        if (feeMatrixCache == null) {
            feeMatrixCache = [
                SELECT DeveloperName, Application_Type__c, Booklet_Pages__c, Validity_Years__c,
                       Base_Fee__c, Tatkal_Surcharge__c, Additional_Booklet_Fee__c, Is_Active__c
                FROM Fee_Matrix__mdt
                WHERE Is_Active__c = true
            ];
        }
        return feeMatrixCache;
    }

    /** Test seam: lets FeeService tests run without deploying custom metadata rows. */
    @TestVisible
    private static void overrideFeeMatrix(List<Fee_Matrix__mdt> rows) {
        feeMatrixCache = rows;
    }

    private static Decimal toDecimal(String picklistValue, Decimal fallbackValue) {
        if (String.isBlank(picklistValue)) {
            return fallbackValue;
        }
        try {
            return Decimal.valueOf(picklistValue.trim());
        } catch (Exception e) {
            return fallbackValue;
        }
    }

    public static Decimal bookletPagesOf(Passport_Application__c app) {
        return toDecimal(app.Booklet_Pages__c, 36);
    }

    public static Integer validityYearsOf(Passport_Application__c app) {
        Decimal d = toDecimal(app.Validity_Years__c, null);
        if (d == null) {
            // Minor passports are 5-year books; everything else defaults to 10.
            return app.Applied_For_Minor__c == true ? 5 : 10;
        }
        return d.intValue();
    }

    /**
     * Resolve the fee for a type / pages / validity combination. Widens the match
     * progressively so a combination with no exact Fee_Matrix__mdt row (for
     * example Diplomatic_Official with a 36-page book) still produces a number.
     */
    public static FeeBreakdown resolveFee(String applicationType, Decimal pages,
                                          Decimal validityYears, Boolean tatkal) {
        FeeBreakdown fb = new FeeBreakdown();
        fb.applicationType = applicationType;
        fb.bookletPages = pages;
        fb.validityYears = validityYears;
        fb.tatkal = tatkal == true;

        Fee_Matrix__mdt exact;
        Fee_Matrix__mdt samePages;
        Fee_Matrix__mdt sameType;

        for (Fee_Matrix__mdt row : feeMatrix()) {
            if (row.Application_Type__c != applicationType) {
                continue;
            }
            if (sameType == null) {
                sameType = row;
            }
            Boolean pagesMatch = pages != null && row.Booklet_Pages__c == pages;
            Boolean validityMatch = validityYears != null && row.Validity_Years__c == validityYears;
            if (pagesMatch && validityMatch) {
                exact = row;
                break;
            }
            if (pagesMatch && samePages == null) {
                samePages = row;
            }
        }

        Fee_Matrix__mdt chosen = exact != null ? exact : (samePages != null ? samePages : sameType);

        if (chosen == null) {
            // No metadata at all -- a safe, obviously-synthetic default rather than null.
            fb.baseFee = 1500;
            fb.matrixRecord = null;
            fb.matched = false;
        } else {
            fb.baseFee = chosen.Base_Fee__c == null ? 0 : chosen.Base_Fee__c;
            fb.additionalBookletFee = chosen.Additional_Booklet_Fee__c == null
                ? 0 : chosen.Additional_Booklet_Fee__c;
            if (fb.tatkal) {
                fb.tatkalSurcharge = chosen.Tatkal_Surcharge__c == null ? 0 : chosen.Tatkal_Surcharge__c;
            }
            fb.matrixRecord = chosen.DeveloperName;
            fb.matched = (exact != null);
        }

        // A 60-page booklet costs more when the matrix only priced the 36-page book.
        if (pages != null && pages > 36 && (exact == null || exact.Booklet_Pages__c != pages)) {
            fb.additionalBookletFee = fb.additionalBookletFee == 0 ? 500 : fb.additionalBookletFee;
        }

        fb.totalFee = (fb.baseFee == null ? 0 : fb.baseFee)
            + (fb.tatkalSurcharge == null ? 0 : fb.tatkalSurcharge)
            + (fb.additionalBookletFee == null ? 0 : fb.additionalBookletFee);
        return fb;
    }

    public static FeeBreakdown resolveFee(Passport_Application__c app) {
        return resolveFee(
            effectiveApplicationType(app),
            bookletPagesOf(app),
            Decimal.valueOf(validityYearsOf(app)),
            app.Tatkal__c == true || effectiveApplicationType(app) == PSK_Constants.RT_TATKAL
        );
    }

    /**
     * Populate Fee__c in place. Only touches records where the fee is blank or
     * one of the driving fields changed, so a manually-overridden fee survives an
     * unrelated edit.
     */
    public static void applyFees(List<Passport_Application__c> apps,
                                 Map<Id, Passport_Application__c> oldMap) {
        for (Passport_Application__c app : apps) {
            Boolean shouldCompute = (app.Fee__c == null || app.Fee__c == 0);
            if (!shouldCompute && oldMap != null && app.Id != null) {
                Passport_Application__c prior = oldMap.get(app.Id);
                if (prior != null) {
                    shouldCompute = app.RecordTypeId != prior.RecordTypeId
                        || app.Booklet_Pages__c != prior.Booklet_Pages__c
                        || app.Validity_Years__c != prior.Validity_Years__c
                        || app.Tatkal__c != prior.Tatkal__c;
                }
            }
            if (shouldCompute) {
                app.Fee__c = (Decimal) resolveFee(app).totalFee;
            }
        }
    }

    // --------------------------------------------------------- Booklet numbering

    /**
     * Leading letters for a booklet number. The Passport_Number_Format validation
     * rule allows ^[A-PR-WY][0-9]{7}$, i.e. everything except Q, X and Z. We
     * additionally drop the visually ambiguous I and O, so this alphabet is a
     * strict subset of what the rule permits.
     */
    private static final String BOOKLET_ALPHABET = 'ABCDEFGHJKLMNPRSTUVWY';

    /**
     * Deterministic passport booklet number matching ^[A-PR-WY][0-9]{7}$.
     * The same seed always produces the same number, which is what keeps the
     * demo generator and the trigger idempotent.
     */
    public static String generateBookletNumber(String seed) {
        String basis = String.isBlank(seed) ? String.valueOf(System.now().getTime()) : seed;
        // Reduce modulo a large prime on every step so the accumulator can never
        // overflow Long, however long the seed is.
        Long h = 2166136261L;
        for (Integer i = 0; i < basis.length(); i++) {
            h = Math.mod(31L * h + basis.charAt(i), 1000000007L);
        }
        if (h < 0) {
            h = -h;
        }
        Long alphabetSize = BOOKLET_ALPHABET.length();
        Integer letterIndex = (Integer) Math.mod(h, alphabetSize);
        Long digits = Math.mod(h / alphabetSize, 10000000L);
        String digitPart = String.valueOf(digits).leftPad(7, '0');
        return BOOKLET_ALPHABET.substring(letterIndex, letterIndex + 1) + digitPart;
    }

    // ------------------------------------------------------------------ Issuance

    /**
     * Create Passport__c + Print_Job__c for the given applications, skipping any
     * application that already has a passport. Safe to call repeatedly.
     */
    public static Map<Id, IssuanceResult> issuePassports(Set<Id> applicationIds) {
        Map<Id, IssuanceResult> results = new Map<Id, IssuanceResult>();
        if (applicationIds == null || applicationIds.isEmpty()) {
            return results;
        }

        Map<Id, Passport_Application__c> apps = new Map<Id, Passport_Application__c>([
            SELECT Id, Name, Status__c, Citizen__c, PSK_Office__c, Passport_Category__c,
                   Booklet_Pages__c, Validity_Years__c, Applied_For_Minor__c, Tatkal__c,
                   Previous_Passport_No__c, First_Name__c, Last_Name__c, RecordTypeId,
                   Payment_Status__c
            FROM Passport_Application__c
            WHERE Id IN :applicationIds
        ]);
        if (apps.isEmpty()) {
            return results;
        }

        // Idempotency guard -- never a second booklet for the same application.
        Map<Id, Passport__c> existingByApp = new Map<Id, Passport__c>();
        for (Passport__c p : [
            SELECT Id, Name, Application__c, Date_of_Issue__c, Date_of_Expiry__c
            FROM Passport__c
            WHERE Application__c IN :apps.keySet()
        ]) {
            existingByApp.put(p.Application__c, p);
        }

        Set<Id> haveJobs = new Set<Id>();
        for (Print_Job__c pj : [
            SELECT Id, Passport_Application__c
            FROM Print_Job__c
            WHERE Passport_Application__c IN :apps.keySet()
        ]) {
            haveJobs.add(pj.Passport_Application__c);
        }

        // Resolve the reissue chain by previous passport number where we can.
        Set<String> priorNumbers = new Set<String>();
        for (Passport_Application__c app : apps.values()) {
            if (String.isNotBlank(app.Previous_Passport_No__c)) {
                priorNumbers.add(app.Previous_Passport_No__c);
            }
        }
        Map<String, Id> priorPassportByNumber = new Map<String, Id>();
        if (!priorNumbers.isEmpty()) {
            for (Passport__c p : [SELECT Id, Name FROM Passport__c WHERE Name IN :priorNumbers]) {
                priorPassportByNumber.put(p.Name, p.Id);
            }
        }

        List<Passport__c> toInsert = new List<Passport__c>();
        List<Id> insertOrder = new List<Id>();

        for (Id appId : apps.keySet()) {
            Passport_Application__c app = apps.get(appId);
            IssuanceResult r = new IssuanceResult();
            r.applicationId = appId;

            Passport__c already = existingByApp.get(appId);
            if (already != null) {
                r.passportId = already.Id;
                r.passportNumber = already.Name;
                r.dateOfIssue = already.Date_of_Issue__c;
                r.dateOfExpiry = already.Date_of_Expiry__c;
                r.created = false;
                r.message = 'Passport ' + already.Name + ' already issued for this application.';
                results.put(appId, r);
                continue;
            }

            Integer validity = validityYearsOf(app);
            Date issued = Date.today();
            String category = String.isBlank(app.Passport_Category__c)
                ? PSK_Constants.PASSPORT_RT_ORDINARY : app.Passport_Category__c;

            Passport__c passport = new Passport__c(
                Name = generateBookletNumber(String.valueOf(appId)),
                Application__c = appId,
                Citizen__c = app.Citizen__c,
                PSK_Office__c = app.PSK_Office__c,
                Status__c = PSK_Constants.PASSPORT_ACTIVE,
                Date_of_Issue__c = issued,
                Date_of_Expiry__c = issued.addYears(validity),
                File_Number__c = fileNumberFor(app),
                RecordTypeId = passportRecordTypeId(category)
            );
            passport.External_Id__c = passport.Name;
            if (String.isNotBlank(app.Previous_Passport_No__c)
                    && priorPassportByNumber.containsKey(app.Previous_Passport_No__c)) {
                passport.Previous_Passport__c = priorPassportByNumber.get(app.Previous_Passport_No__c);
            }
            toInsert.add(passport);
            insertOrder.add(appId);
            results.put(appId, r);
        }

        if (!toInsert.isEmpty()) {
            List<Database.SaveResult> srs = Database.insert(toInsert, false);
            for (Integer i = 0; i < srs.size(); i++) {
                IssuanceResult r = results.get(insertOrder[i]);
                if (srs[i].isSuccess()) {
                    r.passportId = srs[i].getId();
                    r.passportNumber = toInsert[i].Name;
                    r.dateOfIssue = toInsert[i].Date_of_Issue__c;
                    r.dateOfExpiry = toInsert[i].Date_of_Expiry__c;
                    r.created = true;
                    r.message = 'Passport ' + toInsert[i].Name + ' issued.';
                } else {
                    r.created = false;
                    r.message = 'Could not issue passport: ' + firstError(srs[i]);
                }
            }
        }

        // Print jobs -- one per application that does not have one yet.
        List<Print_Job__c> jobs = new List<Print_Job__c>();
        List<Id> jobOrder = new List<Id>();
        for (Id appId : results.keySet()) {
            IssuanceResult r = results.get(appId);
            if (r.passportId == null || haveJobs.contains(appId)) {
                continue;
            }
            jobs.add(new Print_Job__c(
                Passport_Application__c = appId,
                Passport__c = r.passportId,
                Status__c = PSK_Constants.PRINT_QUEUED,
                Queued_Date__c = System.now(),
                Attempt_Number__c = 1,
                Batch_Number__c = 'BATCH-' + Date.today().year() + '-'
                    + String.valueOf(Date.today().dayOfYear()).leftPad(3, '0'),
                Print_Facility__c = apps.get(appId).PSK_Office__c,
                External_Id__c = 'PJ-' + appId
            ));
            jobOrder.add(appId);
        }
        if (!jobs.isEmpty()) {
            List<Database.SaveResult> srs = Database.insert(jobs, false);
            for (Integer i = 0; i < srs.size(); i++) {
                if (srs[i].isSuccess()) {
                    results.get(jobOrder[i]).printJobId = srs[i].getId();
                }
            }
        }

        return results;
    }

    /**
     * Create a Dispatch__c per application that does not yet have one.
     * @return number of dispatches created.
     */
    public static Integer createDispatches(Set<Id> applicationIds) {
        if (applicationIds == null || applicationIds.isEmpty()) {
            return 0;
        }
        Set<Id> already = new Set<Id>();
        for (Dispatch__c d : [
            SELECT Id, Passport_Application__c
            FROM Dispatch__c
            WHERE Passport_Application__c IN :applicationIds
        ]) {
            already.add(d.Passport_Application__c);
        }

        Map<Id, Id> passportByApp = new Map<Id, Id>();
        for (Passport__c p : [
            SELECT Id, Application__c FROM Passport__c WHERE Application__c IN :applicationIds
        ]) {
            passportByApp.put(p.Application__c, p.Id);
        }

        List<Dispatch__c> toInsert = new List<Dispatch__c>();
        for (Id appId : applicationIds) {
            if (already.contains(appId)) {
                continue;
            }
            Integer bucket = Math.abs(String.valueOf(appId).hashCode());
            toInsert.add(new Dispatch__c(
                Passport_Application__c = appId,
                Passport__c = passportByApp.get(appId),
                Status__c = PSK_Constants.DISPATCH_PENDING,
                Courier_Partner__c = PSK_Constants.COURIER_PARTNERS[
                    Math.mod(bucket, PSK_Constants.COURIER_PARTNERS.size())
                ],
                Dispatched_Date__c = System.now(),
                Expected_Delivery_Date__c = Date.today().addDays(5),
                Delivery_Attempts__c = 0,
                Tracking_Number__c = 'TRK' + String.valueOf(Math.mod(bucket, 100000000)).leftPad(9, '0'),
                External_Id__c = 'DSP-' + appId
            ));
        }
        if (toInsert.isEmpty()) {
            return 0;
        }
        Integer created = 0;
        for (Database.SaveResult sr : Database.insert(toInsert, false)) {
            if (sr.isSuccess()) {
                created++;
            }
        }
        return created;
    }

    private static String fileNumberFor(Passport_Application__c app) {
        String basis = String.valueOf(app.Id);
        Integer h = Math.abs(basis.hashCode());
        String tail = String.valueOf(Math.mod(h, 1000000)).leftPad(6, '0');
        return 'PSK' + String.valueOf(Date.today().year()).substring(2) + tail;
    }

    public static String firstError(Database.SaveResult sr) {
        if (sr.getErrors() == null || sr.getErrors().isEmpty()) {
            return 'unknown error';
        }
        return sr.getErrors()[0].getMessage();
    }

    public static String firstError(Database.UpsertResult ur) {
        if (ur.getErrors() == null || ur.getErrors().isEmpty()) {
            return 'unknown error';
        }
        return ur.getErrors()[0].getMessage();
    }

    // ------------------------------------------------- Citizen snapshot handling

    /** Fields copied Citizen -> Application, but only when the application value is blank. */
    public static void copyFromCitizenWhenBlank(List<Passport_Application__c> apps) {
        Set<Id> citizenIds = new Set<Id>();
        for (Passport_Application__c app : apps) {
            if (app.Citizen__c != null) {
                citizenIds.add(app.Citizen__c);
            }
        }
        if (citizenIds.isEmpty()) {
            return;
        }
        Map<Id, Citizen__c> citizens = new Map<Id, Citizen__c>([
            SELECT Id, Date_of_Birth__c, Gender__c, Mobile__c, Email__c, City__c, State__c,
                   Pincode__c, Aadhaar_Verified__c, Aadhaar_Token__c
            FROM Citizen__c
            WHERE Id IN :citizenIds
        ]);

        for (Passport_Application__c app : apps) {
            Citizen__c c = app.Citizen__c == null ? null : citizens.get(app.Citizen__c);
            if (c == null) {
                continue;
            }
            if (app.Date_of_Birth__c == null) {
                app.Date_of_Birth__c = c.Date_of_Birth__c;
            }
            if (String.isBlank(app.Gender__c)) {
                app.Gender__c = c.Gender__c;
            }
            if (String.isBlank(app.Mobile__c)) {
                app.Mobile__c = c.Mobile__c;
            }
            if (String.isBlank(app.Email__c)) {
                app.Email__c = c.Email__c;
            }
            if (String.isBlank(app.City__c)) {
                app.City__c = c.City__c;
            }
            if (String.isBlank(app.State__c)) {
                app.State__c = c.State__c;
            }
            if (String.isBlank(app.Pincode__c)) {
                app.Pincode__c = c.Pincode__c;
            }
            if (app.Aadhaar_Verified__c != true && c.Aadhaar_Verified__c == true) {
                app.Aadhaar_Verified__c = true;
            }
            if (String.isBlank(app.Aadhaar_Token__c)) {
                app.Aadhaar_Token__c = c.Aadhaar_Token__c;
            }
        }
    }

    /**
     * Deterministic natural key for citizen de-duplication:
     * lower(first + last) + date of birth + mobile.
     */
    public static String citizenKey(String firstName, String lastName, Date dob, String mobile) {
        String f = String.isBlank(firstName) ? '' : firstName.trim().toLowerCase();
        String l = String.isBlank(lastName) ? '' : lastName.trim().toLowerCase();
        String d = dob == null ? '' : String.valueOf(dob);
        String m = String.isBlank(mobile) ? '' : mobile.trim().replaceAll('[^0-9]', '');
        return 'CIT-' + (f + l + d + m).left(200).hashCode() + '-' + (f + l).left(12);
    }

    public static String citizenKey(Passport_Application__c app) {
        return citizenKey(app.First_Name__c, app.Last_Name__c, app.Date_of_Birth__c, app.Mobile__c);
    }

    /**
     * Find-or-create a Citizen__c for each application that has none, and stamp
     * Citizen__c on the application. Runs in before-insert context, where DML on
     * a different sObject is allowed.
     */
    public static void ensureCitizens(List<Passport_Application__c> apps) {
        Map<String, List<Passport_Application__c>> needByKey =
            new Map<String, List<Passport_Application__c>>();

        for (Passport_Application__c app : apps) {
            if (app.Citizen__c != null) {
                continue;
            }
            if (String.isBlank(app.First_Name__c) || String.isBlank(app.Last_Name__c)) {
                continue;
            }
            String key = citizenKey(app);
            if (!needByKey.containsKey(key)) {
                needByKey.put(key, new List<Passport_Application__c>());
            }
            needByKey.get(key).add(app);
        }
        if (needByKey.isEmpty()) {
            return;
        }

        Set<String> keys = needByKey.keySet();
        Map<String, Id> existing = new Map<String, Id>();
        for (Citizen__c c : [
            SELECT Id, Citizen_Reference__c FROM Citizen__c WHERE Citizen_Reference__c IN :keys
        ]) {
            existing.put(c.Citizen_Reference__c, c.Id);
        }

        List<Citizen__c> toInsert = new List<Citizen__c>();
        List<String> insertKeys = new List<String>();
        for (String key : keys) {
            if (existing.containsKey(key)) {
                continue;
            }
            Passport_Application__c src = needByKey.get(key)[0];
            toInsert.add(new Citizen__c(
                Name = buildCitizenName(src),
                Citizen_Reference__c = key,
                Date_of_Birth__c = src.Date_of_Birth__c,
                Gender__c = src.Gender__c,
                Mobile__c = src.Mobile__c,
                Email__c = src.Email__c,
                City__c = src.City__c,
                State__c = src.State__c,
                Pincode__c = src.Pincode__c,
                Aadhaar_Verified__c = src.Aadhaar_Verified__c == true,
                Aadhaar_Token__c = src.Aadhaar_Token__c,
                KYC_Status__c = src.Aadhaar_Verified__c == true ? 'Verified' : 'Not Started',
                Notification_Consent__c = src.Notification_Consent__c == true,
                Citizen_Since__c = Date.today()
            ));
            insertKeys.add(key);
        }

        if (!toInsert.isEmpty()) {
            List<Database.SaveResult> srs = Database.insert(toInsert, false);
            for (Integer i = 0; i < srs.size(); i++) {
                if (srs[i].isSuccess()) {
                    existing.put(insertKeys[i], srs[i].getId());
                }
            }
        }

        for (String key : needByKey.keySet()) {
            Id citizenId = existing.get(key);
            if (citizenId == null) {
                continue;
            }
            for (Passport_Application__c app : needByKey.get(key)) {
                app.Citizen__c = citizenId;
            }
        }
    }

    public static String buildCitizenName(Passport_Application__c app) {
        List<String> parts = new List<String>();
        if (String.isNotBlank(app.First_Name__c)) {
            parts.add(app.First_Name__c.trim());
        }
        if (String.isNotBlank(app.Middle_Name__c)) {
            parts.add(app.Middle_Name__c.trim());
        }
        if (String.isNotBlank(app.Last_Name__c)) {
            parts.add(app.Last_Name__c.trim());
        }
        String composed = String.join(parts, ' ');
        return String.isBlank(composed) ? 'Unnamed Citizen' : composed.left(80);
    }

    // ------------------------------------------------------- Ownership routing

    private static Map<String, Id> queueIdByDeveloperName;

    /**
     * Id of a Queue by DeveloperName, or null if no such queue exists (never
     * throws -- a missing queue in a scratch/dev org should not break saves).
     * Cached per transaction.
     */
    public static Id queueId(String developerName) {
        if (String.isBlank(developerName)) {
            return null;
        }
        if (queueIdByDeveloperName == null) {
            queueIdByDeveloperName = new Map<String, Id>();
            for (Group g : [SELECT Id, DeveloperName FROM Group WHERE Type = 'Queue']) {
                queueIdByDeveloperName.put(g.DeveloperName, g.Id);
            }
        }
        return queueIdByDeveloperName.get(developerName);
    }

    /**
     * Auto-assign OwnerId to the specialist queue for the stage a record is
     * entering, replacing manual assignment rules. Only fires on the transition
     * INTO a stage that has a queue (see PSK_Constants.APPLICATION_STAGE_QUEUE),
     * so an officer who has already picked up a record out of the queue keeps it
     * until the record's status moves again -- this never fights a manual
     * reassignment mid-stage.
     */
    public static void routeOwnership(List<Passport_Application__c> newList,
                                      Map<Id, Passport_Application__c> oldMap) {
        for (Passport_Application__c app : newList) {
            String priorStatus = (oldMap != null && app.Id != null && oldMap.containsKey(app.Id))
                ? oldMap.get(app.Id).Status__c : null;
            if (app.Status__c == priorStatus) {
                continue;
            }
            String queueName = PSK_Constants.APPLICATION_STAGE_QUEUE.get(app.Status__c);
            if (queueName == null) {
                continue;
            }
            Id qId = queueId(queueName);
            if (qId != null) {
                app.OwnerId = qId;
            }
        }
    }

    // -------------------------------------------------- Document checklist seeds

    /** Required document types by application record type developer name. */
    public static List<String> checklistTemplate(String recordTypeName) {
        if (recordTypeName == PSK_Constants.RT_MINOR) {
            return new List<String>{
                'Aadhaar Proof', 'Address Proof', 'Date of Birth Proof', 'Annexure'
            };
        }
        if (recordTypeName == PSK_Constants.RT_TATKAL) {
            return new List<String>{
                'Aadhaar Proof', 'Address Proof', 'Date of Birth Proof', 'Annexure', 'Affidavit'
            };
        }
        if (recordTypeName == PSK_Constants.RT_RE_ISSUE) {
            return new List<String>{ 'Aadhaar Proof', 'Address Proof', 'Other' };
        }
        if (recordTypeName == PSK_Constants.RT_LOST_DAMAGED) {
            return new List<String>{
                'Aadhaar Proof', 'Address Proof', 'Affidavit', 'Police Clearance Certificate'
            };
        }
        if (recordTypeName == PSK_Constants.RT_DIPLOMATIC_OFFICIAL) {
            return new List<String>{
                'Aadhaar Proof', 'Address Proof', 'Other', 'Police Clearance Certificate'
            };
        }
        // Fresh and anything unmapped.
        return new List<String>{ 'Aadhaar Proof', 'Address Proof', 'Date of Birth Proof' };
    }

    /**
     * Bulk, idempotent version of the logic behind
     * PSK_DocumentChecklistController.seedFromTemplate -- shared so a checklist
     * seeded by the trigger (on Submit) and one seeded by the button are
     * generated the same way. Skips document types already on the checklist.
     * @return number of checklist items created.
     */
    public static Integer seedChecklistItems(Set<Id> applicationIds) {
        if (applicationIds == null || applicationIds.isEmpty()) {
            return 0;
        }
        Map<Id, Passport_Application__c> apps = new Map<Id, Passport_Application__c>([
            SELECT Id, RecordTypeId FROM Passport_Application__c WHERE Id IN :applicationIds
        ]);
        if (apps.isEmpty()) {
            return 0;
        }

        Map<Id, Set<String>> existingByApp = new Map<Id, Set<String>>();
        for (Document_Checklist_Item__c item : [
            SELECT Passport_Application__c, Document_Type__c
            FROM Document_Checklist_Item__c
            WHERE Passport_Application__c IN :applicationIds
        ]) {
            if (!existingByApp.containsKey(item.Passport_Application__c)) {
                existingByApp.put(item.Passport_Application__c, new Set<String>());
            }
            existingByApp.get(item.Passport_Application__c).add(item.Document_Type__c);
        }

        List<Document_Checklist_Item__c> toInsert = new List<Document_Checklist_Item__c>();
        for (Id appId : apps.keySet()) {
            String rtName = applicationRecordTypeName(apps.get(appId).RecordTypeId);
            Set<String> already = existingByApp.containsKey(appId) ? existingByApp.get(appId) : new Set<String>();
            for (String docType : checklistTemplate(rtName)) {
                if (already.contains(docType)) {
                    continue;
                }
                toInsert.add(new Document_Checklist_Item__c(
                    Passport_Application__c = appId,
                    Document_Type__c = docType,
                    Status__c = PSK_Constants.DOC_REQUIRED,
                    External_Id__c = 'DCI-' + appId + '-' + docType.left(15)
                ));
            }
        }
        if (toInsert.isEmpty()) {
            return 0;
        }
        Integer created = 0;
        for (Database.SaveResult sr : Database.insert(toInsert, false)) {
            if (sr.isSuccess()) {
                created++;
            }
        }
        return created;
    }
}
