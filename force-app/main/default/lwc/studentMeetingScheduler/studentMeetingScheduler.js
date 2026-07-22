import { LightningElement, track, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { refreshApex } from '@salesforce/apex';
import getInvitableParticipants from '@salesforce/apex/StudentMeetingController.getInvitableParticipants';
import scheduleMeeting from '@salesforce/apex/StudentMeetingController.scheduleMeeting';
import cancelMeeting from '@salesforce/apex/StudentMeetingController.cancelMeeting';
import getMyMeetings from '@salesforce/apex/StudentMeetingController.getMyMeetings';

const MY_MEETING_COLUMNS = [
    { label: 'Title', fieldName: 'subject', type: 'text' },
    { label: 'Start', fieldName: 'startTime', type: 'date', typeAttributes: { year: 'numeric', month: 'short', day: '2-digit', hour: '2-digit', minute: '2-digit' } },
    { label: 'Invitees', fieldName: 'attendeeEmails', type: 'text', wrapText: true },
    { label: 'Status', fieldName: 'meetingStatus', type: 'text' },
    { label: 'Sync', fieldName: 'syncStatus', type: 'text' },
    {
        type: 'button',
        typeAttributes: {
            label: 'Cancel',
            name: 'cancel',
            variant: 'destructive-text',
            disabled: { fieldName: 'cancelDisabled' }
        }
    }
];

export default class StudentMeetingScheduler extends LightningElement {
    columns = MY_MEETING_COLUMNS;

    @track subject = '';
    @track startTime;
    @track endTime;
    @track location = '';
    @track meetingLink = '';
    @track description = '';

    @track searchTerm = '';
    @track searchResults = [];
    @track selected = []; // { id, name, role }

    isSaving = false;

    myMeetingsResult;
    @track myMeetings = [];

    /**
     * Loads the current user's scheduled meetings and marks cancelled ones non-cancellable.
     */
    @wire(getMyMeetings)
    wiredMeetings(result) {
        this.myMeetingsResult = result;
        if (result.data) {
            this.myMeetings = result.data.map((m) => ({
                ...m,
                cancelDisabled: m.meetingStatus === 'Cancelled'
            }));
        }
    }

    get selectedIds() {
        return this.selected.map((s) => s.id);
    }

    get canSubmit() {
        return !this.isSaving && this.subject && this.startTime && this.endTime && this.selected.length > 0;
    }

    get canSubmitDisabled() {
        return !this.canSubmit;
    }

    get hasResults() {
        return this.searchResults.length > 0;
    }

    get hasSelected() {
        return this.selected.length > 0;
    }

    handleSubject(e) {
        this.subject = e.target.value;
    }
    handleStart(e) {
        this.startTime = e.target.value;
    }
    handleEnd(e) {
        this.endTime = e.target.value;
    }
    handleLocation(e) {
        this.location = e.target.value;
    }
    handleLink(e) {
        this.meetingLink = e.target.value;
    }
    handleDescription(e) {
        this.description = e.target.value;
    }

    /**
     * Debounced people search; queries only when 2+ characters are typed.
     */
    handleSearch(e) {
        this.searchTerm = e.target.value;
        window.clearTimeout(this.searchDelay);
        const term = this.searchTerm;
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        this.searchDelay = setTimeout(() => this.runSearch(term), 300);
    }

    async runSearch(term) {
        if (!term || term.trim().length < 2) {
            this.searchResults = [];
            return;
        }
        try {
            const rows = await getInvitableParticipants({ searchTerm: term });
            const chosen = new Set(this.selectedIds);
            this.searchResults = rows.filter((r) => !chosen.has(r.id));
        } catch (err) {
            this.toast('Search failed', this.errorText(err), 'error');
        }
    }

    handleAdd(e) {
        const id = e.currentTarget.dataset.id;
        const person = this.searchResults.find((r) => r.id === id);
        if (person) {
            this.selected = [...this.selected, person];
            this.searchResults = this.searchResults.filter((r) => r.id !== id);
        }
    }

    handleRemove(e) {
        const id = e.currentTarget.dataset.id;
        this.selected = this.selected.filter((s) => s.id !== id);
    }

    async handleSchedule() {
        if (!this.canSubmit) {
            return;
        }
        this.isSaving = true;
        const req = {
            subject: this.subject,
            startTime: this.startTime,
            endTime: this.endTime,
            location: this.location,
            meetingLink: this.meetingLink,
            description: this.description,
            attendeeAccountIds: this.selectedIds
        };
        try {
            await scheduleMeeting({ req });
            this.toast('Meeting scheduled', 'Invites are being sent to the selected people.', 'success');
            this.resetForm();
            await refreshApex(this.myMeetingsResult);
        } catch (err) {
            this.toast('Could not schedule', this.errorText(err), 'error');
        } finally {
            this.isSaving = false;
        }
    }

    async handleRowAction(e) {
        if (e.detail.action.name !== 'cancel') {
            return;
        }
        const row = e.detail.row;
        try {
            await cancelMeeting({ meetingId: row.id });
            this.toast('Meeting cancelled', 'Attendees have been notified.', 'success');
            await refreshApex(this.myMeetingsResult);
        } catch (err) {
            this.toast('Could not cancel', this.errorText(err), 'error');
        }
    }

    resetForm() {
        this.subject = '';
        this.startTime = undefined;
        this.endTime = undefined;
        this.location = '';
        this.meetingLink = '';
        this.description = '';
        this.searchTerm = '';
        this.searchResults = [];
        this.selected = [];
    }

    toast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    errorText(err) {
        return err && err.body && err.body.message ? err.body.message : 'Unexpected error';
    }
}