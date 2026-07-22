import { LightningElement, track, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import saveLead from '@salesforce/apex/BrochureFormController.saveLead';
import SPJMIR_logo from '@salesforce/resourceUrl/SPJIMR_Logo';
import { CurrentPageReference } from 'lightning/navigation';
// import getBrochureUrl from '@salesforce/apex/BrochureFormController.getBrochureUrl';
import getBrochureData from '@salesforce/apex/BrochureFormController.getBrochureData';





export default class BrochureForm extends LightningElement {
    @track isModalOpen = true;
    @track isSubmitted = false;
    modalTitle = 'Download Brochure';
    @track courseName;

    @wire(CurrentPageReference)
    getStateFromURL(pageRef) {
        console.log('pageRef', pageRef);
        if (pageRef && pageRef.state && pageRef.state.c__course) {
            this.courseName = pageRef.state.c__course;
        }
        console.log('courseName', this.courseName);

        // if (!this.courseName) {
        //     this.courseName = 'GMP';
        // }
        this.fetchBrochureUrl();

    }

    fetchBrochureUrl() {
        console.log('courseName', this.courseName);
        if (!this.courseName) return;
        getBrochureData({ programCode: this.courseName })
            .then(result => {
                console.log('Brochure Data:', result);
                this.brochureUrl = result.brochureUrl;
                this.brochureThankYouText = result.thankYouText;
            })
            .catch(error => {
                console.error('Error fetching brochure Data', error);
                this.brochureUrl = null;
                this.brochureThankYouText = null;

            });
    }


    @track formData = {
        Name: '',
        Email: '',
        Phone: '',
        State: '',
        City: '',
        Captcha: '',
        LeadSource: 'Website',
        Program: '',
    };

    @track captchaText = '';
    @track imageUrl = SPJMIR_logo;

    connectedCallback() {
        document.addEventListener("copy", function (evt) {
            evt.clipboardData.setData("text/plain", "");

            evt.preventDefault();
        }, false);
        this.generateCaptcha();
        this.isModalOpen = true;
        this.isSubmitted = false;

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
        const value = event.target.value;
        this.formData = { ...this.formData, [field]: value };
    }

    handleSubmit(event) {
        event.preventDefault();

        if (this.formData.Captcha !== this.captchaText) {
            this.showToast('Error', 'Incorrect Captcha. Please try again.', 'error');
            this.generateCaptcha();
            return;
        }

        const allValid = [...this.template.querySelectorAll('lightning-input')]
            .reduce((validSoFar, inputField) => {
                inputField.reportValidity();
                return validSoFar && inputField.checkValidity();
            }, true);

        if (!allValid) return;

        this.formData.Program = this.courseName;
        console.log('formData', JSON.stringify(this.formData));
        saveLead({ leadData: JSON.stringify(this.formData) })
            .then(() => {
                this.showToast('Success', 'Lead created successfully!', 'success');
                this.resetForm();
                this.isSubmitted = true;
                this.modalTitle = 'Thank You';
                // setTimeout(() => {
                //     window.location.href = 'https://www.spjimr.org/wp-content/uploads/2024/05/life-brochure.pdf';
                // }, 5000);
                setTimeout(() => {
                    if (this.brochureUrl) {
                        window.location.href = this.brochureUrl;
                    } else {
                        console.warn('No brochure URL found, redirect skipped');
                    }
                }, 5000);
            })
            .catch(error => {
                this.showToast('Error', error.body?.message || 'Something went wrong', 'error');
            });
    }

    resetForm() {
        this.formData = {
            Name: '',
            Email: '',
            Phone: '',
            State: '',
            City: '',
            Captcha: '',
            LeadSource: 'Website'
        };
        this.generateCaptcha();
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    openModal() {
        this.isModalOpen = true;
    }

    closeModal() {
        this.isModalOpen = false;
    }
}