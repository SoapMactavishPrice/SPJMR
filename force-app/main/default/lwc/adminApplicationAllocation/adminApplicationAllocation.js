import { LightningElement, api, track } from 'lwc';

import getApplicationsPage
    from '@salesforce/apex/ApplicationAllocationLwcController.getApplicationsPage';
import getApplicationsCount
    from '@salesforce/apex/ApplicationAllocationLwcController.getApplicationsCount';

import getAssignedApplicationsPage
    from '@salesforce/apex/ApplicationAllocationLwcController.getAssignedApplicationsPage';
import getAssignedApplicationsCount
    from '@salesforce/apex/ApplicationAllocationLwcController.getAssignedApplicationsCount';

import getVerifiersPage
    from '@salesforce/apex/ApplicationAllocationLwcController.getVerifiersPage';

import reassign
    from '@salesforce/apex/ApplicationAllocationLwcController.reassign';

import { ShowToastEvent } from 'lightning/platformShowToastEvent';

export default class AdminApplicationAllocation extends LightningElement {

    @api recordId;          // Program Id
    @track isLoading = false;

    /* ---------------- MODE SWITCH ---------------- */

    mode = 'allocate';      // allocate | reassign

    get isAllocate() { return this.mode === 'allocate'; }
    get isReassign() { return this.mode === 'reassign'; }

    modeOptions = [
        { label: 'Allocate',  value: 'allocate'  },
        { label: 'Reassign', value: 'reassign' }
    ];

    handleModeChange(event) {
        this.mode = event.detail.value;
        this.resetPagination();
        this.loadAll();
    }

    /* ---------------- PAGE SIZE ---------------- */

    pageSize = 10;

    pageSizeOptions = [
        { label: '10', value: '10' },
        { label: '20', value: '20' },
        { label: '30', value: '30' },
        { label: '50', value: '50' }
    ];

    get pageSizeString() {
        return String(this.pageSize);
    }

    handlePageSizeChange(event) {
        this.pageSize = parseInt(event.detail.value, 10);
        this.resetPagination();
        this.loadAll();
    }

    /* ---------------- ALLOCATE – APPLICATIONS ---------------- */

    @track allocateApplications = [];
    allocateAppsPageNumber = 1;
    allocateAppsTotalPages = 1;
    allocateAppsTotal = 0;
    allocateAllAppsSelected = false;

    get isAllocateAppsPrevDisabled() {
        return this.allocateAppsPageNumber <= 1;
    }

    get isAllocateAppsNextDisabled() {
        return this.allocateAppsPageNumber >= this.allocateAppsTotalPages;
    }

    async loadAllocateApplications() {
        this.isLoading = true;
        try {
            const total = await getApplicationsCount({ programId: this.recordId });
            this.allocateAppsTotal = total;
            this.allocateAppsTotalPages = Math.max(1, Math.ceil(total / this.pageSize));

            const data = await getApplicationsPage({
                programId: this.recordId,
                pageNumber: this.allocateAppsPageNumber,
                pageSize: this.pageSize
            });

            this.allocateApplications = (data || []).map(a => ({
                ...a,
                isSelected: false
            }));
        } catch (e) {
            this.showError(e);
        } finally {
            this.isLoading = false;
        }
    }

    handleAllocateAppSelectAll(event) {
        const checked = event.target.checked;
        this.allocateAllAppsSelected = checked;
        this.allocateApplications = this.allocateApplications.map(a => ({
            ...a,
            isSelected: checked
        }));
    }

    handleAllocateAppCheckbox(event) {
        const id = event.target.dataset.id;
        const checked = event.target.checked;

        this.allocateApplications = this.allocateApplications.map(a =>
            a.appId === id ? { ...a, isSelected: checked } : a
        );
    }

    handleAllocateAppPrev() {
        if (this.allocateAppsPageNumber > 1) {
            this.allocateAppsPageNumber--;
            this.loadAllocateApplications();
        }
    }

    handleAllocateAppNext() {
        if (this.allocateAppsPageNumber < this.allocateAppsTotalPages) {
            this.allocateAppsPageNumber++;
            this.loadAllocateApplications();
        }
    }

    /* ---------------- REASSIGN – VERIFIERS + APPLICATIONS ---------------- */

    @track reassignVerifiers = [];
    @track reassignApplications = [];

    reassignFromPageNumber = 1;       // (not paged in UI, but ready if needed)
    reassignAppsPageNumber = 1;
    reassignAppsTotalPages = 1;
    reassignAppsTotal = 0;
    reassignAllAppsSelected = false;

    get isReassignAppsPrevDisabled() {
        return this.reassignAppsPageNumber <= 1;
    }

    get isReassignAppsNextDisabled() {
        return this.reassignAppsPageNumber >= this.reassignAppsTotalPages;
    }

