import { LightningElement, track, wire, api } from 'lwc';
import getProgramsForLoggedInUser from '@salesforce/apex/ApAccountProgramController.getProgramsForLoggedInUser';
import { NavigationMixin } from 'lightning/navigation';
import { CurrentPageReference } from 'lightning/navigation';
import { refreshApex } from '@salesforce/apex';

import fetchMetadataBulk from '@salesforce/apex/ApplicationFormController.fetchMetadataBulk';

const STATES = {
    APPLY: 'APPLY',
    EDIT: 'EDIT',
    VIEW: 'VIEW',
    NOT_AVAILABLE: 'NOT_AVAILABLE',
    DISABLED: 'DISABLED'
};

const ACTION_CONFIG = {
    VIEW: {
        key: 'view',
        label: 'View',
        title: 'Continue to Application',
        iconName: 'utility:preview',
        variant: 'neutral'
    },

    EDIT: {
        key: 'edit',
        label: 'Edit',
        title: 'Continue to Application',
        iconName: 'utility:edit',
        variant: 'brand'
    },

    APPLY: {
        key: 'applyNow',
        label: 'Apply Now',
        title: 'Apply Now',
        iconName: 'utility:add',
        variant: 'brand'
    },

    NOT_AVAILABLE: {
        key: 'notAvailable',
        label: 'Application not open yet',
        title: 'Application for this programme is not open yet',
        iconName: 'utility:block_visitor',
        variant: 'neutral',
        disabled: true
    },

    DISABLED: {
        key: 'disabled',
        label: 'Application Closed',
        title: 'Application for this programme is closed',
        iconName: 'utility:lock',
        variant: 'neutral',
        disabled: true
    }
};

export default class ApAccountPrograms extends NavigationMixin(LightningElement) {
    @track data = [];
    @track error;
    notificationCount = 0;
    showCustomMessage = false;
    showApplication = false;
    programCode = '';
    showApplist = true;
    isValidApplicant = true;

    metadataPromise;

    async doShowApplication(event) {
        this.programCode = event.detail;
        this.showApplist = false;
        this.showApplication = true;
    }

    doShowAppList() {
        this.showApplication = false;
        this.showApplist = true;
        this.refreshData();
    }

    slotScheduled() {
        this.refreshData();
    }

    @api cmpLabel = 'Dashboard';

    wiredResult;

    @wire(getProgramsForLoggedInUser)
    async wiredPrograms(result) {
        this.wiredResult = result;
        const blockActionsByProgram =
            await this.loadBlockActionsConfig();

        console.log('blockActionsByProgram ' +JSON.stringify(blockActionsByProgram));
        let appIds = [];

        if (result.data) {
            if (!result.data.length > 0) {
                this.error = 'No data found';
                this.data = [];
                return;
            }

            this.data = result.data.map(item => {
                const blockActions =
                    blockActionsByProgram[item.programCode] === true;

                console.log(
                    'Program Code:',
                    item.programCode,
                    'Block Config:',
                    blockActionsByProgram[item.programCode],
                    'Block Actions:',
                    blockActions
                );

                return {
                    ...item,
                    blockActions,
                    actionModel: this.buildActionModel(item)
                };
            });

            this.data.forEach(item => {
                appIds.push(item?.applicationId ? item.applicationId : '');
            });

            this.error = undefined;
            console.log('ApAccountPrograms', JSON.stringify(this.data));

        } else if (result.error) {
            this.error = result.error.body.message;
            console.log('error', JSON.stringify(this.error));
            this.data = [];
        }
    }

    async loadBlockActionsConfig() {
        if (!this.metadataPromise) {
            this.metadataPromise = (async () => {
                try {
                    const metadataResponse = await fetchMetadataBulk({
                        requests: [
                            {
                                metadataName: 'ApplicationProgramBasedConfig__mdt',
                                fields: [
                                    'Intent__c',
                                    'ProgramCode__c',
                                    'Type__c',
                                    'ConfigValue__c'
                                ],
                                filters: [
                                    {
                                        field: 'Intent__c',
                                        operator: '=',
                                        value: 'BlockApplicationActions'
                                    }
                                ]
                            }
                        ]
                    });

                    const blockActionsByProgram = {};

                    const records =
                        metadataResponse?.ApplicationProgramBasedConfig__mdt || [];

                    records.forEach(rec => {
                        if (
                            rec.Type__c === 'Boolean' &&
                            rec.ConfigValue__c != null
                        ) {
                            const programCode =
                                rec.ProgramCode__c?.trim().toUpperCase();

                            if (programCode) {
                                blockActionsByProgram[programCode] =
                                    rec.ConfigValue__c.trim().toLowerCase() === 'true';
                            }
                        }
                    });

                    console.log(
                        'blockActionsByProgram',
                        JSON.stringify(blockActionsByProgram)
                    );

                    return blockActionsByProgram;

                } catch (error) {
                    console.error(
                        'Error fetching BlockApplicationActions metadata',
                        error
                    );

                    return {};
                }
            })();
        }

        return await this.metadataPromise;
    }

    buildActionModel(item) {

        const primaryState =
            this.resolvePrimaryActionState(item);

        return {
            primaryState,
            acceptanceStatus: item?.applicationAcceptanceStatus,
            primaryAction:
                this.getPrimaryActionConfig(
                    primaryState,
                    item?.applicationAcceptanceStatus
                ),
            secondaryActions:
                this.resolveSecondaryActions(item,primaryState)
        };
    }

    getPrimaryActionConfig(state, acceptanceStatus) {

        if (state === STATES.DISABLED) {

            if (acceptanceStatus === 'Too Early') {
                return {
                    key: 'disabled',
                    label: 'Apply Now',
                    title: 'Application for this programme is not open yet',
                    variant: 'neutral',
                    disabled: true
                };
            }

            if (acceptanceStatus === 'Closed') {
                return {
                    key: 'disabled',
                    label: 'Application Closed',
                    title: 'Application for this programme is closed',
                    variant: 'neutral',
                    disabled: true
                };
            }
        }

        return ACTION_CONFIG[state];
    }

    resolvePrimaryActionState(row) {
        if (row?.applyString === 'Not Published') {
            return STATES.NOT_AVAILABLE;
        }

        if (row?.applicationAcceptanceStatus === 'Too Early' || row?.applicationAcceptanceStatus === 'Closed') {
            return STATES.DISABLED;
        }

        if (row?.assignmentStatus === 'Change Requested')
            return STATES.EDIT;
        
        if (row?.applicationStatus === 'Paid' || row?.applicationAcceptanceStatus === 'Paid') {
            return STATES.VIEW;
        }

        if (!row?.applicationStatus) {
            return STATES.APPLY;
        }

        switch (row?.applicationStatus) {
            case 'Initiated':
            case 'In Progress':
            case 'Submitted':
            case 'Unpaid':
                return STATES.EDIT;

            case 'Paid':
                return STATES.VIEW;

            default:
                return STATES.VIEW;
        }
    }

    resolveSecondaryActions(item, primaryState) {

        const actions = [];

        if (item?.applicationId && (primaryState === STATES.EDIT || primaryState === STATES.VIEW)) {
            actions.push({
                key: 'previewPdf',
                label: 'Preview PDF',
                iconName: 'utility:preview',
                variant: 'neutral'
            });
        }

        return actions;
    }

    @wire(CurrentPageReference)
    setCurrentPageReference(pageRef) {
        if (pageRef) {
            this.refreshData();
        }
    }

    refreshData() {
        if (this.wiredResult?.data) {
            refreshApex(this.wiredResult);
        }
    }
}