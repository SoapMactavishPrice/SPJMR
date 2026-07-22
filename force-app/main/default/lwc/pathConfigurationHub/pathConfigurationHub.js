import { LightningElement, wire, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { refreshApex } from '@salesforce/apex';
import getSnapshot from '@salesforce/apex/PathConfigurationHubController.getSnapshot';
import saveWizard from '@salesforce/apex/PathConfigurationHubController.saveWizard';
import saveDependency from '@salesforce/apex/PathConfigurationHubController.saveDependency';
import saveOverride from '@salesforce/apex/PathConfigurationHubController.saveOverride';
import saveMainStage from '@salesforce/apex/PathConfigurationHubController.saveMainStage';

const WIZARD_DEFAULTS = () => ({
    developerName: '',
    masterLabel: '',
    objectApiName: 'Lead',
    pathFieldApiName: 'Status',
    dependencyFieldApiName: 'Lead_Sub_Status__c',
    recordTypeDeveloperName: '',
    modalTitle: 'Edit Dependencies',
    showPathFieldInModal: true,
    pathFieldModalLabel: 'Status',
    dependencyFieldLabel: 'Lead Sub Status',
    dependencyMultiSelect: false,
    leadProgramObjectApiName: 'Lead_Program__c',
    leadProgramParentLookupApi: 'Lead__c',
    programLookupApi: 'Program__c',
    programRelationshipName: 'Program__r',
    programCodeFieldApi: 'Program_Code__c',
    allowEmptyLeadPrograms: false,
    dependencyRequired: true,
    useClientRecordTypePicklist: true,
    programFromRootRecord: false
});

const DEPENDENCY_DEFAULTS = () => ({
    developerName: '',
    masterLabel: '',
    pathConfigDeveloperName: '',
    programCode: '',
    pathStageValueApi: '',
    valueApi: '',
    label: '',
    sortOrder: 0,
    isActive: true
});

const OVERRIDE_DEFAULTS = () => ({
    developerName: '',
    masterLabel: '',
    pathConfigDeveloperName: '',
    programCode: '',
    pathStageValueApi: '',
    showOnPath: true,
    openSubStatusModal: true
});

const MAIN_STAGE_DEFAULTS = () => ({
    developerName: '',
    masterLabel: '',
    pathConfigDeveloperName: '',
    programCode: '',
    pathStageValueApi: '',
    label: '',
    sortOrder: 0,
    isActive: true
});

export default class PathConfigurationHub extends LightningElement {
    wiredSnapshotResult;
    snapshot;
    error;

    editorKind = null;
    devNameLocked = false;

    @track draft = {};

    /** Optional: filter dependency/override tables and prefill new rows */
    pathConfigFocus = '';

    wizardColumns = [
        { label: 'Developer name', fieldName: 'developerName', type: 'text' },
        { label: 'Label', fieldName: 'masterLabel', type: 'text' },
        { label: 'Object', fieldName: 'objectApiName', type: 'text' },
        { label: 'Path field', fieldName: 'pathFieldApiName', type: 'text' },
        { label: 'Record type', fieldName: 'recordTypeDeveloperName', type: 'text' },
        {
            type: 'action',
            typeAttributes: {
                rowActions: [{ label: 'Edit', name: 'edit' }]
            }
        }
    ];

    dependencyColumns = [
        { label: 'Developer name', fieldName: 'developerName', type: 'text' },
        { label: 'Path config', fieldName: 'pathConfigDeveloperName', type: 'text' },
        { label: 'Program', fieldName: 'programCode', type: 'text' },
        { label: 'Stage', fieldName: 'pathStageValueApi', type: 'text' },
        { label: 'Value API', fieldName: 'valueApi', type: 'text' },
        { label: 'Label', fieldName: 'label', type: 'text' },
        { label: 'Sort', fieldName: 'sortOrder', type: 'number' },
        { label: 'Active', fieldName: 'isActive', type: 'boolean' },
        {
            type: 'action',
            typeAttributes: {
                rowActions: [{ label: 'Edit', name: 'edit' }]
            }
        }
    ];

    overrideColumns = [
        { label: 'Developer name', fieldName: 'developerName', type: 'text' },
        { label: 'Path config', fieldName: 'pathConfigDeveloperName', type: 'text' },
        { label: 'Program', fieldName: 'programCode', type: 'text' },
        { label: 'Stage', fieldName: 'pathStageValueApi', type: 'text' },
        { label: 'Show on path', fieldName: 'showOnPath', type: 'boolean' },
        { label: 'Open modal', fieldName: 'openSubStatusModal', type: 'boolean' },
        {
            type: 'action',
            typeAttributes: {
                rowActions: [{ label: 'Edit', name: 'edit' }]
            }
        }
    ];

    mainStageColumns = [
        { label: 'Developer name', fieldName: 'developerName', type: 'text' },
        { label: 'Path config', fieldName: 'pathConfigDeveloperName', type: 'text' },
        { label: 'Program', fieldName: 'programCode', type: 'text' },
        { label: 'Stage API', fieldName: 'pathStageValueApi', type: 'text' },
        { label: 'Label', fieldName: 'label', type: 'text' },
        { label: 'Sort', fieldName: 'sortOrder', type: 'number' },
        { label: 'Active', fieldName: 'isActive', type: 'boolean' },
        {
            type: 'action',
            typeAttributes: {
                rowActions: [{ label: 'Edit', name: 'edit' }]
            }
        }
    ];

    @wire(getSnapshot)
    wiredSnapshot(value) {
        this.wiredSnapshotResult = value;
        if (value.data) {
            this.snapshot = value.data;
            this.error = undefined;
        } else if (value.error) {
            this.error = value.error;
            this.snapshot = undefined;
        }
    }

    get loading() {
        if (!this.wiredSnapshotResult) {
            return true;
        }
        return this.wiredSnapshotResult.loading === true;
    }

    get errorMessage() {
        if (!this.error) {
            return '';
        }
        if (this.error.body && this.error.body.message) {
            return this.error.body.message;
        }
        if (Array.isArray(this.error.body)) {
            return this.error.body.map((m) => m.message).join(', ');
        }
        return this.error.message || 'Unknown error';
    }

    get wizardRows() {
        return this.snapshot && this.snapshot.wizards ? this.snapshot.wizards : [];
    }

    get showList() {
        return this.editorKind === null && !this.loading && !this.error;
    }

    get showWizardEditor() {
        return this.editorKind === 'wizard';
    }

    get showDependencyEditor() {
        return this.editorKind === 'dependency';
    }

    get showOverrideEditor() {
        return this.editorKind === 'override';
    }

    get showMainStageEditor() {
        return this.editorKind === 'mainStage';
    }

    get wizardOptions() {
        if (!this.snapshot || !this.snapshot.wizards) {
            return [{ label: 'All path configs', value: '' }];
        }
        const opts = [{ label: 'All path configs', value: '' }];
        this.snapshot.wizards.forEach((w) => {
            opts.push({
                label: `${w.masterLabel} (${w.developerName})`,
                value: w.developerName
            });
        });
        return opts;
    }

    get filteredDependencies() {
        if (!this.snapshot || !this.snapshot.dependencies) {
            return [];
        }
        const f = this.pathConfigFocus;
        if (!f) {
            return this.snapshot.dependencies;
        }
        return this.snapshot.dependencies.filter((d) => d.pathConfigDeveloperName === f);
    }

    get filteredOverrides() {
        if (!this.snapshot || !this.snapshot.overrides) {
            return [];
        }
        const f = this.pathConfigFocus;
        if (!f) {
            return this.snapshot.overrides;
        }
        return this.snapshot.overrides.filter((o) => o.pathConfigDeveloperName === f);
    }

    get filteredMainStages() {
        if (!this.snapshot || !this.snapshot.mainStages) {
            return [];
        }
        const f = this.pathConfigFocus;
        if (!f) {
            return this.snapshot.mainStages;
        }
        return this.snapshot.mainStages.filter((m) => m.pathConfigDeveloperName === f);
    }

    handlePathConfigFocusChange(event) {
        this.pathConfigFocus = event.detail.value;
    }

    handleWizardRowAction(event) {
        const action = event.detail.action.name;
        const row = event.detail.row;
        if (action === 'edit') {
            this.editorKind = 'wizard';
            this.devNameLocked = true;
            this.draft = { ...row };
        }
    }

    handleDependencyRowAction(event) {
        const action = event.detail.action.name;
        const row = event.detail.row;
        if (action === 'edit') {
            this.editorKind = 'dependency';
            this.devNameLocked = true;
            this.draft = { ...row };
        }
    }

    handleOverrideRowAction(event) {
        const action = event.detail.action.name;
        const row = event.detail.row;
        if (action === 'edit') {
            this.editorKind = 'override';
            this.devNameLocked = true;
            this.draft = { ...row };
        }
    }

    handleMainStageRowAction(event) {
        const action = event.detail.action.name;
        const row = event.detail.row;
        if (action === 'edit') {
            this.editorKind = 'mainStage';
            this.devNameLocked = true;
            this.draft = { ...row };
        }
    }

    newWizard() {
        this.editorKind = 'wizard';
        this.devNameLocked = false;
        this.draft = WIZARD_DEFAULTS();
    }

    newDependency() {
        this.editorKind = 'dependency';
        this.devNameLocked = false;
        const d = DEPENDENCY_DEFAULTS();
        if (this.pathConfigFocus) {
            d.pathConfigDeveloperName = this.pathConfigFocus;
        }
        this.draft = d;
    }

    newOverride() {
        this.editorKind = 'override';
        this.devNameLocked = false;
        const o = OVERRIDE_DEFAULTS();
        if (this.pathConfigFocus) {
            o.pathConfigDeveloperName = this.pathConfigFocus;
        }
        this.draft = o;
    }

    newMainStage() {
        this.editorKind = 'mainStage';
        this.devNameLocked = false;
        const m = MAIN_STAGE_DEFAULTS();
        if (this.pathConfigFocus) {
            m.pathConfigDeveloperName = this.pathConfigFocus;
        }
        this.draft = m;
    }

    closeEditor() {
        this.editorKind = null;
        this.devNameLocked = false;
        this.draft = {};
    }

    handleDraftText(event) {
        const field = event.target.dataset.field;
        const value = event.detail.value;
        this.draft = { ...this.draft, [field]: value };
    }

    handleDraftCheckbox(event) {
        const field = event.target.dataset.field;
        const checked = event.target.checked;
        this.draft = { ...this.draft, [field]: checked };
    }

    handleDraftNumber(event) {
        const field = event.target.dataset.field;
        const raw = event.detail.value;
        const num = raw === '' || raw === null || raw === undefined ? 0 : Number(raw);
        this.draft = { ...this.draft, [field]: num };
    }

    async saveWizardDraft() {
        try {
            const res = await saveWizard({ ...this.draft });
            this.toast('Queued', `${res.message} Job Id: ${res.asyncJobId}`, 'success');
            await refreshApex(this.wiredSnapshotResult);
            this.closeEditor();
        } catch (e) {
            this.toast('Save failed', this.reduceError(e), 'error');
        }
    }

    async saveDependencyDraft() {
        try {
            const res = await saveDependency({ ...this.draft });
            this.toast('Queued', `${res.message} Job Id: ${res.asyncJobId}`, 'success');
            await refreshApex(this.wiredSnapshotResult);
            this.closeEditor();
        } catch (e) {
            this.toast('Save failed', this.reduceError(e), 'error');
        }
    }

    async saveOverrideDraft() {
        try {
            const res = await saveOverride({ ...this.draft });
            this.toast('Queued', `${res.message} Job Id: ${res.asyncJobId}`, 'success');
            await refreshApex(this.wiredSnapshotResult);
            this.closeEditor();
        } catch (e) {
            this.toast('Save failed', this.reduceError(e), 'error');
        }
    }

    async saveMainStageDraft() {
        try {
            const res = await saveMainStage({ ...this.draft });
            this.toast('Queued', `${res.message} Job Id: ${res.asyncJobId}`, 'success');
            await refreshApex(this.wiredSnapshotResult);
            this.closeEditor();
        } catch (e) {
            this.toast('Save failed', this.reduceError(e), 'error');
        }
    }

    toast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant, mode: 'sticky' }));
    }

    reduceError(e) {
        if (e.body && e.body.message) {
            return e.body.message;
        }
        return e.message || 'Unknown error';
    }
}