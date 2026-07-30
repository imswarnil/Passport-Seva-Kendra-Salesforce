/**
 * Shared test-data builders for the PSK unit tests.
 *
 * Every builder produces records that already satisfy the validation rules on
 * Passport_Application__c -- Require_Core_Fields_On_Submit,
 * Minor_Needs_Guardian_Consent and Cannot_Grant_With_Pending_Payment -- so a test
 * can insert directly at any status without a setup dance.
 *
 * Unit tests must NOT call PSK_DemoDataGenerator: that class writes ~1,200 rows
 * and exists for populating a real org, not for test isolation.
 */
@IsTest
public class PSK_TestDataFactory {

    private static Integer sequence = 0;

    private static Integer nextSeq() {
        sequence++;
        return sequence;
    }

    // ------------------------------------------------------------------- PSK__c

    public static PSK__c buildOffice() {
        Integer n = nextSeq();
        return new PSK__c(
            Name = 'Test PSK ' + n,
            Office_Code__c = 'TST' + String.valueOf(n).leftPad(4, '0'),
            Address_Line1__c = n + ' Test Road',
            City__c = 'Pune',
            District__c = 'Pune',
            State__c = 'Maharashtra',
            Pincode__c = '411001',
            Country__c = 'India',
            Region__c = 'West',
            Capacity_Per_Day__c = 200,
            Contact_Number__c = '9000000000',
            Email__c = 'psk' + n + '@example.com',
            Is_Active__c = true
        );
    }

    public static PSK__c createOffice() {
        PSK__c office = buildOffice();
        insert office;
        return office;
    }

    // ------------------------------------------------------------------ Slot__c

    public static Slot__c buildSlot(Id officeId, Date slotDate, Integer capacity) {
        Integer n = nextSeq();
        return new Slot__c(
            PSK_Office__c = officeId,
            Slot_Date__c = slotDate == null ? Date.today() : slotDate,
            Start_Time__c = Time.newInstance(10, 0, 0, 0),
            End_Time__c = Time.newInstance(11, 0, 0, 0),
            Capacity__c = capacity == null ? 5 : capacity,
            External_Id__c = 'TEST-SLOT-' + n
        );
    }

    public static Slot__c createSlot(Id officeId, Integer capacity) {
        Slot__c slot = buildSlot(officeId, Date.today(), capacity);
        insert slot;
        return slot;
    }

    // --------------------------------------------------------------- Citizen__c

    public static Citizen__c buildCitizen() {
        return buildCitizen(false);
    }

    public static Citizen__c buildCitizen(Boolean minor) {
        Integer n = nextSeq();
        return new Citizen__c(
            Name = 'Test Citizen ' + n,
            Citizen_Reference__c = 'TEST-CIT-' + n,
            Date_of_Birth__c = minor
                ? Date.today().addYears(-10)
                : Date.today().addYears(-32),
            Gender__c = 'Female',
            Mobile__c = '98' + String.valueOf(10000000 + n).leftPad(8, '0'),
            Email__c = 'citizen' + n + '@example.com',
            City__c = 'Pune',
            State__c = 'Maharashtra',
            Pincode__c = '411002',
            KYC_Status__c = 'Verified',
            Aadhaar_Verified__c = true,
            Aadhaar_Token__c = 'TOKEN-' + n,
            Notification_Consent__c = true,
            Preferred_Language__c = 'Marathi',
            Citizen_Since__c = Date.today().addDays(-100)
        );
    }

    public static Citizen__c createCitizen() {
        Citizen__c citizen = buildCitizen(false);
        insert citizen;
        return citizen;
    }

    public static Citizen__c createCitizen(Boolean minor) {
        Citizen__c citizen = buildCitizen(minor);
        insert citizen;
        return citizen;
    }

    // ------------------------------------------------ Passport_Application__c

