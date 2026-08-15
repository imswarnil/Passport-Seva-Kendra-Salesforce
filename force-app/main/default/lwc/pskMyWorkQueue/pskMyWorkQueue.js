import { LightningElement } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import getMyWork from '@salesforce/apex/PSK_MyWorkController.getMyWork';

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

const OBJECT_ICON = {
    Passport_Application__c: 'standard:record',
    Document_Checklist_Item__c: 'standard:document',
    Police_Verification__c: 'standard:user_role',
    Objection__c: 'standard:case',
    Print_Job__c: 'standard:print_queue',
    Dispatch__c: 'standard:delivery_installation',
    Appointment__c: 'standard:event',
    Payment__c: 'standard:currency',
    Risk_Flag__c: 'standard:first_non_empty'
};

export default class PskMyWorkQueue extends NavigationMixin(LightningElement) {
    work;
    items = [];
    error;
    hasLoaded = false;
    showBreachedOnly = false;

    connectedCallback() {
        this.loadWork();
    }

    async loadWork() {
        try {
            const data = await getMyWork();
            this.work = data;
            this.items = toList(data, ['items', 'work', 'records', 'assignments']);
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
            const objectApiName = pick(item, ['objectApiName', 'sobjectType', 'objectType', 'type'], null);
            const breached = !!pick(item, ['isSlaBreached', 'slaBreached', 'breached', 'isBreached'], false);
            const dueDate = pick(item, ['dueDate', 'slaDueDate', 'due', 'targetDate'], null);
            return {
                key: `${pick(item, ['id', 'Id', 'recordId'], index)}-${index}`,
                id: pick(item, ['recordId', 'id', 'Id'], null),
                objectApiName,
                icon: pick(item, ['icon', 'iconName'], OBJECT_ICON[objectApiName] || 'standard:task'),
                title: pick(item, ['title', 'name', 'Name', 'subject', 'label'], 'Work item'),
                subtitle: pick(item, ['subtitle', 'description', 'detail', 'applicantName'], ''),
                status: pick(item, ['status', 'Status__c', 'stage'], ''),
                queue: pick(item, ['queue', 'queueName', 'owner', 'ownerName', 'assignedTo'], ''),
                ageLabel: this.ageLabel(item),
                dueDate,
                breached,
                badgeClass: breached ? 'psk-badge psk-badge--danger' : 'psk-badge psk-badge--neutral',
                rowClass: breached ? 'psk-work__item psk-work__item--breached' : 'psk-work__item'
            };
        });
    }

    ageLabel(item) {
        const hours = pick(item, ['ageHours', 'ageInHours', 'hoursOpen'], null);
        if (hours !== null) {
            const value = Number(hours);
            if (Number.isFinite(value)) {
                return value >= 48 ? `${Math.round(value / 24)}d in stage` : `${Math.round(value)}h in stage`;
            }
        }
        const days = pick(item, ['ageDays', 'daysOpen', 'ageInDays'], null);
        if (days !== null) {
            const value = Number(days);
            if (Number.isFinite(value)) {
                return `${Math.round(value)}d in stage`;
            }
        }
        return '';
    }

    get visibleRows() {
        return this.showBreachedOnly ? this.rows.filter((row) => row.breached) : this.rows;
    }

    get breachedCount() {
        return this.rows.filter((row) => row.breached).length;
    }

    get totalCount() {
        return this.rows.length;
    }

    get hasBreaches() {
        return this.breachedCount > 0;
    }

    get breachSummary() {
        return `${this.breachedCount} of ${this.totalCount} past SLA`;
    }

    get toggleLabel() {
        return this.showBreachedOnly ? 'Showing SLA breaches only' : 'Showing all my work';
    }

    get hasRows() {
        return this.visibleRows.length > 0;
    }

    get isLoading() {
        return !this.hasLoaded;
    }

    get hasError() {
        return !!this.error;
    }

    get isEmpty() {
        return this.hasLoaded && !this.hasError && this.totalCount === 0;
    }

    get isFilteredEmpty() {
        return this.hasLoaded && !this.hasError && this.totalCount > 0 && !this.hasRows;
    }

    handleToggle(event) {
        this.showBreachedOnly = event.target.checked;
    }

    handleRefresh() {
        this.hasLoaded = false;
        this.loadWork();
    }

    handleOpen(event) {
        const { id, object } = event.currentTarget.dataset;
        if (!id) {
            return;
        }
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: { recordId: id, objectApiName: object || undefined, actionName: 'view' }
        });
    }

    reduceError(error) {
        if (error?.body?.message) {
            return error.body.message;
        }
        if (Array.isArray(error?.body) && error.body[0]?.message) {
            return error.body[0].message;
        }
        return 'Unable to load your work queue.';
    }
}
