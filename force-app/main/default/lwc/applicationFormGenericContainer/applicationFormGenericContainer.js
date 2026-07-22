import { LightningElement, api, track, wire } from 'lwc';
import { CurrentPageReference } from 'lightning/navigation';
import { NavigationMixin } from 'lightning/navigation';
import { getRecord } from 'lightning/uiRecordApi';
import checkUserValidity from '@salesforce/apex/ApplicationFormController.checkUserValidity';
import fetchMetadataBulk from '@salesforce/apex/ApplicationFormController.fetchMetadataBulk';
import getApplicationStage from '@salesforce/apex/ApplicationFormController.getApplicationStage';
import applicationFormIcons from '@salesforce/resourceUrl/applicationFormIcons';
import APPLICATION_STAGE from '@salesforce/schema/Application__c.Application_Stage__c';
import APPLICATION_STATUS from '@salesforce/schema/Application__c.Application_Status__c';
import PROGRAM_CODE from '@salesforce/schema/Application__c.Program__r.Program_Code__c';
import {
    DEFAULT_ICON_STATES,
    buildFormMetadataRequests,
    getComponentCtor,
    normalizeApplicationFormMetadata
} from './applicationFormConfigHelper';

export default class ApplicationFormGenericContainer extends NavigationMixin(LightningElement) {
    isLoaded = false;
    isAccessChecked = false;
    isAuthorized = false;
    showError = false;
    showConfigError = false;
    errorHeading = 'Access Denied';
    errorMessage = 'You are not authorized to edit this application. Please ensure you are accessing your own application.';
    isPresent = true;
    @api applicationId = '';
    formKey = 'A';
    isNextDisabled = false;
    isPreviousDisabled = false;
    strNextLabel = '';
    currentStep = '';
    progress = 0;
    applicationStatus;
    maxAllowedIndex = 0;
    wiredApplicationResult;
    formConfig;
    iconRegistry = {};
    iconRegistryPromise;
    initializationNonce = 0;
    metadataCache = new Map();

    @wire(CurrentPageReference)
    getPageRef(pageRef) {
        console.log('Page Reference is ', JSON.stringify(pageRef));
        const applicationId = pageRef?.state?.applicationId;
        this.formKey = (pageRef?.state?.form || 'A').trim() || 'A';
        this.applicationId = applicationId || '';

        if (!applicationId) {
            this[NavigationMixin.Navigate]({
                type: 'comm__namedPage',
                attributes: { name: 'Home' }
            });
            return;
        }

        console.log('Id of Application is ' + this.applicationId);
        this.isLoaded = false;
        this.isAccessChecked = false;
        checkUserValidity({ applicationId: this.applicationId })
            .then((result) => {
                this.isAuthorized = result;
                this.isPresent = result;
                this.showError = !result;
                this.showConfigError = false;
                this.errorHeading = 'Access Denied';
                this.errorMessage = 'You are not authorized to edit this application. Please ensure you are accessing your own application.';
            })
            .catch((error) => {
                console.log('Error Verifying Applicant', error);
                this.isAuthorized = false;
                this.isPresent = false;
                this.showError = true;
                this.showConfigError = false;
                this.errorHeading = 'Access Denied';
                this.errorMessage = 'You are not authorized to edit this application. Please ensure you are accessing your own application.';
            })
            .finally(() => {
                this.isAccessChecked = true;
                void this.initializeFromRecord();
            });
    }

    @wire(getRecord, {
        recordId: '$applicationId',
        fields: [APPLICATION_STAGE, APPLICATION_STATUS, PROGRAM_CODE]
    })
    wiredApplication(result) {
        this.wiredApplicationResult = result;
        void this.initializeFromRecord();
    }

    async initializeFromRecord() {
        const data = this.wiredApplicationResult?.data;
        if (!data || !this.isAccessChecked || !this.isAuthorized) {
            return;
        }

        const initNonce = ++this.initializationNonce;
        const stage = data.fields.Application_Stage__c?.value?.trim();
        this.applicationStatus = data.fields.Application_Status__c?.value;
        const programCode = data.fields.Program__r?.value?.fields?.Program_Code__c?.value;

        try {
            await Promise.all([this.loadFormConfig(programCode), this.loadIconRegistry()]);
        } catch (error) {
            if (initNonce !== this.initializationNonce) {
                return;
            }
            this.showConfigurationError(programCode, error);
            return;
        }

        if (initNonce !== this.initializationNonce) {
            return;
        }

        if (!this.formConfig) {
            this.showConfigurationError(programCode);
            return;
        }

        this.steps = this.formConfig.steps.map((step, index) => ({
            ...step,
            componentCtor: getComponentCtor(step.componentName),
            svgStates: this.getIconStates(step.iconKey),
            isSelected: index === 0,
            isCompleted: false,
            isPending: index !== 0
        }));

        const invalidStep = this.steps.find((step) => !step.isPaymentStep && !step.componentCtor);
        if (invalidStep) {
            this.isPresent = false;
            this.showError = true;
            this.showConfigError = true;
            this.errorHeading = 'Configuration Error';
            this.errorMessage = `Step "${invalidStep.label}" is missing a component mapping.`;
            return;
        }

        const stepName = this.formConfig.stageToStepMap?.[stage] ?? this.steps[0]?.name;
        const stageIndex = this.steps.findIndex((stepItem) => stepItem.name === stepName);
        const activeStep = stepName === 'payment' ? this.steps[0]?.name : stepName;

        if (this.applicationStatus === 'Paid') {
            this.maxAllowedIndex = this.steps.length - 1;
        } else {
            this.maxAllowedIndex = Math.max(stageIndex + 1, 0);
        }

        this.initializeSteps(activeStep);
        this.isLoaded = true;

        console.log('Stage:', stage);
        console.log('Max Allowed:', this.maxAllowedIndex);
        this.isPresent = true;
        this.showError = false;
        this.showConfigError = false;
    }

