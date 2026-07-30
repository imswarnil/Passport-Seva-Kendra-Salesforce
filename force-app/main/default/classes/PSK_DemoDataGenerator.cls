/**
 * Idempotent demo data generator for the Passport Seva Kendra app.
 *
 * DESIGN NOTES -- read before changing anything here.
 *
 * 1. IDEMPOTENCY. Every generated record carries a deterministic external id of
 *    the form DEMO-<OBJ>-<n> and is written with
 *    Database.upsert(list, <ExternalIdField>, false). Running generateAll twice
 *    updates the same 1,200-odd rows instead of doubling them.
 *
 *    Two objects cannot follow that pattern:
 *      - Passport__c, because the validation rule External_Id_Must_Mirror_Number
 *        forces External_Id__c == Name (the booklet number). Its upsert key is
 *        therefore a booklet number derived deterministically from the index, and
 *        File_Number__c carries the DEMO- marker that cleanUp matches on.
 *      - Family_Member__c, which has no unique field at all. It is de-duplicated
 *        in memory against a natural key (citizen + relationship + member name).
 *
 * 2. LIFECYCLE CORRECTNESS. Applications are INSERTED DIRECTLY AT their terminal
 *    status -- never inserted then updated. No_Backward_Move_Once_Delivered reads
 *    PRIORVALUE(Status__c), and the stage-stamping trigger would rewrite
 *    Stage_Entered_Date__c on every hop, so an insert-then-advance approach
 *    produces both validation errors and meaningless timestamps.
 *
 * 3. TRIGGER OWNERSHIP. PSK_AutomationControl.bypassTriggers is set for the whole
 *    run so this class owns child-record creation deterministically. Validation
 *    rules are NOT bypassed by that flag, so every cohort is built to satisfy
 *    them -- see buildApplications for the specific constraints.
 *
 * 4. STORAGE. A Developer Edition org holds roughly 2,500 records in ~5 MB, and
 *    this org already carries the inherited Wave/Service-Analytics sample data
 *    plus 1,005 Accounts. scale = 1 therefore produces about 1,236 records, not
 *    thousands. Do not raise the scale-1 mix without checking storageReport().
 *
 * 5. DETERMINISM. A small linear congruential generator seeded from the record
 *    index provides the pseudo-randomness. Math.random() is deliberately not used:
 *    reruns must be reproducible or the upserts stop being idempotent.
 */
