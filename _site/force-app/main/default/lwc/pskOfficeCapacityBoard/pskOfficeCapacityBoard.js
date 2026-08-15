import { LightningElement, api } from 'lwc';
import getUtilisation from '@salesforce/apex/PSK_OfficeCapacityController.getUtilisation';
import getOffices from '@salesforce/apex/PSK_SlotBookingController.getOffices';

const DAYS = 14;

function pick(source, names, fallback) {
    if (!source) {
        return fallback;
    }
    for (const name of names) {
        const value = source[name];
        if (value !== undefined && value !== null) {
            return value;
        }
    }
    return fallback;
}

function toList(data, names) {
    if (Array.isArray(data)) {
        return data;
    }
    const nested = pick(data, names, null);
    return Array.isArray(nested) ? nested : [];
}

function num(value) {
    const parsed = Number(value);
    return Number.isFinite(parsed) ? parsed : 0;
}

const WEEKDAYS = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];

function formatDay(value) {
    if (!value) {
        return { short: '—', weekday: '' };
    }
    const date = new Date(value);
    if (Number.isNaN(date.getTime())) {
        return { short: String(value), weekday: '' };
    }
    return {
        short: `${date.getUTCDate()}`,
        weekday: WEEKDAYS[date.getUTCDay()]
    };
}

export default class PskOfficeCapacityBoard extends LightningElement {
    /** Present only on the PSK__c record page. */
    @api recordId;

    days = DAYS;
    rows = [];
    error;
    hasLoaded = false;
    officeOptions = [];
    selectedOfficeId;
    officesLoaded = false;

    connectedCallback() {
        if (this.recordId) {
            this.selectedOfficeId = this.recordId;
            this.officesLoaded = true;
            this.loadUtilisation();
        } else {
            this.loadOffices();
        }
    }

    get isRecordContext() {
        return !!this.recordId;
    }

    async loadOffices() {
        try {
            const data = await getOffices();
            this.officeOptions = toList(data, ['offices', 'records', 'items']).map((office, index) => ({
                label: pick(office, ['label', 'name', 'Name', 'officeName'], `Office ${index + 1}`),
                value: pick(office, ['value', 'id', 'Id', 'officeId'], `office-${index}`)
            }));
            if (this.officeOptions.length > 0) {
                this.selectedOfficeId = this.officeOptions[0].value;
                this.loadUtilisation();
            } else {
                this.hasLoaded = true;
            }
        } catch (error) {
            this.error = this.reduceError(error, 'Unable to load PSK offices.');
            this.hasLoaded = true;
        } finally {
            this.officesLoaded = true;
        }
    }

    async loadUtilisation() {
        if (!this.selectedOfficeId) {
            return;
        }
        this.hasLoaded = false;
        try {
            const data = await getUtilisation({ officeId: this.selectedOfficeId, days: DAYS });
            this.rows = toList(data, ['days', 'utilisation', 'items', 'records']);
            this.error = undefined;
        } catch (error) {
            this.rows = [];
            this.error = this.reduceError(error, 'Unable to load slot utilisation.');
        } finally {
            this.hasLoaded = true;
        }
    }

    get cells() {
        return (this.rows || []).map((row, index) => {
            const rawDate = pick(row, ['slotDate', 'Slot_Date__c', 'date', 'day'], null);
            const capacity = num(pick(row, ['capacity', 'totalCapacity', 'Capacity__c'], 0));
            const booked = num(pick(row, ['booked', 'bookedCount', 'Booked_Count__c', 'bookings'], 0));
            const explicitPct = pick(row, ['utilisation', 'utilization', 'percent', 'utilisationPercent'], undefined);
            let pct;
            if (explicitPct !== undefined) {
                const value = num(explicitPct);
                pct = value <= 1 && value > 0 ? Math.round(value * 100) : Math.round(value);
            } else {
                pct = capacity > 0 ? Math.round((booked / capacity) * 100) : 0;
            }
            pct = Math.min(Math.max(pct, 0), 100);
            const band = pct >= 90 ? 'critical' : pct >= 70 ? 'high' : pct >= 40 ? 'medium' : 'low';
            const label = formatDay(rawDate);
            return {
                key: `${rawDate || index}-${index}`,
                dayNumber: label.short,
                weekday: label.weekday,
                pct,
                pctLabel: `${pct}%`,
                barStyle: `height: ${Math.max(pct, 3)}%`,
                cellClass: `psk-heat__bar psk-heat__bar--${band}`,
                ariaLabel: `${label.weekday} ${label.short}: ${pct} percent utilised, ${booked} of ${capacity} places booked`,
                capacity,
                booked
            };
        });
    }

    get totalCapacity() {
        return this.cells.reduce((sum, cell) => sum + cell.capacity, 0);
    }

    get totalBooked() {
        return this.cells.reduce((sum, cell) => sum + cell.booked, 0);
    }

    get averageUtilisation() {
        if (!this.cells.length) {
            return 0;
        }
        if (this.totalCapacity > 0) {
            return Math.round((this.totalBooked / this.totalCapacity) * 100);
        }
        return Math.round(this.cells.reduce((sum, cell) => sum + cell.pct, 0) / this.cells.length);
    }

    get averageLabel() {
        return `${this.averageUtilisation}% average utilisation over the next ${DAYS} days`;
    }

    get peakDay() {
        return this.cells.reduce((best, cell) => (!best || cell.pct > best.pct ? cell : best), null);
    }

    get peakLabel() {
        const peak = this.peakDay;
        if (!peak) {
            return '';
        }
        return `Busiest: ${peak.weekday} ${peak.dayNumber} at ${peak.pct}%`;
    }

    get hasCells() {
        return this.cells.length > 0;
    }

    get isLoading() {
        return !this.hasLoaded;
    }

    get hasError() {
        return !!this.error;
    }

    get isEmpty() {
        return this.hasLoaded && !this.hasError && !this.hasCells;
    }

    get showOfficePicker() {
        return !this.isRecordContext && this.officeOptions.length > 0;
    }

    handleOfficeChange(event) {
        this.selectedOfficeId = event.detail.value;
        this.loadUtilisation();
    }

    handleRefresh() {
        this.loadUtilisation();
    }

    reduceError(error, fallback) {
        if (error?.body?.message) {
            return error.body.message;
        }
        if (Array.isArray(error?.body) && error.body[0]?.message) {
            return error.body[0].message;
        }
        return fallback || 'Something went wrong.';
    }
}