    async loadFormConfig(programCode) {
        if (!programCode) {
            this.formConfig = null;
            return;
        }

        if (this.formConfig?.programCode === programCode && this.formConfig?.formKey === this.formKey) {
            return;
        }

        const cacheKey = `${programCode}::${this.formKey}`;
        if (this.metadataCache.has(cacheKey)) {
            this.formConfig = this.metadataCache.get(cacheKey);
            return;
        }

        const metadataResponse = await fetchMetadataBulk({
            requests: buildFormMetadataRequests(programCode)
        });
        this.formConfig = normalizeApplicationFormMetadata(programCode, this.formKey, metadataResponse);
        this.metadataCache.set(cacheKey, this.formConfig);
    }

    async loadIconRegistry() {
        if (!this.iconRegistryPromise) {
            this.iconRegistryPromise = fetch(applicationFormIcons)
                .then((response) => {
                    if (!response.ok) {
                        throw new Error(`Failed to load icon registry: ${response.status}`);
                    }
                    return response.json();
                })
                .then((icons) => {
                    this.iconRegistry = icons || {};
                    return this.iconRegistry;
                })
                .catch(() => {
                    this.iconRegistry = {};
                    return this.iconRegistry;
                });
        }

        await this.iconRegistryPromise;
    }

    getIconStates(iconKey) {
        return this.iconRegistry?.[iconKey] || this.iconRegistry?.default || DEFAULT_ICON_STATES;
    }

    showConfigurationError(programCode) {
        this.isPresent = false;
        this.showError = true;
        this.showConfigError = true;
        this.errorHeading = 'Configuration Missing';
        this.errorMessage = `No application form configuration is available for program code "${programCode || 'Unknown'}" and form "${this.formKey}".`;
    }

    initializeSteps(activeStep) {
        if (!this.steps?.length) {
            return;
        }

        const activeIndex = this.steps.findIndex((step) => step.name === activeStep);
        if (activeIndex === -1) {
            return;
        }

        this.steps = this.steps.map((step, index) => ({
            ...step,
            isSelected: index === activeIndex,
            isCompleted: index < activeIndex,
            isPending: index > activeIndex
        }));

        this.currentStep = activeStep;
        this.progress = ((activeIndex + 1) / this.steps.length) * 100;
        this.isPreviousDisabled = activeIndex === 0;
        this.updateNextLabel(activeIndex);
    }

    updateNextLabel(index) {
        this.strNextLabel = index === this.steps.length - 1 ? 'Go to Dashboard' : 'Next';
    }

    get currentStepConfig() {
        return this.steps.find((step) => step.name === this.currentStep);
    }

    get currentStepCtor() {
        return this.currentStepConfig?.componentCtor;
    }

    get isPayment() {
        return this.currentStepConfig?.isPaymentStep === true;
    }

    get showSpinner() {
        return !this.isAccessChecked || (this.isPresent && !this.isLoaded);
    }

    renderedCallback() {
        if (!this.isLoaded) return;

        this.stepList.forEach((step) => {
            const container = this.template.querySelector(`.icon-slot[data-name="${step.name}"]`);
            if (container) {
                container.innerHTML = '';
                container.innerHTML = step.svg;
            }
        });

        const selectedIndex = this.steps.findIndex((step) => step.isSelected);
        this.isPreviousDisabled = selectedIndex === 0;
    }

    previousStage() {
        const selectedIndex = this.steps.findIndex((step) => step.isSelected);
        if (selectedIndex === 0) return;

        this.moveToStep(selectedIndex - 1);
    }

