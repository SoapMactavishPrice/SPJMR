import { LightningElement, api } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import SlotSchedulerModal from 'c/slotSchedulerModal';
import { updateRecord } from 'lightning/uiRecordApi';
import APPLICATION_STATUS from '@salesforce/schema/Application__c.Application_Status__c'
import APPLICATION_INIT_DATE_TIME from '@salesforce/schema/Application__c.ApplicationInitDtTime__c';
import ID_FIELD from '@salesforce/schema/Application__c.Id'
import checkUserValidity from '@salesforce/apex/ApAccountProgramController.checkUserValidity'
export default class AllApplicationsGrid extends NavigationMixin(LightningElement) {

    _tableData = [];
    showInterview=true
    showAction=true
    showStage=true
    @api
    get tableData() {
        return this._tableData;
    }

    set tableData(value) {
        if (value && Array.isArray(value)) {
            this._tableData = value.map(row => {

                const hideWorkflowColumns =
                    row.isDecisionPresent || row.isRejected;

                return {
                    ...row,
                    hideAction: hideWorkflowColumns,
                    hideInterview: hideWorkflowColumns,
                    hideStage: hideWorkflowColumns,
                    bookingInfoString: row.bookingInfo
                        ? JSON.stringify(row.bookingInfo)
                        : null
                };
            });
        }

    }

    @api tableLabel;

  async handleAction(event) {
    const programCode = event.currentTarget.dataset.programCode;
    const actionName = event.currentTarget.dataset.actionName;
    const appId = event.currentTarget.dataset.applicationId;
    const stageName = event.currentTarget.dataset.stageName;

    const blockedActions = [
        'disabled',
        'notAvailable'
    ];

    if (blockedActions.includes(actionName)) {
        return;
    }


    if (actionName === 'applyNow' && appId) {
        // Find the row to check current status
        const row = this._tableData.find(r => r.applicationId === appId);
        const isFirstClick = !row?.applicationStatus || row.applicationStatus === '';

        if (isFirstClick) {
            const fields = {};
            fields[ID_FIELD.fieldApiName] = appId;
            fields[APPLICATION_STATUS.fieldApiName] = 'Initiated';
            fields[APPLICATION_INIT_DATE_TIME.fieldApiName] = new Date().toISOString();
            try {
                await updateRecord({ fields });
                console.log('Application Status set to Initiated');
            } catch (error) {
                console.log('Error Updating Application', JSON.stringify(error));
            }
        }
    }

    this[NavigationMixin.Navigate]({
        type: 'comm__namedPage',
        attributes: {
            name: 'ApplicationForm_1__c'
        },
        state: {
            applicationId: appId
        }
    });
}

    async handleSchedule(event) {
        const bookingInfoStr = event.currentTarget.dataset.bookinginfo;
        const bookingInfo = bookingInfoStr ? JSON.parse(bookingInfoStr) : null;

        console.log('Parsed booking info:', JSON.stringify(bookingInfo));

        const programCode = event.currentTarget.dataset.programCode;

        const result = await SlotSchedulerModal.open({
            size: 'small',
            description: 'Schedule your interview',
            programCode,
            bookingInfo
        });

        if (result === 'booked') {
            this.dispatchEvent(new CustomEvent('slotscheduled'));
        }
    }
}