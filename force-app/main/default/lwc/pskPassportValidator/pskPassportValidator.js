import { LightningElement, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { gql, graphql } from 'lightning/uiGraphQLApi';

/** Unwraps the { value } envelope the UI API GraphQL layer puts around scalars. */
function val(field) {
    if (field === null || field === undefined) {
        return null;
    }
    return typeof field === 'object' && 'value' in field ? field.value : field;
}

const VERDICT = {
    valid: {
        key: 'valid',
        headline: 'Valid',
        detail: 'This passport is active and within its validity period.',
        icon: 'utility:success',
        theme: 'valid'
    },
    expiring: {
        key: 'expiring',
        headline: 'Valid — expiring soon',
        detail: 'This passport is still active but expires within six months.',
        icon: 'utility:warning',
        theme: 'warning'
    },
    expired: {
        key: 'expired',
        headline: 'Expired',
        detail: 'This passport is past its date of expiry and cannot be used for travel.',
        icon: 'utility:error',
        theme: 'invalid'
    },
    invalid: {
        key: 'invalid',
        headline: 'Not valid',
        detail: 'This passport is no longer valid. Check the status shown below.',
        icon: 'utility:error',
        theme: 'invalid'
    },
    notfound: {
        key: 'notfound',
        headline: 'No match',
        detail: 'No passport in the register matches that number. Check the number and try again.',
        icon: 'utility:search',
        theme: 'unknown'
    }
};

const INVALID_STATUSES = ['Cancelled', 'Lost', 'Surrendered', 'Reissued'];

export default class PskPassportValidator extends NavigationMixin(LightningElement) {
    inputValue = '';
    searchTerm;
    variables;
    passport;
    error;
    hasSearched = false;
    isLoading = false;

    @wire(graphql, {
        query: gql`
            query pskValidatePassport($passportNumber: String) {
                uiapi {
                    query {
                        Passport__c(where: { Name: { eq: $passportNumber } }, first: 5) {
                            edges {
                                node {
                                    Id
                                    Name {
                                        value
                                    }
                                    Holder_Name__c {
                                        value
                                    }
                                    Status__c {
                                        value
                                    }
                                    Date_of_Issue__c {
                                        value
                                    }
                                    Date_of_Expiry__c {
                                        value
                                    }
                                    Days_To_Expiry__c {
                                        value
                                    }
                                    Is_Expired__c {
                                        value
                                    }
                                    Is_Expiring_Soon__c {
                                        value
                                    }
                                    Passport_Category__c {
                                        value
                                    }
                                    Place_of_Issue__c {
                                        value
                                    }
                                    ECR_Status__c {
                                        value
                                    }
                                    Citizen__c {
                                        value
                                    }
                                }
                            }
                        }
                    }
                }
            }
        `,
        variables: '$variables'
    })
    wiredSearch(result) {
        const { data, errors } = result;
        if (data) {
            const edges = data?.uiapi?.query?.Passport__c?.edges;
            const node = Array.isArray(edges) && edges.length > 0 ? edges[0].node : null;
            this.passport = node || undefined;
            this.error = undefined;
            this.isLoading = false;
        } else if (errors) {
            this.passport = undefined;
            this.error = this.reduceErrors(errors);
            this.isLoading = false;
        }
    }

    // ---------- verdict ----------

    get status() {
        return val(this.passport?.Status__c);
    }

    get isExpired() {
        const flag = val(this.passport?.Is_Expired__c);
        if (flag !== null) {
            return !!flag;
        }
        const days = this.daysToExpiry;
        return days !== null && days <= 0;
    }

    get isExpiringSoon() {
        const flag = val(this.passport?.Is_Expiring_Soon__c);
        if (flag !== null) {
            return !!flag;
        }
        const days = this.daysToExpiry;
        return days !== null && days > 0 && days <= 180;
    }

    get verdict() {
        if (!this.hasSearched || this.isLoading || this.error) {
            return null;
        }
        if (!this.passport) {
            return VERDICT.notfound;
        }
        if (this.isExpired) {
            return VERDICT.expired;
        }
        if (INVALID_STATUSES.includes(this.status)) {
            return VERDICT.invalid;
        }
        if (this.isExpiringSoon) {
            return VERDICT.expiring;
        }
        if (this.status === 'Active') {
            return VERDICT.valid;
        }
        return VERDICT.invalid;
    }

    get hasVerdict() {
        return !!this.verdict;
    }

    get verdictClass() {
        return `psk-verdict psk-verdict--${this.verdict?.theme || 'unknown'}`;
    }

    get verdictHeadline() {
        return this.verdict?.headline || '';
    }

    get verdictDetail() {
        return this.verdict?.detail || '';
    }

    get verdictIcon() {
        return this.verdict?.icon || 'utility:info';
    }

    // ---------- holder details ----------

    get hasPassport() {
        return !!this.passport;
    }

    get passportNumber() {
        return val(this.passport?.Name) || this.searchTerm || '—';
    }

    get holderName() {
        return val(this.passport?.Holder_Name__c) || 'Not recorded';
    }

    get statusLabel() {
        return this.status || 'Unknown';
    }

    get dateOfIssue() {
        return val(this.passport?.Date_of_Issue__c);
    }

    get dateOfExpiry() {
        return val(this.passport?.Date_of_Expiry__c);
    }

    get daysToExpiry() {
        const raw = val(this.passport?.Days_To_Expiry__c);
        if (raw === null) {
            return null;
        }
        const parsed = Number(raw);
        return Number.isFinite(parsed) ? parsed : null;
    }

    get daysLabel() {
        const days = this.daysToExpiry;
        if (days === null) {
            return '—';
        }
        return days <= 0 ? `${Math.abs(days)} days overdue` : `${days} days remaining`;
    }

    get category() {
        return val(this.passport?.Passport_Category__c) || '—';
    }

    get placeOfIssue() {
        return val(this.passport?.Place_of_Issue__c) || '—';
    }

    get ecrStatus() {
        return val(this.passport?.ECR_Status__c) || '—';
    }

    get passportRecordId() {
        return this.passport?.Id;
    }

    get citizenId() {
        return val(this.passport?.Citizen__c);
    }

    // ---------- states ----------

    get hasError() {
        return !!this.error;
    }

    get showIdlePrompt() {
        return !this.hasSearched && !this.isLoading;
    }

    get searchDisabled() {
        return this.isLoading || !this.inputValue || this.inputValue.trim().length === 0;
    }

    handleInput(event) {
        this.inputValue = event.target.value || '';
    }

    handleKeyup(event) {
        if (event.key === 'Enter') {
            this.handleSearch();
        }
    }

    handleSearch() {
        const term = (this.inputValue || '').trim().toUpperCase();
        if (!term) {
            return;
        }
        this.searchTerm = term;
        this.passport = undefined;
        this.error = undefined;
        this.hasSearched = true;
        this.isLoading = true;
        this.variables = { passportNumber: term };
    }

    handleClear() {
        this.inputValue = '';
        this.searchTerm = undefined;
        this.variables = undefined;
        this.passport = undefined;
        this.error = undefined;
        this.hasSearched = false;
        this.isLoading = false;
        const input = this.template.querySelector('lightning-input');
        if (input) {
            input.focus();
        }
    }

    handleOpenPassport() {
        if (!this.passportRecordId) {
            return;
        }
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: { recordId: this.passportRecordId, objectApiName: 'Passport__c', actionName: 'view' }
        });
    }

    handleOpenCitizen() {
        if (!this.citizenId) {
            return;
        }
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: { recordId: this.citizenId, objectApiName: 'Citizen__c', actionName: 'view' }
        });
    }

    reduceErrors(errors) {
        const list = Array.isArray(errors) ? errors : [errors];
        const messages = list.map((item) => item?.message || item?.body?.message).filter(Boolean);
        return messages.length ? messages.join(' ') : 'The passport register could not be reached.';
    }
}
