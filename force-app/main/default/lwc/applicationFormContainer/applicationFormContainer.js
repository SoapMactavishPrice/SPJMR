import { LightningElement, api, track, wire } from 'lwc';
import { CurrentPageReference } from 'lightning/navigation';
import { NavigationMixin } from 'lightning/navigation';
import { getRecord } from 'lightning/uiRecordApi';
import checkUserValidity from '@salesforce/apex/ApAccountProgramController.checkUserValidity';
import APPLICATION_STAGE from '@salesforce/schema/Application__c.Application_Stage__c';
import APPLICATION_STATUS from '@salesforce/schema/Application__c.Application_Status__c';
import { updateRecord } from 'lightning/uiRecordApi';
import { refreshApex } from '@salesforce/apex';
import getApplicationStage from '@salesforce/apex/ApAccountProgramController.getApplicationStage';

export default class ApplicationFormContainer extends NavigationMixin(LightningElement) {

    isLoaded = false;
    showError = false;
    isPresent = true;
    @api applicationId = '';
    isNextDisabled = false;
    isPreviousDisabled = false;
    strNextLabel = '';
    currentStep = '';
    progress = 12.5;
    applicationStatus;
    maxAllowedIndex = 0;

    @wire(CurrentPageReference)
    getPageRef(pageRef) {
        console.log('Page Reference is ', JSON.stringify(pageRef));
        this.applicationId = pageRef.state.applicationId;
        if(!this.applicationId){
                 this[NavigationMixin.Navigate]({
                    type: 'comm__namedPage',
                    attributes: { name: 'Home' }
                });
            }
        if (pageRef && pageRef.state && pageRef.state.applicationId) {
            
            console.log('Id of Application is '+this.applicationId)
            
            checkUserValidity()
                .then((result) => {
                    if (!result.includes(this.applicationId)) {
                        this.isPresent = false;
                        this.showError = true;
                    }
                })
                .catch((error) => {
                    console.log('Error Verifying Applicant', error);
                });
        }
    }

    @wire(getRecord, {
        recordId: '$applicationId',
        fields: [APPLICATION_STAGE, APPLICATION_STATUS]
    })
    wiredApplication({ data }) {
        if (data) {
            const stage = data.fields.Application_Stage__c?.value;
            this.applicationStatus = data.fields.Application_Status__c?.value;

            const normalizedStage = stage?.trim();
            const step = this.stageToStepMap[normalizedStage] ?? 'program';
            const stageIndex = this.steps.findIndex(s => s.name === step);

            if (this.applicationStatus === 'Paid') {
                this.maxAllowedIndex = this.steps.length - 1;
            } else {
                this.maxAllowedIndex = stageIndex + 1;
            }

            const activeStep = (step === 'payment') ? 'program' : step;

            this.initializeSteps(activeStep);
            this.isLoaded = true;

            console.log('Stage:', stage);
            console.log('Active UI Step:', activeStep);
            console.log('Max Allowed:', this.maxAllowedIndex);
        }
    }

    stageToStepMap = {
        'Programme Details': 'program',
        'Basic Details': 'basic',
        'Academic Details': 'academic',
        'Entrance Exam': 'exam',
        'Work Experience': 'work',
        'Profile Information': 'profile',
        'Terms & Conditions': 'terms',
        'Terms and Conditions': 'terms',
        'Payment': 'payment'
    };

    stepNameMap = {
        program: 'c-af-program-details-container-gmp',
        basic: 'c-af-basic-details-container-gmp',
        academic: 'c-af-academic-details-container-gmp',
        exam: 'c-af-competitive-exam-details-container-gmp',
        work: 'c-af-work-experience-container-gmp',
        profile: 'c-af-profile-information-container-gmp',
        terms: 'c-af-terms-and-conditions-container-gmp',
        payment: 'c-af-payments-container-g-m-p'
    };

