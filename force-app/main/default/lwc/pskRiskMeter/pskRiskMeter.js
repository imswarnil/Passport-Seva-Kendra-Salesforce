import { LightningElement, api } from 'lwc';

export default class PskRiskMeter extends LightningElement {
    @api score;

    get hasScore() {
        return this.score !== null && this.score !== undefined;
    }

    get clampedScore() {
        return Math.min(Math.max(this.score || 0, 0), 100);
    }

    get fillStyle() {
        return `width: ${this.clampedScore}%`;
    }

    get band() {
        if (this.clampedScore >= 70) {
            return 'High';
        }
        if (this.clampedScore >= 35) {
            return 'Medium';
        }
        return 'Low';
    }

    get bandClass() {
        return `psk-risk-meter__fill psk-risk-meter__fill--${this.band.toLowerCase()}`;
    }
}
