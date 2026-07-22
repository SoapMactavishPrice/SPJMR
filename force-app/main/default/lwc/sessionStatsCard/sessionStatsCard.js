import { LightningElement, api, wire } from 'lwc';
import getSessionStats from '@salesforce/apex/SessionStatsService.getSessionStats';
import getSessionsByStatus from '@salesforce/apex/SessionStatsService.getSessionsByStatus';

export default class SessionStatsCard extends LightningElement {
    @api recordId;
    stats = {};
    details = [];
    isLoadingDetails = false;
    isModalOpen = false;
    selectedStatusLabel = '';

    @wire(getSessionStats, { recordId: '$recordId' })
    wiredStats({ data, error }) {
        if (data) {
            this.stats = data;
        }
    }

    /** When true (AcademicTerm not complete), show termCompletionMessage instead of stats grid. */
    get showTermCompletionMessage() {
        return this.stats && this.stats.termCompletionMessage && String(this.stats.termCompletionMessage).trim() !== '';
    }

    get hasDetails() {
        return Array.isArray(this.details) && this.details.length > 0;
    }

    get detailsTitle() {
        return this.selectedStatusLabel ? `${this.selectedStatusLabel} Sessions` : 'Session Details';
    }

    async handleTileClick(event) {
        const status = event.currentTarget?.dataset?.status;
        const label = event.currentTarget?.dataset?.label;
        if (!status || !this.recordId) {
            return;
        }
        this.selectedStatusLabel = label || status;
        this.isModalOpen = true;
        this.isLoadingDetails = true;
        try {
            const rows = await getSessionsByStatus({
                recordId: this.recordId,
                statusKey: status
            });
            const list = rows || [];
            this.details = list.map((r) => {
                const id = r && r.sessionId ? String(r.sessionId) : '';
                return {
                    ...r,
                    sessionRecordUrl: id ? `/lightning/r/Session__c/${id}/view` : null
                };
            });
        } catch (e) {
            this.details = [];
        } finally {
            this.isLoadingDetails = false;
        }
    }

    handleCloseModal() {
        this.isModalOpen = false;
    }
}