    initializeSteps(activeStep) {
        if (!this.steps || this.steps.length === 0) return;

        const activeIndex = this.steps.findIndex(s => s.name === activeStep);
        if (activeIndex === -1) return;

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

    get isProgram() { return this.currentStep === 'program'; }
    get isBasic() { return this.currentStep === 'basic'; }
    get isAcademic() { return this.currentStep === 'academic'; }
    get isExam() { return this.currentStep === 'exam'; }
    get isWork() { return this.currentStep === 'work'; }
    get isProfile() { return this.currentStep === 'profile'; }
    get isTerms() { return this.currentStep === 'terms'; }
    get isPayment() { return this.currentStep === 'payment'; }
    get isPaymentLocked() { return true; }

    renderedCallback() {
        if (!this.isLoaded) return;

        this.stepList.forEach(step => {
            const container = this.template.querySelector(
                `.icon-slot[data-name="${step.name}"]`
            );
            if (container) {
                container.innerHTML = '';
                container.innerHTML = step.svg;
            }
        });

        const selectedIndex = this.steps.findIndex(s => s.isSelected);
        this.isPreviousDisabled = selectedIndex === 0;
    }

    previousStage() {
        const selectedIndex = this.steps.findIndex(s => s.isSelected);
        if (selectedIndex === 0) return;

        const newIndex = selectedIndex - 1;
        this.moveToStep(newIndex);
    }

    // ✅ SINGLE handleStepClick - duplicate removed
    handleStepClick(event) {
        const clicked = event.currentTarget.dataset.name;
        const clickedIndex = this.steps.findIndex(s => s.name === clicked);

        console.log('Clicked:', clicked, '| Index:', clickedIndex);

        if (clickedIndex === -1) return;
        if (clicked === 'payment') return;

        // Paid users navigate freely
        if (this.applicationStatus === 'Paid') {
            this.moveToStep(clickedIndex);
            return;
        }

        // Fetch fresh stage from DB for non-Paid users
        getApplicationStage({ applicationId: this.applicationId })
            .then(stage => {
                const normalizedStage = stage?.trim();
                const stepName = this.stageToStepMap[normalizedStage] ?? 'program';
                const dbStageIndex = this.steps.findIndex(s => s.name === stepName);

                console.log('DB Stage:', stage, '| dbStageIndex:', dbStageIndex, '| clickedIndex:', clickedIndex);

                // Allow navigation up to and including the current DB stage
                if (clickedIndex <= dbStageIndex) {
                    this.moveToStep(clickedIndex);
                }
            })
            .catch(error => {
                console.error('Error fetching stage:', error);
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
        return this.steps.findIndex(s => s.isSelected);
    }

    constructor() {
        super();
        window.addEventListener('beforeunload', (event) => {
            console.log('Added Before Unload', window.location.href);
            const isApplicationForm = window.location.href.includes('applicationform?');
            if (isApplicationForm) {
                event.preventDefault();
            }
        });
    }

    disconnectedCallback() {
        window.removeEventListener('beforeunload', (event) => {
            console.log('Removed Before Unload');
        });
    }

    async nextStage() {
    if (this.strNextLabel === 'Next') {

        const cachePrevious = this.isPreviousDisabled;
        const cacheNext = this.isNextDisabled;

        this.isPreviousDisabled = true;
        this.isNextDisabled = true;

        const selectedIndex = this.steps.findIndex(s => s.isSelected);
        const currentComponent = this.stepNameMap[this.steps[selectedIndex].name];
        //Safety Check
        const cmp = this.template.querySelector(currentComponent);
        if (!cmp || !cmp.saveForm) {
            console.error('Component not found:', currentComponent);
            this.isPreviousDisabled = cachePrevious;
            this.isNextDisabled = cacheNext;
            return;
        }

        const result = await this.template
            .querySelector(currentComponent)
            .saveForm();

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

        // Update maxAllowedIndex in sync after successful save
        

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

    @track steps = [
        { name: 'program', label: 'Programme Details', isSelected: false, isCompleted: false, isPending: false },
        { name: 'basic', label: 'Basic Details', isSelected: false, isCompleted: false, isPending: true },
        { name: 'academic', label: 'Academic Details', isSelected: false, isCompleted: false, isPending: true },
        { name: 'exam', label: 'Entrance Exam', isSelected: false, isCompleted: false, isPending: true },
        { name: 'work', label: 'Work Experience', isSelected: false, isCompleted: false, isPending: true },
        { name: 'profile', label: 'Profile Information', isSelected: false, isCompleted: false, isPending: true },
        { name: 'terms', label: 'Terms & Conditions', isSelected: false, isCompleted: false, isPending: true },
        { name: 'payment', label: 'Payment', isSelected: false, isCompleted: false, isPending: true }
    ];

    svgMap = {
        profile: {
            selected: `<svg width="80" height="80" viewBox="0 0 80 80"><circle cx="40" cy="40" r="36" fill="#E8DDF7" stroke="#4B2E83" stroke-width="4"/><circle cx="40" cy="30" r="10" stroke="#4B2E83" stroke-width="4" fill="none"/><path d="M25,58c4-12 14-18 15-18s11,6 15,18" stroke="#4B2E83" stroke-width="4" fill="none"/></svg>`,
            completed: `<svg width="80" height="80" viewBox="0 0 80 80"><circle cx="40" cy="40" r="36" fill="#4B2E83"/><circle cx="40" cy="30" r="10" stroke="white" stroke-width="3" fill="none"/><path d="M25,58c4-12 14-18 15-18s11,6 15,18" stroke="white" stroke-width="3" fill="none"/><circle cx="60" cy="60" r="9" fill="#4CAF50"/><polyline points="56,60 59,63 65,56" stroke="white" stroke-width="3" fill="none" stroke-linecap="round"/></svg>`,
            pending: `<svg width="80" height="80" viewBox="0 0 80 80"><circle cx="40" cy="40" r="36" stroke="#B9AFCF" stroke-width="3" fill="none"/><circle cx="40" cy="30" r="10" stroke="#4B2E83" stroke-width="3" fill="none"/><path d="M25,58c4-12 14-18 15-18s11,6 15,18" stroke="#4B2E83" stroke-width="3" fill="none"/></svg>`
        },
        work: {
            selected: `<svg width="80" height="80" viewBox="0 0 80 80"><circle cx="40" cy="40" r="36" fill="#E8DDF7" stroke="#4B2E83" stroke-width="4"/><rect x="24" y="32" width="32" height="20" rx="3" stroke="#4B2E83" stroke-width="4" fill="none"/><rect x="32" y="26" width="16" height="8" rx="2" stroke="#4B2E83" stroke-width="4" fill="none"/><line x1="24" y1="40" x2="56" y2="40" stroke="#4B2E83" stroke-width="3"/></svg>`,
            completed: `<svg width="80" height="80" viewBox="0 0 80 80"><circle cx="40" cy="40" r="36" fill="#4B2E83"/><rect x="24" y="32" width="32" height="20" rx="3" stroke="white" stroke-width="3" fill="none"/><rect x="32" y="26" width="16" height="8" rx="2" stroke="white" stroke-width="3" fill="none"/><line x1="24" y1="40" x2="56" y2="40" stroke="white" stroke-width="3"/><circle cx="60" cy="60" r="9" fill="#4CAF50"/><polyline points="56,60 59,63 65,56" stroke="white" stroke-width="3" fill="none" stroke-linecap="round"/></svg>`,
            pending: `<svg width="80" height="80" viewBox="0 0 80 80"><circle cx="40" cy="40" r="36" stroke="#B9AFCF" stroke-width="3" fill="none"/><rect x="24" y="32" width="32" height="20" rx="3" stroke="#4B2E83" stroke-width="3" fill="none"/><rect x="32" y="26" width="16" height="8" rx="2" stroke="#4B2E83" stroke-width="3" fill="none"/><line x1="24" y1="40" x2="56" y2="40" stroke="#4B2E83" stroke-width="3"/></svg>`
        },
        program: {
            selected: `<svg width="80" height="80" viewBox="0 0 80 80"><circle cx="40" cy="40" r="36" fill="#E8DDF7" stroke="#4B2E83" stroke-width="4"/><polygon points="40,24 20,32 40,40 60,32" fill="none" stroke="#4B2E83" stroke-width="4"/><line x1="40" y1="40" x2="40" y2="50" stroke="#4B2E83" stroke-width="4"/></svg>`,
            completed: `<svg width="80" height="80" viewBox="0 0 80 80"><circle cx="40" cy="40" r="36" fill="#4B2E83"/><polygon points="40,24 20,32 40,40 60,32" stroke="white" stroke-width="3" fill="none"/><line x1="40" y1="40" x2="40" y2="50" stroke="white" stroke-width="3"/><circle cx="60" cy="60" r="9" fill="#4CAF50"/><polyline points="56,60 59,63 65,56" stroke="white" stroke-width="3" fill="none"/></svg>`,
            pending: `<svg width="80" height="80" viewBox="0 0 80 80"><circle cx="40" cy="40" r="36" stroke="#B9AFCF" stroke-width="3" fill="none"/><polygon points="40,24 20,32 40,40 60,32" stroke="#4B2E83" stroke-width="3" fill="none"/><line x1="40" y1="40" x2="40" y2="50" stroke="#4B2E83" stroke-width="3"/></svg>`
        },
        basic: {
            selected: `<svg width="80" height="80" viewBox="0 0 80 80"><circle cx="40" cy="40" r="36" fill="#E8DDF7" stroke="#4B2E83" stroke-width="4"/><rect x="26" y="22" width="28" height="36" rx="4" stroke="#4B2E83" stroke-width="4" fill="none"/><line x1="30" y1="32" x2="50" y2="32" stroke="#4B2E83" stroke-width="3"/><line x1="30" y1="40" x2="50" y2="40" stroke="#4B2E83" stroke-width="3"/><polygon points="48,48 56,56 58,54 50,46" fill="#4B2E83"/></svg>`,
            completed: `<svg width="80" height="80" viewBox="0 0 80 80"><circle cx="40" cy="40" r="36" fill="#4B2E83"/><rect x="26" y="22" width="28" height="36" rx="4" stroke="white" stroke-width="3" fill="none"/><line x1="30" y1="32" x2="50" y2="32" stroke="white" stroke-width="3"/><line x1="30" y1="40" x2="50" y2="40" stroke="white" stroke-width="3"/><circle cx="60" cy="60" r="9" fill="#4CAF50"/><polyline points="56,60 59,63 65,56" stroke="white" stroke-width="3" fill="none" stroke-linecap="round"/></svg>`,
            pending: `<svg width="80" height="80" viewBox="0 0 80 80"><circle cx="40" cy="40" r="36" stroke="#B9AFCF" stroke-width="3" fill="none"/><rect x="26" y="22" width="28" height="36" rx="4" stroke="#4B2E83" stroke-width="3" fill="none"/><line x1="30" y1="32" x2="50" y2="32" stroke="#4B2E83" stroke-width="3"/><line x1="30" y1="40" x2="50" y2="40" stroke="#4B2E83" stroke-width="3"/></svg>`
        },
        academic: {
            selected: `<svg width="80" height="80" viewBox="0 0 80 80"><circle cx="40" cy="40" r="36" fill="#E8DDF7" stroke="#4B2E83" stroke-width="4"/><path d="M20,28 Q28,24 36,28 V52 Q28,48 20,52 Z" stroke="#4B2E83" stroke-width="4" fill="none"/><path d="M44,28 Q52,24 60,28 V52 Q52,48 44,52 Z" stroke="#4B2E83" stroke-width="4" fill="none"/></svg>`,
            completed: `<svg width="80" height="80" viewBox="0 0 80 80"><circle cx="40" cy="40" r="36" fill="#4B2E83"/><path d="M20,28 Q28,24 36,28 V52 Q28,48 20,52 Z" stroke="white" stroke-width="3" fill="none"/><path d="M44,28 Q52,24 60,28 V52 Q52,48 44,52 Z" stroke="white" stroke-width="3" fill="none"/><circle cx="60" cy="60" r="9" fill="#4CAF50"/><polyline points="56,60 59,63 65,56" stroke="white" stroke-width="3" fill="none" stroke-linecap="round"/></svg>`,
            pending: `<svg width="80" height="80" viewBox="0 0 80 80"><circle cx="40" cy="40" r="36" stroke="#B9AFCF" stroke-width="3" fill="none"/><path d="M20,28 Q28,24 36,28 V52 Q28,48 20,52 Z" stroke="#4B2E83" stroke-width="3" fill="none"/><path d="M44,28 Q52,24 60,28 V52 Q52,48 44,52 Z" stroke="#4B2E83" stroke-width="3" fill="none"/></svg>`
        },
        exam: {
            selected: `<svg width="80" height="80" viewBox="0 0 80 80"><circle cx="40" cy="40" r="36" fill="#E8DDF7" stroke="#4B2E83" stroke-width="4"/><rect x="24" y="24" width="32" height="36" rx="4" stroke="#4B2E83" stroke-width="4" fill="none"/><polyline points="28,32 32,36 40,28" stroke="#4B2E83" stroke-width="4" fill="none"/><polyline points="28,44 32,48 40,40" stroke="#4B2E83" stroke-width="4" fill="none"/></svg>`,
            completed: `<svg width="80" height="80" viewBox="0 0 80 80"><circle cx="40" cy="40" r="36" fill="#4B2E83"/><rect x="24" y="24" width="32" height="36" rx="4" stroke="white" stroke-width="3" fill="none"/><polyline points="28,32 32,36 40,28" stroke="white" stroke-width="3" fill="none"/><polyline points="28,44 32,48 40,40" stroke="white" stroke-width="3" fill="none"/><circle cx="60" cy="60" r="9" fill="#4CAF50"/><polyline points="56,60 59,63 65,56" stroke="white" stroke-width="3" fill="none"/></svg>`,
            pending: `<svg width="80" height="80" viewBox="0 0 80 80"><circle cx="40" cy="40" r="36" stroke="#B9AFCF" stroke-width="3" fill="none"/><rect x="24" y="24" width="32" height="36" rx="4" stroke="#4B2E83" stroke-width="3" fill="none"/><polyline points="28,32 32,36 40,28" stroke="#4B2E83" stroke-width="3" fill="none"/><polyline points="28,44 32,48 40,40" stroke="#4B2E83" stroke-width="3" fill="none"/></svg>`
        },
        terms: {
            selected: `<svg width="80" height="80" viewBox="0 0 80 80"><circle cx="40" cy="40" r="36" fill="#E8DDF7" stroke="#4B2E83" stroke-width="4"/><rect x="24" y="22" width="32" height="36" rx="4" stroke="#4B2E83" stroke-width="4" fill="none"/><line x1="30" y1="32" x2="50" y2="32" stroke="#4B2E83" stroke-width="3"/><line x1="30" y1="40" x2="50" y2="40" stroke="#4B2E83" stroke-width="3"/><line x1="30" y1="48" x2="46" y2="48" stroke="#4B2E83" stroke-width="3"/><circle cx="54" cy="50" r="4" stroke="#4B2E83" stroke-width="2" fill="none"/></svg>`,
            completed: `<svg width="80" height="80" viewBox="0 0 80 80"><circle cx="40" cy="40" r="36" fill="#4B2E83"/><rect x="24" y="22" width="32" height="36" rx="4" stroke="white" stroke-width="3" fill="none"/><line x1="30" y1="32" x2="50" y2="32" stroke="white" stroke-width="3"/><line x1="30" y1="40" x2="50" y2="40" stroke="white" stroke-width="3"/><line x1="30" y1="48" x2="46" y2="48" stroke="white" stroke-width="3"/><circle cx="60" cy="60" r="9" fill="#4CAF50"/><polyline points="56,60 59,63 65,56" stroke="white" stroke-width="3" fill="none" stroke-linecap="round"/></svg>`,
            pending: `<svg width="80" height="80" viewBox="0 0 80 80"><circle cx="40" cy="40" r="36" stroke="#B9AFCF" stroke-width="3" fill="none"/><rect x="24" y="22" width="32" height="36" rx="4" stroke="#4B2E83" stroke-width="3" fill="none"/><line x1="30" y1="32" x2="50" y2="32" stroke="#4B2E83" stroke-width="3"/><line x1="30" y1="40" x2="50" y2="40" stroke="#4B2E83" stroke-width="3"/><line x1="30" y1="48" x2="46" y2="48" stroke="#4B2E83" stroke-width="3"/><circle cx="54" cy="50" r="4" stroke="#4B2E83" stroke-width="2" fill="none"/></svg>`
        },
        payment: {
            selected: `<svg width="80" height="80" viewBox="0 0 80 80"><circle cx="40" cy="40" r="36" fill="#E8DDF7" stroke="#4B2E83" stroke-width="4"/><rect x="22" y="30" width="36" height="24" rx="4" stroke="#4B2E83" stroke-width="4" fill="none"/><rect x="22" y="34" width="36" height="6" fill="#4B2E83"/><path d="M34 48h10 M34 44h8 M34 40h8" stroke="#4B2E83" stroke-width="3"/></svg>`,
            completed: `<svg width="80" height="80" viewBox="0 0 80 80"><circle cx="40" cy="40" r="36" fill="#4B2E83"/><rect x="22" y="30" width="36" height="24" rx="4" stroke="white" stroke-width="3" fill="none"/><rect x="22" y="34" width="36" height="6" fill="white"/><path d="M34 48h10 M34 44h8 M34 40h8" stroke="white" stroke-width="3"/><circle cx="60" cy="60" r="9" fill="#4CAF50"/><polyline points="56,60 59,63 65,56" stroke="white" stroke-width="3" fill="none" stroke-linecap="round"/></svg>`,
            pending: `<svg width="80" height="80" viewBox="0 0 80 80"><circle cx="40" cy="40" r="36" stroke="#B9AFCF" stroke-width="3" fill="none"/><rect x="22" y="30" width="36" height="24" rx="4" stroke="#4B2E83" stroke-width="3" fill="none"/><rect x="22" y="34" width="36" height="6" fill="#4B2E83"/><path d="M34 48h10 M34 44h8 M34 40h8" stroke="#4B2E83" stroke-width="3"/></svg>`
        }
    };

    getStepsWithSvg() {
        return this.steps.map(step => {
            let svg;
            if (step.isSelected) {
                svg = this.svgMap[step.name].selected;
            } else if (step.isCompleted) {
                svg = this.svgMap[step.name].completed;
            } else {
                svg = this.svgMap[step.name].pending;
            }
            return { ...step, svg };
        });
    }

    @api
    get stepList() {
        return this.getStepsWithSvg();
    }
}