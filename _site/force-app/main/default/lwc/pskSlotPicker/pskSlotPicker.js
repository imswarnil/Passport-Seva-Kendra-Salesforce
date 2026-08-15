import { LightningElement, api } from 'lwc';
import { notifyRecordUpdateAvailable } from 'lightning/uiRecordApi';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getOffices from '@salesforce/apex/PSK_SlotBookingController.getOffices';
import getAvailableSlots from '@salesforce/apex/PSK_SlotBookingController.getAvailableSlots';
import book from '@salesforce/apex/PSK_SlotBookingController.book';

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

function toList(data, nestedNames) {
    if (Array.isArray(data)) {
        return data;
    }
    const nested = pick(data, nestedNames, null);
    return Array.isArray(nested) ? nested : [];
}

function num(value) {
    const parsed = Number(value);
    return Number.isFinite(parsed) ? parsed : 0;
}

/** Renders a Salesforce Time field (ms since midnight) or a plain string. */
function formatTime(value) {
    if (value === null || value === undefined || value === '') {
        return '';
    }
    if (typeof value === 'number') {
        const totalMinutes = Math.floor(value / 60000);
        const hours = Math.floor(totalMinutes / 60) % 24;
        const minutes = totalMinutes % 60;
        return `${String(hours).padStart(2, '0')}:${String(minutes).padStart(2, '0')}`;
    }
    const text = String(value);
    const match = text.match(/^(\d{2}):(\d{2})/);
    return match ? `${match[1]}:${match[2]}` : text;
}

function todayIso() {
    const now = new Date();
    const offsetMs = now.getTimezoneOffset() * 60000;
    return new Date(now.getTime() - offsetMs).toISOString().slice(0, 10);
}

export default class PskSlotPicker extends LightningElement {
    @api recordId;

    officeOptions = [];
    selectedOfficeId;
    selectedDate = todayIso();
    minDate = todayIso();

    slots = [];
    officesError;
    slotsError;
    officesLoaded = false;
    slotsLoaded = false;
    isLoadingSlots = false;
    bookingSlotId;

    connectedCallback() {
        this.loadOffices();
    }

    async loadOffices() {
        try {
            const data = await getOffices();
            this.officeOptions = toList(data, ['offices', 'records', 'items']).map((office, index) => ({
                label: pick(office, ['label', 'name', 'Name', 'officeName'], `Office ${index + 1}`),
                value: pick(office, ['value', 'id', 'Id', 'officeId'], `office-${index}`)
            }));
            this.officesError = undefined;
        } catch (error) {
            this.officeOptions = [];
            this.officesError = this.reduceError(error, 'Unable to load PSK offices.');
        } finally {
            this.officesLoaded = true;
        }
    }

    async loadSlots() {
        if (!this.selectedOfficeId || !this.selectedDate) {
            this.slots = [];
            this.slotsLoaded = false;
            return;
        }
        this.isLoadingSlots = true;
        try {
            const data = await getAvailableSlots({ officeId: this.selectedOfficeId, d: this.selectedDate });
            this.slots = toList(data, ['slots', 'records', 'items']);
            this.slotsError = undefined;
        } catch (error) {
            this.slots = [];
            this.slotsError = this.reduceError(error, 'Unable to load slots for that date.');
        } finally {
            this.isLoadingSlots = false;
            this.slotsLoaded = true;
        }
    }

    get slotTiles() {
        return (this.slots || []).map((slot, index) => {
            const id = pick(slot, ['id', 'Id', 'slotId'], `slot-${index}`);
            const capacity = num(pick(slot, ['capacity', 'Capacity__c'], 0));
            const booked = num(pick(slot, ['bookedCount', 'Booked_Count__c', 'booked'], 0));
            const remaining = Math.max(capacity - booked, 0);
            const explicitAvailable = pick(slot, ['isAvailable', 'available', 'Is_Available__c'], undefined);
            const isFull = explicitAvailable === undefined ? capacity > 0 && remaining <= 0 : !explicitAvailable;
            const pct = capacity > 0 ? Math.min(Math.round((booked / capacity) * 100), 100) : 0;
            const band = pct >= 90 ? 'full' : pct >= 60 ? 'busy' : 'open';
            const start = formatTime(pick(slot, ['startTime', 'Start_Time__c', 'start'], null));
            const end = formatTime(pick(slot, ['endTime', 'End_Time__c', 'end'], null));
            const timeLabel = end ? `${start} – ${end}` : start || 'Slot';
            return {
                key: `${id}`,
                id,
                timeLabel,
                capacityLabel: capacity > 0 ? `${remaining} of ${capacity} free` : 'Capacity not set',
                ariaLabel: `Book ${timeLabel}, ${remaining} of ${capacity} places free`,
                isFull,
                isBusy: this.bookingSlotId === id,
                disabled: isFull || !!this.bookingSlotId,
                tileClass: `psk-slot psk-slot--${band}${isFull ? ' psk-slot--disabled' : ''}`,
                fillStyle: `width: ${pct}%`
            };
        });
    }

    get hasOffices() {
        return this.officeOptions.length > 0;
    }

    get isLoadingOffices() {
        return !this.officesLoaded;
    }

    get hasOfficesError() {
        return !!this.officesError;
    }

    get noOffices() {
        return this.officesLoaded && !this.officesError && !this.hasOffices;
    }

    get hasSlotsError() {
        return !!this.slotsError;
    }

    get hasSlots() {
        return this.slotTiles.length > 0;
    }

    get showNoSlots() {
        return (
            !!this.selectedOfficeId && this.slotsLoaded && !this.isLoadingSlots && !this.slotsError && !this.hasSlots
        );
    }

    get showPrompt() {
        return this.hasOffices && !this.selectedOfficeId;
    }

    handleOfficeChange(event) {
        this.selectedOfficeId = event.detail.value;
        this.slotsLoaded = false;
        this.loadSlots();
    }

    handleDateChange(event) {
        this.selectedDate = event.detail.value;
        this.slotsLoaded = false;
        this.loadSlots();
    }

    handleRefresh() {
        this.loadSlots();
    }

    async handleBook(event) {
        const slotId = event.currentTarget.dataset.id;
        this.bookingSlotId = slotId;
        try {
            await book({ applicationId: this.recordId, slotId });
            notifyRecordUpdateAvailable([{ recordId: this.recordId }]);
            await this.loadSlots();
            this.showToast('Appointment booked', 'The appointment was created for the selected slot.', 'success');
        } catch (error) {
            this.showToast('Booking failed', this.reduceError(error, 'Unable to book that slot.'), 'error');
        } finally {
            this.bookingSlotId = undefined;
        }
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
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
