import { LightningElement, api, track, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { CloseActionScreenEvent } from 'lightning/actions';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { refreshApex } from '@salesforce/apex';
import getLeadDetails from '@salesforce/apex/ConvertB2CLeadController.getLeadDetails';
import convertB2CLead from '@salesforce/apex/ConvertB2CLeadController.convertB2CLead';

export default class ConvertB2CLead extends NavigationMixin(LightningElement) {
    @api recordId;
    
    @track isLoading = true;
    @track isConverting = false;
    @track conversionComplete = false;
    @track isAlreadyConverted = false;
    
    @track leadName = '';
    @track leadEmail = '';
    @track leadPhone = '';
    @track programs = [];
    @track programCount = 0;
    
    @track errorMessage = '';
    @track successMessage = '';
    @track accountId = '';
    @track opportunityCount = 0;
    @track applicationCount = 0;
    
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
                const lead = data.lead;
                this.leadName = lead.Name || '';
                this.leadEmail = lead.Email || '';
                this.leadPhone = lead.Phone || '';
                this.isAlreadyConverted = data.isConverted || false;
                
                this.programs = data.programs || [];
                this.programCount = data.programCount || 0;
            }
            this.isLoading = false;
        } else if (result.error) {
            this.errorMessage = 'Error loading lead details: ' + result.error.body?.message || result.error.message;
            this.isLoading = false;
        }
    }

    get hasPrograms() {
        return this.programs && this.programs.length > 0;
    }

    get isConvertDisabled() {
        return this.isConverting || !this.hasPrograms || this.isAlreadyConverted;
    }

    async handleConvert() {
        this.isConverting = true;
        this.errorMessage = '';
        
        try {
            const result = await convertB2CLead({ leadId: this.recordId });
            
            if (result.isSuccess) {
                this.conversionComplete = true;
                this.successMessage = result.message;
                this.accountId = result.accountId;
                this.opportunityCount = result.opportunityIds ? result.opportunityIds.length : 0;
                this.applicationCount = result.applicationIds ? result.applicationIds.length : 0;
                
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
}