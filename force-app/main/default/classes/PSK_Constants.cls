/**
 * Central string constants for the Passport Seva Kendra domain.
 *
 * Every status / stage / picklist literal used by PSK Apex lives here so the
 * lifecycle order is defined exactly once. Values MUST match the restricted
 * picklists on Passport_Application__c and its children.
 */
public with sharing class PSK_Constants {

    // ---------------------------------------------------------------- Statuses
    public static final String STATUS_DRAFT = 'Draft';
    public static final String STATUS_SUBMITTED = 'Submitted';
    public static final String STATUS_PAYMENT_PENDING = 'Payment Pending';
    public static final String STATUS_PAID = 'Paid';
    public static final String STATUS_DOC_VERIFICATION = 'Document Verification';
    public static final String STATUS_POLICE_VERIFICATION = 'Police Verification';
    public static final String STATUS_GRANTING = 'Granting';
    public static final String STATUS_PRINTING = 'Printing';
    public static final String STATUS_DISPATCH = 'Dispatch';
    public static final String STATUS_DELIVERED = 'Delivered';
    public static final String STATUS_REJECTED = 'Rejected';
    public static final String STATUS_CANCELLED = 'Cancelled';

    /** Happy-path lifecycle, in order. Does not include Rejected / Cancelled. */
    public static final List<String> LIFECYCLE = new List<String>{
        STATUS_DRAFT,
        STATUS_SUBMITTED,
        STATUS_PAYMENT_PENDING,
        STATUS_PAID,
        STATUS_DOC_VERIFICATION,
        STATUS_POLICE_VERIFICATION,
        STATUS_GRANTING,
        STATUS_PRINTING,
        STATUS_DISPATCH,
        STATUS_DELIVERED
    };

    /** Every legal Status__c value including the two terminal exits. */
    public static final List<String> ALL_STATUSES = new List<String>{
        STATUS_DRAFT,
        STATUS_SUBMITTED,
        STATUS_PAYMENT_PENDING,
        STATUS_PAID,
        STATUS_DOC_VERIFICATION,
        STATUS_POLICE_VERIFICATION,
        STATUS_GRANTING,
        STATUS_PRINTING,
        STATUS_DISPATCH,
        STATUS_DELIVERED,
        STATUS_REJECTED,
        STATUS_CANCELLED
    };

    public static final Set<String> TERMINAL_STATUSES = new Set<String>{
        STATUS_DELIVERED, STATUS_REJECTED, STATUS_CANCELLED
    };

    /** Statuses at or beyond which Payment_Status__c must be 'Paid'. */
    public static final Set<String> REQUIRES_PAID = new Set<String>{
        STATUS_GRANTING, STATUS_PRINTING, STATUS_DISPATCH, STATUS_DELIVERED
    };

    /** Zero-based position of a status in the happy path, or -1. */
    public static Integer lifecycleIndex(String status) {
        for (Integer i = 0; i < LIFECYCLE.size(); i++) {
            if (LIFECYCLE[i] == status) {
                return i;
            }
        }
        return -1;
    }

    public static Boolean isAtOrBeyond(String status, String milestone) {
        Integer a = lifecycleIndex(status);
        Integer b = lifecycleIndex(milestone);
        return a >= 0 && b >= 0 && a >= b;
    }

    // ------------------------------------------------------- Payment statuses
    public static final String PAY_NOT_PAID = 'Not Paid';
    public static final String PAY_PENDING = 'Pending';
    public static final String PAY_PAID = 'Paid';
    public static final String PAY_FAILED = 'Failed';
    public static final String PAY_REFUNDED = 'Refunded';

    public static final List<String> PAYMENT_STATUSES = new List<String>{
        PAY_NOT_PAID, PAY_PENDING, PAY_PAID, PAY_FAILED, PAY_REFUNDED
    };

    // Payment__c.Status__c (child record) -- different value set to the parent
    public static final String PAYMENT_INITIATED = 'Initiated';
    public static final String PAYMENT_SUCCESS = 'Success';
    public static final String PAYMENT_FAILED = 'Failed';
    public static final String PAYMENT_REFUNDED = 'Refunded';

    public static final List<String> PAYMENT_RECORD_STATUSES = new List<String>{
        PAYMENT_INITIATED, PAYMENT_SUCCESS, PAYMENT_FAILED, PAYMENT_REFUNDED
    };

    public static final List<String> PAYMENT_MODES = new List<String>{
        'UPI', 'Net Banking', 'Debit Card', 'Credit Card', 'Challan'
    };

    // ----------------------------------------------------------- Record types
    public static final String RT_FRESH = 'Fresh';
    public static final String RT_RE_ISSUE = 'Re_Issue';
    public static final String RT_TATKAL = 'Tatkal';
    public static final String RT_MINOR = 'Minor';
    public static final String RT_LOST_DAMAGED = 'Lost_Damaged';
    public static final String RT_DIPLOMATIC_OFFICIAL = 'Diplomatic_Official';

    public static final List<String> APPLICATION_RECORD_TYPES = new List<String>{
        RT_FRESH, RT_RE_ISSUE, RT_TATKAL, RT_MINOR, RT_LOST_DAMAGED, RT_DIPLOMATIC_OFFICIAL
    };

    public static final String PASSPORT_RT_ORDINARY = 'Ordinary';
    public static final String PASSPORT_RT_DIPLOMATIC = 'Diplomatic';
    public static final String PASSPORT_RT_OFFICIAL = 'Official';

    // ------------------------------------------------------------- Child enums
    public static final List<String> APPOINTMENT_STATUSES = new List<String>{
        'Scheduled', 'Checked In', 'Completed', 'No Show', 'Cancelled'
    };

    public static final String DOC_REQUIRED = 'Required';
    public static final String DOC_RECEIVED = 'Received';
    public static final String DOC_VERIFIED = 'Verified';
    public static final String DOC_REJECTED = 'Rejected';

    public static final List<String> DOCUMENT_STATUSES = new List<String>{
        DOC_REQUIRED, DOC_RECEIVED, DOC_VERIFIED, DOC_REJECTED
    };

    public static final List<String> DOCUMENT_TYPES = new List<String>{
        'Aadhaar Proof', 'Address Proof', 'Date of Birth Proof', 'Annexure',
        'Affidavit', 'Police Clearance Certificate', 'Other'
    };

    public static final List<String> OBJECTION_TYPES = new List<String>{
        'Document Discrepancy', 'Address Mismatch', 'Name Mismatch',
        'Police Verification Adverse', 'Court Order', 'Other'
    };

    public static final List<String> OBJECTION_STATUSES = new List<String>{
        'Open', 'Applicant Notified', 'Resolved', 'Escalated'
    };

    public static final List<String> PV_STATUSES = new List<String>{
        'Not Initiated', 'Referred', 'In Progress', 'Cleared', 'Adverse'
    };

    public static final List<String> PV_TYPES = new List<String>{ 'Pre-PV', 'Post-PV', 'No PV' };

    public static final List<String> RISK_FLAG_TYPES = new List<String>{
        'Duplicate Application', 'Address Anomaly', 'Document Forgery Suspected',
        'Frequent Reissue', 'Other'
    };

    public static final List<String> RISK_STATUSES = new List<String>{
        'Open', 'Under Review', 'Confirmed', 'Dismissed'
    };

    public static final List<String> SEVERITIES = new List<String>{ 'Low', 'Medium', 'High', 'Critical' };

    public static final List<String> NOTIFICATION_CHANNELS = new List<String>{ 'SMS', 'WhatsApp', 'Email' };

    public static final List<String> NOTIFICATION_TYPES = new List<String>{
        'Status Update', 'Payment Reminder', 'Appointment Reminder', 'Renewal Outreach', 'Custom'
    };

    public static final List<String> NOTIFICATION_STATUSES = new List<String>{
        'Queued', 'Sent', 'Delivered', 'Failed'
    };

    public static final List<String> RENEWAL_OUTREACH_STATUSES = new List<String>{
        'Not Started', 'Notified', 'Responded', 'Converted', 'Ignored'
    };

    /** Global value set PSK_Fulfilment_Status -- Print_Job__c.Status__c. */
    public static final String PRINT_QUEUED = 'Queued';

    public static final List<String> PRINT_STATUSES = new List<String>{
        'Queued', 'Printing', 'Quality Check', 'Printed', 'Failed', 'Reprint Required'
    };

    public static final List<String> REPRINT_REASONS = new List<String>{
        'Print Defect', 'Data Error', 'Booklet Damage', 'Lamination Failure'
    };

    public static final String DISPATCH_PENDING = 'Pending';

    public static final List<String> DISPATCH_STATUSES = new List<String>{
        'Pending', 'Packed', 'In Transit', 'Out for Delivery', 'Delivered', 'Returned', 'Lost in Transit'
    };

    public static final List<String> DISPATCH_RETURN_REASONS = new List<String>{
        'Address Not Found', 'Recipient Unavailable', 'Refused', 'Incomplete Address', 'Other'
    };

    /** Global value set PSK_Courier_Partner. */
    public static final List<String> COURIER_PARTNERS = new List<String>{
        'India Post Speed Post', 'BlueDart', 'DTDC', 'Delhivery', 'Hand Delivery'
    };

    // ------------------------------------------------------------- Passport__c
    public static final String PASSPORT_ACTIVE = 'Active';
    public static final String PASSPORT_EXPIRED = 'Expired';
    public static final String PASSPORT_CANCELLED = 'Cancelled';
    public static final String PASSPORT_LOST = 'Lost';
    public static final String PASSPORT_SURRENDERED = 'Surrendered';
    public static final String PASSPORT_REISSUED = 'Reissued';

    /**
     * NOTE: 'Lost' is only exposed on the Ordinary Passport__c record type.
     * Diplomatic / Official record types omit it.
     */
    public static final List<String> PASSPORT_STATUSES = new List<String>{
        PASSPORT_ACTIVE, PASSPORT_EXPIRED, PASSPORT_CANCELLED,
        PASSPORT_LOST, PASSPORT_SURRENDERED, PASSPORT_REISSUED
    };

    public static final List<String> PASSPORT_STATUSES_NON_ORDINARY = new List<String>{
        PASSPORT_ACTIVE, PASSPORT_EXPIRED, PASSPORT_CANCELLED,
        PASSPORT_SURRENDERED, PASSPORT_REISSUED
    };

    public static final List<String> CANCELLATION_REASONS = new List<String>{
        'Reissued', 'Lost', 'Damaged', 'Surrendered', 'Revoked', 'Data Error'
    };

    // ------------------------------------------------------------- Citizen__c
    public static final List<String> KYC_STATUSES = new List<String>{
        'Not Started', 'In Progress', 'Verified', 'Failed'
    };

    public static final List<String> LANGUAGES = new List<String>{
        'Hindi', 'English', 'Marathi', 'Tamil', 'Telugu', 'Bengali',
        'Gujarati', 'Kannada', 'Malayalam', 'Punjabi'
    };

    public static final List<String> GENDERS = new List<String>{ 'Male', 'Female', 'Transgender' };

    public static final List<String> RELATIONSHIPS = new List<String>{
        'Father', 'Mother', 'Spouse', 'Son', 'Daughter', 'Guardian', 'Sibling', 'Other'
    };

    public static final List<String> MARITAL_STATUSES = new List<String>{
        'Single', 'Married', 'Divorced', 'Widowed'
    };

    public static final List<String> REASONS_FOR_REISSUE = new List<String>{
        'Expiry', 'Pages Exhausted', 'Change of Details', 'Damaged', 'Lost'
    };

    public static final List<String> PASSPORT_CATEGORIES = new List<String>{
        'Ordinary', 'Diplomatic', 'Official'
    };

    public static final List<String> ECR_STATUSES = new List<String>{ 'ECR', 'ECNR' };

    public static final List<String> REGIONS = new List<String>{
        'North', 'South', 'East', 'West', 'Central', 'North East'
    };

    /** Indian_States global value set: 28 states + 8 union territories. */
    public static final List<String> INDIAN_STATES = new List<String>{
        'Andhra Pradesh', 'Arunachal Pradesh', 'Assam', 'Bihar', 'Chhattisgarh',
        'Goa', 'Gujarat', 'Haryana', 'Himachal Pradesh', 'Jharkhand', 'Karnataka',
        'Kerala', 'Madhya Pradesh', 'Maharashtra', 'Manipur', 'Meghalaya',
        'Mizoram', 'Nagaland', 'Odisha', 'Punjab', 'Rajasthan', 'Sikkim',
        'Tamil Nadu', 'Telangana', 'Tripura', 'Uttar Pradesh', 'Uttarakhand',
        'West Bengal', 'Andaman and Nicobar Islands', 'Chandigarh',
        'Dadra and Nagar Haveli and Daman and Diu', 'Delhi', 'Jammu and Kashmir',
        'Ladakh', 'Lakshadweep', 'Puducherry'
    };

    /** Clearance_Level__c depends on Passport_Category__c. */
    public static final Map<String, List<String>> CLEARANCE_BY_CATEGORY =
        new Map<String, List<String>>{
            'Diplomatic' => new List<String>{ 'Ambassador', 'Consular', 'Minister' },
            'Official' => new List<String>{ 'Govt Deputation', 'Delegation' }
        };

    /**
     * Record-type picklist availability on Passport_Application__c.
     *
     * A restricted picklist value is only writable if it is ALSO assigned to the
     * record type -- otherwise the platform rejects the row with
     * INVALID_OR_NULL_FOR_RESTRICTED_PICKLIST. These maps mirror the
     * <picklistValues> blocks in
     * objects/Passport_Application__c/recordTypes/*.recordType-meta.xml, so any
     * Apex that stamps one of these fields can pick a legal value for the record
     * type it is writing. Keep them in step with that metadata.
     */
    public static final Map<String, List<String>> PV_TYPES_BY_RECORD_TYPE =
        new Map<String, List<String>>{
            RT_FRESH => new List<String>{ 'Pre-PV', 'Post-PV' },
            RT_RE_ISSUE => new List<String>{ 'Post-PV', 'No PV' },
            RT_TATKAL => new List<String>{ 'Post-PV' },
            RT_MINOR => new List<String>{ 'No PV' },
            RT_LOST_DAMAGED => new List<String>{ 'Pre-PV' },
            RT_DIPLOMATIC_OFFICIAL => new List<String>{ 'No PV' }
        };

    public static final Map<String, List<String>> BOOKLET_PAGES_BY_RECORD_TYPE =
        new Map<String, List<String>>{
            RT_FRESH => new List<String>{ '36', '60' },
            RT_RE_ISSUE => new List<String>{ '36', '60' },
            RT_TATKAL => new List<String>{ '36', '60' },
            RT_MINOR => new List<String>{ '36' },
            RT_LOST_DAMAGED => new List<String>{ '36', '60' },
            RT_DIPLOMATIC_OFFICIAL => new List<String>{ '60' }
        };

    public static final Map<String, List<String>> VALIDITY_BY_RECORD_TYPE =
        new Map<String, List<String>>{
            RT_FRESH => new List<String>{ '10', '5' },
            RT_RE_ISSUE => new List<String>{ '10', '5' },
            RT_TATKAL => new List<String>{ '10', '5' },
            RT_MINOR => new List<String>{ '5' },
            RT_LOST_DAMAGED => new List<String>{ '10', '5' },
            RT_DIPLOMATIC_OFFICIAL => new List<String>{ '10', '5' }
        };

    public static final Map<String, List<String>> ECR_BY_RECORD_TYPE =
        new Map<String, List<String>>{
            RT_FRESH => new List<String>{ 'ECR', 'ECNR' },
            RT_RE_ISSUE => new List<String>{ 'ECR', 'ECNR' },
            RT_TATKAL => new List<String>{ 'ECR', 'ECNR' },
            RT_MINOR => new List<String>{ 'ECNR' },
            RT_LOST_DAMAGED => new List<String>{ 'ECR', 'ECNR' },
            RT_DIPLOMATIC_OFFICIAL => new List<String>{ 'ECNR' }
        };

    /** Record types that expose Reason_For_Reissue__c at all, and with which values. */
    public static final Map<String, List<String>> REISSUE_REASONS_BY_RECORD_TYPE =
        new Map<String, List<String>>{
            RT_RE_ISSUE => new List<String>{ 'Expiry', 'Pages Exhausted', 'Change of Details' },
            RT_TATKAL => new List<String>{ 'Expiry', 'Damaged', 'Lost' },
            RT_LOST_DAMAGED => new List<String>{ 'Damaged', 'Lost' }
        };

    /** Only Diplomatic_Official may carry a non-Ordinary Passport_Category__c. */
    public static final Map<String, List<String>> CATEGORIES_BY_RECORD_TYPE =
        new Map<String, List<String>>{
            RT_FRESH => new List<String>{ 'Ordinary' },
            RT_RE_ISSUE => new List<String>{ 'Ordinary' },
            RT_TATKAL => new List<String>{ 'Ordinary' },
            RT_MINOR => new List<String>{ 'Ordinary' },
            RT_LOST_DAMAGED => new List<String>{ 'Ordinary' },
            RT_DIPLOMATIC_OFFICIAL => new List<String>{ 'Diplomatic', 'Official' }
        };

    /**
     * First legal value of `field` for `recordType`, or `fallback` when the record
     * type is unknown. Deterministic: callers that need variety index into the
     * matching map themselves.
     */
    public static String firstAllowed(Map<String, List<String>> byRecordType,
                                      String recordType, String fallback) {
        List<String> allowed = byRecordType.get(recordType);
        return (allowed == null || allowed.isEmpty()) ? fallback : allowed[0];
    }

    /** Deterministic pick of a record-type-legal value, cycling with `index`. */
    public static String allowedAt(Map<String, List<String>> byRecordType,
                                   String recordType, Integer index, String fallback) {
        List<String> allowed = byRecordType.get(recordType);
        if (allowed == null || allowed.isEmpty()) {
            return fallback;
        }
        Integer i = (index == null) ? 0 : Math.abs(index);
        return allowed[Math.mod(i, allowed.size())];
    }

    // --------------------------------------------------------------- Demo data
    public static final String DEMO_PREFIX = 'DEMO-';
    public static final String CLEANUP_TOKEN = 'DELETE-PSK-DEMO-DATA';

    // ------------------------------------------------------- Ownership routing
    /**
     * Queue DeveloperName a Passport_Application__c should be auto-assigned to
     * when it enters that Status. Statuses not present here (Draft, Submitted,
     * Payment Pending, Paid, and the terminal statuses) keep whoever owns them --
     * that is front-office / applicant-facing work, not a specialist queue.
     * Keep in step with force-app/main/default/queues/*.queue-meta.xml.
     */
    public static final Map<String, String> APPLICATION_STAGE_QUEUE =
        new Map<String, String>{
            STATUS_DOC_VERIFICATION => 'Document_Verification',
            STATUS_POLICE_VERIFICATION => 'Police_Verification',
            STATUS_GRANTING => 'Granting',
            STATUS_PRINTING => 'Printing_And_Dispatch',
            STATUS_DISPATCH => 'Printing_And_Dispatch'
        };

    public static final String QUEUE_POLICE_VERIFICATION = 'Police_Verification';
    public static final String QUEUE_OBJECTIONS = 'Objections';
    public static final String QUEUE_RISK_REVIEW = 'Risk_Review';

    // ------------------------------------------------------------- Approvals
    public static final String APPROVAL_NOT_REQUIRED = 'Not Required';
    public static final String APPROVAL_PENDING = 'Pending';
    public static final String APPROVAL_APPROVED = 'Approved';
    public static final String APPROVAL_REJECTED = 'Rejected';

    public static final List<String> APPROVAL_STATUSES = new List<String>{
        APPROVAL_NOT_REQUIRED, APPROVAL_PENDING, APPROVAL_APPROVED, APPROVAL_REJECTED
    };
}