    /** Minimal, validation-rule-safe application at the given status. */
    public static Passport_Application__c buildApplication(String status) {
        Integer n = nextSeq();
        Passport_Application__c app = new Passport_Application__c(
            External_Id__c = 'TEST-APP-' + n,
            Status__c = String.isBlank(status) ? PSK_Constants.STATUS_DRAFT : status,
            // Require_Core_Fields_On_Submit
            First_Name__c = 'Aarav',
            Last_Name__c = 'Sharma' + n,
            Date_of_Birth__c = Date.newInstance(1990, 4, 12),
            Mobile__c = '97' + String.valueOf(10000000 + n).leftPad(8, '0'),
            Address_Line1__c = n + ' MG Road',
            City__c = 'Pune',
            District__c = 'Pune',
            State__c = 'Maharashtra',
            Pincode__c = '411003',
            Country__c = 'India',
            Email__c = 'applicant' + n + '@example.com',
            Gender__c = 'Male',
            Passport_Category__c = 'Ordinary',
            Booklet_Pages__c = '36',
            Validity_Years__c = '10',
            ECR_Status__c = 'ECNR',
            Police_Verification_Type__c = 'Post-PV'
        );
        // Cannot_Grant_With_Pending_Payment
        app.Payment_Status__c = PSK_Constants.REQUIRES_PAID.contains(app.Status__c)
            ? PSK_Constants.PAY_PAID
            : PSK_Constants.PAY_NOT_PAID;
        return app;
    }

    public static Passport_Application__c buildApplication(String status, String recordTypeName) {
        Passport_Application__c app = buildApplication(status);
        Id rtId = PSK_ApplicationService.applicationRecordTypeId(recordTypeName);
        if (rtId != null) {
            app.RecordTypeId = rtId;
        }
        if (recordTypeName == PSK_Constants.RT_MINOR) {
            // Minor_Needs_Guardian_Consent
            app.Applied_For_Minor__c = true;
            app.Guardian_Consent__c = true;
            app.Guardian_Name__c = 'Rajesh Sharma';
            app.Validity_Years__c = '5';
            app.Date_of_Birth__c = Date.today().addYears(-9);
            app.Marital_Status__c = 'Single';
        }
        if (recordTypeName == PSK_Constants.RT_TATKAL) {
            app.Tatkal__c = true;
        }
        if (recordTypeName == PSK_Constants.RT_DIPLOMATIC_OFFICIAL) {
            app.Passport_Category__c = 'Diplomatic';
            app.Clearance_Level__c = 'Consular';
        }
        if (recordTypeName == PSK_Constants.RT_RE_ISSUE
                || recordTypeName == PSK_Constants.RT_LOST_DAMAGED) {
            app.Previous_Passport_No__c =
                PSK_ApplicationService.generateBookletNumber('TEST-PREV-' + app.External_Id__c);
            app.Previous_Passport_Expiry__c = Date.today().addDays(-30);
            app.Reason_For_Reissue__c = 'Expiry';
        }
        return app;
    }

    public static Passport_Application__c createApplication(String status) {
        Passport_Application__c app = buildApplication(status);
        insert app;
        return app;
    }

    public static Passport_Application__c createApplication(String status, String recordTypeName) {
        Passport_Application__c app = buildApplication(status, recordTypeName);
        insert app;
        return app;
    }

    /** Application already wired to a citizen and an office. */
    public static Passport_Application__c createLinkedApplication(String status) {
        Citizen__c citizen = createCitizen();
        PSK__c office = createOffice();
        Passport_Application__c app = buildApplication(status);
        app.Citizen__c = citizen.Id;
        app.PSK_Office__c = office.Id;
        insert app;
        return app;
    }

    // --------------------------------------------------------------- Children

    public static Appointment__c buildAppointment(Id applicationId, Id slotId, String status) {
        Integer n = nextSeq();
        return new Appointment__c(
            Passport_Application__c = applicationId,
            Slot__c = slotId,
            Status__c = String.isBlank(status) ? 'Scheduled' : status,
            Counter_Number__c = 'C01',
            External_Id__c = 'TEST-APT-' + n
        );
    }

    public static Payment__c buildPayment(Id applicationId, Decimal amount, String status) {
        Integer n = nextSeq();
        return new Payment__c(
            Passport_Application__c = applicationId,
            Amount__c = amount,
            Status__c = String.isBlank(status) ? PSK_Constants.PAYMENT_SUCCESS : status,
            Payment_Mode__c = 'UPI',
            Payment_Date__c = System.now(),
            Payment_Reference__c = 'TEST-PAYREF-' + n,
            External_Id__c = 'TEST-PAY-' + n
        );
    }

    public static Payment__c createPayment(Id applicationId, Decimal amount, String status) {
        Payment__c payment = buildPayment(applicationId, amount, status);
        insert payment;
        return payment;
    }

    public static Document_Checklist_Item__c buildDocument(Id applicationId, String docType,
                                                          String status) {
        Integer n = nextSeq();
        return new Document_Checklist_Item__c(
            Passport_Application__c = applicationId,
            Document_Type__c = String.isBlank(docType) ? 'Aadhaar Proof' : docType,
            Status__c = String.isBlank(status) ? PSK_Constants.DOC_REQUIRED : status,
            External_Id__c = 'TEST-DCI-' + n
        );
    }

