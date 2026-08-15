import { LightningElement, api, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { getRecord } from 'lightning/uiRecordApi';
import getProfile from '@salesforce/apex/PSK_Citizen360Controller.getProfile';
import NAME_FIELD from '@salesforce/schema/Citizen__c.Name';
import KYC_FIELD from '@salesforce/schema/Citizen__c.KYC_Status__c';
import AADHAAR_VERIFIED_FIELD from '@salesforce/schema/Citizen__c.Aadhaar_Verified__c';
import BLACKLISTED_FIELD from '@salesforce/schema/Citizen__c.Is_Blacklisted__c';
import BLACKLIST_REASON_FIELD from '@salesforce/schema/Citizen__c.Blacklist_Reason__c';
import IS_MINOR_FIELD from '@salesforce/schema/Citizen__c.Is_Minor__c';
import AGE_FIELD from '@salesforce/schema/Citizen__c.Age__c';
import MOBILE_FIELD from '@salesforce/schema/Citizen__c.Mobile__c';
import EMAIL_FIELD from '@salesforce/schema/Citizen__c.Email__c';
import CITY_FIELD from '@salesforce/schema/Citizen__c.City__c';
import STATE_FIELD from '@salesforce/schema/Citizen__c.State__c';
import LANGUAGE_FIELD from '@salesforce/schema/Citizen__c.Preferred_Language__c';
import REFERENCE_FIELD from '@salesforce/schema/Citizen__c.Citizen_Reference__c';

const RECORD_FIELDS = [
    NAME_FIELD,
    KYC_FIELD,
    AADHAAR_VERIFIED_FIELD,
    BLACKLISTED_FIELD,
    BLACKLIST_REASON_FIELD,
    IS_MINOR_FIELD,
    AGE_FIELD,
    MOBILE_FIELD,
    EMAIL_FIELD,
    CITY_FIELD,
    STATE_FIELD,
    LANGUAGE_FIELD,
    REFERENCE_FIELD
];

const KYC_THEME = {
    Verified: 'success',
    'In Progress': 'info',
    Failed: 'danger',
    'Not Started': 'neutral'
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

function toList(source, names) {
    if (Array.isArray(source)) {
        return source;
    }
    const nested = pick(source, names, null);
    return Array.isArray(nested) ? nested : [];
}

export default class PskCitizen360 extends NavigationMixin(LightningElement) {
    @api recordId;

    profile;
    profileError;
    profileLoaded = false;
    activeTab = 'applications';

    wiredRecordResult;

    @wire(getRecord, { recordId: '$recordId', fields: RECORD_FIELDS })
    wiredRecord(result) {
        this.wiredRecordResult = result;
    }

    connectedCallback() {
        this.loadProfile();
    }

    async loadProfile() {
        try {
            this.profile = await getProfile({ citizenId: this.recordId });
            this.profileError = undefined;
        } catch (error) {
            this.profile = undefined;
            this.profileError = this.reduceError(error);
        } finally {
            this.profileLoaded = true;
        }
    }

    fieldValue(field) {
        return this.wiredRecordResult?.data?.fields?.[field.fieldApiName]?.value;
    }

    // ---------- identity header ----------

    get citizenName() {
        return this.fieldValue(NAME_FIELD) || 'Citizen';
    }

    get citizenReference() {
        return this.fieldValue(REFERENCE_FIELD) || '—';
    }

    get kycStatus() {
        return this.fieldValue(KYC_FIELD) || 'Not Started';
    }

    get kycBadgeClass() {
        return `psk-badge psk-badge--${KYC_THEME[this.kycStatus] || 'neutral'}`;
    }

    get aadhaarVerified() {
        return !!this.fieldValue(AADHAAR_VERIFIED_FIELD);
    }

    get aadhaarBadgeClass() {
        return this.aadhaarVerified ? 'psk-badge psk-badge--success' : 'psk-badge psk-badge--neutral';
    }

    get aadhaarLabel() {
        return this.aadhaarVerified ? 'Aadhaar verified' : 'Aadhaar not verified';
    }

    get isBlacklisted() {
        return !!this.fieldValue(BLACKLISTED_FIELD);
    }

    get blacklistReason() {
        return this.fieldValue(BLACKLIST_REASON_FIELD) || 'No reason recorded.';
    }

    get isMinor() {
        return !!this.fieldValue(IS_MINOR_FIELD);
    }

    get age() {
        const value = this.fieldValue(AGE_FIELD);
        return value === undefined || value === null ? '—' : value;
    }

    get mobile() {
        return this.fieldValue(MOBILE_FIELD) || '—';
    }

    get email() {
        return this.fieldValue(EMAIL_FIELD) || '—';
    }

    get location() {
        const parts = [this.fieldValue(CITY_FIELD), this.fieldValue(STATE_FIELD)].filter(Boolean);
        return parts.length ? parts.join(', ') : '—';
    }

    get language() {
        return this.fieldValue(LANGUAGE_FIELD) || '—';
    }

    get riskScore() {
        return pick(this.profile, ['riskScore', 'Risk_Score__c', 'aggregateRiskScore'], undefined);
    }

    // ---------- related collections ----------

    get applications() {
        return toList(pick(this.profile, ['applications', 'passportApplications'], null), []).map((app, index) => ({
            key: pick(app, ['id', 'Id'], `app-${index}`),
            id: pick(app, ['id', 'Id'], null),
            title: pick(app, ['arn', 'name', 'Name', 'applicationNumber'], 'Application'),
            status: pick(app, ['status', 'Status__c'], ''),
            subtitle: pick(app, ['category', 'Passport_Category__c', 'recordType', 'recordTypeName'], ''),
            timestamp: pick(app, ['submittedDate', 'Submitted_Date__c', 'createdDate', 'CreatedDate'], null),
            objectApiName: 'Passport_Application__c'
        }));
    }

    get passports() {
        return toList(pick(this.profile, ['passports', 'issuedPassports'], null), []).map((p, index) => ({
            key: pick(p, ['id', 'Id'], `passport-${index}`),
            id: pick(p, ['id', 'Id'], null),
            title: pick(p, ['passportNumber', 'name', 'Name', 'number'], 'Passport'),
            status: pick(p, ['status', 'Status__c'], ''),
            subtitle: pick(p, ['category', 'Passport_Category__c'], ''),
            timestamp: pick(p, ['dateOfExpiry', 'Date_of_Expiry__c', 'expiry'], null),
            objectApiName: 'Passport__c'
        }));
    }

    get familyMembers() {
        return toList(pick(this.profile, ['familyMembers', 'family', 'members'], null), []).map((m, index) => ({
            key: pick(m, ['id', 'Id'], `member-${index}`),
            id: pick(m, ['id', 'Id'], null),
            title: pick(m, ['memberName', 'Member_Name__c', 'displayName', 'Display_Name__c', 'name', 'Name'], 'Family member'),
            status: pick(m, ['relationship', 'Relationship__c'], ''),
            subtitle: pick(m, ['isGuardian', 'Is_Guardian__c'], false) ? 'Guardian' : '',
            timestamp: null,
            objectApiName: 'Family_Member__c'
        }));
    }

    get applicationCount() {
        return this.applications.length;
    }

    get passportCount() {
        return this.passports.length;
    }

    get familyCount() {
        return this.familyMembers.length;
    }

    get hasApplications() {
        return this.applicationCount > 0;
    }

    get hasPassports() {
        return this.passportCount > 0;
    }

    get hasFamily() {
        return this.familyCount > 0;
    }

    get applicationsTabLabel() {
        return `Applications (${this.applicationCount})`;
    }

    get passportsTabLabel() {
        return `Passports (${this.passportCount})`;
    }

    get familyTabLabel() {
        return `Family (${this.familyCount})`;
    }

    // ---------- states ----------

    get isLoading() {
        return !this.profileLoaded;
    }

    get hasError() {
        return !!this.profileError;
    }

    get showBody() {
        return this.profileLoaded && !this.profileError;
    }

    handleOpenRecord(event) {
        const { id, object } = event.currentTarget.dataset;
        if (!id) {
            return;
        }
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: { recordId: id, objectApiName: object, actionName: 'view' }
        });
    }

    handleRetry() {
        this.profileLoaded = false;
        this.loadProfile();
    }

    reduceError(error) {
        if (error?.body?.message) {
            return error.body.message;
        }
        if (Array.isArray(error?.body) && error.body[0]?.message) {
            return error.body[0].message;
        }
        return 'Unable to load this citizen profile.';
    }
}
