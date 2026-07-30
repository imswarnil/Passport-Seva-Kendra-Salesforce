/**
 * Per-day slot capacity versus bookings for one PSK office -- the data behind
 * the office utilisation chart.
 */
public with sharing class PSK_OfficeCapacityController {

    public class DayUtilisation {
        @AuraEnabled public Date slotDate;
        @AuraEnabled public String dayLabel;
        @AuraEnabled public Integer slotCount;
        @AuraEnabled public Integer capacity;
        @AuraEnabled public Integer booked;
        @AuraEnabled public Integer available;
        @AuraEnabled public Decimal utilisationPercent;
        @AuraEnabled public Boolean isFull;

        public DayUtilisation(Date d) {
            this.slotDate = d;
            this.dayLabel = d == null ? '' : d.format();
            this.slotCount = 0;
            this.capacity = 0;
            this.booked = 0;
            this.available = 0;
            this.utilisationPercent = 0;
            this.isFull = false;
        }
    }

    public class OfficeUtilisation {
        @AuraEnabled public Id officeId;
        @AuraEnabled public String officeName;
        @AuraEnabled public String officeCode;
        @AuraEnabled public String city;
        @AuraEnabled public String state;
        @AuraEnabled public Integer capacityPerDay;
        @AuraEnabled public Date fromDate;
        @AuraEnabled public Date toDate;
        @AuraEnabled public Integer totalCapacity;
        @AuraEnabled public Integer totalBooked;
        @AuraEnabled public Decimal overallUtilisationPercent;
        @AuraEnabled public Integer fullDays;
        @AuraEnabled public List<DayUtilisation> days;
    }

    /**
     * @param officeId the PSK__c office
     * @param days     horizon starting today; defaults to 14, capped at 90
     */
    @AuraEnabled(cacheable=true)
    public static OfficeUtilisation getUtilisation(Id officeId, Integer days) {
        if (officeId == null) {
            throw new AuraHandledException('An office id is required.');
        }
        Integer horizon = (days == null || days <= 0) ? 14 : Math.min(days, 90);

        List<PSK__c> offices = [
            SELECT Id, Name, Office_Code__c, City__c, State__c, Capacity_Per_Day__c
            FROM PSK__c
            WHERE Id = :officeId
            WITH USER_MODE
            LIMIT 1
        ];
        if (offices.isEmpty()) {
            throw new AuraHandledException('Office not found, or you do not have access to it.');
        }
        PSK__c office = offices[0];

        Date fromDate = Date.today();
        Date toDate = fromDate.addDays(horizon - 1);

        OfficeUtilisation u = new OfficeUtilisation();
        u.officeId = office.Id;
        u.officeName = office.Name;
        u.officeCode = office.Office_Code__c;
        u.city = office.City__c;
        u.state = office.State__c;
        u.capacityPerDay = office.Capacity_Per_Day__c == null
            ? null : office.Capacity_Per_Day__c.intValue();
        u.fromDate = fromDate;
        u.toDate = toDate;

        // Pre-seed every day in the window so the chart has no gaps.
        Map<Date, DayUtilisation> byDate = new Map<Date, DayUtilisation>();
        List<DayUtilisation> ordered = new List<DayUtilisation>();
        for (Integer i = 0; i < horizon; i++) {
            Date d = fromDate.addDays(i);
            DayUtilisation du = new DayUtilisation(d);
            byDate.put(d, du);
            ordered.add(du);
        }

        for (Slot__c s : [
            SELECT Id, Slot_Date__c, Capacity__c, Booked_Count__c
            FROM Slot__c
            WHERE PSK_Office__c = :officeId
              AND Slot_Date__c >= :fromDate
              AND Slot_Date__c <= :toDate
            WITH USER_MODE
            ORDER BY Slot_Date__c
            LIMIT 2000
        ]) {
            DayUtilisation du = byDate.get(s.Slot_Date__c);
            if (du == null) {
                continue;
            }
            du.slotCount++;
            du.capacity += (s.Capacity__c == null ? 0 : s.Capacity__c.intValue());
            du.booked += (s.Booked_Count__c == null ? 0 : s.Booked_Count__c.intValue());
        }

        Integer totalCapacity = 0;
        Integer totalBooked = 0;
        Integer fullDays = 0;
        for (DayUtilisation du : ordered) {
            du.available = du.capacity - du.booked;
            du.utilisationPercent = du.capacity == 0
                ? 0
                : (Decimal.valueOf(du.booked) / du.capacity * 100).setScale(1);
            du.isFull = (du.capacity > 0 && du.available <= 0);
            if (du.isFull) {
                fullDays++;
            }
            totalCapacity += du.capacity;
            totalBooked += du.booked;
        }

        u.days = ordered;
        u.totalCapacity = totalCapacity;
        u.totalBooked = totalBooked;
        u.fullDays = fullDays;
        u.overallUtilisationPercent = totalCapacity == 0
            ? 0
            : (Decimal.valueOf(totalBooked) / totalCapacity * 100).setScale(1);
        return u;
    }

    /**
     * Utilisation across every active office for the next {@code days} days --
     * the network-level roll-up.
     */
    @AuraEnabled(cacheable=true)
    public static List<OfficeUtilisation> getNetworkUtilisation(Integer days) {
        Integer horizon = (days == null || days <= 0) ? 14 : Math.min(days, 90);
        Date fromDate = Date.today();
        Date toDate = fromDate.addDays(horizon - 1);

        Map<Id, OfficeUtilisation> byOffice = new Map<Id, OfficeUtilisation>();
        for (PSK__c office : [
            SELECT Id, Name, Office_Code__c, City__c, State__c, Capacity_Per_Day__c
            FROM PSK__c
            WHERE Is_Active__c = true
            WITH USER_MODE
            ORDER BY Name
            LIMIT 200
        ]) {
            OfficeUtilisation u = new OfficeUtilisation();
            u.officeId = office.Id;
            u.officeName = office.Name;
            u.officeCode = office.Office_Code__c;
            u.city = office.City__c;
            u.state = office.State__c;
            u.capacityPerDay = office.Capacity_Per_Day__c == null
                ? null : office.Capacity_Per_Day__c.intValue();
            u.fromDate = fromDate;
            u.toDate = toDate;
            u.totalCapacity = 0;
            u.totalBooked = 0;
            u.fullDays = 0;
            u.overallUtilisationPercent = 0;
            u.days = new List<DayUtilisation>();
            byOffice.put(office.Id, u);
        }
        if (byOffice.isEmpty()) {
            return new List<OfficeUtilisation>();
        }

        Set<Id> officeIds = byOffice.keySet();
        for (AggregateResult ar : [
            SELECT PSK_Office__c officeId, SUM(Capacity__c) cap, SUM(Booked_Count__c) booked
            FROM Slot__c
            WHERE PSK_Office__c IN :officeIds
              AND Slot_Date__c >= :fromDate
              AND Slot_Date__c <= :toDate
            WITH USER_MODE
            GROUP BY PSK_Office__c
        ]) {
            OfficeUtilisation u = byOffice.get((Id) ar.get('officeId'));
            if (u == null) {
                continue;
            }
            Decimal cap = (Decimal) ar.get('cap');
            Decimal booked = (Decimal) ar.get('booked');
            u.totalCapacity = cap == null ? 0 : cap.intValue();
            u.totalBooked = booked == null ? 0 : booked.intValue();
            u.overallUtilisationPercent = u.totalCapacity == 0
                ? 0
                : (Decimal.valueOf(u.totalBooked) / u.totalCapacity * 100).setScale(1);
        }

        return byOffice.values();
    }
}