public with sharing class PSK_DemoDataGenerator {

    // ==================================================================== Config

    /** Record counts at scale = 1. Multiplied by scale, floored at 1. */
    private static final Map<String, Integer> SCALE_1_MIX = new Map<String, Integer>{
        'PSK__c' => 6,
        'Slot__c' => 60,
        'Citizen__c' => 120,
        'Family_Member__c' => 60,
        'Passport_Application__c' => 150,
        'Appointment__c' => 90,
        'Document_Checklist_Item__c' => 250,
        'Payment__c' => 110,
        'Objection__c' => 30,
        'Police_Verification__c' => 50,
        'Risk_Flag__c' => 25,
        'Passport__c' => 70,
        'Print_Job__c' => 55,
        'Dispatch__c' => 50,
        'Notification_Log__c' => 90,
        'Renewal__c' => 20
    };

    /** Generation stages, in dependency order. */
    public static final List<String> STAGES = new List<String>{
        'offices', 'slots', 'citizens', 'family', 'applications', 'appointments',
        'documents', 'payments', 'objections', 'police', 'risk', 'passports',
        'printjobs', 'dispatches', 'notifications', 'renewals'
    };

    /** Deletion order -- the reverse of the dependency graph. */
    private static final List<String> DELETE_ORDER = new List<String>{
        'Renewal__c', 'Notification_Log__c', 'Risk_Flag__c', 'Police_Verification__c',
        'Dispatch__c', 'Print_Job__c', 'Objection__c', 'Payment__c',
        'Document_Checklist_Item__c', 'Appointment__c',
        // Passport__c MUST precede Passport_Application__c: Passport__c.Application__c
        // has deleteConstraint Restrict.
        'Passport__c', 'Passport_Application__c',
        'Family_Member__c', 'Citizen__c', 'Slot__c', 'PSK__c'
    };

    private static final Integer CHUNK = 200;
    private static final Integer MAX_OFFICES = 99; // Office_Code__c is Text(10): 'DEMO-PSKnn'

    // ================================================================== Wrappers

    public class ObjectCount {
        @AuraEnabled public String objectName;
        @AuraEnabled public Integer created;
        @AuraEnabled public Integer failed;
        @AuraEnabled public Integer existingTotal;
        public ObjectCount(String objectName) {
            this.objectName = objectName;
            this.created = 0;
            this.failed = 0;
        }
    }

    public class Summary {
        @AuraEnabled public String action;
        @AuraEnabled public Integer scale;
        @AuraEnabled public DateTime startedAt;
        @AuraEnabled public Integer elapsedMs;
        @AuraEnabled public Integer totalUpserted;
        @AuraEnabled public Integer totalFailed;
        @AuraEnabled public Integer totalDeleted;
        @AuraEnabled public List<ObjectCount> counts;
        @AuraEnabled public List<String> errors;
        @AuraEnabled public List<String> messages;

        private Map<String, ObjectCount> byObject = new Map<String, ObjectCount>();
        private Long startMs;

        public Summary(String action, Integer scale) {
            this.action = action;
            this.scale = scale;
            this.startedAt = System.now();
            this.startMs = System.currentTimeMillis();
            this.totalUpserted = 0;
            this.totalFailed = 0;
            this.totalDeleted = 0;
            this.counts = new List<ObjectCount>();
            this.errors = new List<String>();
            this.messages = new List<String>();
        }

        public ObjectCount forObject(String objectName) {
            if (!byObject.containsKey(objectName)) {
                ObjectCount oc = new ObjectCount(objectName);
                byObject.put(objectName, oc);
                counts.add(oc);
            }
            return byObject.get(objectName);
        }

        public void note(String message) {
            this.messages.add(message);
        }

        /** Failures are surfaced, never swallowed. */
        public void fail(String objectName, String message) {
            forObject(objectName).failed++;
            this.totalFailed++;
            if (this.errors.size() < 100) {
                this.errors.add(objectName + ': ' + message);
            }
        }

        public void succeeded(String objectName, Integer howMany) {
            forObject(objectName).created += howMany;
            this.totalUpserted += howMany;
        }

        public void finish() {
            this.elapsedMs = (Integer) (System.currentTimeMillis() - this.startMs);
        }
    }

    // =============================================================== Entry points

    /** Generate every stage in dependency order. */
    public static Summary generateAll(Integer scale) {
        Integer s = normaliseScale(scale);
        Summary sum = new Summary('generateAll', s);
        Boolean priorBypass = PSK_AutomationControl.bypassTriggers;
        PSK_AutomationControl.bypassTriggers = true;
        try {
            for (String stage : STAGES) {
                runStage(stage, s, sum);
            }
        } catch (Exception e) {
            sum.errors.add('Fatal: ' + e.getTypeName() + ' - ' + e.getMessage()
                + ' @ ' + e.getStackTraceString());
        } finally {
            PSK_AutomationControl.bypassTriggers = priorBypass;
            sum.finish();
        }
        return sum;
    }

    /** Generate a single stage. Useful for splitting a run across transactions. */
    public static Summary generateStage(String stageName, Integer scale) {
        Integer s = normaliseScale(scale);
        Summary sum = new Summary('generateStage:' + stageName, s);
        String stage = String.isBlank(stageName) ? '' : stageName.trim().toLowerCase();
        if (!new Set<String>(STAGES).contains(stage)) {
            sum.errors.add('Unknown stage "' + stageName + '". Valid stages: '
                + String.join(STAGES, ', ') + '.');
            sum.finish();
            return sum;
        }
        Boolean priorBypass = PSK_AutomationControl.bypassTriggers;
        PSK_AutomationControl.bypassTriggers = true;
        try {
            runStage(stage, s, sum);
        } catch (Exception e) {
            sum.errors.add('Fatal: ' + e.getTypeName() + ' - ' + e.getMessage());
        } finally {
            PSK_AutomationControl.bypassTriggers = priorBypass;
            sum.finish();
        }
        return sum;
    }

    /**
     * Delete every DEMO- record, in reverse dependency order.
     * @param confirmToken must be exactly 'DELETE-PSK-DEMO-DATA'
     */
    public static Summary cleanUp(String confirmToken) {
        if (confirmToken != PSK_Constants.CLEANUP_TOKEN) {
            throw new PSK_DemoDataException(
                'cleanUp refused: pass the exact confirmation token \''
                + PSK_Constants.CLEANUP_TOKEN + '\' to delete demo data.'
            );
        }
        Summary sum = new Summary('cleanUp', null);
        Boolean priorBypass = PSK_AutomationControl.bypassTriggers;
        PSK_AutomationControl.bypassTriggers = true;
        try {
            for (String objectName : DELETE_ORDER) {
                deleteDemoRecords(objectName, sum);
            }
        } catch (Exception e) {
            sum.errors.add('Fatal: ' + e.getTypeName() + ' - ' + e.getMessage());
        } finally {
            PSK_AutomationControl.bypassTriggers = priorBypass;
            sum.finish();
        }
        return sum;
    }

    /** Wipe and regenerate. */
    public static Summary reset(Integer scale) {
        Summary wipe = cleanUp(PSK_Constants.CLEANUP_TOKEN);
        Summary build = generateAll(scale);
        build.action = 'reset';
        build.totalDeleted = wipe.totalDeleted;
        build.note('Cleanup removed ' + wipe.totalDeleted + ' record(s) before regenerating.');
        for (String e : wipe.errors) {
            build.errors.add('cleanUp -> ' + e);
        }
        return build;
    }

    /** Row counts per object, so storage pressure is visible before and after a run. */
    public static String storageReport() {
        List<String> lines = new List<String>();
        lines.add('PSK storage report @ ' + System.now().format());
        lines.add('-----------------------------------------------');
        Integer grandTotal = 0;
        Integer demoTotal = 0;

        for (String objectName : new List<String>{
            'PSK__c', 'Slot__c', 'Citizen__c', 'Family_Member__c', 'Passport_Application__c',
            'Appointment__c', 'Document_Checklist_Item__c', 'Payment__c', 'Objection__c',
            'Police_Verification__c', 'Risk_Flag__c', 'Passport__c', 'Print_Job__c',
            'Dispatch__c', 'Notification_Log__c', 'Renewal__c'
        }) {
            Integer total = Database.countQuery('SELECT COUNT() FROM ' + objectName);
            Integer demo = Database.countQuery(
                'SELECT COUNT() FROM ' + objectName + ' WHERE ' + demoFilter(objectName)
            );
            grandTotal += total;
            demoTotal += demo;
            lines.add(objectName.rightPad(30) + ' total=' + String.valueOf(total).leftPad(6)
                + '   demo=' + String.valueOf(demo).leftPad(6));
        }

        lines.add('-----------------------------------------------');
        lines.add('PSK objects total'.rightPad(30) + ' total=' + String.valueOf(grandTotal).leftPad(6)
            + '   demo=' + String.valueOf(demoTotal).leftPad(6));
        lines.add('Account (shared, not generated)'.rightPad(30) + ' total='
            + String.valueOf(Database.countQuery('SELECT COUNT() FROM Account')).leftPad(6));
        lines.add('');
        lines.add('Developer Edition holds roughly 2,500 records in ~5 MB of data storage.');
        return String.join(lines, '\n');
    }

    /**
     * Back-fill Citizen__c on legacy applications that predate the lookup.
     * Matches on the same natural key the trigger uses, so a re-run is a no-op.
     * @return number of applications stamped.
     */
    public static Integer backfillCitizens() {
        List<Passport_Application__c> orphans = [
            SELECT Id, First_Name__c, Middle_Name__c, Last_Name__c, Date_of_Birth__c, Mobile__c,
                   Email__c, Gender__c, City__c, State__c, Pincode__c, Aadhaar_Verified__c,
                   Aadhaar_Token__c, Notification_Consent__c
            FROM Passport_Application__c
            WHERE Citizen__c = NULL
              AND First_Name__c != NULL
              AND Last_Name__c != NULL
            LIMIT 2000
        ];
        if (orphans.isEmpty()) {
            return 0;
        }

        // Group by natural key so two applications for the same person share a citizen.
        Map<String, List<Passport_Application__c>> byKey =
            new Map<String, List<Passport_Application__c>>();
        for (Passport_Application__c app : orphans) {
            String key = PSK_ApplicationService.citizenKey(app);
            if (!byKey.containsKey(key)) {
                byKey.put(key, new List<Passport_Application__c>());
            }
            byKey.get(key).add(app);
        }

        List<Citizen__c> citizens = new List<Citizen__c>();
        List<String> keys = new List<String>(byKey.keySet());
        for (String key : keys) {
            Passport_Application__c src = byKey.get(key)[0];
            citizens.add(new Citizen__c(
                Name = PSK_ApplicationService.buildCitizenName(src),
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
        }

        Boolean priorBypass = PSK_AutomationControl.bypassTriggers;
        PSK_AutomationControl.bypassTriggers = true;
        Integer stamped = 0;
        try {
            Map<String, Id> idByKey = new Map<String, Id>();
            for (Integer offset = 0; offset < citizens.size(); offset += CHUNK) {
                Integer endAt = Math.min(offset + CHUNK, citizens.size());
                List<Citizen__c> slice = new List<Citizen__c>();
                List<String> sliceKeys = new List<String>();
                for (Integer i = offset; i < endAt; i++) {
                    slice.add(citizens[i]);
                    sliceKeys.add(keys[i]);
                }
                List<Database.UpsertResult> urs =
                    Database.upsert(slice, Citizen__c.Citizen_Reference__c, false);
                for (Integer i = 0; i < urs.size(); i++) {
                    if (urs[i].isSuccess()) {
                        idByKey.put(sliceKeys[i], urs[i].getId());
                    }
                }
            }

            List<Passport_Application__c> toStamp = new List<Passport_Application__c>();
            for (String key : byKey.keySet()) {
                Id citizenId = idByKey.get(key);
                if (citizenId == null) {
                    continue;
                }
                for (Passport_Application__c app : byKey.get(key)) {
                    toStamp.add(new Passport_Application__c(Id = app.Id, Citizen__c = citizenId));
                }
            }
            for (Integer offset = 0; offset < toStamp.size(); offset += CHUNK) {
                Integer endAt = Math.min(offset + CHUNK, toStamp.size());
                List<Passport_Application__c> slice = new List<Passport_Application__c>();
                for (Integer i = offset; i < endAt; i++) {
                    slice.add(toStamp[i]);
                }
                for (Database.SaveResult sr : Database.update(slice, false)) {
                    if (sr.isSuccess()) {
                        stamped++;
                    }
                }
            }
        } finally {
            PSK_AutomationControl.bypassTriggers = priorBypass;
        }
        return stamped;
    }

    /** LWC entry point. Returns the Summary serialised as JSON. */
    @AuraEnabled
    public static String runFromUI(Integer scale) {
        if (!Schema.sObjectType.Passport_Application__c.isCreateable()) {
            throw new AuraHandledException(
                'You do not have permission to create passport applications.'
            );
        }
        try {
            return JSON.serializePretty(generateAll(scale));
        } catch (Exception e) {
            throw new AuraHandledException('Demo data generation failed: ' + e.getMessage());
        }
    }

    @AuraEnabled
    public static String storageReportFromUI() {
        return storageReport();
    }

    public class PSK_DemoDataException extends Exception {}

    // ================================================================== Dispatch

    private static void runStage(String stage, Integer scale, Summary sum) {
        if (stage == 'offices') {
            buildOffices(scale, sum);
        } else if (stage == 'slots') {
            buildSlots(scale, sum);
        } else if (stage == 'citizens') {
            buildCitizens(scale, sum);
        } else if (stage == 'family') {
            buildFamilyMembers(scale, sum);
        } else if (stage == 'applications') {
            buildApplications(scale, sum);
        } else if (stage == 'appointments') {
            buildAppointments(scale, sum);
        } else if (stage == 'documents') {
            buildDocuments(scale, sum);
        } else if (stage == 'payments') {
            buildPayments(scale, sum);
        } else if (stage == 'objections') {
            buildObjections(scale, sum);
        } else if (stage == 'police') {
            buildPoliceVerifications(scale, sum);
        } else if (stage == 'risk') {
            buildRiskFlags(scale, sum);
        } else if (stage == 'passports') {
            buildPassports(scale, sum);
        } else if (stage == 'printjobs') {
            buildPrintJobs(scale, sum);
        } else if (stage == 'dispatches') {
            buildDispatches(scale, sum);
        } else if (stage == 'notifications') {
            buildNotifications(scale, sum);
        } else if (stage == 'renewals') {
            buildRenewals(scale, sum);
        }
    }

    private static Integer normaliseScale(Integer scale) {
        if (scale == null || scale < 1) {
            return 1;
        }
        // Above 3 a Developer Edition org runs out of data storage.
        return Math.min(scale, 5);
    }

    private static Integer target(String objectName, Integer scale) {
        Integer base = SCALE_1_MIX.get(objectName);
        return base == null ? 0 : Math.max(1, base * scale);
    }

    // ======================================================= Deterministic random

    /**
     * Linear congruential generator (the numerical-recipes constants), seeded from
     * the record index. Deliberately not Math.random(): reruns must reproduce the
     * same values or the idempotent upserts start rewriting fields on every run.
     * All intermediate values stay below 2^61, so no Long overflow.
     */
    public class Lcg {
        private Long state;

        public Lcg(Integer seed) {
            this.state = Math.mod(Math.abs(seed) * 1103515245L + 12345L, 2147483648L);
        }

        public Integer nextInt(Integer bound) {
            state = Math.mod(state * 1103515245L + 12345L, 2147483648L);
            if (bound == null || bound <= 0) {
                return 0;
            }
            Long limit = bound;
            return (Integer) Math.mod(state / 65536L, limit);
        }

        /** Inclusive on both ends. */
        public Integer between(Integer lowValue, Integer highValue) {
            if (highValue <= lowValue) {
                return lowValue;
            }
            return lowValue + nextInt(highValue - lowValue + 1);
        }

        public Boolean chance(Integer percent) {
            return nextInt(100) < percent;
        }

        public String pick(List<String> options) {
            if (options == null || options.isEmpty()) {
                return null;
            }
            return options[nextInt(options.size())];
        }
    }

    // ==================================================================== Corpora

    private static final List<String> MALE_FIRST = new List<String>{
        'Aarav', 'Vivaan', 'Aditya', 'Vihaan', 'Arjun', 'Sai', 'Reyansh', 'Krishna',
        'Ishaan', 'Rohan', 'Rahul', 'Karthik', 'Manish', 'Suresh', 'Rajesh', 'Anil',
        'Vikram', 'Nikhil', 'Prakash', 'Sandeep', 'Harish', 'Deepak', 'Ganesh', 'Mahesh'
    };

    private static final List<String> FEMALE_FIRST = new List<String>{
        'Aadhya', 'Ananya', 'Diya', 'Ishita', 'Kavya', 'Meera', 'Nisha', 'Pooja',
        'Priya', 'Riya', 'Sanya', 'Shreya', 'Sneha', 'Tanvi', 'Anjali', 'Deepika',
        'Lakshmi', 'Neha', 'Radha', 'Sunita', 'Vaishnavi', 'Divya', 'Geeta', 'Rekha'
    };

    private static final List<String> LAST_NAMES = new List<String>{
        'Sharma', 'Verma', 'Patel', 'Reddy', 'Nair', 'Iyer', 'Singh', 'Kumar',
        'Gupta', 'Joshi', 'Desai', 'Mehta', 'Chopra', 'Bose', 'Banerjee', 'Chatterjee',
        'Pillai', 'Menon', 'Rao', 'Naidu', 'Shetty', 'Kulkarni', 'Deshpande', 'Bhatt',
        'Agarwal', 'Malhotra', 'Kapoor', 'Trivedi', 'Pandey', 'Mishra'
    };

    private static final List<String> MIDDLE_NAMES = new List<String>{
        '', '', 'Kumar', 'Devi', 'Lal', 'Prasad', 'Chandra', 'Nath'
    };

    /** city | state | pincode prefix -- states come from the Indian_States value set. */
    private static final List<String> CITY_STATE_PIN = new List<String>{
        'Mumbai|Maharashtra|400',
        'Pune|Maharashtra|411',
        'Nagpur|Maharashtra|440',
        'Delhi|Delhi|110',
        'Bengaluru|Karnataka|560',
        'Mysuru|Karnataka|570',
        'Chennai|Tamil Nadu|600',
        'Coimbatore|Tamil Nadu|641',
        'Hyderabad|Telangana|500',
        'Warangal|Telangana|506',
        'Ahmedabad|Gujarat|380',
        'Surat|Gujarat|395',
        'Jaipur|Rajasthan|302',
        'Jodhpur|Rajasthan|342',
        'Lucknow|Uttar Pradesh|226',
        'Kanpur|Uttar Pradesh|208',
        'Kolkata|West Bengal|700',
        'Siliguri|West Bengal|734',
        'Kochi|Kerala|682',
        'Thiruvananthapuram|Kerala|695',
        'Bhopal|Madhya Pradesh|462',
        'Indore|Madhya Pradesh|452',
        'Patna|Bihar|800',
        'Chandigarh|Chandigarh|160',
        'Amritsar|Punjab|143',
        'Ludhiana|Punjab|141',
        'Bhubaneswar|Odisha|751',
        'Guwahati|Assam|781',
        'Dehradun|Uttarakhand|248',
        'Shimla|Himachal Pradesh|171',
        'Panaji|Goa|403',
        'Raipur|Chhattisgarh|492',
        'Ranchi|Jharkhand|834',
        'Visakhapatnam|Andhra Pradesh|530',
        'Vijayawada|Andhra Pradesh|520',
        'Srinagar|Jammu and Kashmir|190',
        'Leh|Ladakh|194',
        'Imphal|Manipur|795',
        'Shillong|Meghalaya|793',
        'Aizawl|Mizoram|796',
        'Kohima|Nagaland|797',
        'Agartala|Tripura|799',
        'Gangtok|Sikkim|737',
        'Itanagar|Arunachal Pradesh|791',
        'Puducherry|Puducherry|605',
        'Port Blair|Andaman and Nicobar Islands|744',
        'Kavaratti|Lakshadweep|682',
        'Silvassa|Dadra and Nagar Haveli and Daman and Diu|396'
    };

    private static final List<String> STREETS = new List<String>{
        'MG Road', 'Nehru Nagar', 'Gandhi Marg', 'Station Road', 'Civil Lines',
        'Anna Salai', 'Brigade Road', 'Park Street', 'Linking Road', 'Ring Road',
        'Sector 17', 'Rajaji Salai', 'Bandra West', 'Jubilee Hills', 'Koramangala'
    };

    private static final List<String> POLICE_STATIONS = new List<String>{
        'Central PS', 'Cantonment PS', 'City Chowk PS', 'Sadar Bazaar PS',
        'Kotwali PS', 'Gandhi Nagar PS', 'Sector 5 PS', 'Marine Drive PS'
    };

    private static String pinFor(String prefix, Lcg rnd) {
        return prefix + String.valueOf(rnd.between(1, 999)).leftPad(3, '0');
    }

    /** A plausible 10-digit Indian mobile number: first digit 6-9. */
    private static String mobileFor(Lcg rnd) {
        String head = String.valueOf(rnd.between(6, 9));
        String tail = '';
        for (Integer i = 0; i < 9; i++) {
            tail += String.valueOf(rnd.nextInt(10));
        }
        return head + tail;
    }

    // =============================================================== Upsert plumbing

    /**
     * Chunked partial-success upsert keyed on an external id field. Per-row
     * failures are recorded on the Summary rather than aborting the run.
     */
    private static void upsertAll(List<SObject> records, Schema.SObjectField externalIdField,
                                  String objectName, Summary sum) {
        if (records == null || records.isEmpty()) {
            return;
        }
        for (Integer offset = 0; offset < records.size(); offset += CHUNK) {
            Integer endAt = Math.min(offset + CHUNK, records.size());
            List<SObject> slice = new List<SObject>();
            for (Integer i = offset; i < endAt; i++) {
                slice.add(records[i]);
            }
            List<Database.UpsertResult> urs;
            try {
                urs = Database.upsert(slice, externalIdField, false);
            } catch (Exception e) {
                sum.fail(objectName, 'chunk starting at ' + offset + ' threw '
                    + e.getTypeName() + ' - ' + e.getMessage());
                continue;
            }
            Integer ok = 0;
            for (Integer i = 0; i < urs.size(); i++) {
                if (urs[i].isSuccess()) {
                    ok++;
                } else {
                    sum.fail(objectName, PSK_ApplicationService.firstError(urs[i]));
                }
            }
            sum.succeeded(objectName, ok);
        }
    }

    /** Insert with partial success, for objects with no usable external id. */
    private static void insertAll(List<SObject> records, String objectName, Summary sum) {
        if (records == null || records.isEmpty()) {
            return;
        }
        for (Integer offset = 0; offset < records.size(); offset += CHUNK) {
            Integer endAt = Math.min(offset + CHUNK, records.size());
            List<SObject> slice = new List<SObject>();
            for (Integer i = offset; i < endAt; i++) {
                slice.add(records[i]);
            }
            Integer ok = 0;
            for (Database.SaveResult sr : Database.insert(slice, false)) {
                if (sr.isSuccess()) {
                    ok++;
                } else {
                    sum.fail(objectName, PSK_ApplicationService.firstError(sr));
                }
            }
            sum.succeeded(objectName, ok);
        }
    }

    /** SOQL fragment identifying this generator's records, per object. */
    private static String demoFilter(String objectName) {
        if (objectName == 'PSK__c') {
            return 'Office_Code__c LIKE \'DEMO-%\'';
        }
        if (objectName == 'Citizen__c') {
            return 'Citizen_Reference__c LIKE \'DEMO-%\'';
        }
        if (objectName == 'Passport__c') {
            // External_Id__c mirrors the booklet number, so File_Number__c carries the marker.
            return 'File_Number__c LIKE \'DEMO-%\'';
        }
        if (objectName == 'Family_Member__c') {
            return 'Citizen__r.Citizen_Reference__c LIKE \'DEMO-%\'';
        }
        return 'External_Id__c LIKE \'DEMO-%\'';
    }

    private static void deleteDemoRecords(String objectName, Summary sum) {
        List<SObject> victims;
        try {
            victims = Database.query(
                'SELECT Id FROM ' + objectName + ' WHERE ' + demoFilter(objectName) + ' LIMIT 10000'
            );
        } catch (Exception e) {
            sum.fail(objectName, 'query failed - ' + e.getMessage());
            return;
        }
        if (victims.isEmpty()) {
            return;
        }
        Integer deleted = 0;
        for (Integer offset = 0; offset < victims.size(); offset += CHUNK) {
            Integer endAt = Math.min(offset + CHUNK, victims.size());
            List<SObject> slice = new List<SObject>();
            for (Integer i = offset; i < endAt; i++) {
                slice.add(victims[i]);
            }
            for (Database.DeleteResult dr : Database.delete(slice, false)) {
                if (dr.isSuccess()) {
                    deleted++;
                } else {
                    sum.fail(objectName, dr.getErrors().isEmpty()
                        ? 'delete failed' : dr.getErrors()[0].getMessage());
                }
            }
        }
        sum.totalDeleted += deleted;
        sum.forObject(objectName).existingTotal = deleted;
        sum.note('Deleted ' + deleted + ' ' + objectName + ' record(s).');
    }

    // ================================================================ Stage: PSK__c

    private static void buildOffices(Integer scale, Summary sum) {
        Integer howMany = Math.min(target('PSK__c', scale), MAX_OFFICES);
        List<PSK__c> offices = new List<PSK__c>();
        for (Integer i = 1; i <= howMany; i++) {
            Lcg rnd = new Lcg(9100 + i);
            List<String> loc = CITY_STATE_PIN[Math.mod(i * 7, CITY_STATE_PIN.size())].split('\\|');
            offices.add(new PSK__c(
                Name = 'PSK ' + loc[0] + ' (Demo)',
                Office_Code__c = 'DEMO-PSK' + String.valueOf(i).leftPad(2, '0'),
                Address_Line1__c = rnd.between(1, 200) + ' ' + rnd.pick(STREETS),
                Address_Line2__c = 'Passport Seva Kendra Complex',
                City__c = loc[0],
                District__c = loc[0],
                State__c = loc[1],
                Pincode__c = pinFor(loc[2], rnd),
                Country__c = 'India',
                Region__c = PSK_Constants.REGIONS[Math.mod(i - 1, PSK_Constants.REGIONS.size())],
                Capacity_Per_Day__c = rnd.between(4, 12) * 25,
                Contact_Number__c = mobileFor(rnd),
                Email__c = 'psk' + i + '.demo@example.gov.in',
                Is_Active__c = true
            ));
        }
        upsertAll(offices, PSK__c.Office_Code__c, 'PSK__c', sum);
    }

    // =============================================================== Stage: Slot__c

    private static void buildSlots(Integer scale, Summary sum) {
        List<PSK__c> offices = demoOffices();
        if (offices.isEmpty()) {
            sum.fail('Slot__c', 'no demo PSK offices found -- run the "offices" stage first.');
            return;
        }
        Integer howMany = target('Slot__c', scale);
        List<Slot__c> slots = new List<Slot__c>();
        for (Integer i = 1; i <= howMany; i++) {
            Lcg rnd = new Lcg(9200 + i);
            PSK__c office = offices[Math.mod(i - 1, offices.size())];
            // Spread across a fortnight: five working days per office.
            Integer dayOffset = Math.mod((i - 1) / offices.size(), 14);
            Integer startHour = 9 + Math.mod(i, 8);
            slots.add(new Slot__c(
                PSK_Office__c = office.Id,
                Slot_Date__c = Date.today().addDays(dayOffset),
                Start_Time__c = Time.newInstance(startHour, 0, 0, 0),
                End_Time__c = Time.newInstance(startHour + 1, 0, 0, 0),
                // Generous capacity so the Slot_Not_Overbooked validation rule never
                // trips during a bulk load, and re-runs stay safe.
                Capacity__c = rnd.between(8, 15),
                External_Id__c = 'DEMO-SLOT-' + i
            ));
        }
        upsertAll(slots, Slot__c.External_Id__c, 'Slot__c', sum);
    }

    // ============================================================ Stage: Citizen__c

    private static void buildCitizens(Integer scale, Summary sum) {
        Integer howMany = target('Citizen__c', scale);

        // Reuse the Accounts already in the org rather than creating more.
        List<Account> accounts = [SELECT Id FROM Account ORDER BY CreatedDate LIMIT 200];

        List<Citizen__c> citizens = new List<Citizen__c>();
        for (Integer i = 1; i <= howMany; i++) {
            Lcg rnd = new Lcg(9300 + i);
            Boolean female = Math.mod(i, 2) == 0;
            String gender = PSK_Constants.GENDERS[Math.mod(i, 3) == 2 ? 2 : (female ? 1 : 0)];
            String firstName = female ? rnd.pick(FEMALE_FIRST) : rnd.pick(MALE_FIRST);
            String lastName = rnd.pick(LAST_NAMES);
            List<String> loc = CITY_STATE_PIN[Math.mod(i * 5, CITY_STATE_PIN.size())].split('\\|');

            // Every 10th citizen is a minor, so the Minor cohort has real parents.
            Boolean minor = Math.mod(i, 10) == 0;
            Date dob = minor
                ? Date.today().addYears(-rnd.between(3, 17)).addDays(-rnd.between(0, 300))
                : Date.today().addYears(-rnd.between(19, 68)).addDays(-rnd.between(0, 300));

            String kyc = PSK_Constants.KYC_STATUSES[Math.mod(i - 1, PSK_Constants.KYC_STATUSES.size())];
            Boolean blacklisted = Math.mod(i, 37) == 0;

            citizens.add(new Citizen__c(
                Name = firstName + ' ' + lastName,
                Citizen_Reference__c = 'DEMO-CIT-' + i,
                Date_of_Birth__c = dob,
                Gender__c = gender,
                Mobile__c = mobileFor(rnd),
                Email__c = firstName.toLowerCase() + '.' + lastName.toLowerCase()
                    + i + '@example.com',
                City__c = loc[0],
                State__c = loc[1],
                Pincode__c = pinFor(loc[2], rnd),
                KYC_Status__c = kyc,
                Aadhaar_Verified__c = (kyc == 'Verified'),
                Aadhaar_Token__c = 'AADHAAR-TOKEN-' + String.valueOf(i * 7919).leftPad(10, '0'),
                Notification_Consent__c = rnd.chance(80),
                Consent_Timestamp__c = System.now().addDays(-rnd.between(1, 500)),
                Citizen_Since__c = Date.today().addDays(-rnd.between(30, 1800)),
                Preferred_Language__c = PSK_Constants.LANGUAGES[
                    Math.mod(i - 1, PSK_Constants.LANGUAGES.size())
                ],
                Is_Blacklisted__c = blacklisted,
                Blacklist_Reason__c = blacklisted ? 'Demo record flagged for adverse report review.' : null,
                Notes__c = 'Generated by PSK_DemoDataGenerator (DEMO-CIT-' + i + ').',
                Account__c = accounts.isEmpty() || !rnd.chance(40)
                    ? null : accounts[Math.mod(i, accounts.size())].Id
            ));
        }
        upsertAll(citizens, Citizen__c.Citizen_Reference__c, 'Citizen__c', sum);
    }

    // ======================================================= Stage: Family_Member__c

    /**
     * Family_Member__c has no unique field, so it cannot be upserted. Instead the
     * existing rows are read and matched on a natural key -- citizen + relationship
     * + member name -- and only the missing ones inserted.
     */
    private static void buildFamilyMembers(Integer scale, Summary sum) {
        List<Citizen__c> citizens = demoCitizens();
        if (citizens.isEmpty()) {
            sum.fail('Family_Member__c', 'no demo citizens found -- run the "citizens" stage first.');
            return;
        }

        Set<String> existing = new Set<String>();
        for (Family_Member__c fm : [
            SELECT Citizen__c, Relationship__c, Member_Name__c
            FROM Family_Member__c
            WHERE Citizen__r.Citizen_Reference__c LIKE 'DEMO-%'
            LIMIT 10000
        ]) {
            existing.add(fm.Citizen__c + '|' + fm.Relationship__c + '|' + fm.Member_Name__c);
        }

        Integer howMany = target('Family_Member__c', scale);
        List<Family_Member__c> members = new List<Family_Member__c>();
        for (Integer i = 1; i <= howMany; i++) {
            Lcg rnd = new Lcg(9400 + i);
            Citizen__c citizen = citizens[Math.mod(i - 1, citizens.size())];
            String relationship = PSK_Constants.RELATIONSHIPS[
                Math.mod(i - 1, PSK_Constants.RELATIONSHIPS.size())
            ];
            Boolean female = (relationship == 'Mother' || relationship == 'Daughter');
            String memberName = (female ? rnd.pick(FEMALE_FIRST) : rnd.pick(MALE_FIRST))
                + ' ' + rnd.pick(LAST_NAMES);

            String key = citizen.Id + '|' + relationship + '|' + memberName;
            if (existing.contains(key)) {
                continue;
            }
            existing.add(key);

            // Link roughly a third to a real citizen record so the formula fields
            // (Member_Mobile__c, Member_Date_of_Birth__c) resolve.
            Citizen__c related = rnd.chance(35)
                ? citizens[Math.mod(i * 3, citizens.size())] : null;
            if (related != null && related.Id == citizen.Id) {
                related = null;
            }

            members.add(new Family_Member__c(
                Citizen__c = citizen.Id,
                Member_Name__c = memberName,
                Relationship__c = relationship,
                Related_Citizen__c = related == null ? null : related.Id,
                Is_Guardian__c = (relationship == 'Guardian' || relationship == 'Father'
                    || relationship == 'Mother')
            ));
        }
        insertAll(members, 'Family_Member__c', sum);
    }

    // ================================================= Stage: Passport_Application__c

    /**
     * Build one cohort per Status__c value, INSERTED DIRECTLY AT that status.
     *
     * Validation rules honoured here:
     *  - Require_Core_Fields_On_Submit: every record (not just non-Draft) gets
     *    First_Name__c, Last_Name__c, Date_of_Birth__c, Mobile__c, Address_Line1__c
     *    and a Citizen__c.
     *  - Minor_Needs_Guardian_Consent: Applied_For_Minor__c implies
     *    Guardian_Consent__c = true and Validity_Years__c = '5'.
     *  - Cannot_Grant_With_Pending_Payment: Granting and beyond get
     *    Payment_Status__c = 'Paid'.
     *  - No_Backward_Move_Once_Delivered: never triggered, because nothing is
     *    inserted and then advanced.
     *  - Clearance_Level__c is a dependent picklist on Passport_Category__c, so the
     *    Diplomatic_Official cohort picks a level from the matching branch only.
     */
    private static void buildApplications(Integer scale, Summary sum) {
        List<Citizen__c> citizens = demoCitizens();
        List<PSK__c> offices = demoOffices();
        if (citizens.isEmpty() || offices.isEmpty()) {
            sum.fail('Passport_Application__c',
                'demo citizens and offices are required -- run the earlier stages first.');
            return;
        }
        Map<String, Id> rtIds = PSK_ApplicationService.applicationRecordTypeIds();

        Integer howMany = target('Passport_Application__c', scale);
        List<Passport_Application__c> apps = new List<Passport_Application__c>();

        for (Integer i = 1; i <= howMany; i++) {
            Lcg rnd = new Lcg(9500 + i);

            String status = PSK_Constants.ALL_STATUSES[
                Math.mod(i - 1, PSK_Constants.ALL_STATUSES.size())
            ];
            String rtName = PSK_Constants.APPLICATION_RECORD_TYPES[
                Math.mod(i - 1, PSK_Constants.APPLICATION_RECORD_TYPES.size())
            ];
            Boolean isMinorType = (rtName == PSK_Constants.RT_MINOR);
            Boolean isTatkal = (rtName == PSK_Constants.RT_TATKAL);
            Boolean isDiplomatic = (rtName == PSK_Constants.RT_DIPLOMATIC_OFFICIAL);
            Boolean isReissue = (rtName == PSK_Constants.RT_RE_ISSUE);
            Boolean isLostDamaged = (rtName == PSK_Constants.RT_LOST_DAMAGED);

            // Pick a citizen whose age suits the record type.
            Citizen__c citizen = pickCitizen(citizens, i, isMinorType);
            List<String> loc = CITY_STATE_PIN[Math.mod(i * 3, CITY_STATE_PIN.size())].split('\\|');

            Boolean female = Math.mod(i, 2) == 0;
            String gender = PSK_Constants.GENDERS[Math.mod(i, 7) == 3 ? 2 : (female ? 1 : 0)];
            String firstName = female ? rnd.pick(FEMALE_FIRST) : rnd.pick(MALE_FIRST);
            String lastName = rnd.pick(LAST_NAMES);
            String middleName = MIDDLE_NAMES[Math.mod(i, MIDDLE_NAMES.size())];

            Date dob = isMinorType
                ? Date.today().addYears(-rnd.between(4, 17)).addDays(-rnd.between(0, 300))
                : Date.today().addYears(-rnd.between(19, 66)).addDays(-rnd.between(0, 300));

            String category = 'Ordinary';
            String clearance = null;
            if (isDiplomatic) {
                category = Math.mod(i, 2) == 0 ? 'Diplomatic' : 'Official';
                List<String> branch = PSK_Constants.CLEARANCE_BY_CATEGORY.get(category);
                clearance = branch[Math.mod(i, branch.size())];
            }

            String validity = isMinorType ? '5' : (Math.mod(i, 11) == 0 ? '5' : '10');
            String bookletPages = Math.mod(i, 3) == 0 ? '60' : '36';

            Passport_Application__c app = new Passport_Application__c(
                External_Id__c = 'DEMO-APP-' + i,
                RecordTypeId = rtIds.get(rtName),
                Status__c = status,
                Citizen__c = citizen.Id,
                PSK_Office__c = offices[Math.mod(i - 1, offices.size())].Id,

                // Require_Core_Fields_On_Submit
                First_Name__c = firstName,
                Middle_Name__c = String.isBlank(middleName) ? null : middleName,
                Last_Name__c = lastName,
                Date_of_Birth__c = dob,
                Mobile__c = mobileFor(rnd),
                Address_Line1__c = rnd.between(1, 400) + ', ' + rnd.pick(STREETS),

                Address_Line2__c = rnd.chance(50) ? 'Near ' + rnd.pick(STREETS) : null,
                City__c = loc[0],
                District__c = loc[0],
                State__c = loc[1],
                Pincode__c = pinFor(loc[2], rnd),
                Country__c = 'India',
                Years_At_Address__c = rnd.between(1, 25),

                Email__c = firstName.toLowerCase() + '.' + lastName.toLowerCase()
                    + i + '@example.com',
                Mobile_For_Alerts__c = mobileFor(rnd),
                Gender__c = gender,
                Place_of_Birth__c = loc[0],
                Father_Name__c = rnd.pick(MALE_FIRST) + ' ' + lastName,
                Mother_Name__c = rnd.pick(FEMALE_FIRST) + ' ' + lastName,
                Marital_Status__c = isMinorType
                    ? 'Single'
                    : PSK_Constants.MARITAL_STATUSES[
                        Math.mod(i - 1, PSK_Constants.MARITAL_STATUSES.size())
                      ],

                Passport_Category__c = category,
                Clearance_Level__c = clearance,
                Booklet_Pages__c = bookletPages,
                Validity_Years__c = validity,
                ECR_Status__c = PSK_Constants.ECR_STATUSES[Math.mod(i - 1, 2)],
                Tatkal__c = isTatkal,

                Police_Verification_Type__c = PSK_Constants.PV_TYPES[
                    Math.mod(i - 1, PSK_Constants.PV_TYPES.size())
                ],
                Risk_Score__c = rnd.between(0, 100),

                Aadhaar_Verified__c = rnd.chance(75),
                Aadhaar_Token__c = 'AADHAAR-TOKEN-' + String.valueOf(i * 7919).leftPad(10, '0'),
                Notification_Consent__c = rnd.chance(85),
                Consent_Timestamp__c = System.now().addDays(-rnd.between(1, 200))
            );

            // Minor_Needs_Guardian_Consent
            if (isMinorType) {
                app.Applied_For_Minor__c = true;
                app.Guardian_Consent__c = true;
                app.Guardian_Name__c = rnd.pick(MALE_FIRST) + ' ' + lastName;
            }
            if (!isMinorType && !String.isBlank(app.Marital_Status__c)
                    && app.Marital_Status__c == 'Married') {
                app.Spouse_Name__c = (female ? rnd.pick(MALE_FIRST) : rnd.pick(FEMALE_FIRST))
                    + ' ' + lastName;
            }
            if (isReissue || isLostDamaged) {
                app.Previous_Passport_No__c =
                    PSK_ApplicationService.generateBookletNumber('DEMO-PREV-' + i);
                app.Previous_Passport_Expiry__c = Date.today().addDays(-rnd.between(1, 900));
                app.Reason_For_Reissue__c = isLostDamaged
                    ? (Math.mod(i, 2) == 0 ? 'Lost' : 'Damaged')
                    : PSK_Constants.REASONS_FOR_REISSUE[
                        Math.mod(i - 1, PSK_Constants.REASONS_FOR_REISSUE.size())
                      ];
            }

            applyStatusFields(app, status, i, rnd);

            // Fee comes from the same Fee_Matrix__mdt path the trigger uses.
            app.Fee__c = PSK_ApplicationService.resolveFee(
                rtName,
                Decimal.valueOf(bookletPages),
                Decimal.valueOf(validity),
                isTatkal
            ).totalFee;

            apps.add(app);
        }

        upsertAll(apps, Passport_Application__c.External_Id__c, 'Passport_Application__c', sum);
    }

    /**
     * Status-consistent dates and payment state. Every one of the five
     * Payment_Status__c values appears: Granting-and-beyond is forced to Paid, so
     * Failed and Refunded are placed on the Rejected and Cancelled cohorts and
     * Not Paid / Pending on the early stages.
     */
    private static void applyStatusFields(Passport_Application__c app, String status,
                                          Integer i, Lcg rnd) {
        DateTime nowStamp = System.now();
        Integer age = rnd.between(1, 45);

        if (status == PSK_Constants.STATUS_DRAFT) {
            app.Payment_Status__c = PSK_Constants.PAY_NOT_PAID;
            app.Stage_Entered_Date__c = nowStamp.addDays(-age);
            return;
        }

        // Everything past Draft has been submitted.
        app.Submitted_Date__c = nowStamp.addDays(-age);
        app.Stage_Entered_Date__c = nowStamp.addDays(-rnd.between(0, Math.max(1, age / 2)));

        if (status == PSK_Constants.STATUS_REJECTED) {
            app.Payment_Status__c = PSK_Constants.PAY_FAILED;
        } else if (status == PSK_Constants.STATUS_CANCELLED) {
            app.Payment_Status__c = PSK_Constants.PAY_REFUNDED;
        } else if (PSK_Constants.REQUIRES_PAID.contains(status)) {
            // Cannot_Grant_With_Pending_Payment
            app.Payment_Status__c = PSK_Constants.PAY_PAID;
        } else if (status == PSK_Constants.STATUS_SUBMITTED
                || status == PSK_Constants.STATUS_PAYMENT_PENDING) {
            app.Payment_Status__c = Math.mod(i, 2) == 0
                ? PSK_Constants.PAY_PENDING : PSK_Constants.PAY_NOT_PAID;
        } else {
            // Paid, Document Verification, Police Verification
            app.Payment_Status__c = PSK_Constants.PAY_PAID;
        }

        if (app.Payment_Status__c == PSK_Constants.PAY_PAID
                || app.Payment_Status__c == PSK_Constants.PAY_REFUNDED) {
            app.Payment_Date__c = app.Submitted_Date__c.addDays(1);
            app.Payment_Mode__c = PSK_Constants.PAYMENT_MODES[
                Math.mod(i - 1, PSK_Constants.PAYMENT_MODES.size())
            ];
            app.Payment_Reference__c = 'DEMO-APPPAY-' + i;
        }

        if (PSK_Constants.isAtOrBeyond(status, PSK_Constants.STATUS_POLICE_VERIFICATION)) {
            app.Documents_Verified__c = true;
        }
        if (PSK_Constants.isAtOrBeyond(status, PSK_Constants.STATUS_GRANTING)) {
            app.Granted_Date__c = app.Submitted_Date__c.addDays(rnd.between(2, 10));
        }
    }

    private static Citizen__c pickCitizen(List<Citizen__c> citizens, Integer i, Boolean wantMinor) {
        // Minors were seeded at every 10th index in buildCitizens.
        Integer start = Math.mod(i - 1, citizens.size());
        for (Integer step = 0; step < citizens.size(); step++) {
            Citizen__c c = citizens[Math.mod(start + step, citizens.size())];
            Boolean isMinor = (c.Is_Minor__c == true);
            if (isMinor == wantMinor) {
                return c;
            }
        }
        return citizens[start];
    }

    // ======================================================== Stage: Appointment__c

    private static void buildAppointments(Integer scale, Summary sum) {
        List<Passport_Application__c> apps = demoApplications();
        List<Slot__c> slots = demoSlots();
        if (apps.isEmpty() || slots.isEmpty()) {
            sum.fail('Appointment__c',
                'demo applications and slots are required -- run the earlier stages first.');
            return;
        }

        // Only applications that actually got as far as an appointment.
        List<Passport_Application__c> eligible = new List<Passport_Application__c>();
        for (Passport_Application__c app : apps) {
            if (app.Status__c != PSK_Constants.STATUS_DRAFT) {
                eligible.add(app);
            }
        }
        if (eligible.isEmpty()) {
            eligible = apps;
        }

        Integer howMany = Math.min(target('Appointment__c', scale), eligible.size());
        List<Appointment__c> appointments = new List<Appointment__c>();
        for (Integer i = 1; i <= howMany; i++) {
            Lcg rnd = new Lcg(9600 + i);
            Passport_Application__c app = eligible[Math.mod(i - 1, eligible.size())];
            // Round-robin across slots so no slot approaches Capacity__c and the
            // Slot_Not_Overbooked validation rule never fires on a bulk load.
            Slot__c slot = slots[Math.mod(i - 1, slots.size())];
            String status = PSK_Constants.APPOINTMENT_STATUSES[
                Math.mod(i - 1, PSK_Constants.APPOINTMENT_STATUSES.size())
            ];

            DateTime checkIn = null;
            DateTime checkOut = null;
            if (status == 'Checked In' || status == 'Completed') {
                checkIn = DateTime.newInstance(
                    slot.Slot_Date__c,
                    slot.Start_Time__c == null ? Time.newInstance(10, 0, 0, 0) : slot.Start_Time__c
                );
                if (status == 'Completed') {
                    checkOut = checkIn.addMinutes(rnd.between(25, 95));
                }
            }

            appointments.add(new Appointment__c(
                External_Id__c = 'DEMO-APT-' + i,
                Passport_Application__c = app.Id,
                Slot__c = slot.Id,
                Status__c = status,
                Counter_Number__c = 'C' + String.valueOf(rnd.between(1, 24)).leftPad(2, '0'),
                Check_In_Time__c = checkIn,
                Check_Out_Time__c = checkOut
            ));
        }
        upsertAll(appointments, Appointment__c.External_Id__c, 'Appointment__c', sum);
    }

    // ============================================= Stage: Document_Checklist_Item__c

    private static void buildDocuments(Integer scale, Summary sum) {
        List<Passport_Application__c> apps = demoApplications();
        if (apps.isEmpty()) {
            sum.fail('Document_Checklist_Item__c',
                'no demo applications found -- run the "applications" stage first.');
            return;
        }

        Integer howMany = target('Document_Checklist_Item__c', scale);
        List<Document_Checklist_Item__c> items = new List<Document_Checklist_Item__c>();
        Integer counter = 0;
        Integer appIndex = 0;

        while (counter < howMany) {
            Passport_Application__c app = apps[Math.mod(appIndex, apps.size())];
            appIndex++;
            Integer perApp = 3 + Math.mod(appIndex, 3); // 3-5 documents
            for (Integer j = 0; j < perApp && counter < howMany; j++) {
                counter++;
                Lcg rnd = new Lcg(9700 + counter);
                String docType = PSK_Constants.DOCUMENT_TYPES[
                    Math.mod(counter - 1, PSK_Constants.DOCUMENT_TYPES.size())
                ];
                String status = PSK_Constants.DOCUMENT_STATUSES[
                    Math.mod(counter - 1, PSK_Constants.DOCUMENT_STATUSES.size())
                ];
                // A Draft application has not handed anything over yet.
                if (app.Status__c == PSK_Constants.STATUS_DRAFT) {
                    status = PSK_Constants.DOC_REQUIRED;
                }

                Date received = (status == PSK_Constants.DOC_REQUIRED)
                    ? null : Date.today().addDays(-rnd.between(2, 40));
                Date verified = (status == PSK_Constants.DOC_VERIFIED)
                    ? received.addDays(rnd.between(0, 3)) : null;

                items.add(new Document_Checklist_Item__c(
                    External_Id__c = 'DEMO-DCI-' + counter,
                    Passport_Application__c = app.Id,
                    Document_Type__c = docType,
                    Status__c = status,
                    Received_Date__c = received,
                    Verified_Date__c = verified,
                    Rejection_Reason__c = (status == PSK_Constants.DOC_REJECTED)
                        ? 'Illegible scan - applicant asked to resubmit.' : null,
                    Notes__c = 'Demo checklist item for ' + docType + '.'
                ));
            }
        }
        upsertAll(items, Document_Checklist_Item__c.External_Id__c,
            'Document_Checklist_Item__c', sum);
    }

    // ============================================================ Stage: Payment__c

    private static void buildPayments(Integer scale, Summary sum) {
        List<Passport_Application__c> apps = demoApplications();
        if (apps.isEmpty()) {
            sum.fail('Payment__c', 'no demo applications found -- run the "applications" stage first.');
            return;
        }

        // Applications that have moved past the payment gate first.
        List<Passport_Application__c> paying = new List<Passport_Application__c>();
        for (Passport_Application__c app : apps) {
            if (app.Status__c != PSK_Constants.STATUS_DRAFT) {
                paying.add(app);
            }
        }
        if (paying.isEmpty()) {
            paying = apps;
        }

        Integer howMany = target('Payment__c', scale);
        List<Payment__c> payments = new List<Payment__c>();
        for (Integer i = 1; i <= howMany; i++) {
            Lcg rnd = new Lcg(9800 + i);
            Passport_Application__c app = paying[Math.mod(i - 1, paying.size())];

            String status = PSK_Constants.PAYMENT_RECORD_STATUSES[
                Math.mod(i - 1, PSK_Constants.PAYMENT_RECORD_STATUSES.size())
            ];
            // Keep the child consistent with the parent's payment state.
            if (app.Payment_Status__c == PSK_Constants.PAY_PAID
                    && Math.mod(i, 4) != 0) {
                status = PSK_Constants.PAYMENT_SUCCESS;
            }

            Decimal fee = (app.Fee__c == null || app.Fee__c <= 0) ? 1500 : app.Fee__c;
            Decimal amount = (status == PSK_Constants.PAYMENT_SUCCESS)
                ? fee
                : (status == PSK_Constants.PAYMENT_REFUNDED ? fee : (fee / 2).setScale(2));

            payments.add(new Payment__c(
                External_Id__c = 'DEMO-PAY-' + i,
                Passport_Application__c = app.Id,
                Payment_Reference__c = 'DEMO-PAYREF-' + String.valueOf(i).leftPad(8, '0'),
                Amount__c = amount,
                Status__c = status,
                Payment_Mode__c = PSK_Constants.PAYMENT_MODES[
                    Math.mod(i - 1, PSK_Constants.PAYMENT_MODES.size())
                ],
                Payment_Date__c = System.now().addDays(-rnd.between(1, 60)),
                Gateway_Response__c = '{"demo":true,"status":"' + status
                    + '","reference":"DEMO-PAYREF-' + i + '"}'
            ));
        }
        upsertAll(payments, Payment__c.External_Id__c, 'Payment__c', sum);
    }

    // ========================================================== Stage: Objection__c

    private static void buildObjections(Integer scale, Summary sum) {
        List<Passport_Application__c> apps = demoApplications();
        if (apps.isEmpty()) {
            sum.fail('Objection__c', 'no demo applications found.');
            return;
        }
        Integer howMany = target('Objection__c', scale);
        List<Objection__c> objections = new List<Objection__c>();
        for (Integer i = 1; i <= howMany; i++) {
            Lcg rnd = new Lcg(9900 + i);
            Passport_Application__c app = apps[Math.mod(i * 3, apps.size())];
            String status = PSK_Constants.OBJECTION_STATUSES[
                Math.mod(i - 1, PSK_Constants.OBJECTION_STATUSES.size())
            ];
            Date raised = Date.today().addDays(-rnd.between(3, 90));
            objections.add(new Objection__c(
                External_Id__c = 'DEMO-OBJ-' + i,
                Passport_Application__c = app.Id,
                Objection_Type__c = PSK_Constants.OBJECTION_TYPES[
                    Math.mod(i - 1, PSK_Constants.OBJECTION_TYPES.size())
                ],
                Status__c = status,
                Raised_Date__c = raised,
                Resolved_Date__c = (status == 'Resolved') ? raised.addDays(rnd.between(1, 20)) : null,
                Description__c = 'Demo objection raised during verification of application '
                    + app.Name + '.',
                Resolution_Notes__c = (status == 'Resolved')
                    ? 'Applicant supplied the corrected document; objection closed.' : null
            ));
        }
        upsertAll(objections, Objection__c.External_Id__c, 'Objection__c', sum);
    }

    // ================================================= Stage: Police_Verification__c

    private static void buildPoliceVerifications(Integer scale, Summary sum) {
        List<Passport_Application__c> apps = demoApplications();
        if (apps.isEmpty()) {
            sum.fail('Police_Verification__c', 'no demo applications found.');
            return;
        }
        Integer howMany = target('Police_Verification__c', scale);
        List<Police_Verification__c> pvs = new List<Police_Verification__c>();
        for (Integer i = 1; i <= howMany; i++) {
            Lcg rnd = new Lcg(10000 + i);
            Passport_Application__c app = apps[Math.mod(i * 2, apps.size())];
            String status = PSK_Constants.PV_STATUSES[
                Math.mod(i - 1, PSK_Constants.PV_STATUSES.size())
            ];
            Date referred = (status == 'Not Initiated')
                ? null : Date.today().addDays(-rnd.between(5, 70));
            Date reportBack = (status == 'Cleared' || status == 'Adverse')
                ? referred.addDays(rnd.between(3, 30)) : null;

            pvs.add(new Police_Verification__c(
                External_Id__c = 'DEMO-PV-' + i,
                Passport_Application__c = app.Id,
                PV_Type__c = PSK_Constants.PV_TYPES[Math.mod(i - 1, PSK_Constants.PV_TYPES.size())],
                Status__c = status,
                Police_Station__c = rnd.pick(POLICE_STATIONS),
                Verifying_Officer__c = 'SI ' + rnd.pick(MALE_FIRST) + ' ' + rnd.pick(LAST_NAMES),
                Referred_Date__c = referred,
                Report_Received_Date__c = reportBack,
                Remarks__c = (status == 'Adverse')
                    ? 'Address could not be confirmed by the local beat officer.'
                    : 'Demo verification record.'
            ));
        }
        upsertAll(pvs, Police_Verification__c.External_Id__c, 'Police_Verification__c', sum);
    }

    // ========================================================== Stage: Risk_Flag__c

    private static void buildRiskFlags(Integer scale, Summary sum) {
        List<Passport_Application__c> apps = demoApplications();
        if (apps.isEmpty()) {
            sum.fail('Risk_Flag__c', 'no demo applications found.');
            return;
        }
        Integer howMany = target('Risk_Flag__c', scale);
        List<Risk_Flag__c> flags = new List<Risk_Flag__c>();
        for (Integer i = 1; i <= howMany; i++) {
            Lcg rnd = new Lcg(10100 + i);
            Passport_Application__c app = apps[Math.mod(i * 5, apps.size())];
            String status = PSK_Constants.RISK_STATUSES[
                Math.mod(i - 1, PSK_Constants.RISK_STATUSES.size())
            ];
            flags.add(new Risk_Flag__c(
                External_Id__c = 'DEMO-RISK-' + i,
                Passport_Application__c = app.Id,
                Flag_Type__c = PSK_Constants.RISK_FLAG_TYPES[
                    Math.mod(i - 1, PSK_Constants.RISK_FLAG_TYPES.size())
                ],
                Severity__c = PSK_Constants.SEVERITIES[
                    Math.mod(i - 1, PSK_Constants.SEVERITIES.size())
                ],
                Status__c = status,
                Flagged_Date__c = Date.today().addDays(-rnd.between(1, 120)),
                Reviewed_By__c = (status == 'Open') ? null : UserInfo.getUserId(),
                Description__c = 'Demo risk flag raised by automated screening on application '
                    + app.Name + '.'
            ));
        }
        upsertAll(flags, Risk_Flag__c.External_Id__c, 'Risk_Flag__c', sum);
    }

    // =========================================================== Stage: Passport__c

    /**
     * Two kinds of booklet:
     *   - "current": one per application at Granting or beyond, Status Active.
     *   - "historical": Application__c left null, Citizen__c set, an earlier status
     *     (Expired / Reissued / Cancelled / Lost / Surrendered) so the reissue chain
     *     and every Status__c value are represented.
     *
     * Constraints honoured:
     *   - External_Id_Must_Mirror_Number: External_Id__c is always set to Name.
     *   - Passport_Number_Format: Name comes from
     *     PSK_ApplicationService.generateBookletNumber, which matches ^[A-PR-WY][0-9]{7}$.
     *   - Active_Requires_Issue_And_Expiry_Dates: both dates are always populated.
     *   - Status 'Lost' exists only on the Ordinary record type, so it is only ever
     *     assigned there.
     */
    private static void buildPassports(Integer scale, Summary sum) {
        List<Passport_Application__c> apps = demoApplications();
        List<Citizen__c> citizens = demoCitizens();
        List<PSK__c> offices = demoOffices();
        if (apps.isEmpty() || citizens.isEmpty()) {
            sum.fail('Passport__c', 'demo applications and citizens are required.');
            return;
        }

        List<Passport_Application__c> granted = new List<Passport_Application__c>();
        for (Passport_Application__c app : apps) {
            if (PSK_Constants.isAtOrBeyond(app.Status__c, PSK_Constants.STATUS_GRANTING)) {
                granted.add(app);
            }
        }

        Integer howMany = target('Passport__c', scale);
        Integer currentCount = Math.min(granted.size(), howMany);
        Integer historicalCount = howMany - currentCount;

        Id rtOrdinary = PSK_ApplicationService.passportRecordTypeId(
            PSK_Constants.PASSPORT_RT_ORDINARY);
        Id rtDiplomatic = PSK_ApplicationService.passportRecordTypeId(
            PSK_Constants.PASSPORT_RT_DIPLOMATIC);
        Id rtOfficial = PSK_ApplicationService.passportRecordTypeId(
            PSK_Constants.PASSPORT_RT_OFFICIAL);

        List<Passport__c> passports = new List<Passport__c>();

        // ---- current booklets
        for (Integer i = 1; i <= currentCount; i++) {
            Lcg rnd = new Lcg(10200 + i);
            Passport_Application__c app = granted[i - 1];
            String category = String.isBlank(app.Passport_Category__c)
                ? 'Ordinary' : app.Passport_Category__c;
            Integer validity = String.isBlank(app.Validity_Years__c)
                ? 10 : Integer.valueOf(app.Validity_Years__c);
            Date issued = Date.today().addDays(-rnd.between(1, 900));

            String number = PSK_ApplicationService.generateBookletNumber('DEMO-PASS-' + i);
            passports.add(new Passport__c(
                Name = number,
                External_Id__c = number, // External_Id_Must_Mirror_Number
                Application__c = app.Id,
                Citizen__c = app.Citizen__c,
                PSK_Office__c = app.PSK_Office__c,
                RecordTypeId = recordTypeForCategory(category, rtOrdinary, rtDiplomatic, rtOfficial),
                Status__c = PSK_Constants.PASSPORT_ACTIVE,
                Date_of_Issue__c = issued,
                Date_of_Expiry__c = issued.addYears(validity),
                File_Number__c = 'DEMO-P' + String.valueOf(i).leftPad(6, '0'),
                Remarks__c = 'Generated by PSK_DemoDataGenerator (current booklet #' + i + ').'
            ));
        }

        // ---- historical booklets, for the reissue chain
        for (Integer j = 1; j <= historicalCount; j++) {
            Integer i = currentCount + j;
            Lcg rnd = new Lcg(10200 + i);

            // Deliberately reuse a citizen that already holds a current booklet, so
            // linkReissueChain always has a real chain to build rather than relying
            // on an incidental collision. Falls back to any demo citizen when no
            // application reached Granting.
            Citizen__c citizen = null;
            if (currentCount > 0) {
                Id ownerId = granted[Math.mod(j - 1, currentCount)].Citizen__c;
                for (Citizen__c candidate : citizens) {
                    if (candidate.Id == ownerId) {
                        citizen = candidate;
                        break;
                    }
                }
            }
            if (citizen == null) {
                citizen = citizens[Math.mod(j * 3, citizens.size())];
            }

            // Non-Ordinary record types do not expose the 'Lost' status.
            List<String> statusPool = PSK_Constants.PASSPORT_STATUSES;
            String status = statusPool[Math.mod(j, statusPool.size())];
            if (status == PSK_Constants.PASSPORT_ACTIVE) {
                status = PSK_Constants.PASSPORT_EXPIRED; // only current booklets are Active
            }

            Date issued = Date.today().addYears(-rnd.between(11, 18));
            String number = PSK_ApplicationService.generateBookletNumber('DEMO-PASS-' + i);
            passports.add(new Passport__c(
                Name = number,
                External_Id__c = number,
                Application__c = null,
                Citizen__c = citizen.Id,
                PSK_Office__c = offices.isEmpty()
                    ? null : offices[Math.mod(j, offices.size())].Id,
                RecordTypeId = rtOrdinary,
                Status__c = status,
                Date_of_Issue__c = issued,
                Date_of_Expiry__c = issued.addYears(10),
                File_Number__c = 'DEMO-P' + String.valueOf(i).leftPad(6, '0'),
                Cancellation_Reason__c = cancellationReasonFor(status),
                Remarks__c = 'Generated by PSK_DemoDataGenerator (historical booklet #' + i + ').'
            ));
        }

        upsertAll(passports, Passport__c.External_Id__c, 'Passport__c', sum);
        linkReissueChain(sum);
    }

    private static Id recordTypeForCategory(String category, Id ordinary,
                                            Id diplomatic, Id official) {
        if (category == 'Diplomatic') {
            return diplomatic;
        }
        if (category == 'Official') {
            return official;
        }
        return ordinary;
    }

    private static String cancellationReasonFor(String status) {
        if (status == PSK_Constants.PASSPORT_REISSUED) {
            return 'Reissued';
        }
        if (status == PSK_Constants.PASSPORT_LOST) {
            return 'Lost';
        }
        if (status == PSK_Constants.PASSPORT_SURRENDERED) {
            return 'Surrendered';
        }
        if (status == PSK_Constants.PASSPORT_CANCELLED) {
            return 'Revoked';
        }
        return null;
    }

    /**
     * Point each current booklet at an older booklet for the same citizen, so
     * PSK_PassportController.getPassport has a chain to walk.
     */
    private static void linkReissueChain(Summary sum) {
        Map<Id, List<Passport__c>> byCitizen = new Map<Id, List<Passport__c>>();
        for (Passport__c p : [
            SELECT Id, Citizen__c, Status__c, Date_of_Issue__c, Previous_Passport__c
            FROM Passport__c
            WHERE File_Number__c LIKE 'DEMO-%' AND Citizen__c != NULL
            ORDER BY Date_of_Issue__c
            LIMIT 5000
        ]) {
            if (!byCitizen.containsKey(p.Citizen__c)) {
                byCitizen.put(p.Citizen__c, new List<Passport__c>());
            }
            byCitizen.get(p.Citizen__c).add(p);
        }

        List<Passport__c> toUpdate = new List<Passport__c>();
        for (List<Passport__c> chain : byCitizen.values()) {
            for (Integer i = 1; i < chain.size(); i++) {
                if (chain[i].Previous_Passport__c == chain[i - 1].Id) {
                    continue;
                }
                toUpdate.add(new Passport__c(
                    Id = chain[i].Id,
                    Previous_Passport__c = chain[i - 1].Id
                ));
            }
        }
        if (toUpdate.isEmpty()) {
            return;
        }
        for (Integer offset = 0; offset < toUpdate.size(); offset += CHUNK) {
            Integer endAt = Math.min(offset + CHUNK, toUpdate.size());
            List<Passport__c> slice = new List<Passport__c>();
            for (Integer i = offset; i < endAt; i++) {
                slice.add(toUpdate[i]);
            }
            for (Database.SaveResult sr : Database.update(slice, false)) {
                if (!sr.isSuccess()) {
                    sum.fail('Passport__c', 'reissue chain link - '
                        + PSK_ApplicationService.firstError(sr));
                }
            }
        }
        sum.note('Linked ' + toUpdate.size() + ' passport(s) into reissue chains.');
    }

    // ========================================================== Stage: Print_Job__c

    private static void buildPrintJobs(Integer scale, Summary sum) {
        List<Passport_Application__c> apps = demoApplications();
        if (apps.isEmpty()) {
            sum.fail('Print_Job__c', 'no demo applications found.');
            return;
        }
        Map<Id, Id> passportByApp = demoPassportByApplication();

        List<Passport_Application__c> printable = new List<Passport_Application__c>();
        for (Passport_Application__c app : apps) {
            if (PSK_Constants.isAtOrBeyond(app.Status__c, PSK_Constants.STATUS_PRINTING)) {
                printable.add(app);
            }
        }
        if (printable.isEmpty()) {
            printable = apps;
        }

        Integer howMany = target('Print_Job__c', scale);
        List<Print_Job__c> jobs = new List<Print_Job__c>();
        for (Integer i = 1; i <= howMany; i++) {
            Lcg rnd = new Lcg(10300 + i);
            Passport_Application__c app = printable[Math.mod(i - 1, printable.size())];
            String status = PSK_Constants.PRINT_STATUSES[
                Math.mod(i - 1, PSK_Constants.PRINT_STATUSES.size())
            ];
            DateTime queued = System.now().addDays(-rnd.between(1, 45));
            DateTime printed = (status == 'Printed' || status == 'Quality Check')
                ? queued.addHours(rnd.between(2, 40)) : null;
            // Attempts beyond the first are the reprints.
            Integer attempt = (status == 'Reprint Required' || Math.mod(i, 11) == 0) ? 2 : 1;

            jobs.add(new Print_Job__c(
                External_Id__c = 'DEMO-PJ-' + i,
                Passport_Application__c = app.Id,
                Passport__c = passportByApp.get(app.Id),
                Print_Facility__c = app.PSK_Office__c,
                Status__c = status,
                Queued_Date__c = queued,
                Printed_Date__c = printed,
                Attempt_Number__c = attempt,
                Batch_Number__c = 'DEMO-B' + String.valueOf(Math.mod(i, 20) + 1).leftPad(3, '0'),
                Quality_Check_Passed__c = (status == 'Printed'),
                Failure_Reason__c = (status == 'Failed')
                    ? 'Printer jam during lamination pass.' : null,
                Reprint_Reason__c = (attempt > 1)
                    ? PSK_Constants.REPRINT_REASONS[
                        Math.mod(i - 1, PSK_Constants.REPRINT_REASONS.size())
                      ]
                    : null
            ));
        }
        upsertAll(jobs, Print_Job__c.External_Id__c, 'Print_Job__c', sum);
    }

    // =========================================================== Stage: Dispatch__c

    private static void buildDispatches(Integer scale, Summary sum) {
        List<Passport_Application__c> apps = demoApplications();
        if (apps.isEmpty()) {
            sum.fail('Dispatch__c', 'no demo applications found.');
            return;
        }
        Map<Id, Id> passportByApp = demoPassportByApplication();

        List<Passport_Application__c> shippable = new List<Passport_Application__c>();
        for (Passport_Application__c app : apps) {
            if (PSK_Constants.isAtOrBeyond(app.Status__c, PSK_Constants.STATUS_DISPATCH)) {
                shippable.add(app);
            }
        }
        if (shippable.isEmpty()) {
            shippable = apps;
        }

        Integer howMany = target('Dispatch__c', scale);
        List<Dispatch__c> dispatches = new List<Dispatch__c>();
        for (Integer i = 1; i <= howMany; i++) {
            Lcg rnd = new Lcg(10400 + i);
            Passport_Application__c app = shippable[Math.mod(i - 1, shippable.size())];
            String status = PSK_Constants.DISPATCH_STATUSES[
                Math.mod(i - 1, PSK_Constants.DISPATCH_STATUSES.size())
            ];
            DateTime dispatched = (status == PSK_Constants.DISPATCH_PENDING || status == 'Packed')
                ? null : System.now().addDays(-rnd.between(1, 30));
            DateTime delivered = (status == 'Delivered')
                ? dispatched.addDays(rnd.between(1, 7)) : null;

            dispatches.add(new Dispatch__c(
                External_Id__c = 'DEMO-DSP-' + i,
                Passport_Application__c = app.Id,
                Passport__c = passportByApp.get(app.Id),
                Status__c = status,
                Courier_Partner__c = PSK_Constants.COURIER_PARTNERS[
                    Math.mod(i - 1, PSK_Constants.COURIER_PARTNERS.size())
                ],
                Tracking_Number__c = 'DEMOTRK' + String.valueOf(i).leftPad(9, '0'),
                Dispatched_Date__c = dispatched,
                Delivered_Date__c = delivered,
                Expected_Delivery_Date__c = Date.today().addDays(rnd.between(-10, 10)),
                Delivery_Attempts__c = (status == 'Returned') ? 3 : rnd.between(0, 2),
                Received_By__c = (status == 'Delivered')
                    ? rnd.pick(MALE_FIRST) + ' ' + rnd.pick(LAST_NAMES) : null,
                Return_Reason__c = (status == 'Returned')
                    ? PSK_Constants.DISPATCH_RETURN_REASONS[
                        Math.mod(i - 1, PSK_Constants.DISPATCH_RETURN_REASONS.size())
                      ]
                    : null,
                Remarks__c = 'Demo dispatch record #' + i + '.'
            ));
        }
        upsertAll(dispatches, Dispatch__c.External_Id__c, 'Dispatch__c', sum);
    }

    // ==================================================== Stage: Notification_Log__c

    private static void buildNotifications(Integer scale, Summary sum) {
        List<Passport_Application__c> apps = demoApplications();
        if (apps.isEmpty()) {
            sum.fail('Notification_Log__c', 'no demo applications found.');
            return;
        }
        Integer howMany = target('Notification_Log__c', scale);
        List<Notification_Log__c> logs = new List<Notification_Log__c>();
        for (Integer i = 1; i <= howMany; i++) {
            Lcg rnd = new Lcg(10500 + i);
            Passport_Application__c app = apps[Math.mod(i - 1, apps.size())];
            String channel = PSK_Constants.NOTIFICATION_CHANNELS[
                Math.mod(i - 1, PSK_Constants.NOTIFICATION_CHANNELS.size())
            ];
            String messageType = PSK_Constants.NOTIFICATION_TYPES[
                Math.mod(i - 1, PSK_Constants.NOTIFICATION_TYPES.size())
            ];
            String status = PSK_Constants.NOTIFICATION_STATUSES[
                Math.mod(i - 1, PSK_Constants.NOTIFICATION_STATUSES.size())
            ];

            logs.add(new Notification_Log__c(
                External_Id__c = 'DEMO-NOTIF-' + i,
                Provider_Message_Id__c = 'DEMO-MSG-' + String.valueOf(i).leftPad(10, '0'),
                Passport_Application__c = app.Id,
                Channel__c = channel,
                Message_Type__c = messageType,
                Status__c = status,
                Recipient_Number__c = String.isBlank(app.Mobile__c) ? mobileFor(rnd) : app.Mobile__c,
                Sent_Date__c = (status == 'Queued') ? null : System.now().addDays(-rnd.between(1, 60)),
                Message_Body__c = bodyFor(messageType, app)
            ));
        }
        upsertAll(logs, Notification_Log__c.External_Id__c, 'Notification_Log__c', sum);
    }

    private static String bodyFor(String messageType, Passport_Application__c app) {
        if (messageType == 'Payment Reminder') {
            return 'Dear applicant, the fee for application ' + app.Name
                + ' is still outstanding. Please complete payment to proceed.';
        }
        if (messageType == 'Appointment Reminder') {
            return 'Reminder: your Passport Seva Kendra appointment for ' + app.Name
                + ' is scheduled. Please carry your original documents.';
        }
        if (messageType == 'Renewal Outreach') {
            return 'Your passport is approaching expiry. You can apply for re-issue now.';
        }
        if (messageType == 'Custom') {
            return 'Message regarding application ' + app.Name + ' from Passport Seva Kendra.';
        }
        return 'Application ' + app.Name + ' has moved to status ' + app.Status__c + '.';
    }

    // ============================================================ Stage: Renewal__c

    private static void buildRenewals(Integer scale, Summary sum) {
        List<Passport_Application__c> apps = demoApplications();
        if (apps.isEmpty()) {
            sum.fail('Renewal__c', 'no demo applications found.');
            return;
        }
        List<Passport_Application__c> delivered = new List<Passport_Application__c>();
        for (Passport_Application__c app : apps) {
            if (app.Status__c == PSK_Constants.STATUS_DELIVERED) {
                delivered.add(app);
            }
        }
        if (delivered.isEmpty()) {
            delivered = apps;
        }

        Integer howMany = target('Renewal__c', scale);
        List<Renewal__c> renewals = new List<Renewal__c>();
        for (Integer i = 1; i <= howMany; i++) {
            Lcg rnd = new Lcg(10600 + i);
            Passport_Application__c app = delivered[Math.mod(i - 1, delivered.size())];
            String outreach = PSK_Constants.RENEWAL_OUTREACH_STATUSES[
                Math.mod(i - 1, PSK_Constants.RENEWAL_OUTREACH_STATUSES.size())
            ];
            Date expiry = Date.today().addDays(rnd.between(15, 360));

            renewals.add(new Renewal__c(
                External_Id__c = 'DEMO-REN-' + i,
                Passport_Application__c = app.Id,
                Expiry_Date__c = expiry,
                Outreach_Status__c = outreach,
                Notification_Sent_Date__c = (outreach == 'Not Started')
                    ? null : Date.today().addDays(-rnd.between(1, 40)),
                Follow_Up_Date__c = (outreach == 'Notified' || outreach == 'Responded')
                    ? Date.today().addDays(rnd.between(3, 30)) : null,
                Converted_Application__c = (outreach == 'Converted')
                    ? apps[Math.mod(i * 7, apps.size())].Id : null
            ));
        }
        upsertAll(renewals, Renewal__c.External_Id__c, 'Renewal__c', sum);
    }

    // ============================================================== Demo selectors

    private static List<PSK__c> officeCache;
    private static List<Slot__c> slotCache;
    private static List<Citizen__c> citizenCache;
    private static List<Passport_Application__c> applicationCache;

    private static List<PSK__c> demoOffices() {
        if (officeCache == null) {
            officeCache = [
                SELECT Id, Name, Office_Code__c, City__c, State__c
                FROM PSK__c
                WHERE Office_Code__c LIKE 'DEMO-%'
                ORDER BY Office_Code__c
                LIMIT 200
            ];
        }
        return officeCache;
    }

    private static List<Slot__c> demoSlots() {
        if (slotCache == null) {
            slotCache = [
                SELECT Id, Slot_Date__c, Start_Time__c, Capacity__c, Booked_Count__c
                FROM Slot__c
                WHERE External_Id__c LIKE 'DEMO-%'
                ORDER BY External_Id__c
                LIMIT 2000
            ];
        }
        return slotCache;
    }

    private static List<Citizen__c> demoCitizens() {
        if (citizenCache == null) {
            citizenCache = [
                SELECT Id, Name, Citizen_Reference__c, Date_of_Birth__c, Is_Minor__c, Mobile__c
                FROM Citizen__c
                WHERE Citizen_Reference__c LIKE 'DEMO-%'
                ORDER BY Citizen_Reference__c
                LIMIT 5000
            ];
        }
        return citizenCache;
    }

    private static List<Passport_Application__c> demoApplications() {
        if (applicationCache == null) {
            applicationCache = [
                SELECT Id, Name, External_Id__c, Status__c, Payment_Status__c, Fee__c,
                       Citizen__c, PSK_Office__c, Passport_Category__c, Validity_Years__c,
                       Mobile__c, RecordTypeId
                FROM Passport_Application__c
                WHERE External_Id__c LIKE 'DEMO-%'
                ORDER BY External_Id__c
                LIMIT 5000
            ];
        }
        return applicationCache;
    }

    private static Map<Id, Id> demoPassportByApplication() {
        Map<Id, Id> byApp = new Map<Id, Id>();
        for (Passport__c p : [
            SELECT Id, Application__c
            FROM Passport__c
            WHERE File_Number__c LIKE 'DEMO-%' AND Application__c != NULL
            LIMIT 5000
        ]) {
            byApp.put(p.Application__c, p.Id);
        }
        return byApp;
    }

    /** Drop the cached selectors -- needed when stages run in one transaction. */
    @TestVisible
    private static void clearCaches() {
        officeCache = null;
        slotCache = null;
        citizenCache = null;
        applicationCache = null;
    }
}
