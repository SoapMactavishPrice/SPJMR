import { LightningElement, api, track, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { CloseActionScreenEvent } from 'lightning/actions';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { refreshApex } from '@salesforce/apex';
import getLeadDetails from '@salesforce/apex/ConvertB2BLeadController.getLeadDetails';
import convertB2BLead from '@salesforce/apex/ConvertB2BLeadController.convertB2BLead';

const MOU_OPTION_YES = 'yes';
const MOU_OPTION_NO = 'no';

export default class ConvertB2BLead extends NavigationMixin(LightningElement) {
    @api recordId;
    
    /** First step: MOU question. Summary step after Continue. */
    @track showMouStep = true;
    @track mouChoice = null;
    /** Set when user leaves the MOU step; drives preview text and Apex conversion. */
    @track isMouContractRequiredForConversion = false;

    _lastMouResetRecordId;

    mouRadioOptions = [
        { label: 'Yes', value: MOU_OPTION_YES },
        { label: 'No', value: MOU_OPTION_NO }
    ];

    @track isLoading = true;
    @track isConverting = false;
    @track conversionComplete = false;
    @track isAlreadyConverted = false;
    
    @track leadName = '';
    @track leadEmail = '';
    @track companyName = '';
    @track opportunityAmount = '';
    @track minStudents = '';
    @track maxStudents = '';
    @track programs = [];
    @track programCount = 0;
    
    @track errorMessage = '';
    @track successMessage = '';
    @track accountId = '';
    @track opportunityId = '';
    @track createdContractCount = 0;
    
    wiredLeadResult;

    @wire(getLeadDetails, { leadId: '$recordId' })
    wiredLead(result) {
        this.wiredLeadResult = result;
        this.isLoading = true;
        
        if (result.data) {
            const data = result.data;
            
            if (data.error) {
                this.errorMessage = data.error;
            } else {
                if (this.recordId && this._lastMouResetRecordId !== this.recordId) {
                    this._lastMouResetRecordId = this.recordId;
                    this.showMouStep = true;
                    this.mouChoice = null;
                    this.isMouContractRequiredForConversion = false;
                }

                const lead = data.lead;
                this.leadName = lead.Name || '';
                this.leadEmail = lead.Email || '';
                this.companyName = data.company || '';
                this.opportunityAmount = data.opportunityAmount ? '$' + data.opportunityAmount : 'Not specified';
                this.minStudents = data.minStudents || 'Not specified';
                this.maxStudents = data.maxStudents || 'Not specified';
                this.isAlreadyConverted = data.isConverted || false;
                
                this.programs = data.programs || [];
                this.programCount = data.programCount || 0;
            }
            this.isLoading = false;
        } else if (result.error) {
            this.errorMessage = 'Error loading lead details: ' + (result.error.body?.message || result.error.message);
            this.isLoading = false;
        }
    }

    get hasPrograms() {
        return this.programs && this.programs.length > 0;
    }

    get contractCount() {
        if (!this.isMouContractRequiredForConversion) {
            return 0;
        }
        return this.programCount * 2;
    }

    get isMouYes() {
        return this.isMouContractRequiredForConversion === true;
    }

    get opportunityPreviewLine() {
        return this.isMouYes
            ? '1 Opportunity (with main contract linked)'
            : '1 Opportunity';
    }

    get isMouContinueDisabled() {
        return this.mouChoice !== MOU_OPTION_YES && this.mouChoice !== MOU_OPTION_NO;
    }

    get isConvertDisabled() {
        return this.isConverting || !this.hasPrograms || this.isAlreadyConverted;
    }

    handleMouChoiceChange(event) {
        this.mouChoice = event.detail.value;
    }

    handleMouContinue() {
        this.isMouContractRequiredForConversion = this.mouChoice === MOU_OPTION_YES;
        this.showMouStep = false;
    }

    async handleConvert() {
        this.isConverting = true;
        this.errorMessage = '';
        
        try {
            const result = await convertB2BLead({
                leadId: this.recordId,
                isMouContractRequired: this.isMouContractRequiredForConversion === true
            });
            
            if (result.isSuccess) {
                this.conversionComplete = true;
                this.successMessage = result.message;
                this.accountId = result.accountId;
                this.opportunityId = result.opportunityId;
                this.createdContractCount = result.contractIds ? result.contractIds.length : 0;
                
                this.dispatchEvent(
                    new ShowToastEvent({
                        title: 'Success',
                        message: result.message,
                        variant: 'success'
                    })
                );
                
                await refreshApex(this.wiredLeadResult);
                
            } else {
                this.errorMessage = result.message;
                this.dispatchEvent(
                    new ShowToastEvent({
                        title: 'Conversion Failed',
                        message: result.message,
                        variant: 'error'
                    })
                );
            }
        } catch (error) {
            this.errorMessage = error.body?.message || error.message || 'An unexpected error occurred';
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Error',
                    message: this.errorMessage,
                    variant: 'error'
                })
            );
        } finally {
            this.isConverting = false;
        }
    }

    handleCancel() {
        this.dispatchEvent(new CloseActionScreenEvent());
    }

    navigateToAccount() {
        if (this.accountId) {
            this[NavigationMixin.Navigate]({
                type: 'standard__recordPage',
                attributes: {
                    recordId: this.accountId,
                    objectApiName: 'Account',
                    actionName: 'view'
                }
            });
        }
    }

    navigateToOpportunity() {
        if (this.opportunityId) {
            this[NavigationMixin.Navigate]({
                type: 'standard__recordPage',
                attributes: {
                    recordId: this.opportunityId,
                    objectApiName: 'Opportunity',
                    actionName: 'view'
                }
            });
        }
    }
}