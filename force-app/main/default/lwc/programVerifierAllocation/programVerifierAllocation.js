import { LightningElement, api, track, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

// Apex methods
import loadInit from '@salesforce/apex/ApplicationAllocationLwcController.loadInit';
import getApplicationsPage from '@salesforce/apex/ApplicationAllocationLwcController.getApplicationsPage';
import getApplicationsCount from '@salesforce/apex/ApplicationAllocationLwcController.getApplicationsCount';
import autoAllocate from '@salesforce/apex/ApplicationAllocationLwcController.autoAllocate';
import manualAllocate from '@salesforce/apex/ApplicationAllocationLwcController.manualAllocate';

// reassignment: stage-aware methods (you added these in controller)
import getReassignListPageByStage from '@salesforce/apex/ApplicationAllocationLwcController.getReassignListPageByStage';
import getReassignListCountByStage from '@salesforce/apex/ApplicationAllocationLwcController.getReassignListCountByStage';
import reassignApplicationsByStage from '@salesforce/apex/ApplicationAllocationLwcController.reassignApplicationsByStage';

export default class ProgramVerifierAllocation extends LightningElement {
    @api recordId;

    verificationType = 'Application'; // 'Application' or 'Document'
    verificationTypeOptions = [
        { label: 'Application Verification', value: 'Application' },
        { label: 'Document Verification', value: 'Document' }
    ];

    @track applications = [];
    @track verifiers = [];

    selectedAppIdSet = new Set();
    selectedVerifierIdSet = new Set();

    applicationsPageNumber = 1;
    applicationsPageSize = 10;
    applicationsTotal = 0;

    isLoading = false;

    // Reassign-related (now used for both Application and Document)
    showReassignSection = true;
    reassignVerifierOptions = [];
    selectedCurrentPtm = null;
    selectedToPtm = null;

    assignedApplications = []; // items come from getReassignListPageByStage
    selectedAssignedVerificationIdSet = new Set();
    assignedPageNumber = 1;
    assignedPageSize = 10;
    assignedTotal = 0;

    pageSizeOptions = [
        { label: '5', value: 5 },
        { label: '10', value: 10 },
        { label: '20', value: 20 },
        { label: '50', value: 50 },
    ];

    reassignPageSizeOptions = [
        { label: '5', value: 5 },
        { label: '10', value: 10 },
        { label: '20', value: 20 },
        { label: '50', value: 50 },
    ];

    // Convenient labels for template
    get verificationTypeLabel() {
        return this.verificationType === 'Application' ? 'Application' : 'Document';
    }
    get verificationTypeLabelPlural() {
        return this.verificationType === 'Application' ? 'Applications' : 'Documents';
    }
    get verificationTypeLabelPluralLower() {
        return this.verificationTypeLabelPlural.toLowerCase();
    }

    get applicationsTotalPages() {
        return Math.max(1, Math.ceil(this.applicationsTotal / this.applicationsPageSize));
    }
    get assignedTotalPages() {
        return Math.max(1, Math.ceil(this.assignedTotal / this.assignedPageSize));
    }
    get isEmptyApps() {
        return !this.applications || this.applications.length === 0;
    }
    get isEmptyVerifiers() {
        return !this.verifiers || this.verifiers.length === 0;
    }
    get isEmptyAssigned() {
        return !this.assignedApplications || this.assignedApplications.length === 0;
    }
    get allAssignedSelected() {
        return this.assignedApplications.length > 0 && this.selectedAssignedVerificationIdSet.size === this.assignedApplications.length;
    }

    // ---------------------------
    // Wire: load verifiers & initial apps (loadInit filters verifiers by stage)
    // ---------------------------
    @wire(loadInit, { programId: '$recordId', stage: '$verificationType' })
    wiredInit({ data, error }) {
        if (data) {
            // data.verifiers is array of { ptmId, userId, name } from your Apex
            this.verifiers = data.verifiers || [];

            // Convert to radio options for reassignment (value = ptmId)
            this.reassignVerifierOptions = (this.verifiers || []).map(v => ({ label: v.name, value: v.ptmId }));

            // reset assignment UI state & load apps
            this.selectedVerifierIdSet.clear();
            this.selectedAppIdSet.clear();
            this.applicationsPageNumber = 1;
            this.loadApplicationsPage();

            // reset reassign state
            this.selectedCurrentPtm = null;
            this.selectedToPtm = null;
            this.assignedApplications = [];
            this.selectedAssignedVerificationIdSet.clear();
          
            this.assignedPageNumber = 1;
        } else if (error) {
            this.showError(error);
        }
    }

    // ---------------------------
    // Handle verification type change (Application <-> Document)
    // ---------------------------
    handleVerificationChange(event) {
        this.verificationType = event.detail.value;
        this.applicationsPageNumber = 1;

        // Show reassign for both stages as requested
        this.showReassignSection = true;

        // clear selections & reload (wired loadInit will refresh verifiers automatically)
        this.selectedAppIdSet.clear();
        this.selectedVerifierIdSet.clear();
        this.selectedCurrentPtm = null;
        this.selectedToPtm = null;
        this.assignedApplications = [];
        this.assignedTotal = 0;
        this.assignedPageNumber = 1;

        // explicit reload of applications (wiredLoadInit may not update apps immediately)
        this.loadApplicationsPage();
    }

    // ---------------------------
    // Main applications list (existing)
    // ---------------------------
    loadApplicationsPage() {
        this.isLoading = true;
        Promise.all([
            getApplicationsPage({
                programId: this.recordId,
                stage: this.verificationType,
                pageNumber: this.applicationsPageNumber,
                pageSize: this.applicationsPageSize
            }),
            getApplicationsCount({
                programId: this.recordId,
                stage: this.verificationType
            })
        ])
        .then(([apps, total]) => {
            this.applications = apps || [];
            this.applicationsTotal = total || 0;
            this.selectedAppIdSet.clear();
        })
        .catch(err => this.showError(err))
        .finally(() => { this.isLoading = false; });
    }

    handleAppsPrev() {
        if (this.applicationsPageNumber > 1) {
            this.applicationsPageNumber--;
            this.loadApplicationsPage();
        }
    }
    handleAppsNext() {
        if ((this.applicationsPageNumber * this.applicationsPageSize) < this.applicationsTotal) {
            this.applicationsPageNumber++;
            this.loadApplicationsPage();
        }
    }
    handleAppsPageSize(event) {
        this.applicationsPageSize = Number(event.detail.value);
        this.applicationsPageNumber = 1;
        this.loadApplicationsPage();
    }

    // selectors for main list
    get allAppsSelected() {
        return this.applications.length > 0 && this.selectedAppIdSet.size === this.applications.length;
    }
    toggleSelectAllApps(event) {
        const checked = event.target.checked;
        this.selectedAppIdSet.clear();
        this.template.querySelectorAll('.app-checkbox').forEach(i => {
            i.checked = checked;
            if (checked) this.selectedAppIdSet.add(i.dataset.id);
        });
    }
    handleAppCheckbox(event) {
        const id = event.target.dataset.id;
        if (event.target.checked) this.selectedAppIdSet.add(id);
        else this.selectedAppIdSet.delete(id);
    }

    // Verifier selectors for assignment
    get allVerifiersSelected() {
        return this.verifiers.length > 0 && this.selectedVerifierIdSet.size === this.verifiers.length;
    }
    toggleSelectAllVerifiers(event) {
        const checked = event.target.checked;
        this.selectedVerifierIdSet.clear();
        this.template.querySelectorAll('.verifier-checkbox').forEach(i => {
            i.checked = checked;
            if (checked) this.selectedVerifierIdSet.add(i.dataset.id);
        });
    }
    handleVerifierCheckbox(event) {
        const id = event.target.dataset.id;
        if (event.target.checked) this.selectedVerifierIdSet.add(id);
        else this.selectedVerifierIdSet.delete(id);
    }

    // Manual assign
    handleManualAssign() {
        const appIds = Array.from(this.selectedAppIdSet);
        const verifierIds = Array.from(this.selectedVerifierIdSet);

        if (!appIds.length) return this.showToast('Validation', 'Select at least one Application', 'warning');
        if (!verifierIds.length) return this.showToast('Validation', 'Select at least one Verifier', 'warning');

        this.isLoading = true;
        manualAllocate({
            programId: this.recordId,
            applicationIds: appIds,
            verifierPtmIds: verifierIds
        })
        .then(() => {
            this.showToast('Success','Manual Allocation Completed','success');
            this.applicationsPageNumber = 1;
            this.loadApplicationsPage();
            this.clearSelectionDom('.app-checkbox');
            this.clearSelectionDom('.verifier-checkbox');
        })
        .catch(err => this.showError(err))
        .finally(() => this.isLoading = false);
    }

    // Auto assign
    handleAutoAssign() {
        const appIds = Array.from(this.selectedAppIdSet);
        const verifierIds = Array.from(this.selectedVerifierIdSet);

        if (!appIds.length) return this.showToast('Validation', 'Select at least one Application', 'warning');
        if (!verifierIds.length) return this.showToast('Validation', 'Select at least one Verifier', 'warning');

        this.isLoading = true;
        autoAllocate({
            programId: this.recordId,
            applicationIds: appIds,
            verifierPtmIds: verifierIds,
            verificationType: this.verificationType
        })
        .then(() => {
            this.showToast('Success','Auto Allocation Completed','success');
            this.applicationsPageNumber = 1;
            this.loadApplicationsPage();
            this.clearSelectionDom('.app-checkbox');
            this.clearSelectionDom('.verifier-checkbox');
        })
        .catch(err => this.showError(err))
        .finally(() => this.isLoading = false);
    }

    clearSelectionDom(selector) {
        this.template.querySelectorAll(selector).forEach(c => c.checked = false);
        if (selector === '.app-checkbox') this.selectedAppIdSet.clear();
        if (selector === '.verifier-checkbox') this.selectedVerifierIdSet.clear();
    }

    // =========================
    // REASSIGN (both stages)
    // =========================
    handleCurrentVerifierChange(event) {
        this.selectedCurrentPtm = event.detail.value;
        this.selectedAssignedVerificationIdSet.clear();
        this.assignedPageNumber = 1;
        this.loadReassignListForCurrent();
    }

    handleToVerifierChange(event) {
        this.selectedToPtm = event.detail.value;
    }

    loadReassignListForCurrent() {
        if (!this.selectedCurrentPtm) {
            this.assignedApplications = [];
            this.assignedTotal = 0;
            return;
        }

        this.isLoading = true;
        Promise.all([
            getReassignListPageByStage({
                programId: this.recordId,
                verificationType: this.verificationType,
                currentPtmId: this.selectedCurrentPtm,
                pageNumber: this.assignedPageNumber,
                pageSize: this.assignedPageSize
            }),
            getReassignListCountByStage({
                programId: this.recordId,
                verificationType: this.verificationType,
                currentPtmId: this.selectedCurrentPtm
            })
        ])
        .then(([rows, total]) => {

    // Map rows from Apex (NO dedupe here)
    this.assignedApplications = (rows || []).map(r => ({
        avId: r.avId,
        applicationId: r.appId,
        applicationName: r.appName
    }));

    // TOTAL MUST COME FROM APEX COUNT
    this.assignedTotal = total || 0;

    // reset checkboxes
    this.template.querySelectorAll &&
        this.template.querySelectorAll('.assigned-app-checkbox')
        .forEach(i => i.checked = false);

    this.selectedAssignedVerificationIdSet.clear();
})


        .catch(err => this.showError(err))
        .finally(() => this.isLoading = false);
    }

    // assigned pagination controls
    handleAssignedPrev() {
        if (this.assignedPageNumber > 1) {
            this.assignedPageNumber--;
            this.loadReassignListForCurrent();
        }
    }
    handleAssignedNext() {
        if ((this.assignedPageNumber * this.assignedPageSize) < this.assignedTotal) {
            this.assignedPageNumber++;
            this.loadReassignListForCurrent();
        }
    }
    handleAssignedPageSize(event) {
        this.assignedPageSize = Number(event.detail.value);
        this.assignedPageNumber = 1;
        this.loadReassignListForCurrent();
    }

    toggleSelectAllAssigned(event) {
        const checked = event.target.checked;
        this.selectedAssignedVerificationIdSet.clear();
        this.template.querySelectorAll('.assigned-app-checkbox').forEach(i => {
            i.checked = checked;
            if (checked) this.selectedAssignedVerificationIdSet.add(i.dataset.id);
        });
    }

    handleAssignedAppCheckbox(event) {
        const id = event.target.dataset.id;
        if (event.target.checked) this.selectedAssignedVerificationIdSet.add(id);
        else this.selectedAssignedVerificationIdSet.delete(id);
    }

    // Reassign selected AV records (stage aware)
    handleReassignSelected() {
        if (!this.selectedCurrentPtm) return this.showToast('Validation','Select current verifier','warning');
        if (!this.selectedToPtm) return this.showToast('Validation','Select target verifier','warning');

        const selectedAVs = Array.from(this.selectedAssignedVerificationIdSet);
        if (selectedAVs.length === 0) {
            return this.showToast('Validation','Select at least one assigned record (or use Reassign All)', 'warning');
        }

        this.isLoading = true;
        reassignApplicationsByStage({
            programId: this.recordId,
            verificationType: this.verificationType,
            fromPtmId: this.selectedCurrentPtm,
            toPtmId: this.selectedToPtm,
            applicationVerificationIds: selectedAVs
        })
        .then(() => {
            this.showToast('Success','Reassigned selected records','success');
            this.loadReassignListForCurrent();
            this.applicationsPageNumber = 1;
            this.loadApplicationsPage();
            this.selectedAssignedVerificationIdSet.clear();
        })
        .catch(err => this.showError(err))
        .finally(() => this.isLoading = false);
    }

    // Reassign All for current verifier
    handleReassignAll() {
        if (!this.selectedCurrentPtm) return this.showToast('Validation','Select current verifier','warning');
        if (!this.selectedToPtm) return this.showToast('Validation','Select target verifier','warning');

        this.isLoading = true;
        reassignApplicationsByStage({
            programId: this.recordId,
            verificationType: this.verificationType,
            fromPtmId: this.selectedCurrentPtm,
            toPtmId: this.selectedToPtm,
            applicationVerificationIds: [] // empty => server will reassign all eligible
        })
        .then(() => {
            this.showToast('Success','Reassigned all records for current verifier','success');
            this.loadReassignListForCurrent();
            this.applicationsPageNumber = 1;
            this.loadApplicationsPage();
            this.selectedAssignedVerificationIdSet.clear();
        })
        .catch(err => this.showError(err))
        .finally(() => this.isLoading = false);
    }

    // Toast / error helpers
    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
    showError(error) {
        const msg = (error && error.body && error.body.message) || error.message || 'Unknown error';
        this.showToast('Error', msg, 'error');
        // eslint-disable-next-line no-console
        console.error(error);
    }

    

}