import { LightningElement, api, wire } from 'lwc';
import { getRecord, notifyRecordUpdateAvailable } from 'lightning/uiRecordApi';
import { refreshApex } from '@salesforce/apex';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getSidebarData from '@salesforce/apex/PSK_ApplicationSidebarController.getSidebarData';
import advanceApplication from '@salesforce/apex/PSK_ApplicationActionsController.advance';
import rejectApplication from '@salesforce/apex/PSK_ApplicationActionsController.reject';
import STATUS_FIELD from '@salesforce/schema/Passport_Application__c.Status__c';
import RISK_SCORE_FIELD from '@salesforce/schema/Passport_Application__c.Risk_Score__c';
import PAYMENT_STATUS_FIELD from '@salesforce/schema/Passport_Application__c.Payment_Status__c';
import IS_MINOR_FIELD from '@salesforce/schema/Passport_Application__c.Is_Minor__c';

const RECORD_FIELDS = [STATUS_FIELD, RISK_SCORE_FIELD, PAYMENT_STATUS_FIELD, IS_MINOR_FIELD];

const NEXT_STEP_LABEL = {
    Draft: 'Submit Application',
    Submitted: 'Request Payment',
    'Payment Pending': 'Mark Paid',
    Paid: 'Send to Document Verification',
    'Document Verification': 'Validate Documents & Send to Police Verification',
    'Police Verification': 'Clear Verification & Send to Granting',
    Granting: 'Send to Printing',
    Printing: 'Send to Dispatch',
    Dispatch: 'Mark Delivered'
};

const TERMINAL_STATUSES = ['Delivered', 'Rejected', 'Cancelled'];

export default class PskApplicationSidebar extends LightningElement {
    @api recordId;

    sidebar;
    error;
    isActionRunning = false;

    wiredRecordResult;
    wiredSidebarResult;

    @wire(getRecord, { recordId: '$recordId', fields: RECORD_FIELDS })
    wiredRecord(result) {
        this.wiredRecordResult = result;
    }

    @wire(getSidebarData, { applicationId: '$recordId' })
    wiredSidebar(result) {
        this.wiredSidebarResult = result;
        const { data, error } = result;
        if (data) {
            this.sidebar = data;
            this.error = undefined;
        } else if (error) {
            this.error = this.reduceError(error);
        }
    }

    get record() {
        return this.wiredRecordResult;
    }

    get riskScore() {
        return this.record?.data?.fields?.Risk_Score__c?.value;
    }

    get status() {
        return this.record?.data?.fields?.Status__c?.value;
    }

    get paymentStatus() {
        return this.record?.data?.fields?.Payment_Status__c?.value;
    }

    get isMinor() {
        return this.record?.data?.fields?.Is_Minor__c?.value;
    }

    get documentsProgressLabel() {
        if (!this.sidebar || !this.sidebar.documentsTotal) {
            return 'No checklist items yet';
        }
        return `${this.sidebar.documentsVerified} of ${this.sidebar.documentsTotal} verified`;
    }

    get documentsProgressStyle() {
        if (!this.sidebar || !this.sidebar.documentsTotal) {
            return 'width: 0%';
        }
        const pct = (this.sidebar.documentsVerified / this.sidebar.documentsTotal) * 100;
        return `width: ${pct}%`;
    }

    get hasDocumentsRejected() {
        return this.sidebar && this.sidebar.documentsRejected > 0;
    }

    get paymentBadgeClass() {
        return `psk-badge ${this.badgeModifier(this.sidebar?.paymentStatus)}`;
    }

    get pvBadgeClass() {
        return `psk-badge ${this.badgeModifier(this.sidebar?.policeVerificationStatus)}`;
    }

    get hasOpenRiskFlags() {
        return this.sidebar && this.sidebar.openRiskFlags > 0;
    }

    get riskFlagBadgeClass() {
        return this.hasOpenRiskFlags ? 'psk-badge psk-badge--danger' : 'psk-badge psk-badge--success';
    }

    get riskFlagLabel() {
        if (!this.sidebar || !this.sidebar.totalRiskFlags) {
            return 'No flags';
        }
        return `${this.sidebar.openRiskFlags} open of ${this.sidebar.totalRiskFlags}`;
    }

    get hasPayment() {
        return !!this.sidebar?.paymentStatus;
    }

    get hasPoliceVerification() {
        return !!this.sidebar?.policeVerificationStatus;
    }

    get hasError() {
        return !!this.error;
    }

    get nextStepLabel() {
        return NEXT_STEP_LABEL[this.status];
    }

    get hasNextStep() {
        return !!this.nextStepLabel;
    }

    get isTerminal() {
        return TERMINAL_STATUSES.includes(this.status);
    }

    get canReject() {
        return this.status && !this.isTerminal;
    }

    get actionsDisabled() {
        return this.isActionRunning;
    }

    async handleAdvance() {
        this.isActionRunning = true;
        try {
            const result = await advanceApplication({ applicationId: this.recordId });
            this.showToast('Success', result.message, 'success');
            await this.refreshAll();
        } catch (error) {
            this.showToast('Action failed', this.reduceError(error), 'error');
        } finally {
            this.isActionRunning = false;
        }
    }

    async handleReject() {
        this.isActionRunning = true;
        try {
            const result = await rejectApplication({ applicationId: this.recordId });
            this.showToast('Application rejected', result.message, 'warning');
            await this.refreshAll();
        } catch (error) {
            this.showToast('Action failed', this.reduceError(error), 'error');
        } finally {
            this.isActionRunning = false;
        }
    }

    async refreshAll() {
        notifyRecordUpdateAvailable([{ recordId: this.recordId }]);
        await Promise.all([refreshApex(this.wiredRecordResult), refreshApex(this.wiredSidebarResult)]);
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    badgeModifier(status) {
        const positive = ['Success', 'Paid', 'Cleared', 'Verified'];
        const negative = ['Failed', 'Adverse', 'Rejected'];
        if (positive.includes(status)) {
            return 'psk-badge--success';
        }
        if (negative.includes(status)) {
            return 'psk-badge--danger';
        }
        return 'psk-badge--neutral';
    }

    reduceError(error) {
        if (error && error.body && error.body.message) {
            return error.body.message;
        }
        if (typeof error === 'string') {
            return error;
        }
        return 'Unable to load application snapshot.';
    }
}
