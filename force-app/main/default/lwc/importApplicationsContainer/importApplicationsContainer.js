import { LightningElement } from 'lwc';

export default class ImportApplicationsContainer extends LightningElement {

    selectedOption = '';

    options = [
        {
            label: 'Profile Shortlist / Applicant State Management',
            value: 'profileShortlist'
        },
        {
            label: 'Offer Generation',
            value: 'offerGeneration'
        }
    ];

    get showSelectionMessage() {
        return !this.selectedOption;
    }

    handleOptionChange(event) {
        this.selectedOption = event.detail.value;
    }

    get showApplicantStateManagement() {
        return this.selectedOption === 'profileShortlist';
    }

    get showOfferGeneration() {
        return this.selectedOption === 'offerGeneration';
    }
}