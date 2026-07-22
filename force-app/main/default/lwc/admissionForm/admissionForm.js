import { LightningElement, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import submitApplication from '@salesforce/apex/AdmissionController.submitApplication';
import { loadStyle } from 'lightning/platformResourceLoader';
import customCSS from '@salesforce/resourceUrl/CustomCSS';

export default class AdmissionForm extends LightningElement {
    @track formData = {
        Name: '',
        Email: '',
        Phone: '',
        State: '',
        City: '',
        WorkExperience: '',
        CurrentDesignation: '',
        Organization: '',
        HasCompletedGraduation: '',
        College: '',
        HasEntranceScore: '',
        EntranceExamName: '',
        EntranceExamScore: '',
        ReferralSource: '',
        Query: '',
        Captcha: '',
        AgreedToTerms: false,
        Program: 'GMP'
    };

    @track workExperienceOptions = [
        { label: 'Less than 1 year', value: '<1' },
        { label: '1-2 years', value: '1-2' },
        { label: '3-5 years', value: '3-5' },
        { label: '5-10 years', value: '5-10' },
        { label: 'More than 10 years', value: '10+' }
    ];

    @track yesNoOptions = [
        { label: 'Yes', value: 'Yes' },
        { label: 'No', value: 'No' }
    ];

    @track referralSourceOptions = [
        { label: 'Website', value: 'Website' },
        { label: 'Social Media', value: 'Social Media' },
        { label: 'Friend/Family', value: 'Referral' },
        { label: 'Email', value: 'Email' },
        { label: 'Advertisement', value: 'Advertisement' },
        { label: 'Other', value: 'Other' }
    ];

    @track captchaText = '';

    connectedCallback() {
        document.addEventListener("copy", function (evt) {
            evt.clipboardData.setData("text/plain", "");

            evt.preventDefault();
        }, false);
        this.generateCaptcha();

        loadStyle(this, customCSS)
            .then(() => {
                console.log('Custom CSS loaded successfully');
            })
            .catch(error => {
                console.error('Error loading custom CSS:', error);
            });
    }

    generateCaptcha() {
        const chars = '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ';
        let result = '';
        for (let i = 0; i < 6; i++) {
            result += chars.charAt(Math.floor(Math.random() * chars.length));
        }
        this.captchaText = result;
    }

    handleChange(event) {
        const field = event.target.name;
        const value = event.target.type === 'checkbox' ? event.target.checked : event.target.value;
        this.formData = { ...this.formData, [field]: value };
        if (field === 'HasCompletedGraduation') {
            if (value === 'Yes') {
                this.entranceExamOptions = [
                    { label: 'GMAT', value: 'GMAT' },
                    { label: 'GRE', value: 'GRE' },
                    { label: 'CAT', value: 'CAT' },
                    { label: 'XAT', value: 'XAT' },
                    { label: 'Other', value: 'Other' }
                ];
            } else {
                this.entranceExamOptions = [
                    { label: 'N/A', value: 'N/A' }
                ];
                this.formData.EntranceExamName = 'N/A';
            }
        }
    }



    handleSubmit(event) {
        event.preventDefault();

        if (this.formData.Captcha !== this.captchaText) {
            this.showToast('Error', 'The captcha you entered is incorrect', 'error');
            this.generateCaptcha();
            return;
        }

        const allValid = [...this.template.querySelectorAll('lightning-input, lightning-combobox, lightning-radio-group')]
            .reduce((validSoFar, inputField) => {
                inputField.reportValidity();
                return validSoFar && inputField.checkValidity();
            }, true);

        if (!allValid) return;
        console.log('formData', JSON.stringify(this.formData));


        // Submit form
        submitApplication({ formData: JSON.stringify(this.formData) })
            .then(() => {
                this.showToast('Success', 'Your application has been submitted successfully!', 'success');
                this.resetForm();
            })
            .catch(error => {
                this.showToast('Error', error.body.message, 'error');
            });
    }

    resetForm() {
        this.formData = {
            Name: '',
            Email: '',
            Phone: '',
            State: '',
            City: '',
            WorkExperience: '',
            CurrentDesignation: '',
            Organization: '',
            HasCompletedGraduation: '',
            College: '',
            HasEntranceScore: '',
            EntranceExamName: '',
            EntranceExamScore: '',
            ReferralSource: '',
            Query: '',
            Captcha: '',
            AgreedToTerms: false,
            Program: 'GMP'
        };
        this.generateCaptcha();
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({
            title,
            message,
            variant
        }));
    }
}