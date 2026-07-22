import { LightningElement, api, wire, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { getPicklistValues } from 'lightning/uiObjectInfoApi';
import LEAD_STATUS_FIELD from '@salesforce/schema/Lead.Status';
import getPathUiModel from '@salesforce/apex/ConfigurablePathController.getPathUiModel';
import getDependencyOptionsForTarget from '@salesforce/apex/ConfigurablePathController.getDependencyOptionsForTarget';
import savePathTransition from '@salesforce/apex/ConfigurablePathController.savePathTransition';
import { getRecord, getFieldValue } from 'lightning/uiRecordApi';
import STATUS_FIELD from '@salesforce/schema/Lead.Status';
import OPPORTUNITY_STAGE_FIELD from '@salesforce/schema/Opportunity.StageName';
import { refreshApex } from '@salesforce/apex';

export default class ConfigurablePath extends LightningElement {
    @api recordId;
    @api configDeveloperName;
    
    wiredPathResult;
    uiModel;
    _lastLeadPicklistWireData;
    _lastOppPicklistWireData;
    stagesView = [];
    selectedTargetValue;
    modalOpen = false;
    saving = false;
    modalLoadingOptions = false;
    modalDualListOptions = [];
    modalDependencyValues = [];
    modalDependencySingle = '';
    modalUsePerProgram = false;
    @track modalProgramRows = [];

    cacheLeadPathValue = '';
    cacheOppPathValue = '';

    get recordIdForLeadPathRefresh() {
        return this.recordId && this.recordId.startsWith('00Q') ? this.recordId : undefined;
    }

    get recordIdForOppPathRefresh() {
        return this.recordId && this.recordId.startsWith('006') ? this.recordId : undefined;
    }

    @wire(getRecord, { recordId: '$recordIdForLeadPathRefresh', fields: [STATUS_FIELD] })
    wiredLeadPathRefresh({ data, error }) {
        if (data) {
            const newStatus = getFieldValue(data, STATUS_FIELD);
            if (newStatus !== this.cacheLeadPathValue) {
                this.cacheLeadPathValue = newStatus;
                refreshApex(this.wiredPathResult);
            }
        } else if (error) {
            console.log('ConfigurablePath Lead getRecord error', JSON.stringify(error));
        }
    }

    @wire(getRecord, { recordId: '$recordIdForOppPathRefresh', fields: [OPPORTUNITY_STAGE_FIELD] })
    wiredOppPathRefresh({ data, error }) {
        if (data) {
            const newStage = getFieldValue(data, OPPORTUNITY_STAGE_FIELD);
            if (newStage !== this.cacheOppPathValue) {
                this.cacheOppPathValue = newStage;
                refreshApex(this.wiredPathResult);
            }
        } else if (error) {
            console.log('ConfigurablePath Opportunity getRecord error', JSON.stringify(error));
        }
    }

    @wire(getPathUiModel, {
        recordId: '$recordId',
        configDeveloperName: '$resolvedConfigName'
    })
    wiredPath(result) {
        this.wiredPathResult = result;
        const { data, error } = result;
        if (data) {
            this.applyUiModel(data);
            console.log(JSON.stringify(data))
        } else if (error) {
            this.uiModel = null;
            this.stagesView = [];
            this.toastError(error.body?.message || error.message || 'Failed to load path.');
        }
    }

    get resolvedConfigName() {
        return this.configDeveloperName || 'B2C_Lead_Path';
    }

    get wireLeadPicklistRecordTypeId() {
        if (this.uiModel?.pathObjectApiName !== 'Lead' || !this.uiModel?.useClientPathStages) {
            return undefined;
        }
        const id = this.uiModel.pathRecordTypeId;
        return id || undefined;
    }

    get wireOppPicklistRecordTypeId() {
        if (this.uiModel?.pathObjectApiName !== 'Opportunity' || !this.uiModel?.useClientPathStages) {
            return undefined;
        }
        const id = this.uiModel.pathRecordTypeId;
        return id || undefined;
    }

    @wire(getPicklistValues, {
        recordTypeId: '$wireLeadPicklistRecordTypeId',
        fieldApiName: LEAD_STATUS_FIELD
    })
    wiredLeadStatusPicklist(result) {
        const { data, error } = result;
        if (error) {
            this._lastLeadPicklistWireData = null;
            if (this.uiModel?.useClientPathStages && this.uiModel?.pathObjectApiName === 'Lead') {
                this.stagesView = [];
                this.toastError(error.body?.message || error.message || 'Failed to load path picklist.');
            }
            return;
        }
        if (!data) {
            return;
        }
        this._lastLeadPicklistWireData = data;
        this.maybeApplyPicklistWireToStages();
    }

    @wire(getPicklistValues, {
        recordTypeId: '$wireOppPicklistRecordTypeId',
        fieldApiName: OPPORTUNITY_STAGE_FIELD
    })
    wiredOpportunityStagePicklist(result) {
        const { data, error } = result;
        if (error) {
            this._lastOppPicklistWireData = null;
            if (this.uiModel?.useClientPathStages && this.uiModel?.pathObjectApiName === 'Opportunity') {
                this.stagesView = [];
                this.toastError(error.body?.message || error.message || 'Failed to load opportunity stage picklist.');
            }
            return;
        }
        if (!data) {
            return;
        }
        this._lastOppPicklistWireData = data;
        this.maybeApplyPicklistWireToStages();
    }

    maybeApplyPicklistWireToStages() {
        if (!this.uiModel?.useClientPathStages || !this.clientPathPicklistSupported) {
            return;
        }
        const obj = this.uiModel.pathObjectApiName;
        const pickData =
            obj === 'Lead' ? this._lastLeadPicklistWireData : obj === 'Opportunity' ? this._lastOppPicklistWireData : null;
        if (pickData) {
            this.applyPicklistWireToStages(pickData);
        } else {
            this.stagesView = [];
        }
    }

    get clientPathPicklistSupported() {
        return (
            (this.uiModel?.pathObjectApiName === 'Lead' && this.uiModel?.pathFieldApiName === 'Status') ||
            (this.uiModel?.pathObjectApiName === 'Opportunity' && this.uiModel?.pathFieldApiName === 'StageName')
        );
    }

    applyUiModel(data) {
        this.uiModel = data;
        if (data.useClientPathStages && this.clientPathPicklistSupported) {
            this.maybeApplyPicklistWireToStages();
        } else {
            this.stagesView = (data.stages || []).map((s) => ({
                ...s,
                itemClass: this.segmentClass(s)
            }));
        }
        const stages = this.effectiveStagesList;
        if (!this.selectedTargetValue || !stages.some((x) => x.value === this.selectedTargetValue)) {
            this.selectedTargetValue = data.currentPathValue;
        }
    }

    get effectiveStagesList() {
        if (this.uiModel?.useClientPathStages && this.stagesView.length > 0) {
            return this.stagesView.map((s) => ({
                label: s.label,
                value: s.value,
                isCurrent: s.isCurrent,
                isComplete: s.isComplete
            }));
        }
        return this.uiModel?.stages || [];
    }

    includeStageOnPathForWire(entry, currentPathValue) {
        if (currentPathValue && entry.value === currentPathValue) {
            return true;
        }
        const order = this.uiModel?.programScopedMainStageApis;
        if (order && order.length > 0 && !order.includes(entry.value)) {
            return false;
        }
        const f = this.uiModel?.stageUiFlagsByPathValue?.[entry.value];
        if (f && f.showOnPath === false) {
            return false;
        }
        return true;
    }

    /** Sub-status modal only if Path Stage Override exists for this status and Open Sub Status Modal is true. */
    get openSubStatusModalForSelectedStage() {
        const v = this.selectedTargetValue;
        if (!v || !this.uiModel) {
            return false;
        }
        const f = this.uiModel.stageUiFlagsByPathValue?.[v];
        if (!f) {
            return false;
        }
        return f.openSubStatusModal !== false;
    }

    /** @param {{ values?: { label: string; value: string }[] }} picklistData */
    applyPicklistWireToStages(picklistData) {
        const current = this.uiModel?.currentPathValue;
        const labelOverrides = this.uiModel?.mainStageLabelByApi || {};
        let values = [...(picklistData.values || [])].filter((v) => this.includeStageOnPathForWire(v, current));
        const order = this.uiModel?.programScopedMainStageApis;
        if (order && order.length > 0) {
            const byVal = new Map(values.map((x) => [x.value, x]));
            const next = [];
            for (const api of order) {
                const e = byVal.get(api);
                if (e) {
                    const label = labelOverrides[api] || e.label;
                    next.push({ label, value: e.value });
                }
            }
            values = next;
        }
        if (current && !values.some((v) => v.value === current)) {
            const fallbackLabel = labelOverrides[current] || current;
            values = [...values, { label: fallbackLabel, value: current }];
        }
        let currentIndex = -1;
        values.forEach((v, i) => {
            if (v.value === current) {
                currentIndex = i;
            }
        });
        this.stagesView = values.map((v, i) => {
            const row = {
                label: v.label,
                value: v.value,
                isCurrent: v.value === current,
                isComplete: currentIndex >= 0 && i < currentIndex
            };
            return { ...row, itemClass: this.segmentClass(row) };
        });
    }

    segmentClass(stage) {
        let cls = 'path-segment';
        if (stage.isCurrent) {
            cls += ' path-segment_current';
        } else if (stage.isComplete) {
            cls += ' path-segment_complete';
        } else {
            cls += ' path-segment_future';
        }
        return cls;
    }

    get showChrome() {
        return this.uiModel && this.uiModel.loadOk;
    }

    get loadErrorMessage() {
        return this.uiModel && !this.uiModel.loadOk ? this.uiModel.loadErrorMessage : '';
    }

    get hasLoadError() {
        return this.uiModel && !this.uiModel.loadOk;
    }

    get modalTitle() {
        return (this.uiModel && this.uiModel.modalTitle) || 'Edit dependencies';
    }

    get showPathInModal() {
        return Boolean(this.uiModel && this.uiModel.showPathFieldInModal);
    }

    get pathModalLabel() {
        return (this.uiModel && this.uiModel.pathFieldModalLabel) || 'Status';
    }

    get pathModalValue() {
        return this.selectedTargetValue || '';
    }

    get dependencyLabel() {
        return (this.uiModel && this.uiModel.dependencyFieldLabel) || 'Dependency';
    }

    get dependencyMulti() {
        return Boolean(this.uiModel && this.uiModel.dependencyMultiSelect);
    }

    get dualListOptions() {
        if (this.modalOpen) {
            return this.modalDualListOptions || [];
        }
        return this.uiModel && this.uiModel.dependencyOptions ? this.uiModel.dependencyOptions : [];
    }

    get markCompleteDisabled() {
        return !this.showChrome || this.saving || !this.selectedTargetValue;
    }

    get saveModalDisabled() {
        return this.saving || this.modalLoadingOptions;
    }

    async handleStageClick(event) {
        const value = event.currentTarget.dataset.value;
        if (value) {
            this.selectedTargetValue = value;
            const baseStages = this.uiModel.useClientPathStages ? this.stagesView : this.uiModel.stages || [];
            this.stagesView = baseStages.map((s) => ({
                ...s,
                itemClass: this.segmentClassForValue(s, value)
            }));
            if (this.modalOpen) {
                await this.loadModalDependencyOptions();
                this.pruneModalSelectionsToOptions();
            }
        }
    }

    segmentClassForValue(stage, selectedValue) {
        const stages = this.uiModel.useClientPathStages ? this.stagesView : this.uiModel.stages || [];
        let selectedIndex = -1;
        let stageIndex = -1;
        let idx = 0;
        for (const pe of stages) {
            if (pe.value === selectedValue) {
                selectedIndex = idx;
            }
            if (pe.value === stage.value) {
                stageIndex = idx;
            }
            idx++;
        }
        const isSelected = stage.value === selectedValue;
        const isComplete = selectedIndex >= 0 && stageIndex < selectedIndex;
        let cls = 'path-segment';
        if (isSelected) {
            cls += ' path-segment_current';
        } else if (isComplete) {
            cls += ' path-segment_complete';
        } else {
            cls += ' path-segment_future';
        }
        return cls;
    }

    async handleOpenModal() {
        if (!this.uiModel || !this.selectedTargetValue) {
            return;
        }
        if (!this.openSubStatusModalForSelectedStage) {
            await this.savePathWithoutModal();
            return;
        }
        const preset = this.uiModel.selectedDependencyValues || [];
        console.log('Preset is ',JSON.stringify(preset))
        this.modalDependencyValues = [...preset];
        this.modalDependencySingle = preset.length > 0 ? preset[0] : '';
        this.modalUsePerProgram = false;
        this.modalProgramRows = [];
        this.modalOpen = true;
        this.modalLoadingOptions = true;
        console.log('UI Model Dep Options: ',JSON.stringify(this.uiModel.dependencyOptionsByTargetStage))
        if (this.uiModel.dependencyOptionsByTargetStage) {
            await this.loadModalDependencyOptions();
        } else {
            this.modalDualListOptions = this.uiModel.dependencyOptions || [];
        }
        this.modalLoadingOptions = false;
        if (this.modalOpen) {
            this.pruneModalSelectionsToOptions();
        }
    }

    async loadModalDependencyOptions() {
        if (!this.uiModel || !this.uiModel.dependencyOptionsByTargetStage) {
            return;
        }
        try {
            const res = await getDependencyOptionsForTarget({
                recordId: this.recordId,
                configDeveloperName: this.resolvedConfigName,
                targetPathValue: this.selectedTargetValue
            });
            console.log('getDepOptions: ',JSON.stringify(res))
            if (res.loadOk) {
                if (res.usePerProgramLayout) {
                    this.modalUsePerProgram = true;
                    this.modalProgramRows = (res.programContexts || []).map((b) => ({
                        leadProgramId: b.leadProgramId,
                        programName: b.programName,
                        programCode: b.programCode,
                        sectionHeading: `${b.programName} — Sub Status`,
                        options: (b.options || []).map((o) => ({ label: o.label, value: o.value })),
                        selectedValue: b.currentValue || ''
                    }));
                    this.modalDualListOptions = [];
                } else {
                    this.modalUsePerProgram = false;
                    this.modalProgramRows = [];
                    this.modalDualListOptions = res.options || [];
                }
            } else {
                this.modalDualListOptions = [];
                this.modalUsePerProgram = false;
                this.modalProgramRows = [];
                this.toastError(res.loadErrorMessage || 'Could not load sub-status options.');
                this.modalOpen = false;
            }
        } catch (e) {
            this.modalDualListOptions = [];
            this.modalUsePerProgram = false;
            this.modalProgramRows = [];
            this.toastError(e.body?.message || e.message || 'Could not load sub-status options.');
            this.modalOpen = false;
        }
    }

    pruneModalSelectionsToOptions() {
        if (this.modalUsePerProgram) {
            this.modalProgramRows = (this.modalProgramRows || []).map((row) => {
                const allowed = new Set((row.options || []).map((o) => o.value));
                const v = row.selectedValue;
                return { ...row, selectedValue: allowed.has(v) ? v : '' };
            });
            return;
        }
        const allowed = new Set((this.modalDualListOptions || []).map((o) => o.value));
        if (this.uiModel.dependencyMultiSelect) {
            this.modalDependencyValues = (this.modalDependencyValues || []).filter((v) => allowed.has(v));
        } else if (this.modalDependencySingle && !allowed.has(this.modalDependencySingle)) {
            this.modalDependencySingle = '';
        }
    }

    async savePathWithoutModal() {
        if (!this.uiModel || !this.selectedTargetValue || !this.recordId) {
            return;
        }
        this.saving = true;
        try {
            const result = await savePathTransition({
                recordId: this.recordId,
                configDeveloperName: this.resolvedConfigName,
                newPathValue: this.selectedTargetValue,
                dependencyValues: [],
                perProgramSubStatuses: null
            });
            if (result.success) {
                this.toastSuccess(result.message || 'Saved.');
                this.scheduleFullPageReload();
            } else {
                this.toastError(result.message || 'Save failed.');
            }
        } catch (e) {
            this.toastError(e.body?.message || e.message || 'Save failed.');
        } finally {
            this.saving = false;
        }
    }

    /** Brief delay so the success toast shows before the record page reloads. */
    scheduleFullPageReload() {
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        window.setTimeout(() => {
            window.location.reload();
        }, 400);
    }

    handleCloseModal() {
        this.modalOpen = false;
    }

    handleDualChange(event) {
        this.modalDependencyValues = event.detail.value || [];
    }

    handleComboChange(event) {
        this.modalDependencySingle = event.detail.value;
    }

    handlePerProgramComboChange(event) {
        const lpid = event.target.dataset.lpid;
        const val = event.detail.value;
        this.modalProgramRows = this.modalProgramRows.map((row) =>
            row.leadProgramId === lpid ? { ...row, selectedValue: val } : row
        );
    }

    async handleSaveModal() {
        const perProgramPayload = this.modalUsePerProgram
            ? this.modalProgramRows.map((r) => ({
                  leadProgramId: r.leadProgramId,
                  subStatusValue: r.selectedValue || ''
              }))
            : null;
        const deps = this.modalUsePerProgram
            ? []
            : this.uiModel.dependencyMultiSelect
              ? this.modalDependencyValues
              : this.modalDependencySingle
                ? [this.modalDependencySingle]
                : [];

        this.saving = true;
        try {
           
            const result = await savePathTransition({
                recordId: this.recordId,
                configDeveloperName: this.resolvedConfigName,
                newPathValue: this.selectedTargetValue,
                dependencyValues: deps,
                perProgramSubStatuses: perProgramPayload
            });
             console.log('Save Result Params : ',this.recordId, this.resolvedConfigName, 
                JSON.stringify(deps),JSON.stringify(perProgramPayload)
             )
            if (result.success) {
                this.toastSuccess(result.message || 'Saved.');
                this.modalOpen = false;
                this.scheduleFullPageReload();
            } else {
                this.toastError(result.message || 'Save failed.');
            }
        } catch (e) {
            this.toastError(e.body?.message || e.message || 'Save failed.');
        } finally {
            this.saving = false;
        }
    }

    toastError(message) {
        this.dispatchEvent(
            new ShowToastEvent({
                title: 'Error',
                message,
                variant: 'error',
                mode: 'sticky'
            })
        );
    }

    toastSuccess(message) {
        this.dispatchEvent(
            new ShowToastEvent({
                title: 'Success',
                message,
                variant: 'success'
            })
        );
    }
}