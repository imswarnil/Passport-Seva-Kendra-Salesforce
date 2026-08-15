/**
 * One chronological activity feed for a Passport Application, merging every
 * child object into a single sorted list the LWC can render without knowing the
 * data model.
 */
public with sharing class PSK_ApplicationTimelineController {

    public class TimelineEntry implements Comparable {
        @AuraEnabled public Id recordId;
        @AuraEnabled public String type;
        @AuraEnabled public String icon;
        @AuraEnabled public String title;
        @AuraEnabled public String subtitle;
        @AuraEnabled public DateTime timestamp;
        @AuraEnabled public String status;
        @AuraEnabled public String variant;

        public TimelineEntry(String type, String icon, String title, String subtitle,
                             DateTime timestamp, String status, String variant, Id recordId) {
            this.type = type;
            this.icon = icon;
            this.title = title;
            this.subtitle = subtitle;
            this.timestamp = timestamp;
            this.status = status;
            this.variant = variant;
            this.recordId = recordId;
        }

        /** Newest first; null timestamps sink to the bottom. */
        public Integer compareTo(Object other) {
            TimelineEntry o = (TimelineEntry) other;
            if (this.timestamp == null && o.timestamp == null) {
                return 0;
            }
            if (this.timestamp == null) {
                return 1;
            }
            if (o.timestamp == null) {
                return -1;
            }
            if (this.timestamp > o.timestamp) {
                return -1;
            }
            return this.timestamp < o.timestamp ? 1 : 0;
        }
    }

    @AuraEnabled(cacheable=true)
    public static List<TimelineEntry> getTimeline(Id applicationId) {
        List<TimelineEntry> entries = new List<TimelineEntry>();
        if (applicationId == null) {
            return entries;
        }

        List<Passport_Application__c> apps = [
            SELECT Id, Name, Status__c, CreatedDate, Submitted_Date__c, Granted_Date__c,
                   Stage_Entered_Date__c, Payment_Status__c, Fee__c
            FROM Passport_Application__c
            WHERE Id = :applicationId
            WITH USER_MODE
            LIMIT 1
        ];
        if (apps.isEmpty()) {
            return entries;
        }
        Passport_Application__c app = apps[0];

        entries.add(new TimelineEntry(
            'Application', 'standard:document', 'Application created',
            app.Name, app.CreatedDate, app.Status__c, 'inverse', app.Id
        ));
        if (app.Submitted_Date__c != null) {
            entries.add(new TimelineEntry(
                'Application', 'utility:upload', 'Application submitted',
                'Left Draft', app.Submitted_Date__c, 'Submitted', 'inverse', app.Id
            ));
        }
        if (app.Granted_Date__c != null) {
            entries.add(new TimelineEntry(
                'Application', 'utility:approval', 'Application granted',
                'Cleared for printing', app.Granted_Date__c, 'Granting', 'success', app.Id
            ));
        }

        if (Schema.sObjectType.Appointment__c.isAccessible()) {
            for (Appointment__c a : [
                SELECT Id, Name, Status__c, Counter_Number__c, Check_In_Time__c, Check_Out_Time__c,
                       CreatedDate, Slot__r.Slot_Date__c, Slot__r.Start_Time__c
                FROM Appointment__c
                WHERE Passport_Application__c = :applicationId
                WITH USER_MODE
                LIMIT 50
            ]) {
                String sub = a.Slot__r != null && a.Slot__r.Slot_Date__c != null
                    ? 'Slot ' + a.Slot__r.Slot_Date__c.format() : 'Appointment';
                if (String.isNotBlank(a.Counter_Number__c)) {
                    sub += ' - counter ' + a.Counter_Number__c;
                }
                entries.add(new TimelineEntry(
                    'Appointment', 'standard:event', 'Appointment ' + toLower(a.Status__c),
                    sub, a.Check_In_Time__c != null ? a.Check_In_Time__c : a.CreatedDate,
                    a.Status__c, variantForAppointment(a.Status__c), a.Id
                ));
            }
        }

        if (Schema.sObjectType.Payment__c.isAccessible()) {
            for (Payment__c p : [
                SELECT Id, Name, Status__c, Amount__c, Payment_Mode__c, Payment_Date__c,
                       Payment_Reference__c, CreatedDate
                FROM Payment__c
                WHERE Passport_Application__c = :applicationId
                WITH USER_MODE
                LIMIT 50
            ]) {
                String amount = p.Amount__c == null ? '' : 'INR ' + p.Amount__c.setScale(2);
                entries.add(new TimelineEntry(
                    'Payment', 'standard:currency', 'Payment ' + toLower(p.Status__c),
                    amount + (String.isBlank(p.Payment_Mode__c) ? '' : ' via ' + p.Payment_Mode__c),
                    p.Payment_Date__c != null ? p.Payment_Date__c : p.CreatedDate,
                    p.Status__c, p.Status__c == PSK_Constants.PAYMENT_SUCCESS ? 'success' : 'warning',
                    p.Id
                ));
            }
        }

        if (Schema.sObjectType.Document_Checklist_Item__c.isAccessible()) {
            for (Document_Checklist_Item__c d : [
                SELECT Id, Name, Document_Type__c, Status__c, Received_Date__c,
                       Verified_Date__c, CreatedDate
                FROM Document_Checklist_Item__c
                WHERE Passport_Application__c = :applicationId
                WITH USER_MODE
                LIMIT 100
            ]) {
                Date effective = d.Verified_Date__c != null ? d.Verified_Date__c : d.Received_Date__c;
                DateTime stamp = effective == null
                    ? d.CreatedDate
                    : DateTime.newInstance(effective, Time.newInstance(12, 0, 0, 0));
                entries.add(new TimelineEntry(
                    'Document', 'standard:file', 'Document ' + toLower(d.Status__c),
                    d.Document_Type__c, stamp, d.Status__c,
                    d.Status__c == PSK_Constants.DOC_REJECTED ? 'error'
                        : (d.Status__c == PSK_Constants.DOC_VERIFIED ? 'success' : 'inverse'),
                    d.Id
                ));
            }
        }

        if (Schema.sObjectType.Police_Verification__c.isAccessible()) {
            for (Police_Verification__c pv : [
                SELECT Id, Name, Status__c, PV_Type__c, Police_Station__c, Referred_Date__c,
                       Report_Received_Date__c, CreatedDate
                FROM Police_Verification__c
                WHERE Passport_Application__c = :applicationId
                WITH USER_MODE
                LIMIT 50
            ]) {
                Date effective = pv.Report_Received_Date__c != null
                    ? pv.Report_Received_Date__c : pv.Referred_Date__c;
                DateTime stamp = effective == null
                    ? pv.CreatedDate
                    : DateTime.newInstance(effective, Time.newInstance(12, 0, 0, 0));
                entries.add(new TimelineEntry(
                    'Police Verification', 'standard:custom_notification',
                    'Police verification ' + toLower(pv.Status__c),
                    (String.isBlank(pv.PV_Type__c) ? '' : pv.PV_Type__c + ' ')
                        + (String.isBlank(pv.Police_Station__c) ? '' : '- ' + pv.Police_Station__c),
                    stamp, pv.Status__c,
                    pv.Status__c == 'Adverse' ? 'error'
                        : (pv.Status__c == 'Cleared' ? 'success' : 'inverse'),
                    pv.Id
                ));
            }
        }

        if (Schema.sObjectType.Objection__c.isAccessible()) {
            for (Objection__c o : [
                SELECT Id, Name, Objection_Type__c, Status__c, Raised_Date__c,
                       Resolved_Date__c, CreatedDate
                FROM Objection__c
                WHERE Passport_Application__c = :applicationId
                WITH USER_MODE
                LIMIT 50
            ]) {
                Date effective = o.Resolved_Date__c != null ? o.Resolved_Date__c : o.Raised_Date__c;
                DateTime stamp = effective == null
                    ? o.CreatedDate
                    : DateTime.newInstance(effective, Time.newInstance(12, 0, 0, 0));
                entries.add(new TimelineEntry(
                    'Objection', 'standard:case', 'Objection ' + toLower(o.Status__c),
                    o.Objection_Type__c, stamp, o.Status__c,
                    o.Status__c == 'Resolved' ? 'success' : 'error', o.Id
                ));
            }
        }

        if (Schema.sObjectType.Notification_Log__c.isAccessible()) {
            for (Notification_Log__c n : [
                SELECT Id, Name, Channel__c, Message_Type__c, Status__c, Sent_Date__c, CreatedDate
                FROM Notification_Log__c
                WHERE Passport_Application__c = :applicationId
                WITH USER_MODE
                ORDER BY Sent_Date__c DESC NULLS LAST
                LIMIT 50
            ]) {
                entries.add(new TimelineEntry(
                    'Notification', 'standard:email',
                    (String.isBlank(n.Channel__c) ? 'Notification' : n.Channel__c) + ' '
                        + toLower(n.Status__c),
                    n.Message_Type__c, n.Sent_Date__c != null ? n.Sent_Date__c : n.CreatedDate,
                    n.Status__c, n.Status__c == 'Failed' ? 'error' : 'inverse', n.Id
                ));
            }
        }

        if (Schema.sObjectType.Print_Job__c.isAccessible()) {
            for (Print_Job__c pj : [
                SELECT Id, Name, Status__c, Batch_Number__c, Attempt_Number__c,
                       Queued_Date__c, Printed_Date__c, CreatedDate
                FROM Print_Job__c
                WHERE Passport_Application__c = :applicationId
                WITH USER_MODE
                LIMIT 50
            ]) {
                entries.add(new TimelineEntry(
                    'Print Job', 'standard:work_order', 'Print job ' + toLower(pj.Status__c),
                    String.isBlank(pj.Batch_Number__c) ? 'Attempt ' + pj.Attempt_Number__c
                        : 'Batch ' + pj.Batch_Number__c,
                    pj.Printed_Date__c != null ? pj.Printed_Date__c
                        : (pj.Queued_Date__c != null ? pj.Queued_Date__c : pj.CreatedDate),
                    pj.Status__c, pj.Status__c == 'Failed' ? 'error' : 'inverse', pj.Id
                ));
            }
        }

        if (Schema.sObjectType.Dispatch__c.isAccessible()) {
            for (Dispatch__c ds : [
                SELECT Id, Name, Status__c, Courier_Partner__c, Tracking_Number__c,
                       Dispatched_Date__c, Delivered_Date__c, CreatedDate
                FROM Dispatch__c
                WHERE Passport_Application__c = :applicationId
                WITH USER_MODE
                LIMIT 50
            ]) {
                entries.add(new TimelineEntry(
                    'Dispatch', 'standard:package', 'Dispatch ' + toLower(ds.Status__c),
                    (String.isBlank(ds.Courier_Partner__c) ? '' : ds.Courier_Partner__c)
                        + (String.isBlank(ds.Tracking_Number__c) ? '' : ' ' + ds.Tracking_Number__c),
                    ds.Delivered_Date__c != null ? ds.Delivered_Date__c
                        : (ds.Dispatched_Date__c != null ? ds.Dispatched_Date__c : ds.CreatedDate),
                    ds.Status__c,
                    ds.Status__c == 'Delivered' ? 'success'
                        : (ds.Status__c == 'Returned' || ds.Status__c == 'Lost in Transit'
                            ? 'error' : 'inverse'),
                    ds.Id
                ));
            }
        }

        entries.sort();
        return entries;
    }

    private static String variantForAppointment(String status) {
        if (status == 'Completed') {
            return 'success';
        }
        if (status == 'No Show' || status == 'Cancelled') {
            return 'error';
        }
        return 'inverse';
    }

    private static String toLower(String s) {
        return String.isBlank(s) ? 'updated' : s.toLowerCase();
    }
}
