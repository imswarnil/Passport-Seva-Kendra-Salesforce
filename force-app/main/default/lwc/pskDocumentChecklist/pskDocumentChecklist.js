import { LightningElement, api } from 'lwc';
import { notifyRecordUpdateAvailable } from 'lightning/uiRecordApi';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getItems from '@salesforce/apex/PSK_DocumentChecklistController.getItems';
import setStatus from '@salesforce/apex/PSK_DocumentChecklistController.setStatus';
import seedFromTemplate from '@salesforce/apex/PSK_DocumentChecklistController.seedFromTemplate';

const STATUS_OPTIONS = [
    { label: 'Required', value: 'Required' },
    { label: 'Received', value: 'Received' },
    { label: 'Verified', value: 'Verified' },
    { label: 'Rejected', value: 'Rejected' }
];

// Document_Checklist_Item__c has no Is_Mandatory__c field, so if the Apex
// wrapper does not expose a mandatory flag we fall back to this core set.
const MANDATORY_TYPES = ['Aadhaar Proof', 'Address Proof', 'Date of Birth Proof'];

const BADGE_BY_STATUS = {
    Verified: 'psk-badge psk-badge--success',
    Received: 'psk-badge psk-badge--info',
    Rejected: 'psk-badge psk-badge--danger',
    Required: 'psk-badge psk-badge--neutral'
};

/** Reads the first property that actually exists on a wrapper. */
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

/** Accepts either a bare list or a wrapper that contains one. */
function toList(data) {
    if (Array.isArray(data)) {
        return data;
    }
    const nested = pick(data, ['items', 'records', 'checklist'], null);
    return Array.isArray(nested) ? nested : [];
}

export default class PskDocumentChecklist extends LightningElement {
    @api recordId;

    statusOptions = STATUS_OPTIONS;
    items = [];
    error;
    hasLoaded = false;
    busyRowId;
    isSeeding = false;

    connectedCallback() {
        this.loadItems();
    }

    async loadItems() {
        try {
            const data = await getItems({ applicationId: this.recordId });
            this.items = toList(data);
            this.error = undefined;
        } catch (error) {
            this.items = [];
            this.error = this.reduceError(error);
        } finally {
            this.hasLoaded = true;
        }
    }

    get rows() {
        return (this.items || []).map((item, index) => {
            const id = pick(item, ['id', 'Id', 'itemId', 'recordId'], `row-${index}`);
            const documentType = pick(item, ['documentType', 'Document_Type__c', 'type', 'name', 'Name'], 'Document');
            const status = pick(item, ['status', 'Status__c'], 'Required');
            const mandatoryFlag = pick(item, ['isMandatory', 'mandatory', 'Is_Mandatory__c'], undefined);
            const mandatory =
                mandatoryFlag === undefined ? MANDATORY_TYPES.includes(documentType) : !!mandatoryFlag;
            return {
                key: `${id}`,
                id,
                documentType,
                status,
                mandatory,
                badgeClass: BADGE_BY_STATUS[status] || BADGE_BY_STATUS.Required,
                comboboxLabel: `Status for ${documentType}`,
                notes: pick(item, ['notes', 'Notes__c'], ''),
                rejectionReason: pick(item, ['rejectionReason', 'Rejection_Reason__c'], ''),
                isRejected: status === 'Rejected',
                isBusy: this.busyRowId === id,
                rowClass: mandatory ? 'psk-doc-row psk-doc-row--mandatory' : 'psk-doc-row'
            };
        });
    }

    get mandatoryRows() {
        return this.rows.filter((row) => row.mandatory);
    }

    get scopedRows() {
        return this.mandatoryRows.length > 0 ? this.mandatoryRows : this.rows;
    }

    get mandatoryTotal() {
        return this.scopedRows.length;
    }

    get mandatoryVerified() {
        return this.scopedRows.filter((row) => row.status === 'Verified').length;
    }

    get progressPercent() {
        const total = this.mandatoryTotal;
        return total ? Math.round((this.mandatoryVerified / total) * 100) : 0;
    }

    get progressStyle() {
        return `width: ${this.progressPercent}%`;
    }

    get progressLabel() {
        if (!this.mandatoryTotal) {
            return 'No checklist items yet';
        }
        return `${this.mandatoryVerified} of ${this.mandatoryTotal} mandatory documents verified`;
    }

    get rejectedCount() {
        return this.rows.filter((row) => row.status === 'Rejected').length;
    }

    get hasRejected() {
        return this.rejectedCount > 0;
    }

    get rejectedLabel() {
        return `${this.rejectedCount} document${this.rejectedCount === 1 ? '' : 's'} rejected`;
    }

    get isComplete() {
        return this.mandatoryTotal > 0 && this.mandatoryVerified === this.mandatoryTotal;
    }

    get isLoading() {
        return !this.hasLoaded;
    }

    get hasError() {
        return !!this.error;
    }

    get hasRows() {
        return this.rows.length > 0;
    }

    get isEmpty() {
        return this.hasLoaded && !this.hasError && !this.hasRows;
    }

    get seedDisabled() {
        return this.isSeeding;
    }

    async handleStatusChange(event) {
        const itemId = event.currentTarget.dataset.id;
        const newStatus = event.detail.value;
        this.busyRowId = itemId;
        try {
            await setStatus({ itemId, status: newStatus });
            await this.refreshAll();
            this.showToast('Document updated', `Status set to ${newStatus}.`, 'success');
        } catch (error) {
            this.showToast('Update failed', this.reduceError(error), 'error');
        } finally {
            this.busyRowId = undefined;
        }
    }

    async handleSeed() {
        this.isSeeding = true;
        try {
            await seedFromTemplate({ applicationId: this.recordId });
            await this.refreshAll();
            this.showToast('Checklist seeded', 'Standard documents were added to this application.', 'success');
        } catch (error) {
            this.showToast('Unable to seed checklist', this.reduceError(error), 'error');
        } finally {
            this.isSeeding = false;
        }
    }

    handleRefresh() {
        this.loadItems();
    }

    async refreshAll() {
        notifyRecordUpdateAvailable([{ recordId: this.recordId }]);
        await this.loadItems();
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    reduceError(error) {
        if (error?.body?.message) {
            return error.body.message;
        }
        if (Array.isArray(error?.body) && error.body[0]?.message) {
            return error.body[0].message;
        }
        if (typeof error === 'string') {
            return error;
        }
        return 'Unable to load the document checklist.';
    }
}
