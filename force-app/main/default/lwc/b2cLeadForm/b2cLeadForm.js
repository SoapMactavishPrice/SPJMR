import { LightningElement, track } from 'lwc';
import { createRecord } from 'lightning/uiRecordApi';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { NavigationMixin } from 'lightning/navigation';
import LEAD_OBJECT from '@salesforce/schema/Lead';
import LEAD_FIRSTNAME from '@salesforce/schema/Lead.FirstName';
import LEAD_LASTNAME from '@salesforce/schema/Lead.LastName';
import LEAD_EMAIL from '@salesforce/schema/Lead.Email';
import LEAD_PHONE from '@salesforce/schema/Lead.Phone';
import LEAD_STATUS from '@salesforce/schema/Lead.Status';
import LEAD_COMPANY from '@salesforce/schema/Lead.Company';

export default class B2cLeadForm extends NavigationMixin(LightningElement) {
    @track firstName = '';
    @track lastName = '';
    @track email = '';
    @track phone = '';
    @track company = '';
    @track status = 'Open - Not Contacted';
    @track isSaving = false;
    @track errorMessage = '';

    get statusOptions() {
        return [
            { label: 'Open - Not Contacted', value: 'Open - Not Contacted' },
            { label: 'Working - Contacted', value: 'Working - Contacted' },
            { label: 'Closed - Converted', value: 'Closed - Converted' },
            { label: 'Closed - Not Converted', value: 'Closed - Not Converted' }
        ];
    }

    handleFirstNameChange(event) {
        this.firstName = event.target.value;
        this.clearError();
    }

    handleLastNameChange(event) {
        this.lastName = event.target.value;
        this.clearError();
    }

    handleEmailChange(event) {
        this.email = event.target.value;
        this.clearError();
    }

    handlePhoneChange(event) {
        this.phone = event.target.value;
        this.clearError();
    }

    handleCompanyChange(event) {
        this.company = event.target.value;
        this.clearError();
    }

    handleStatusChange(event) {
        this.status = event.detail.value;
        this.clearError();
    }

    clearError() {
        this.errorMessage = '';
    }

    handleCancel() {
        this.dispatchEvent(
            new CustomEvent('close', {
                bubbles: true,
                composed: true
            })
        );
    }

    async handleSave() {
        // Validate required fields
        const lastNameVal = (this.lastName || '').trim();
        const companyVal = (this.company || '').trim();

        const validationErrors = [];
        
        if (!lastNameVal) {
            validationErrors.push('Last Name is required.');
        }

        if (!companyVal) {
            validationErrors.push('Company is required.');
        }

        // Show validation errors if any
        if (validationErrors.length > 0) {
            this.errorMessage = validationErrors.join(' ');
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Validation Error',
                    message: validationErrors.join(' '),
                    variant: 'error'
                })
            );
            return;
        }

        try {
            this.isSaving = true;
            this.errorMessage = '';

            const leadFields = {};
            leadFields[LEAD_LASTNAME.fieldApiName] = lastNameVal;
            leadFields[LEAD_COMPANY.fieldApiName] = companyVal;
            leadFields[LEAD_STATUS.fieldApiName] = this.status;
            
            if (this.firstName && this.firstName.trim()) {
                leadFields[LEAD_FIRSTNAME.fieldApiName] = this.firstName.trim();
            }
            
            if (this.email && this.email.trim()) {
                leadFields[LEAD_EMAIL.fieldApiName] = this.email.trim();
            }
            
            if (this.phone && this.phone.trim()) {
                leadFields[LEAD_PHONE.fieldApiName] = this.phone.trim();
            }

            // Set RecordTypeId for B2C if available
            // You may need to query for the RecordTypeId in your org
            // For now, we'll create without explicit RecordTypeId

            const leadInput = {
                apiName: LEAD_OBJECT.objectApiName,
                fields: leadFields
            };

            const leadRecord = await createRecord(leadInput);

            // Success — show toast and navigate to detail page
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Success',
                    message: 'B2C Lead created successfully.',
                    variant: 'success'
                })
            );
            
            // Navigate to the Lead detail page
            this[NavigationMixin.Navigate]({
                type: 'standard__recordPage',
                attributes: {
                    recordId: leadRecord.id,
                    objectApiName: 'Lead',
                    actionName: 'view'
                }
            });

            // Dispatch success event to parent
            this.dispatchEvent(
                new CustomEvent('success', {
                    bubbles: true,
                    composed: true
                })
            );

        } catch (error) {
            console.error('Error:', error);

            let errorMsg = 'Unknown error occurred.';
            
            if (error.body) {
                if (Array.isArray(error.body.fieldErrors)) {
                    const fieldErrors = [];
                    Object.keys(error.body.fieldErrors).forEach(field => {
                        error.body.fieldErrors[field].forEach(err => {
                            fieldErrors.push(`${field}: ${err.message}`);
                        });
                    });
                    errorMsg = fieldErrors.length > 0 ? fieldErrors.join(' ') : error.body.message || error.message;
                } else if (error.body.message) {
                    errorMsg = error.body.message;
                } else if (Array.isArray(error.body.pageErrors)) {
                    errorMsg = error.body.pageErrors.map(e => e.message).join(' ');
                }
            } else if (error.message) {
                errorMsg = error.message;
            }

            this.errorMessage = errorMsg;

            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Error',
                    message: errorMsg,
                    variant: 'error'
                })
            );

        } finally {
            this.isSaving = false;
        }
    }
}