    handleStepClick(event) {
        const clicked = event.currentTarget.dataset.name;
        const clickedIndex = this.steps.findIndex((step) => step.name === clicked);

        console.log('Clicked:', clicked, '| Index:', clickedIndex);

        if (clickedIndex === -1) return;
        if (this.steps[clickedIndex]?.isPaymentStep || !this.steps[clickedIndex]?.allowDirectClick) return;

        if (this.applicationStatus === 'Paid') {
            this.moveToStep(clickedIndex);
            return;
        }

        getApplicationStage({ applicationId: this.applicationId })
            .then((stage) => {
                const normalizedStage = stage?.trim();
                const stepName = this.formConfig?.stageToStepMap?.[normalizedStage] ?? this.steps[0]?.name;
                const dbStageIndex = this.steps.findIndex((step) => step.name === stepName);

                console.log('DB Stage:', stage, '| dbStageIndex:', dbStageIndex, '| clickedIndex:', clickedIndex);

                if (clickedIndex <= dbStageIndex) {
                    this.moveToStep(clickedIndex);
                }
            })
            .catch((error) => {
                console.error('Error fetching stage:', error);// Keep the user on the current step if stage lookup fails.
            });
    }

    moveToStep(targetIndex) {
        this.steps = this.steps.map((step, index) => {
            if (index < targetIndex) {
                return { ...step, isCompleted: true, isSelected: false, isPending: false };
            }
            if (index === targetIndex) {
                return { ...step, isSelected: true, isCompleted: false, isPending: false };
            }
            return { ...step, isCompleted: false, isSelected: false, isPending: true };
        });

        this.currentStep = this.steps[targetIndex].name;
        this.progress = ((targetIndex + 1) / this.steps.length) * 100;
        this.isPreviousDisabled = targetIndex === 0;
        this.updateNextLabel(targetIndex);
    }

    get currentStepIndex() {
        return this.steps.findIndex((step) => step.isSelected);
    }

    beforeUnloadHandler = (event) => {
        const isApplicationForm = window.location.href.includes('applicationform?');
        if (isApplicationForm) {
            event.preventDefault();
        }
    };

    constructor() {
        super();
        window.addEventListener('beforeunload', this.beforeUnloadHandler);
    }

    disconnectedCallback() {
        window.removeEventListener('beforeunload', this.beforeUnloadHandler);
    }

    async nextStage() {
        if (this.strNextLabel === 'Next') {
            const cachePrevious = this.isPreviousDisabled;
            const cacheNext = this.isNextDisabled;

            this.isPreviousDisabled = true;
            this.isNextDisabled = true;

            const selectedIndex = this.steps.findIndex((step) => step.isSelected);
            const cmp = this.refs.activeStepComponent;
            if (!this.isPayment && (!cmp || !cmp.saveForm)) {
                console.error('Active step component not found for', this.currentStep);
                this.isPreviousDisabled = cachePrevious;
                this.isNextDisabled = cacheNext;
                return;
            }

            const result = this.isPayment ? true : await cmp.saveForm();

            if (!result) {
                this.isPreviousDisabled = cachePrevious;
                this.isNextDisabled = cacheNext;
                return;
            }

            if (this.applicationStatus !== 'Paid') {
                this.maxAllowedIndex = Math.max(this.maxAllowedIndex, selectedIndex + 2);
            }

            if (selectedIndex + 1 > this.maxAllowedIndex) {
                this.isPreviousDisabled = cachePrevious;
                this.isNextDisabled = cacheNext;
                return;
            }

            const nextStep = this.steps[selectedIndex + 1];
            this.steps = this.steps.map((step, index) => {
                if (index === selectedIndex) {
                    return { ...step, isSelected: false, isCompleted: true, isPending: false };
                }
                if (index === selectedIndex + 1) {
                    return { ...step, isSelected: true, isCompleted: false, isPending: false };
                }
                return step;
            });

            this.currentStep = nextStep.name;
            this.progress = ((selectedIndex + 2) / this.steps.length) * 100;
            this.updateNextLabel(selectedIndex + 1);

            this.isPreviousDisabled = false;
            this.isNextDisabled = cacheNext;
        } else if (this.strNextLabel === 'Go to Dashboard') {
            this[NavigationMixin.Navigate]({
                type: 'comm__namedPage',
                attributes: { name: 'Home' }
            });
        }
    }

    @track steps = [];

    getStepsWithSvg() {
        return this.steps.map((step) => {
            let svg;
            if (step.isSelected) {
                svg = step.svgStates.selected;
            } else if (step.isCompleted) {
                svg = step.svgStates.completed;
            } else {
                svg = step.svgStates.pending;
            }

            return { ...step, svg };
        });
    }

    @api
    get stepList() {
        return this.getStepsWithSvg();
    }

    async saveCurrentStep() {
        const cachePrevious = this.isPreviousDisabled;
        const cacheNext = this.isNextDisabled;

        this.isPreviousDisabled = true;
        this.isNextDisabled = true;

        try {
            const cmp = this.refs.activeStepComponent;

            if (!cmp || !cmp.saveForm) {
                console.error('Active step component not found for', this.currentStep);
                return false;
            }

            return await cmp.saveForm();
        } finally {
            this.isPreviousDisabled = cachePrevious;
            this.isNextDisabled = cacheNext;
        }
    }

    async saveAndExit() {
        const saved = await this.saveCurrentStep();

        if (!saved) {
            return;
        }

        this[NavigationMixin.Navigate]({
            type: 'comm__namedPage',
            attributes: {
                name: 'Home'
            }
        });
    }
}