    public static Police_Verification__c buildPoliceVerification(Id applicationId, String status) {
        Integer n = nextSeq();
        return new Police_Verification__c(
            Passport_Application__c = applicationId,
            Status__c = String.isBlank(status) ? 'Referred' : status,
            PV_Type__c = 'Post-PV',
            Police_Station__c = 'Central PS',
            Referred_Date__c = Date.today().addDays(-5),
            External_Id__c = 'TEST-PV-' + n
        );
    }

    public static Objection__c buildObjection(Id applicationId, String status) {
        Integer n = nextSeq();
        return new Objection__c(
            Passport_Application__c = applicationId,
            Objection_Type__c = 'Document Discrepancy',
            Status__c = String.isBlank(status) ? 'Open' : status,
            Raised_Date__c = Date.today().addDays(-3),
            Description__c = 'Test objection ' + n,
            External_Id__c = 'TEST-OBJ-' + n
        );
    }

    public static Risk_Flag__c buildRiskFlag(Id applicationId, String status) {
        Integer n = nextSeq();
        return new Risk_Flag__c(
            Passport_Application__c = applicationId,
            Flag_Type__c = 'Address Anomaly',
            Severity__c = 'Medium',
            Status__c = String.isBlank(status) ? 'Open' : status,
            Flagged_Date__c = Date.today().addDays(-2),
            Description__c = 'Test risk flag ' + n,
            External_Id__c = 'TEST-RISK-' + n
        );
    }

    public static Notification_Log__c buildNotification(Id applicationId, String status) {
        Integer n = nextSeq();
        return new Notification_Log__c(
            Passport_Application__c = applicationId,
            Channel__c = 'SMS',
            Message_Type__c = 'Status Update',
            Status__c = String.isBlank(status) ? 'Sent' : status,
            Recipient_Number__c = '9000000001',
            Sent_Date__c = System.now().addDays(-1),
            Message_Body__c = 'Test notification ' + n,
            Provider_Message_Id__c = 'TEST-MSG-' + n,
            External_Id__c = 'TEST-NOTIF-' + n
        );
    }

    public static Renewal__c buildRenewal(Id applicationId, String outreachStatus) {
        Integer n = nextSeq();
        return new Renewal__c(
            Passport_Application__c = applicationId,
            Expiry_Date__c = Date.today().addDays(120),
            Outreach_Status__c = String.isBlank(outreachStatus) ? 'Notified' : outreachStatus,
            Notification_Sent_Date__c = Date.today().addDays(-10),
            External_Id__c = 'TEST-REN-' + n
        );
    }

    public static Family_Member__c buildFamilyMember(Id citizenId, String relationship) {
        Integer n = nextSeq();
        return new Family_Member__c(
            Citizen__c = citizenId,
            Member_Name__c = 'Relative ' + n,
            Relationship__c = String.isBlank(relationship) ? 'Father' : relationship,
            Is_Guardian__c = true
        );
    }

    // -------------------------------------------------------------- Passport__c

    /**
     * Booklet number and External_Id__c always agree, and the issue / expiry dates
     * are always populated, so External_Id_Must_Mirror_Number,
     * Passport_Number_Format and Active_Requires_Issue_And_Expiry_Dates all pass.
     */
    public static Passport__c buildPassport(Id applicationId, Id citizenId, String status) {
        Integer n = nextSeq();
        String number = PSK_ApplicationService.generateBookletNumber('TEST-PASS-' + n);
        Date issued = Date.today().addDays(-30);
        return new Passport__c(
            Name = number,
            External_Id__c = number,
            Application__c = applicationId,
            Citizen__c = citizenId,
            Status__c = String.isBlank(status) ? PSK_Constants.PASSPORT_ACTIVE : status,
            Date_of_Issue__c = issued,
            Date_of_Expiry__c = issued.addYears(10),
            File_Number__c = 'TEST-P' + String.valueOf(n).leftPad(6, '0'),
            RecordTypeId = PSK_ApplicationService.passportRecordTypeId(
                PSK_Constants.PASSPORT_RT_ORDINARY)
        );
    }

    public static Passport__c createPassport(Id applicationId, Id citizenId) {
        Passport__c passport = buildPassport(applicationId, citizenId, PSK_Constants.PASSPORT_ACTIVE);
        insert passport;
        return passport;
    }

