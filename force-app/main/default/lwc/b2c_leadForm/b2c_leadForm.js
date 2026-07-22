import { LightningElement, wire,track } from 'lwc';
import LEAD_OBJECT from '@salesforce/schema/Lead';
import { getObjectInfo, getPicklistValuesByRecordType } from 'lightning/uiObjectInfoApi';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { getRecord } from 'lightning/uiRecordApi';
import { CloseActionScreenEvent } from 'lightning/actions';
import NAME_FIELD from '@salesforce/schema/Program.Name';
export default class B2c_leadForm extends LightningElement {

    recordTypeId;
    selectedProgramId;
    programName;
    firstName = '';
    lastName = '';
    email = '';
    mobile = '';
    partnerCompany='';
    isStateSelected = false
    isCountrySelected = false
    country = '';
    state = '';
    city = '';
    showB2C = false;
    modalTitle = 'New Lead: B2C'
    isWorkingProfessional = '';
    graduationStatus = 'Yes';
    findAboutUs=''
    organization = '';
    designation = '';
    selectedPrograms=[];
    age='';
    college = '';
    yearOfGraduation = '';
    currentlyStudyingIn = '';


    countryOptions = [];
    stateOptions = [];
    cityOptions = [];
    workExpYears = ''
    allStateValues = [];
    allCityValues = [];
entranceExamStatus = 'No';


@track entranceExams = [
    { id: 1, examName: '', score: '' }
];

get showEntranceSection() {
    return this.entranceExamStatus === 'Yes';
}

    yesNoOptions = [
        { label: 'Yes', value: 'Yes' },
        { label: 'No', value: 'No' }
    ];


    get showCompanySection() {
        return this.isWorkingProfessional === 'Yes';
    }
    get hasSelectedPrograms() {
        return this.selectedPrograms && this.selectedPrograms.length > 0;
    }

    get showGraduationCompleted() {
        return this.graduationStatus === 'Yes';
    }

    get showCurrentlyStudying() {
        return this.graduationStatus === 'No';
    }


    @wire(getObjectInfo, { objectApiName: LEAD_OBJECT })
    objectInfoHandler({ data, error }) {
        if (data) {
            this.recordTypeId = data.defaultRecordTypeId;
        }
        else if(error){
            console.error('Error Fetching Lead Object Info '+JSON.stringify(error));
        }
    }

    @wire(getPicklistValuesByRecordType, { objectApiName: LEAD_OBJECT, recordTypeId: '$recordTypeId' })
    picklistHandler({ data, error }) {
        if (data) {
            this.countryOptions = data.picklistFieldValues.Country__c.values;

            this.allStateValues = data.picklistFieldValues.State__c.values || [];
            this.allCityValues = data.picklistFieldValues.City__c.values || [];

            this.stateOptions = [];
            this.cityOptions = [];
        }
        else if(error){
            console.error('Error Fetching Picklist Values '+JSON.stringify(error));
        }
    }

    @wire(getRecord, { recordId: '$selectedProgramId', fields: [NAME_FIELD] })
    wiredProgram({ data, error }) {
        if (data) {
            this.programName = data.fields.Name.value;
        } else if (error) {
            console.error('Error Fetching Program name '+JSON.stringify(error));
        }
    }

    handleExamChange(event) {
    const index = Number(event.target.dataset.index);
    const field = event.target.name;
    const value = event.target.value;

    this.entranceExams[index][field] = value;
    this.entranceExams = [...this.entranceExams];
}

handleB2CPreview(){
    this.showB2C = true;
}

handleAddExam() {
    const newId = Date.now();

    this.entranceExams = [
        ...this.entranceExams,
        { id: newId, examName: '', score: '' }
    ];
}

handleRemoveExam(event) {
    const index = Number(event.target.dataset.index);

    if (this.entranceExams.length > 1) {
        this.entranceExams.splice(index, 1);
        this.entranceExams = [...this.entranceExams];
    }
}

    handleInputChange(event) {
        const field = event.target.name;
        const value = event.target.value;

        this[field] = value;
        console.log('Field is ', field)
    }

    handleAddProgram(){
        if (!this.selectedProgramId) {
            this.showToast('Info', 'Please search and select a program to add.', 'info');
            return;
        }
        console.log('Adding Program ',this.programName)
        const alreadyAdded = this.selectedPrograms.some(p => p.id === this.selectedProgramId);
        if (alreadyAdded) {
            this.showToast('Info', 'This program is already added.', 'info');
            this.clearProgramPicker();
            return;
        }

        // If name not yet fetched, fetch it now
        let programName = this.programName;
        

        this.selectedPrograms = [
            ...this.selectedPrograms,
            {
                id: this.selectedProgramId,
                name: programName || 'Program'
            }
        ];
        
        this.clearProgramPicker();

    }



    clearProgramPicker() {
        this.selectedProgramId = null;
        this.selectedProgramName = '';
        const recordPickers = this.template.querySelectorAll('lightning-record-picker');
        recordPickers.forEach(picker => {
            picker.clearSelection();
        });
    }
     handleRemoveProgram(event) {
        const programId = event.currentTarget.dataset.id;
        this.selectedPrograms = this.selectedPrograms.filter(p => p.id !== programId);
    }

    handleProgramRecordChange(event) {
     this.selectedProgramId = event.detail.recordId;
    this.programName = event.detail.record?.fields?.Name?.value;
    console.log('Program Id is', this.selectedProgramId)
    }

    handleCancel(){
        this.showB2C = false
        // this.dispatchEvent(new CloseActionScreenEvent())
    }

    handleCreateLead(){

    }

    handleComboChange(event) {
        const field = event.target.name;
        const value = event.detail.value;
        console.log('Field is ', field)
        console.log('Value is ', value)
        switch (field) {
            case 'country':
                this.country = value;
                this.state = '';
                this.city = '';
                this.isCountrySelected = true
                this.isStateSelected = false
                this.stateOptions = this.allStateValues;
                this.cityOptions = [];
                break;

            case 'state':
                this.state = value;
                this.city = '';
                this.cityOptions = this.allCityValues;
                this.isStateSelected = true
                break;

            case 'city':
                this.city = value;
                break;
            case 'workingProfessional':
                this.isWorkingProfessional = value;
                if (value === 'No') {
                    this.organization = '';
                    this.designation = '';
                }
                break;

            case 'graduationStatus':
                this.graduationStatus = value;
                this.college = '';
                this.yearOfGraduation = '';
                this.currentlyStudyingIn = '';
                break;

            case 'entranceExamStatus':
        this.entranceExamStatus = value;

        if (value === 'No') {
            this.entranceExams = [
                { id: 1, examName: '', score: '' }
            ];
    }
    break;
        }
    }

     showToast(title, message, variant) {
        this.dispatchEvent(
            new ShowToastEvent({
                title: title,
                message: message,
                variant: variant
            })
        );
    }
}