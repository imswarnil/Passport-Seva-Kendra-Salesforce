import { LightningElement, wire } from 'lwc';
import getRecordTypeSummary from '@salesforce/apex/PSK_HomeController.getRecordTypeSummary';

export default class PskHomeSidebarSummary extends LightningElement {
    summary = [];
    error;
    showCounts = true;

    @wire(getRecordTypeSummary)
    wiredSummary({ data, error }) {
        if (data) {
            this.summary = data;
            this.error = undefined;
        } else if (error) {
            this.error = error?.body?.message || 'Unable to load record type summary.';
        }
    }

    get total() {
        return this.summary.reduce((sum, s) => sum + s.count, 0);
    }

    get rows() {
        const total = this.total;
        return this.summary.map((s) => ({
            key: s.status,
            label: s.status,
            display: this.showCounts ? String(s.count) : `${total ? Math.round((s.count / total) * 100) : 0}%`
        }));
    }

    get hasRows() {
        return this.rows.length > 0;
    }

    get hasError() {
        return !!this.error;
    }

    get toggleLabel() {
        return this.showCounts ? 'Showing counts' : 'Showing percentages';
    }

    handleToggle(event) {
        this.showCounts = event.target.checked;
    }
}
