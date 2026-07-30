import { LightningElement, api, wire } from 'lwc';
import { getRecord, notifyRecordUpdateAvailable } from 'lightning/uiRecordApi';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import preview from '@salesforce/apex/PSK_FeeService.preview';
import recalculate from '@salesforce/apex/PSK_FeeService.recalculate';
import FEE_FIELD from '@salesforce/schema/Passport_Application__c.Fee__c';
import TATKAL_FIELD from '@salesforce/schema/Passport_Application__c.Tatkal__c';
import CATEGORY_FIELD from '@salesforce/schema/Passport_Application__c.Passport_Category__c';
import VALIDITY_FIELD from '@salesforce/schema/Passport_Application__c.Validity_Years__c';
import BOOKLET_FIELD from '@salesforce/schema/Passport_Application__c.Booklet_Pages__c';
import PAYMENT_STATUS_FIELD from '@salesforce/schema/Passport_Application__c.Payment_Status__c';

const RECORD_FIELDS = [
    FEE_FIELD,
    TATKAL_FIELD,
    CATEGORY_FIELD,
    VALIDITY_FIELD,
    BOOKLET_FIELD,
    PAYMENT_STATUS_FIELD
];

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

function num(value) {
    const parsed = Number(value);
    return Number.isFinite(parsed) ? parsed : 0;
}

export default class PskFeeCalculator extends LightningElement {
    @api recordId;

    quote;
    error;
    hasLoaded = false;
    isRecalculating = false;

    wiredRecordResult;

    @wire(getRecord, { recordId: '$recordId', fields: RECORD_FIELDS })
    wiredRecord(result) {
        this.wiredRecordResult = result;
    }

    connectedCallback() {
        this.loadPreview();
    }

    async loadPreview() {
        try {
            const data = await preview({ applicationId: this.recordId });
            this.quote = data;
            this.error = undefined;
        } catch (error) {
            this.quote = undefined;
            this.error = this.reduceError(error);
        } finally {
            this.hasLoaded = true;
        }
    }

    // ---------- record-sourced context (field API names are known) ----------

    fieldValue(field) {
        return this.wiredRecordResult?.data?.fields?.[field.fieldApiName]?.value;
    }

    get recordFee() {
        return this.fieldValue(FEE_FIELD);
    }

    get isTatkal() {
        const fromQuote = pick(this.quote, ['isTatkal', 'tatkal', 'Tatkal__c'], undefined);
        return fromQuote === undefined ? !!this.fieldValue(TATKAL_FIELD) : !!fromQuote;
    }

    get applicationType() {
        return (
            pick(this.quote, ['applicationType', 'Application_Type__c', 'category', 'matrixApplicationType'], null) ||
            this.fieldValue(CATEGORY_FIELD) ||
            '—'
        );
    }

    get validityYears() {
        return (
            pick(this.quote, ['validityYears', 'Validity_Years__c'], null) ?? this.fieldValue(VALIDITY_FIELD) ?? '—'
        );
    }

    get bookletPages() {
        return pick(this.quote, ['bookletPages', 'Booklet_Pages__c'], null) ?? this.fieldValue(BOOKLET_FIELD) ?? '—';
    }

    get paymentStatus() {
        return this.fieldValue(PAYMENT_STATUS_FIELD) || 'Not started';
    }

    // ---------- fee derivation lines ----------

    get baseFee() {
        return num(pick(this.quote, ['baseFee', 'Base_Fee__c', 'base'], 0));
    }

    get tatkalSurcharge() {
        return num(pick(this.quote, ['tatkalSurcharge', 'Tatkal_Surcharge__c', 'surcharge'], 0));
    }

    get additionalBookletFee() {
        return num(pick(this.quote, ['additionalBookletFee', 'Additional_Booklet_Fee__c', 'bookletFee'], 0));
    }

    get totalFee() {
        const explicit = pick(this.quote, ['totalFee', 'total', 'fee', 'Fee__c', 'amount'], undefined);
        if (explicit !== undefined) {
            return num(explicit);
        }
        return this.baseFee + this.tatkalSurcharge + this.additionalBookletFee;
    }

    get hasTatkalSurcharge() {
        return this.tatkalSurcharge > 0;
    }

    get hasBookletFee() {
        return this.additionalBookletFee > 0;
    }

    get matrixLabel() {
        return pick(this.quote, ['matrixLabel', 'matrixName', 'feeMatrixName', 'DeveloperName'], null);
    }

    get hasMatrix() {
        const found = pick(this.quote, ['matrixFound', 'hasMatrix', 'isMatched'], undefined);
        if (found !== undefined) {
            return !!found;
        }
        return this.totalFee > 0;
    }

    get isOutOfSync() {
        const stored = this.recordFee;
        if (stored === undefined || stored === null || !this.quote) {
            return false;
        }
        return Math.abs(num(stored) - this.totalFee) > 0.009;
    }

    get syncMessage() {
        return `The stored Fee on this application does not match the current Fee Matrix derivation. Recalculate to update it.`;
    }

    // ---------- states ----------

    get isLoading() {
        return !this.hasLoaded;
    }

    get hasError() {
        return !!this.error;
    }

    get isEmpty() {
        return this.hasLoaded && !this.hasError && !this.hasMatrix;
    }

    get showBreakdown() {
        return this.hasLoaded && !this.hasError && this.hasMatrix;
    }

    get recalculateDisabled() {
        return this.isRecalculating;
    }

    async handleRecalculate() {
        this.isRecalculating = true;
        try {
            await recalculate({ applicationId: this.recordId });
            notifyRecordUpdateAvailable([{ recordId: this.recordId }]);
            await this.loadPreview();
            this.showToast('Fee recalculated', 'The application fee was recalculated from the Fee Matrix.', 'success');
        } catch (error) {
            this.showToast('Recalculation failed', this.reduceError(error), 'error');
        } finally {
            this.isRecalculating = false;
        }
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
        return 'Unable to derive the fee for this application.';
    }
}
