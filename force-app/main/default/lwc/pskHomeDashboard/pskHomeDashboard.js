import { LightningElement, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { refreshApex } from '@salesforce/apex';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getHomeStats from '@salesforce/apex/PSK_HomeController.getHomeStats';
import getRecentApplications from '@salesforce/apex/PSK_HomeController.getRecentApplications';
import getRecordTypeOptions from '@salesforce/apex/PSK_HomeController.getRecordTypeOptions';
import PASSPORT_APPLICATION_OBJECT from '@salesforce/schema/Passport_Application__c';
import FIRST_NAME_FIELD from '@salesforce/schema/Passport_Application__c.First_Name__c';
import LAST_NAME_FIELD from '@salesforce/schema/Passport_Application__c.Last_Name__c';
import MOBILE_FIELD from '@salesforce/schema/Passport_Application__c.Mobile__c';
import PASSPORT_CATEGORY_FIELD from '@salesforce/schema/Passport_Application__c.Passport_Category__c';
import TATKAL_FIELD from '@salesforce/schema/Passport_Application__c.Tatkal__c';

const RECENT_COLUMNS = [
    { label: 'ARN', fieldName: 'arnUrl', type: 'url', typeAttributes: { label: { fieldName: 'arn' }, target: '_self' } },
    { label: 'Applicant', fieldName: 'applicantName' },
    { label: 'Status', fieldName: 'Status__c' },
    { label: 'Category', fieldName: 'Passport_Category__c' },
    { label: 'Payment', fieldName: 'Payment_Status__c' },
    { label: 'Risk Score', fieldName: 'Risk_Score__c', type: 'number', cellAttributes: { alignment: 'left' } },
    { label: 'Tatkal', fieldName: 'Tatkal__c', type: 'boolean' }
];

const DONUT_COLORS = ['#1a2a5e', '#c9a227', '#4a5f9c', '#8a6d0f', '#7a86ad', '#e4c766', '#2f3f78', '#b23b3b', '#5a6488', '#0f1733'];

export default class PskHomeDashboard extends NavigationMixin(LightningElement) {
    columns = RECENT_COLUMNS;
    objectApiName = PASSPORT_APPLICATION_OBJECT;
    firstNameField = FIRST_NAME_FIELD;
    lastNameField = LAST_NAME_FIELD;
    mobileField = MOBILE_FIELD;
    passportCategoryField = PASSPORT_CATEGORY_FIELD;
    tatkalField = TATKAL_FIELD;

    stats;
    recentRows = [];
    error;
    isLoading = true;
    showQuickCreate = false;
    selectedRecordTypeId = null;
    recordTypeOptions = [];

    wiredStatsResult;
    wiredRecentResult;

    @wire(getRecordTypeOptions)
    wiredRecordTypeOptions({ data }) {
        if (data) {
            this.recordTypeOptions = data.map((opt) => ({ label: opt.label, value: opt.value }));
        }
    }

    @wire(getHomeStats, { recordTypeId: '$selectedRecordTypeId' })
    wiredStats(result) {
        this.wiredStatsResult = result;
        const { data, error } = result;
        if (data) {
            this.stats = data;
            this.error = undefined;
            this.isLoading = false;
        } else if (error) {
            this.error = this.reduceError(error);
            this.isLoading = false;
        }
    }

    @wire(getRecentApplications, { recordLimit: 8, recordTypeId: '$selectedRecordTypeId' })
    wiredRecent(result) {
        this.wiredRecentResult = result;
        const { data, error } = result;
        if (data) {
            this.recentRows = data.map((app) => ({
                ...app,
                arn: app.Name,
                arnUrl: `/lightning/r/Passport_Application__c/${app.Id}/view`,
                applicantName: [app.First_Name__c, app.Last_Name__c].filter(Boolean).join(' ')
            }));
        } else if (error) {
            this.error = this.reduceError(error);
        }
    }

    get sortedStatusBreakdown() {
        if (!this.stats || !this.stats.statusBreakdown) {
            return [];
        }
        return this.stats.statusBreakdown.slice().sort((a, b) => b.count - a.count);
    }

    get statusLegend() {
        const total = this.sortedStatusBreakdown.reduce((sum, s) => sum + s.count, 0);
        return this.sortedStatusBreakdown.map((s, index) => ({
            key: s.status,
            status: s.status,
            count: s.count,
            pct: total ? Math.round((s.count / total) * 100) : 0,
            swatchStyle: `background-color: ${DONUT_COLORS[index % DONUT_COLORS.length]}`
        }));
    }

    get hasStatusData() {
        return this.statusLegend.length > 0;
    }

    get donutStyle() {
        const total = this.sortedStatusBreakdown.reduce((sum, s) => sum + s.count, 0);
        if (!total) {
            return 'background: conic-gradient(#eef0f4 0deg 360deg)';
        }
        let cumulative = 0;
        const stops = this.sortedStatusBreakdown.map((s, index) => {
            const start = (cumulative / total) * 360;
            cumulative += s.count;
            const end = (cumulative / total) * 360;
            const color = DONUT_COLORS[index % DONUT_COLORS.length];
            return `${color} ${start}deg ${end}deg`;
        });
        return `background: conic-gradient(${stops.join(', ')})`;
    }

    get hasRecent() {
        return this.recentRows && this.recentRows.length > 0;
    }

    get hasError() {
        return !!this.error;
    }

    get filterCountLabel() {
        if (!this.stats) {
            return '';
        }
        const count = this.stats.totalApplications;
        const scope = this.selectedRecordTypeId
            ? this.recordTypeOptions.find((o) => o.value === this.selectedRecordTypeId)?.label
            : 'all record types';
        return `${count} application${count === 1 ? '' : 's'} · ${scope}`;
    }

    handleRecordTypeChange(event) {
        this.selectedRecordTypeId = event.detail.value || null;
    }

    handleRefresh() {
        this.isLoading = true;
        Promise.all([refreshApex(this.wiredStatsResult), refreshApex(this.wiredRecentResult)]).finally(() => {
            this.isLoading = false;
        });
    }

    handleNewApplication() {
        this[NavigationMixin.Navigate]({
            type: 'standard__objectPage',
            attributes: {
                objectApiName: 'Passport_Application__c',
                actionName: 'new'
            }
        });
    }

    handleToggleQuickCreate() {
        this.showQuickCreate = !this.showQuickCreate;
    }

    handleQuickCreateSuccess(event) {
        this.showQuickCreate = false;
        this.dispatchEvent(
            new ShowToastEvent({
                title: 'Application created',
                message: 'Draft application created successfully.',
                variant: 'success'
            })
        );
        this.handleRefresh();
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId: event.detail.id,
                objectApiName: 'Passport_Application__c',
                actionName: 'view'
            }
        });
    }

    handleQuickCreateCancel() {
        this.showQuickCreate = false;
    }

    handleViewAll() {
        this[NavigationMixin.Navigate]({
            type: 'standard__objectPage',
            attributes: {
                objectApiName: 'Passport_Application__c',
                actionName: 'list'
            }
        });
    }

    reduceError(error) {
        if (error && error.body && error.body.message) {
            return error.body.message;
        }
        return 'An unknown error occurred while loading the dashboard.';
    }
}
