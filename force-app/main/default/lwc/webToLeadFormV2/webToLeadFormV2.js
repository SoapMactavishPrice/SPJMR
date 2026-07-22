import { LightningElement, track, wire } from 'lwc';
import verifyToken from '@salesforce/apex/LeadWebFormHelper.verifyToken';
import { CurrentPageReference } from 'lightning/navigation';
import getVisibilityConfig from '@salesforce/apex/LeadWebFormHelper.getVisibilityConfig'
import submitForm from '@salesforce/apex/LeadWebFormHelper.submitForm'
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
export default class WebToLeadFormV2 extends LightningElement {

    @track config = {};
    programCode;

    @wire(CurrentPageReference)
    getStateParameters(currentPageReference) {
        if (currentPageReference) {
            this.programCode = currentPageReference.state?.programCode || 'GMP';
            console.log('Program Code:', this.programCode);
        }
    }

    // 🔹 Fetch metadata based on programCode
    @wire(getVisibilityConfig, { programCode: '$programCode' })
    wiredConfig({ data, error }) {
        if (!this.programCode) return; // 🛑 IMPORTANT

        if (data) {
            console.log('RAW DATA:', data);

            this.config = { ...data }; // force reactivity

            console.log('FINAL CONFIG:', JSON.stringify(this.config));
        } else if (error) {
            console.error(error);
        }
    }


    get graduationOptions() {
        return [
            { label: 'Yes', value: 'Yes' },
            { label: 'No', value: 'No' }
        ];
    }

    get workOptions() {
        return [
            { label: '0-2', value: '0-2' },
            { label: '2-3', value: '2-3' },
            { label: '3+', value: '3+' }
        ];
    }
    get countryCodes(){
        return [
            { label: '+91 India', value: '+91' },
            { label: 'USA', value: 'USA' },
            { label: 'UK', value: 'UK' }
        ];
    }

    get yesNoOptions() {
        return [
            { label: 'Yes', value: 'Yes' },
            { label: 'No', value: 'No' }
        ];
    }

    get examOptions() {
        return [
            { label: 'CAT', value: 'CAT' },
            { label: 'GMAT', value: 'GMAT' },
            { label: 'GRE', value: 'GRE' }
        ];
    }

    get showGraduation() {
        return !!this.config?.Graduation__c;
    }

    get showWorkExperience() {
        console.log(this.config?.Work_Experience__c + ' is work xp ')
        return !!this.config?.Work_Experience__c;
    }

    get showEntranceExam() {
        return !!this.config?.Entrance_Exam__c;
    }

    get showEntranceExamName() {
        return !!this.config?.Entrance_Exam_Name__c;
    }

    get showEntranceExamScores() {
        return !!this.config?.Entrance_Exam_Scores__c;
    }

    get showPartnerCompany() {
        return this.config?.SPJIMRPartnerCompany__c;
    }

    get showCurrentEmployer() {
        return this.config?.Current_Employer__c;
    }

    get showCourse() {
        return this.config?.Course__c === true;
    }

    get showCurrentOrganization() {
        return this.config?.Current_Organization__c === true;
    }

    get showCountry() {
        return this.config?.Country__c === true;
    }

    get showCurrentDesignation() {
        return this.config?.Current_Designation__c === true;
    }

    get showInterestedProgramme() {
        return this.config?.Interested_Programme__c === true;
    }

    get showSource() {
        return this.config?.Source__c === true;
    }

    get showDesignation() {
        return this.config?.Designation__c === true;
    }

    get showQuery() {
        return this.config?.Query__c === true;
    }


    @track isTokenUnsuccessful = false;
    @track isErrorVerifyToken = false;
    @track isErrorGeneratingToken = false;
    @track tokenError = '';
    @track isSussessfulCreate = false;
    @track successMessage = '';
    siteKey = '6LdIKZcsAAAAAG5gjqUp-WmC7FHhpI6S-OC65bIO';


    handleClick() {
        let formData = {};
        console.log('Clicked Button')
        this.isTokenUnsuccessful = false;
        this.isErrorVerifyToken = false;
        this.isErrorGeneratingToken = false;
        this.tokenError = '';
        //Reset seccuss flag
        this.isSussessfulCreate = false;
        this.successMessage = '';


        let isValid = true;

        // Get all inputs + combobox + textarea
        const allFields = this.template.querySelectorAll(
            'lightning-input, lightning-combobox, lightning-textarea'
        );

        allFields.forEach(field => {

            // 🔥 Skip hidden fields
            if (!field.offsetParent) return;

            let value = field.value;

            if (field.type === 'checkbox') {
                value = field.checked;
            }

            // Validation
            if (!value || value === '') {
                field.setCustomValidity('This field is required');
                isValid = false;
            } else {
                field.setCustomValidity('');
            }

            field.reportValidity();
            if (field.name) {
            formData[field.name] = value;

            console.log('FORM DATA:', JSON.stringify(formData));
        }
        });

        if (!isValid) {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Error',
                    message: 'Please fill all required fields',
                    variant: 'error'
                })
            );
            return;
        }

        /* google recaptcha logic start */
        grecaptcha.execute('6LeF5JcsAAAAAPnCmAG2tIOourv2V3etCcFiq_rP', { action: 'submit' })//Replace your SITE_KEY
            .then(token => {
                //If you want to see the token, uncomment below line 
                console.log('Token->>>>', token);
                // Send the token to your Apex controller for verification
                verifyToken({
                    token: token
                })
                    .then(result => {
                        // Handle the result from Apex
                        if (result.success) {
                            // Verification successful, implement your business logic here
                            console.log('Captcha Success')
                            console.log('Form Data is '+JSON.stringify(formData))
                            submitForm({ formData: formData, programCode: this.programCode })
                                .then((result) => {
                                    this.dispatchEvent(
                                        new ShowToastEvent({
                                            title: 'Success',
                                            message: result,
                                            variant: 'success'
                                        })
                                    );
                                })
                                .catch(error => {
                                    console.error(error);
                                    this.dispatchEvent(
                                        new ShowToastEvent({
                                            title: 'Error',
                                            message: error.body?.message || 'Something went wrong',
                                            variant: 'error'
                                        })
                                    );
                                });
                        } else {
                            // Token verification unsucessful, display an error message
                            this.isTokenUnsuccessful = true;
                            this.isErrorVerifyToken = false;
                            this.isErrorGeneratingToken = false;
                            this.tokenError = 'Token verification unsuccessful->>>>' + result.message;
                        }
                    })
                    .catch(error => {
                        // Handle any error verify token from Apex
                        this.isTokenUnsuccessful = false;
                        this.isErrorVerifyToken = true;
                        this.isErrorGeneratingToken = false;
                        this.tokenError = 'Error verify token->>>>' + error.body.message;
                    });
            })
            .catch(error => {
                //Handle error generating token
                this.isTokenUnsuccessful = false;
                this.isErrorVerifyToken = false;
                this.isErrorGeneratingToken = true;
                this.tokenError = 'reCAPTCHA token generation error->>>>' + error;
            });
        /* google recaptcha logic end */


    }



}