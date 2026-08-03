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

    /**
     * Apex test methods in one class run in PARALLEL transactions. The builders
     * below stamp unique External_Id__c / Payment_Reference__c / Office_Code__c
     * values, and a plain 1,2,3... counter restarts at 1 in every method -- so two
     * methods racing each other insert the same unique key and the loser fails
     * with an opaque row-level DML error rather than a duplicate-value message.
     * Seeding the counter's namespace per transaction removes the collision.
     */
    private static final String RUN =
        String.valueOf(Math.abs(Crypto.getRandomInteger())).right(7).leftPad(7, '0');

    private static Integer nextSeq() {
        sequence++;
        return sequence;
    }

    /** Transaction-unique key suffix: '<run>-<n>'. */
    private static String nextKey() {
        return RUN + '-' + nextSeq();
    }

    // ------------------------------------------------------------------- PSK__c

    public static PSK__c buildOffice() {
        Integer n = nextSeq();
        return new PSK__c(
            Name = 'Test PSK ' + n,
            // Office_Code__c is Text(10) and unique: 'T' + 5 run digits + 4 seq digits.
            Office_Code__c = 'T' + RUN.right(5) + String.valueOf(n).leftPad(4, '0'),
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
        return new Slot__c(
            PSK_Office__c = officeId,
            Slot_Date__c = slotDate == null ? Date.today() : slotDate,
            Start_Time__c = Time.newInstance(10, 0, 0, 0),
            End_Time__c = Time.newInstance(11, 0, 0, 0),
            // Capacity_Must_Be_Positive rejects <= 0. Null is legal and means
            // "no capacity configured" -- see buildSlotWithoutCapacity.
            Capacity__c = capacity == null ? 5 : capacity,
            External_Id__c = 'TEST-SLOT-' + nextKey()
        );
    }

    public static Slot__c createSlot(Id officeId, Integer capacity) {
        Slot__c slot = buildSlot(officeId, Date.today(), capacity);
        insert slot;
        return slot;
    }

    /**
     * A slot whose Capacity__c is left NULL. Capacity_Must_Be_Positive only fires
     * on a populated non-positive number, so this is the one shape that reaches
     * AppointmentTriggerHandler's "no capacity configured" guard. A zero would be
     * rejected by the validation rule before the trigger ever saw it.
     */
    public static Slot__c buildSlotWithoutCapacity(Id officeId) {
        Slot__c slot = buildSlot(officeId, Date.today(), null);
        slot.Capacity__c = null;
        return slot;
    }

    public static Slot__c createSlotWithoutCapacity(Id officeId) {
        Slot__c slot = buildSlotWithoutCapacity(officeId);
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
            Citizen_Reference__c = 'TEST-CIT-' + RUN + '-' + n,
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
            Aadhaar_Token__c = 'TOKEN-' + RUN + '-' + n,
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
            External_Id__c = 'TEST-APP-' + RUN + '-' + n,
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

    /**
     * An application on a specific record type.
     *
     * Passport_Category__c, Booklet_Pages__c, Validity_Years__c, ECR_Status__c,
     * Police_Verification_Type__c and Reason_For_Reissue__c are all RESTRICTED
     * picklists whose value sets are further narrowed per record type. Writing a
     * value the record type does not expose fails with
     * INVALID_OR_NULL_FOR_RESTRICTED_PICKLIST, so every one of them is re-stamped
     * here from PSK_Constants' record-type maps rather than left at the
     * Fresh-shaped defaults buildApplication(status) produces.
     */
    public static Passport_Application__c buildApplication(String status, String recordTypeName) {
        Passport_Application__c app = buildApplication(status);
        Id rtId = PSK_ApplicationService.applicationRecordTypeId(recordTypeName);
        if (rtId != null) {
            app.RecordTypeId = rtId;
        }

        app.Passport_Category__c = PSK_Constants.firstAllowed(
            PSK_Constants.CATEGORIES_BY_RECORD_TYPE, recordTypeName, 'Ordinary');
        app.Booklet_Pages__c = PSK_Constants.firstAllowed(
            PSK_Constants.BOOKLET_PAGES_BY_RECORD_TYPE, recordTypeName, '36');
        app.Validity_Years__c = PSK_Constants.firstAllowed(
            PSK_Constants.VALIDITY_BY_RECORD_TYPE, recordTypeName, '10');
        app.ECR_Status__c = PSK_Constants.firstAllowed(
            PSK_Constants.ECR_BY_RECORD_TYPE, recordTypeName, 'ECNR');
        app.Police_Verification_Type__c = PSK_Constants.firstAllowed(
            PSK_Constants.PV_TYPES_BY_RECORD_TYPE, recordTypeName, 'Post-PV');

        if (recordTypeName == PSK_Constants.RT_MINOR) {
            // Minor_Needs_Guardian_Consent + Minor_Validity_Must_Be_5
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
            // Diplomatic_Requires_Clearance_Level, and Clearance_Level__c is a
            // dependent picklist on Passport_Category__c.
            app.Clearance_Level__c = PSK_Constants.CLEARANCE_BY_CATEGORY
                .get(app.Passport_Category__c)[0];
        }
        if (recordTypeName == PSK_Constants.RT_RE_ISSUE
                || recordTypeName == PSK_Constants.RT_LOST_DAMAGED) {
            // Reissue_Requires_Previous_Passport / Lost_Damaged_Requires_Reason
            app.Previous_Passport_No__c =
                PSK_ApplicationService.generateBookletNumber('TEST-PREV-' + app.External_Id__c);
            app.Previous_Passport_Expiry__c = Date.today().addDays(-30);
            app.Reason_For_Reissue__c = PSK_Constants.firstAllowed(
                PSK_Constants.REISSUE_REASONS_BY_RECORD_TYPE, recordTypeName, null);
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
        String s = String.isBlank(status) ? 'Scheduled' : status;
        Appointment__c apt = new Appointment__c(
            Passport_Application__c = applicationId,
            Slot__c = slotId,
            Status__c = s,
            Counter_Number__c = 'C01',
            External_Id__c = 'TEST-APT-' + nextKey()
        );
        // Completed_Requires_Check_In / Check_Out_After_Check_In
        if (s == 'Completed' || s == 'Checked In') {
            apt.Check_In_Time__c = System.now().addHours(-2);
        }
        if (s == 'Completed') {
            apt.Check_Out_Time__c = System.now().addHours(-1);
        }
        return apt;
    }

    public static Payment__c buildPayment(Id applicationId, Decimal amount, String status) {
        String key = nextKey();
        String s = String.isBlank(status) ? PSK_Constants.PAYMENT_SUCCESS : status;
        Payment__c pay = new Payment__c(
            Passport_Application__c = applicationId,
            Amount__c = amount,
            Status__c = s,
            Payment_Mode__c = 'UPI',
            Payment_Date__c = System.now(),
            // Success_Requires_Reference
            Payment_Reference__c = 'TEST-PAYREF-' + key,
            External_Id__c = 'TEST-PAY-' + key
        );
        // Refunded_Requires_Gateway_Response
        if (s == PSK_Constants.PAYMENT_REFUNDED) {
            pay.Gateway_Response__c =
                '{"status":"REFUNDED","refundId":"RFND-' + key + '","gateway":"TEST"}';
        }
        return pay;
    }

    public static Payment__c createPayment(Id applicationId, Decimal amount, String status) {
        Payment__c payment = buildPayment(applicationId, amount, status);
        insert payment;
        return payment;
    }

    public static Document_Checklist_Item__c buildDocument(Id applicationId, String docType,
                                                          String status) {
        String s = String.isBlank(status) ? PSK_Constants.DOC_REQUIRED : status;
        Document_Checklist_Item__c doc = new Document_Checklist_Item__c(
            Passport_Application__c = applicationId,
            Document_Type__c = String.isBlank(docType) ? 'Aadhaar Proof' : docType,
            Status__c = s,
            External_Id__c = 'TEST-DCI-' + nextKey()
        );
        // Received_Requires_Received_Date / Verified_Requires_Verified_Date
        if (s == PSK_Constants.DOC_RECEIVED || s == PSK_Constants.DOC_VERIFIED
                || s == PSK_Constants.DOC_REJECTED) {
            doc.Received_Date__c = Date.today().addDays(-3);
        }
        if (s == PSK_Constants.DOC_VERIFIED) {
            doc.Verified_Date__c = Date.today().addDays(-1);
        }
        // Rejected_Requires_Rejection_Reason
        if (s == PSK_Constants.DOC_REJECTED) {
            doc.Rejection_Reason__c = 'The scan is illegible; please upload a clearer copy.';
        }
        return doc;
    }

    public static Police_Verification__c buildPoliceVerification(Id applicationId, String status) {
        String s = String.isBlank(status) ? 'Referred' : status;
        Police_Verification__c pv = new Police_Verification__c(
            Passport_Application__c = applicationId,
            Status__c = s,
            PV_Type__c = 'Post-PV',
            External_Id__c = 'TEST-PV-' + nextKey()
        );
        // Referred_Requires_Station_And_Date fires for ANY status other than
        // 'Not Initiated', so the station and referral date are unconditional
        // for every verification that has actually started.
        if (s != 'Not Initiated') {
            pv.Police_Station__c = 'Central PS';
            pv.Referred_Date__c = Date.today().addDays(-5);
        }
        // Cleared_Requires_Report_Date (and Report_Date_Not_Before_Referral)
        if (s == 'Cleared') {
            pv.Report_Received_Date__c = Date.today().addDays(-1);
        }
        // Adverse_Requires_Remarks
        if (s == 'Adverse') {
            pv.Report_Received_Date__c = Date.today().addDays(-1);
            pv.Remarks__c = 'Address could not be confirmed at the stated residence.';
        }
        return pv;
    }

    public static Objection__c buildObjection(Id applicationId, String status) {
        String key = nextKey();
        String s = String.isBlank(status) ? 'Open' : status;
        Objection__c obj = new Objection__c(
            Passport_Application__c = applicationId,
            Objection_Type__c = 'Document Discrepancy',
            Status__c = s,
            Raised_Date__c = Date.today().addDays(-3),
            Description__c = 'Test objection ' + key,
            External_Id__c = 'TEST-OBJ-' + key
        );
        // Resolved_Requires_Notes_And_Date + Resolved_Date_Not_Before_Raised
        if (s == 'Resolved') {
            obj.Resolution_Notes__c = 'Applicant supplied the corrected document; closed.';
            obj.Resolved_Date__c = Date.today().addDays(-1);
        }
        return obj;
    }

    public static Risk_Flag__c buildRiskFlag(Id applicationId, String status) {
        String key = nextKey();
        String s = String.isBlank(status) ? 'Open' : status;
        Risk_Flag__c flag = new Risk_Flag__c(
            Passport_Application__c = applicationId,
            Flag_Type__c = 'Address Anomaly',
            Severity__c = 'Medium',
            Status__c = s,
            Flagged_Date__c = Date.today().addDays(-2),
            // Critical_Requires_Description -- always populated, so raising the
            // severity in a test never trips the rule.
            Description__c = 'Test risk flag ' + key,
            External_Id__c = 'TEST-RISK-' + key
        );
        // Reviewed_Requires_Reviewer
        if (s == 'Confirmed' || s == 'Dismissed') {
            flag.Reviewed_By__c = UserInfo.getUserId();
        }
        return flag;
    }

    public static Notification_Log__c buildNotification(Id applicationId, String status) {
        String n = nextKey();
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
        String n = nextKey();
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
        String bookletNo = PSK_ApplicationService.generateBookletNumber('TEST-PASS-' + RUN + '-' + n);
        Date issued = Date.today().addDays(-30);
        String s = String.isBlank(status) ? PSK_Constants.PASSPORT_ACTIVE : status;
        Passport__c passport = new Passport__c(
            Name = bookletNo,
            External_Id__c = bookletNo,
            Application__c = applicationId,
            Citizen__c = citizenId,
            Status__c = s,
            Date_of_Issue__c = issued,
            Date_of_Expiry__c = issued.addYears(10),
            File_Number__c = 'TP' + RUN + String.valueOf(n).leftPad(4, '0'),
            RecordTypeId = PSK_ApplicationService.passportRecordTypeId(
                PSK_Constants.PASSPORT_RT_ORDINARY)
        );
        // Cancelled_Requires_Reason
        if (s == PSK_Constants.PASSPORT_CANCELLED || s == PSK_Constants.PASSPORT_LOST
                || s == PSK_Constants.PASSPORT_SURRENDERED) {
            passport.Cancellation_Reason__c =
                (s == PSK_Constants.PASSPORT_LOST) ? 'Lost'
                    : (s == PSK_Constants.PASSPORT_SURRENDERED ? 'Surrendered' : 'Data Error');
        }
        return passport;
    }

    public static Passport__c createPassport(Id applicationId, Id citizenId) {
        Passport__c passport = buildPassport(applicationId, citizenId, PSK_Constants.PASSPORT_ACTIVE);
        insert passport;
        return passport;
    }

    public static Print_Job__c buildPrintJob(Id applicationId, Id passportId, String status) {
        String key = nextKey();
        String s = String.isBlank(status) ? PSK_Constants.PRINT_QUEUED : status;
        Print_Job__c job = new Print_Job__c(
            Passport_Application__c = applicationId,
            Passport__c = passportId,
            Status__c = s,
            Queued_Date__c = System.now().addHours(-4),
            Attempt_Number__c = 1,
            Batch_Number__c = 'TEST-B001',
            External_Id__c = 'TEST-PJ-' + key
        );
        // Printed_Requires_Date + Printed_Requires_Quality_Check
        if (s == 'Printed') {
            job.Printed_Date__c = System.now().addHours(-1);
            job.Quality_Check_Passed__c = true;
        }
        // Failed_Requires_Reason
        if (s == 'Failed') {
            job.Failure_Reason__c = 'Printer jam on the laminator; booklet discarded.';
        }
        // Reprint_Requires_Reason
        if (s == 'Reprint Required') {
            job.Reprint_Reason__c = 'Print Defect';
        }
        return job;
    }

    public static Dispatch__c buildDispatch(Id applicationId, Id passportId, String status) {
        Integer n = nextSeq();
        String s = String.isBlank(status) ? PSK_Constants.DISPATCH_PENDING : status;
        Dispatch__c dsp = new Dispatch__c(
            Passport_Application__c = applicationId,
            Passport__c = passportId,
            Status__c = s,
            Courier_Partner__c = 'BlueDart',
            // In_Transit_Requires_Tracking -- always populated.
            Tracking_Number__c = 'TT' + RUN + String.valueOf(n).leftPad(4, '0'),
            Dispatched_Date__c = System.now().addDays(-2),
            Delivery_Attempts__c = 1,
            External_Id__c = 'TEST-DSP-' + RUN + '-' + n
        );
        // Delivered_Requires_Date_And_Receiver
        if (s == 'Delivered') {
            dsp.Delivered_Date__c = System.now().addDays(-1);
            dsp.Received_By__c = 'Self';
        }
        // Returned_Requires_Reason
        if (s == 'Returned') {
            dsp.Return_Reason__c = 'Recipient Unavailable';
        }
        return dsp;
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
