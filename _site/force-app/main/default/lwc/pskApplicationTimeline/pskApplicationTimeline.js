import { LightningElement, api } from 'lwc';
import getTimeline from '@salesforce/apex/PSK_ApplicationTimelineController.getTimeline';

/** Fallback icon/theme per event type. Keys are matched case-insensitively. */
const TYPE_STYLE = {
    appointment: { icon: 'standard:event', theme: 'navy' },
    payment: { icon: 'standard:currency', theme: 'gold' },
    document: { icon: 'standard:document', theme: 'navy' },
    police: { icon: 'standard:user_role', theme: 'navy' },
    policeverification: { icon: 'standard:user_role', theme: 'navy' },
    objection: { icon: 'standard:case', theme: 'danger' },
    notification: { icon: 'standard:email', theme: 'muted' },
    print: { icon: 'standard:print_queue', theme: 'gold' },
    printjob: { icon: 'standard:print_queue', theme: 'gold' },
    dispatch: { icon: 'standard:delivery_installation', theme: 'gold' },
    riskflag: { icon: 'standard:first_non_empty', theme: 'danger' },
    status: { icon: 'standard:flow', theme: 'navy' },
    passport: { icon: 'standard:record', theme: 'navy' }
};

const DEFAULT_STYLE = { icon: 'standard:default', theme: 'muted' };

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

function toList(data) {
    if (Array.isArray(data)) {
        return data;
    }
    const nested = pick(data, ['events', 'items', 'timeline', 'entries'], null);
    return Array.isArray(nested) ? nested : [];
}

function styleForType(type) {
    if (!type) {
        return DEFAULT_STYLE;
    }
    const key = String(type).toLowerCase().replace(/[^a-z]/g, '');
    return TYPE_STYLE[key] || DEFAULT_STYLE;
}

export default class PskApplicationTimeline extends LightningElement {
    @api recordId;

    events = [];
    error;
    hasLoaded = false;
    newestFirst = true;
    selectedType = 'all';

    connectedCallback() {
        this.loadTimeline();
    }

    async loadTimeline() {
        try {
            const data = await getTimeline({ applicationId: this.recordId });
            this.events = toList(data);
            this.error = undefined;
        } catch (error) {
            this.events = [];
            this.error = this.reduceError(error);
        } finally {
            this.hasLoaded = true;
        }
    }

    get normalisedEvents() {
        return (this.events || []).map((event, index) => {
            const type = pick(event, ['type', 'eventType', 'category', 'objectType'], 'Event');
            const style = styleForType(type);
            const timestamp = pick(event, ['timestamp', 'when', 'eventDate', 'dateTime', 'occurredAt', 'date'], null);
            const parsed = timestamp ? new Date(timestamp).getTime() : NaN;
            return {
                key: `${pick(event, ['id', 'Id', 'recordId'], index)}-${index}`,
                type,
                typeKey: String(type).toLowerCase(),
                icon: pick(event, ['icon', 'iconName'], style.icon),
                title: pick(event, ['title', 'label', 'headline', 'name', 'Name'], String(type)),
                subtitle: pick(event, ['subtitle', 'description', 'detail', 'body'], ''),
                timestamp,
                sortValue: Number.isNaN(parsed) ? 0 : parsed,
                markerClass: `psk-tl__marker psk-tl__marker--${style.theme}`
            };
        });
    }

    get typeOptions() {
        const seen = new Map();
        this.normalisedEvents.forEach((event) => {
            if (!seen.has(event.typeKey)) {
                seen.set(event.typeKey, event.type);
            }
        });
        const options = [{ label: 'All activity', value: 'all' }];
        [...seen.entries()].forEach(([value, label]) => options.push({ label, value }));
        return options;
    }

    get visibleEvents() {
        let list = this.normalisedEvents;
        if (this.selectedType !== 'all') {
            list = list.filter((event) => event.typeKey === this.selectedType);
        }
        const sorted = [...list].sort((a, b) => a.sortValue - b.sortValue);
        if (this.newestFirst) {
            sorted.reverse();
        }
        return sorted;
    }

    get hasEvents() {
        return this.visibleEvents.length > 0;
    }

    get isLoading() {
        return !this.hasLoaded;
    }

    get hasError() {
        return !!this.error;
    }

    get isEmpty() {
        return this.hasLoaded && !this.hasError && this.normalisedEvents.length === 0;
    }

    get isFilteredEmpty() {
        return this.hasLoaded && !this.hasError && this.normalisedEvents.length > 0 && !this.hasEvents;
    }

    get sortLabel() {
        return this.newestFirst ? 'Newest first' : 'Oldest first';
    }

    get sortIcon() {
        return this.newestFirst ? 'utility:arrowdown' : 'utility:arrowup';
    }

    get countLabel() {
        const count = this.visibleEvents.length;
        return `${count} event${count === 1 ? '' : 's'}`;
    }

    handleTypeChange(event) {
        this.selectedType = event.detail.value;
    }

    handleToggleSort() {
        this.newestFirst = !this.newestFirst;
    }

    handleRefresh() {
        this.hasLoaded = false;
        this.loadTimeline();
    }

    reduceError(error) {
        if (error?.body?.message) {
            return error.body.message;
        }
        if (Array.isArray(error?.body) && error.body[0]?.message) {
            return error.body[0].message;
        }
        return 'Unable to load the application timeline.';
    }
}
