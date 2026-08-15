import { LightningElement, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { gql, graphql, refreshGraphQL } from 'lightning/uiGraphQLApi';

const PRINT_COLUMNS = ['Queued', 'Printing', 'Quality Check', 'Printed', 'Failed', 'Reprint Required'];
const DISPATCH_COLUMNS = [
    'Pending',
    'Packed',
    'In Transit',
    'Out for Delivery',
    'Delivered',
    'Returned',
    'Lost in Transit'
];

const NEGATIVE_STATUSES = ['Failed', 'Reprint Required', 'Returned', 'Lost in Transit'];
const DONE_STATUSES = ['Printed', 'Delivered'];

/** Unwraps the { value } envelope the UI API GraphQL layer puts around scalars. */
function val(field) {
    if (field === null || field === undefined) {
        return null;
    }
    return typeof field === 'object' && 'value' in field ? field.value : field;
}

function edgesOf(collection) {
    const edges = collection?.edges;
    return Array.isArray(edges) ? edges.filter((edge) => !!edge?.node) : [];
}

function columnTheme(status) {
    if (NEGATIVE_STATUSES.includes(status)) {
        return 'danger';
    }
    if (DONE_STATUSES.includes(status)) {
        return 'success';
    }
    return 'navy';
}

export default class PskFulfilmentBoard extends NavigationMixin(LightningElement) {
    printJobs = [];
    dispatches = [];
    error;
    hasLoaded = false;
    activeLane = 'print';

    graphqlResult;

    @wire(graphql, {
        query: gql`
            query pskFulfilmentBoard {
                uiapi {
                    query {
                        Print_Job__c(first: 200) {
                            edges {
                                node {
                                    Id
                                    Name {
                                        value
                                    }
                                    Status__c {
                                        value
                                    }
                                    ARN__c {
                                        value
                                    }
                                    Batch_Number__c {
                                        value
                                    }
                                    Print_Facility__c {
                                        value
                                    }
                                    Attempt_Number__c {
                                        value
                                    }
                                    Queued_Date__c {
                                        value
                                    }
                                }
                            }
                        }
                        Dispatch__c(first: 200) {
                            edges {
                                node {
                                    Id
                                    Name {
                                        value
                                    }
                                    Status__c {
                                        value
                                    }
                                    ARN__c {
                                        value
                                    }
                                    Courier_Partner__c {
                                        value
                                    }
                                    Tracking_Number__c {
                                        value
                                    }
                                    Expected_Delivery_Date__c {
                                        value
                                    }
                                    Dispatched_Date__c {
                                        value
                                    }
                                }
                            }
                        }
                    }
                }
            }
        `
    })
    wiredBoard(result) {
        this.graphqlResult = result;
        const { data, errors } = result;
        if (data) {
            const query = data?.uiapi?.query;
            this.printJobs = edgesOf(query?.Print_Job__c).map((edge) => edge.node);
            this.dispatches = edgesOf(query?.Dispatch__c).map((edge) => edge.node);
            this.error = undefined;
            this.hasLoaded = true;
        } else if (errors) {
            this.printJobs = [];
            this.dispatches = [];
            this.error = this.reduceErrors(errors);
            this.hasLoaded = true;
        }
    }

    // ---------- lanes ----------

    buildLane(statuses, records, cardBuilder) {
        const byStatus = new Map(statuses.map((status) => [status, []]));
        records.forEach((record) => {
            const status = val(record.Status__c) || 'Unassigned';
            if (!byStatus.has(status)) {
                byStatus.set(status, []);
            }
            byStatus.get(status).push(cardBuilder(record));
        });
        return [...byStatus.entries()].map(([status, cards]) => ({
            key: status,
            status,
            count: cards.length,
            cards,
            hasCards: cards.length > 0,
            headerClass: `psk-col__head psk-col__head--${columnTheme(status)}`
        }));
    }

    get printLane() {
        return this.buildLane(PRINT_COLUMNS, this.printJobs, (record) => ({
            key: record.Id,
            id: record.Id,
            objectApiName: 'Print_Job__c',
            title: val(record.Name) || 'Print job',
            arn: val(record.ARN__c),
            line1: val(record.Print_Facility__c),
            line2: val(record.Batch_Number__c) ? `Batch ${val(record.Batch_Number__c)}` : null,
            attempt: val(record.Attempt_Number__c),
            timestamp: val(record.Queued_Date__c)
        }));
    }

    get dispatchLane() {
        return this.buildLane(DISPATCH_COLUMNS, this.dispatches, (record) => ({
            key: record.Id,
            id: record.Id,
            objectApiName: 'Dispatch__c',
            title: val(record.Name) || 'Dispatch',
            arn: val(record.ARN__c),
            line1: val(record.Courier_Partner__c),
            line2: val(record.Tracking_Number__c),
            attempt: null,
            timestamp: val(record.Dispatched_Date__c) || val(record.Expected_Delivery_Date__c)
        }));
    }

    get activeColumns() {
        return this.activeLane === 'print' ? this.printLane : this.dispatchLane;
    }

    get printCount() {
        return this.printJobs.length;
    }

    get dispatchCount() {
        return this.dispatches.length;
    }

    get printTabClass() {
        return this.activeLane === 'print' ? 'psk-lane-tab psk-lane-tab--active' : 'psk-lane-tab';
    }

    get dispatchTabClass() {
        return this.activeLane === 'dispatch' ? 'psk-lane-tab psk-lane-tab--active' : 'psk-lane-tab';
    }

    get printTabSelected() {
        return this.activeLane === 'print' ? 'true' : 'false';
    }

    get dispatchTabSelected() {
        return this.activeLane === 'dispatch' ? 'true' : 'false';
    }

    get printTabLabel() {
        return `Printing (${this.printCount})`;
    }

    get dispatchTabLabel() {
        return `Dispatch (${this.dispatchCount})`;
    }

    // ---------- states ----------

    get isLoading() {
        return !this.hasLoaded;
    }

    get hasError() {
        return !!this.error;
    }

    get isEmpty() {
        return this.hasLoaded && !this.hasError && this.printCount === 0 && this.dispatchCount === 0;
    }

    get showBoard() {
        return this.hasLoaded && !this.hasError && !this.isEmpty;
    }

    handleSelectLane(event) {
        this.activeLane = event.currentTarget.dataset.lane;
    }

    handleLaneKeydown(event) {
        if (event.key === 'ArrowLeft' || event.key === 'ArrowRight') {
            event.preventDefault();
            this.activeLane = this.activeLane === 'print' ? 'dispatch' : 'print';
        }
    }

    handleRefresh() {
        if (this.graphqlResult) {
            refreshGraphQL(this.graphqlResult);
        }
    }

    handleOpen(event) {
        const { id, object } = event.currentTarget.dataset;
        if (!id) {
            return;
        }
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: { recordId: id, objectApiName: object, actionName: 'view' }
        });
    }

    reduceErrors(errors) {
        const list = Array.isArray(errors) ? errors : [errors];
        const messages = list
            .map((item) => item?.message || item?.body?.message)
            .filter(Boolean);
        return messages.length ? messages.join(' ') : 'Unable to load the fulfilment board.';
    }
}