    public static Print_Job__c buildPrintJob(Id applicationId, Id passportId, String status) {
        Integer n = nextSeq();
        return new Print_Job__c(
            Passport_Application__c = applicationId,
            Passport__c = passportId,
            Status__c = String.isBlank(status) ? PSK_Constants.PRINT_QUEUED : status,
            Queued_Date__c = System.now().addHours(-4),
            Attempt_Number__c = 1,
            Batch_Number__c = 'TEST-B001',
            External_Id__c = 'TEST-PJ-' + n
        );
    }

    public static Dispatch__c buildDispatch(Id applicationId, Id passportId, String status) {
        Integer n = nextSeq();
        return new Dispatch__c(
            Passport_Application__c = applicationId,
            Passport__c = passportId,
            Status__c = String.isBlank(status) ? PSK_Constants.DISPATCH_PENDING : status,
            Courier_Partner__c = 'BlueDart',
            Tracking_Number__c = 'TESTTRK' + String.valueOf(n).leftPad(6, '0'),
            Dispatched_Date__c = System.now().addDays(-2),
            Delivery_Attempts__c = 1,
            External_Id__c = 'TEST-DSP-' + n
        );
    }

    // -------------------------------------------------------- Custom metadata

    /**
     * In-memory Fee_Matrix__mdt rows. Custom metadata cannot be inserted, but it
     * can be constructed and injected, which keeps fee tests independent of what
     * happens to be deployed in the org.
     */
    public static List<Fee_Matrix__mdt> feeMatrixRows() {
        return new List<Fee_Matrix__mdt>{
            new Fee_Matrix__mdt(
                DeveloperName = 'Test_Fresh_36_10', Application_Type__c = PSK_Constants.RT_FRESH,
                Booklet_Pages__c = 36, Validity_Years__c = 10, Base_Fee__c = 1500,
                Tatkal_Surcharge__c = 2000, Additional_Booklet_Fee__c = 0, Is_Active__c = true
            ),
            new Fee_Matrix__mdt(
                DeveloperName = 'Test_Fresh_60_10', Application_Type__c = PSK_Constants.RT_FRESH,
                Booklet_Pages__c = 60, Validity_Years__c = 10, Base_Fee__c = 2000,
                Tatkal_Surcharge__c = 2000, Additional_Booklet_Fee__c = 0, Is_Active__c = true
            ),
            new Fee_Matrix__mdt(
                DeveloperName = 'Test_Tatkal_36_10', Application_Type__c = PSK_Constants.RT_TATKAL,
                Booklet_Pages__c = 36, Validity_Years__c = 10, Base_Fee__c = 1500,
                Tatkal_Surcharge__c = 2000, Additional_Booklet_Fee__c = 0, Is_Active__c = true
            ),
            new Fee_Matrix__mdt(
                DeveloperName = 'Test_Minor_36_5', Application_Type__c = PSK_Constants.RT_MINOR,
                Booklet_Pages__c = 36, Validity_Years__c = 5, Base_Fee__c = 1000,
                Tatkal_Surcharge__c = 2000, Additional_Booklet_Fee__c = 0, Is_Active__c = true
            )
        };
    }

    /** In-memory SLA_Config__mdt rows for PSK_MyWorkController. */
    public static List<SLA_Config__mdt> slaRows() {
        return new List<SLA_Config__mdt>{
            new SLA_Config__mdt(
                DeveloperName = 'Test_Submitted', Stage__c = PSK_Constants.STATUS_SUBMITTED,
                Service_Type__c = 'Passport', Target_Hours__c = 24, Escalation_Hours__c = 48,
                Owner_Queue_Name__c = 'Submitted', Applies_To_Tatkal__c = false, Is_Active__c = true
            ),
            new SLA_Config__mdt(
                DeveloperName = 'Test_Submitted_Tatkal', Stage__c = PSK_Constants.STATUS_SUBMITTED,
                Service_Type__c = 'Passport', Target_Hours__c = 4, Escalation_Hours__c = 8,
                Owner_Queue_Name__c = 'Tatkal', Applies_To_Tatkal__c = true, Is_Active__c = true
            ),
            new SLA_Config__mdt(
                DeveloperName = 'Test_Granting', Stage__c = PSK_Constants.STATUS_GRANTING,
                Service_Type__c = 'Passport', Target_Hours__c = 48, Escalation_Hours__c = 96,
                Owner_Queue_Name__c = 'Granting', Applies_To_Tatkal__c = false, Is_Active__c = true
            )
        };
    }
}
