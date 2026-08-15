import { LightningElement, api, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { getRecord } from 'lightning/uiRecordApi';
import getPassport from '@salesforce/apex/PSK_PassportController.getPassport';
import NAME_FIELD from '@salesforce/schema/Passport__c.Name';
import HOLDER_FIELD from '@salesforce/schema/Passport__c.Holder_Name__c';
import STATUS_FIELD from '@salesforce/schema/Passport__c.Status__c';
import ISSUE_FIELD from '@salesforce/schema/Passport__c.Date_of_Issue__c';
import EXPIRY_FIELD from '@salesforce/schema/Passport__c.Date_of_Expiry__c';
import DAYS_FIELD from '@salesforce/schema/Passport__c.Days_To_Expiry__c';
import IS_EXPIRED_FIELD from '@salesforce/schema/Passport__c.Is_Expired__c';
import IS_EXPIRING_FIELD from '@salesforce/schema/Passport__c.Is_Expiring_Soon__c';
import CATEGORY_FIELD from '@salesforce/schema/Passport__c.Passport_Category__c';
import PLACE_FIELD from '@salesforce/schema/Passport__c.Place_of_Issue__c';
import VALIDITY_FIELD from '@salesforce/schema/Passport__c.Validity_Years__c';
import BOOKLET_FIELD from '@salesforce/schema/Passport__c.Booklet_Pages__c';
import ECR_FIELD from '@salesforce/schema/Passport__c.ECR_Status__c';
import FILE_NUMBER_FIELD from '@salesforce/schema/Passport__c.File_Number__c';
import PREVIOUS_FIELD from '@salesforce/schema/Passport__c.Previous_Passport__c';
import PREVIOUS_NAME_FIELD from '@salesforce/schema/Passport__c.Previous_Passport__r.Name';

const RECORD_FIELDS = [
    NAME_FIELD,
    HOLDER_FIELD,
    STATUS_FIELD,
    ISSUE_FIELD,
    EXPIRY_FIELD,
    DAYS_FIELD,
    IS_EXPIRED_FIELD,
    IS_EXPIRING_FIELD,
    CATEGORY_FIELD,
    PLACE_FIELD,
    VALIDITY_FIELD,
    BOOKLET_FIELD,
    ECR_FIELD,
    FILE_NUMBER_FIELD,
    PREVIOUS_FIELD,
    PREVIOUS_NAME_FIELD
];

const RING_RADIUS = 42;
const RING_CIRCUMFERENCE = 2 * Math.PI * RING_RADIUS;

const STATUS_THEME = {
    Active: 'success',
    Expired: 'danger',
    Cancelled: 'danger',
    Lost: 'danger',
    Surrendered: 'neutral',
    Reissued: 'neutral'
};

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

export default class PskPassportCard extends NavigationMixin(LightningElement) {
    @api recordId;

    ringCircumference = RING_CIRCUMFERENCE;
    detail;
    detailError;
    recordError;
    recordLoaded = false;

    wiredRecordResult;

    @wire(getRecord, { recordId: '$recordId', fields: RECORD_FIELDS })
    wiredRecord(result) {
        this.wiredRecordResult = result;
        if (result.data) {
            this.recordError = undefined;
            this.recordLoaded = true;
        } else if (result.error) {
            this.recordError = this.reduceError(result.error, 'Unable to load this passport.');
            this.recordLoaded = true;
        }
    }

    connectedCallback() {
        this.loadDetail();
    }

    async loadDetail() {
        try {
            this.detail = await getPassport({ passportId: this.recordId });
            this.detailError = undefined;
        } catch (error) {
            // The reissue chain is enrichment only - the card still renders without it.
            this.detail = undefined;
            this.detailError = this.reduceError(error, 'Reissue history is unavailable.');
        }
    }

    fieldValue(field) {
        const fields = this.wiredRecordResult?.data?.fields;
        if (!fields) {
            return undefined;
        }
        if (field === PREVIOUS_NAME_FIELD) {
            return fields.Previous_Passport__r?.value?.fields?.Name?.value;
        }
        return fields[field.fieldApiName]?.value;
    }

    // ---------- booklet face ----------

    get passportNumber() {
        return this.fieldValue(NAME_FIELD) || '—';
    }

    get holderName() {
        return this.fieldValue(HOLDER_FIELD) || 'Holder not recorded';
    }

    get status() {
        return this.fieldValue(STATUS_FIELD) || 'Unknown';
    }

    get statusBadgeClass() {
        return `psk-badge psk-badge--${STATUS_THEME[this.status] || 'neutral'}`;
    }

    get dateOfIssue() {
        return this.fieldValue(ISSUE_FIELD);
    }

    get dateOfExpiry() {
        return this.fieldValue(EXPIRY_FIELD);
    }

    get category() {
        return this.fieldValue(CATEGORY_FIELD) || '—';
    }

    get placeOfIssue() {
        return this.fieldValue(PLACE_FIELD) || '—';
    }

    get bookletPages() {
        return this.fieldValue(BOOKLET_FIELD) || '—';
    }

    get ecrStatus() {
        return this.fieldValue(ECR_FIELD) || '—';
    }

    get fileNumber() {
        return this.fieldValue(FILE_NUMBER_FIELD) || '—';
    }

    // ---------- expiry ring ----------

    get daysToExpiry() {
        const value = this.fieldValue(DAYS_FIELD);
        return value === undefined || value === null ? null : Number(value);
    }

    get validityYears() {
        const value = Number(this.fieldValue(VALIDITY_FIELD));
        return Number.isFinite(value) && value > 0 ? value : 10;
    }

    get isExpired() {
        const flag = this.fieldValue(IS_EXPIRED_FIELD);
        if (flag !== undefined && flag !== null) {
            return !!flag;
        }
        return this.daysToExpiry !== null && this.daysToExpiry <= 0;
    }

    get isExpiringSoon() {
        const flag = this.fieldValue(IS_EXPIRING_FIELD);
        if (flag !== undefined && flag !== null) {
            return !!flag;
        }
        return this.daysToExpiry !== null && this.daysToExpiry > 0 && this.daysToExpiry <= 180;
    }

    get ringFraction() {
        const days = this.daysToExpiry;
        if (days === null) {
            return 0;
        }
        const totalDays = this.validityYears * 365;
        return Math.min(Math.max(days / totalDays, 0), 1);
    }

    get ringDashOffset() {
        return RING_CIRCUMFERENCE * (1 - this.ringFraction);
    }

    get ringClass() {
        if (this.isExpired) {
            return 'psk-ring__value psk-ring__value--expired';
        }
        if (this.isExpiringSoon) {
            return 'psk-ring__value psk-ring__value--soon';
        }
        return 'psk-ring__value psk-ring__value--ok';
    }

    get ringHeadline() {
        if (this.daysToExpiry === null) {
            return '—';
        }
        if (this.isExpired) {
            return `${Math.abs(this.daysToExpiry)}`;
        }
        return `${this.daysToExpiry}`;
    }

    get ringCaption() {
        if (this.daysToExpiry === null) {
            return 'no expiry date';
        }
        return this.isExpired ? 'days overdue' : 'days left';
    }

    get ringAriaLabel() {
        if (this.daysToExpiry === null) {
            return 'Expiry countdown unavailable';
        }
        return this.isExpired
            ? `Expired ${Math.abs(this.daysToExpiry)} days ago`
            : `${this.daysToExpiry} days until expiry`;
    }

    get expiryNoticeClass() {
        if (this.isExpired) {
            return 'psk-notice psk-notice--danger';
        }
        return 'psk-notice psk-notice--warning';
    }

    get expiryNotice() {
        if (this.isExpired) {
            return 'This passport has expired. A re-issue application is required.';
        }
        if (this.isExpiringSoon) {
            return 'This passport expires within six months. Prompt the holder to apply for re-issue.';
        }
        return '';
    }

    get showExpiryNotice() {
        return this.isExpired || this.isExpiringSoon;
    }

    // ---------- reissue chain ----------

    get chain() {
        const fromApex = toList(this.detail, ['chain', 'reissueChain', 'previousPassports', 'history']);
        if (fromApex.length > 0) {
            return fromApex.map((link, index) => ({
                key: pick(link, ['id', 'Id'], `link-${index}`),
                id: pick(link, ['id', 'Id'], null),
                number: pick(link, ['passportNumber', 'name', 'Name', 'number'], 'Unknown'),
                status: pick(link, ['status', 'Status__c'], ''),
                issued: pick(link, ['dateOfIssue', 'Date_of_Issue__c', 'issued'], null),
                isCurrent: pick(link, ['isCurrent', 'current'], false)
            }));
        }
        const previousId = this.fieldValue(PREVIOUS_FIELD);
        if (!previousId) {
            return [];
        }
        return [
            {
                key: previousId,
                id: previousId,
                number: this.fieldValue(PREVIOUS_NAME_FIELD) || 'Previous passport',
                status: 'Reissued',
                issued: null,
                isCurrent: false
            }
        ];
    }

    get hasChain() {
        return this.chain.length > 0;
    }

    // ---------- states ----------

    get isLoading() {
        return !this.recordLoaded;
    }

    get hasError() {
        return !!this.recordError;
    }

    get showCard() {
        return this.recordLoaded && !this.recordError;
    }

    handleOpenChainLink(event) {
        const recordId = event.currentTarget.dataset.id;
        if (!recordId) {
            return;
        }
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: { recordId, objectApiName: 'Passport__c', actionName: 'view' }
        });
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