    async loadReassignVerifiers() {
        try {
            const data = await getVerifiersPage({
                programId: this.recordId,
                pageNumber: this.reassignFromPageNumber,
                pageSize: 200  // plenty, no UI pagination for verifiers now
            });

            this.reassignVerifiers = (data || []).map(v => ({
                ...v,
                isFromSelected: false
            }));
        } catch (e) {
            this.showError(e);
        }
    }

    handleReassignFromCheckbox(event) {
        const id = event.target.dataset.id;
        const checked = event.target.checked;

        this.reassignVerifiers = this.reassignVerifiers.map(v =>
            v.ptmId === id ? { ...v, isFromSelected: checked } : v
        );

        // whenever from-verifiers change, reload apps
        this.reassignAppsPageNumber = 1;
        this.loadReassignApplications();
    }

    async loadReassignApplications() {
        const fromIds = this.reassignVerifiers
            .filter(v => v.isFromSelected)
            .map(v => v.ptmId);

        // if no verifiers selected, clear table
        if (!fromIds || fromIds.length === 0) {
            this.reassignApplications = [];
            this.reassignAppsTotal = 0;
            this.reassignAppsTotalPages = 1;
            return;
        }

        this.isLoading = true;
        try {
            const total = await getAssignedApplicationsCount({
                programId: this.recordId,
                fromVerifierPtmIds: fromIds
            });

            this.reassignAppsTotal = total;
            this.reassignAppsTotalPages = Math.max(1, Math.ceil(total / this.pageSize));

            const data = await getAssignedApplicationsPage({
                programId: this.recordId,
                fromVerifierPtmIds: fromIds,
                pageNumber: this.reassignAppsPageNumber,
                pageSize: this.pageSize
            });

            this.reassignApplications = (data || []).map(a => ({
                ...a,
                isSelected: false
            }));
        } catch (e) {
            this.showError(e);
        } finally {
            this.isLoading = false;
        }
    }

    handleReassignAppSelectAll(event) {
        const checked = event.target.checked;
        this.reassignAllAppsSelected = checked;

        this.reassignApplications = this.reassignApplications.map(a => ({
            ...a,
            isSelected: checked
        }));
    }

    handleReassignAppCheckbox(event) {
        const id = event.target.dataset.id;
        const checked = event.target.checked;

        this.reassignApplications = this.reassignApplications.map(a =>
            a.currentVerificationId === id ? { ...a, isSelected: checked } : a
        );
    }

    handleReassignAppPrev() {
        if (this.reassignAppsPageNumber > 1) {
            this.reassignAppsPageNumber--;
            this.loadReassignApplications();
        }
    }

    handleReassignAppNext() {
        if (this.reassignAppsPageNumber < this.reassignAppsTotalPages) {
            this.reassignAppsPageNumber++;
            this.loadReassignApplications();
        }
    }

    /* ---------------- REASSIGN – ACTION ---------------- */

    get isReassignButtonDisabled() {
        return !this.reassignApplications.some(a => a.isSelected);
    }

    async handleReassign() {
        const selectedVerificationIds = this.reassignApplications
            .filter(a => a.isSelected)
            .map(a => a.currentVerificationId);

        // NOTE: You still need TO-verifier selection somewhere in UI
        // for now we just stop if none selected
        const toVerifierIds = []; // TODO: plug your "To" verifier selection here

        if (!selectedVerificationIds.length || !toVerifierIds.length) {
            this.showErrorMessage('Please select at least one application and one target verifier.');
            return;
        }

        this.isLoading = true;
        try {
            await reassign({
                programId: this.recordId,
                applicationVerificationIds: selectedVerificationIds,
                toVerifierPtmIds: toVerifierIds
            });

            this.showSuccess('Reassignment completed');
            // refresh apps after reassign
            this.loadReassignApplications();
        } catch (e) {
            this.showError(e);
        } finally {
            this.isLoading = false;
        }
    }

    /* ---------------- COMMON LOAD + RESET ---------------- */

    connectedCallback() {
        this.loadAll();
    }

    loadAll() {
        if (this.isAllocate) {
            this.loadAllocateApplications();
        }
        if (this.isReassign) {
            this.loadReassignVerifiers();
            this.loadReassignApplications();
        }
    }

    resetPagination() {
        this.allocateAppsPageNumber = 1;
        this.reassignAppsPageNumber = 1;
    }

    /* ---------------- TOAST HELPERS ---------------- */

    showSuccess(message) {
        this.dispatchEvent(new ShowToastEvent({
            title: 'Success',
            message,
            variant: 'success'
        }));
    }

    showError(error) {
        const message = error && error.body && error.body.message
            ? error.body.message
            : (error && error.message) || 'Unknown error';
        this.showErrorMessage(message);
    }

    showErrorMessage(message) {
        this.dispatchEvent(new ShowToastEvent({
            title: 'Error',
            message,
            variant: 'error'
        }));
    }
}