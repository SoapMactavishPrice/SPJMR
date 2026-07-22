import { LightningElement, api, wire, track } from 'lwc';
import getMajorMap from '@salesforce/apex/AddElectivelwcController.getMajorMap';
import getSamMap from '@salesforce/apex/AddElectivelwcController.getSamMap';
import getMajorLectureList_mandatory from '@salesforce/apex/AddElectivelwcController.getMajorLectureList_mandatory';
import getMajorLectureList_elective from '@salesforce/apex/AddElectivelwcController.getMajorLectureList_elective';
import getCourseOffered from '@salesforce/apex/AddElectivelwcController.getCourseOffered';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { CloseActionScreenEvent } from 'lightning/actions';

export default class AddElectivelwc extends LightningElement {

    @track showSpinner = false;
    @api recordId;
    @track majorValue;
    @track majorName;
    @track majorOptions = [];
    @track semValue;
    @track semName;
    @track semOptions = [];

    @track major_mandatorytableData = [];
    @track major_electivetableData = [];
    @track mpreselectedRowIds = [];
    @track npreselectedRowIds = [];
    @track majTerm;
    @track minTerm = true;

    @track ccOptions = [];
    @track changeCCoptions = [];
    @track ccValue;
    @track ccName;
    @track sectionValue;
    @track sectionName;

    totalCredit = 40;
    addedCredit = 0;
    actualCredit = 0;
    balanceCredit = 0;

    connectedCallback() {
        this.showSpinner = true;
        setTimeout(() => {
            this.handlerGetMajorData();
            // this.showSpinner = false;
        }, 2000);
    }

    handlerGetMajorData() {
        getMajorMap({
            stdId: this.recordId
        }).then((result) => {
            console.log('getMajorMap:>>>> ', result);
            this.majorOptions = result.map((item) => ({
                label: item.name,
                value: item.id,
                sec: item.sec,
                secname: item.secname,
                rId: item.rid
            }));
            this.majorValue = this.majorOptions[0].value;
            this.majorName = this.majorOptions[0].label;
            this.sectionValue = this.majorOptions[0].sec;
            this.sectionName = this.majorOptions[0].secname;

            this.handlerGetSemesterData();

        }).catch((error) => {
            this.error = error;
            console.error('Error In fetching handlerGetData:', error);
        });
    }

    handlerGetSemesterData() {
        getSamMap({
            gId: this.majorOptions[0].rId
        }).then((result) => {
            console.log('getSamMap:>>>> ', result);
            this.semOptions = result.map((item) => ({
                label: item.name,
                value: item.id,
                samId: item.samname
            }));
            this.semValue = this.semOptions[0].value;
            this.semName = this.semOptions[0].label;
            this.handlerGetMandatoryMajorLectureDate();
            this.handlerGetElectiveMajorLectureDate();
            this.handlerGetCourseData();
            console.log(this.majorValue);
            console.log(this.semOptions[0].samId);

        })
    }

    handlerGetCourseData() {
        getCourseOffered({
            gradeId: this.majorValue
        }).then((data) => {
            console.log('getCourseOffered data ', data);
            var temp = [];
            temp = data.map((item) => ({
                label: item.name,
                value: item.id
            }));

            this.ccOptions = temp;
            this.ccValue = this.ccOptions[0].value;
            this.ccName = this.ccOptions[0].label;
            this.changeCCoptions = temp.filter(item => item.label != this.ccOptions[0].label);

            // getAPBS({
            //     rId: this.majorgradeOptions[0].rId
            // }).then((data) => {
            //     this.sectionName = data.Section__r.Name;
            //     this.rollNumberName = data.Roll_No__c;
            // })

        }).catch((error) => {

        })
    }

    columnsMan = [

        {
            label: 'Lecture Name',
            fieldName: 'Lecture_Name_v1__c',
            type: 'text',
            sortable: true,
            cellAttributes: { alignment: 'left' }, // Align to the start
            initialWidth: 300
        },
        {
            label: 'Credit Assigned',
            fieldName: 'Credits__c',
            type: 'number',
            sortable: true,
            cellAttributes: { alignment: 'left' }, // Align to the start
            // initialWidth: 300
        }
    ];

    columnsElec = [
        {
            label: '',
            type: 'checkbox',
            fieldName: 'id',
            sortable: false,
            cellAttributes: { alignment: 'left' }, // Align to the start
            initialWidth: 50
        },
        {
            label: 'Lecture Name',
            fieldName: 'Lecture_Name_v1__c',
            type: 'text',
            sortable: true,
            cellAttributes: { alignment: 'left' }, // Align to the start
            initialWidth: 250
        },
        {
            label: 'Credit Assigned',
            fieldName: 'Credits__c',
            type: 'number',
            sortable: true,
            cellAttributes: { alignment: 'left' }, // Align to the start
            // initialWidth: 10
        }
    ];

    handlerGetMandatoryMajorLectureDate() {
        getMajorLectureList_mandatory({
            gradeId: this.majorValue,
            termId: this.semOptions[0].samId
        }).then((res) => {
            console.log('getMajorLectureList_mandatory : ', res);
            this.showSpinner = false;
            res.forEach(element => {
                this.addedCredit = this.addedCredit + element.Credits__c;
                this.actualCredit = this.actualCredit + element.Credits__c;
            });
            this.balanceCredit = this.totalCredit - this.addedCredit;
            console.log('this.preselectedRowIds ', JSON.stringify(this.npreselectedRowIds));
            this.major_mandatorytableData = res;
        }).catch((err) => {
            this.showSpinner = false;
        })
    }

    handlerGetElectiveMajorLectureDate() {
        getMajorLectureList_elective({
            gradeId: this.majorValue,
            termId: this.semOptions[0].samId
        }).then((res) => {
            console.log('getMajorLectureList_elective : ', res);
            this.showSpinner = false;
            this.major_electivetableData = res;
        }).catch((err) => {
            this.showSpinner = false;
        })
    }


    @track selectedRows = '';
    handleRowSelection(event) {
        this.selectedRows = event.detail.selectedRows;
        console.log('Selected Rows:', JSON.stringify(this.selectedRows));
        this.addedCredit = this.actualCredit + this.selectedRows.reduce((acc, row) => acc + row.Credits__c, 0);

        if (this.addedCredit > this.totalCredit) {
            this.showErrorToast('You cannot add more credit defined as per the Total Credit');
        }

        // Recalculate Balance Credit
        this.balanceCredit = this.totalCredit - this.addedCredit;
        this.balanceCredit = this.balanceCredit < 0 ? 0 : this.balanceCredit;
    }

    handlerOnSave() {
        if (this.addedCredit > this.totalCredit) {
            this.showErrorToast('You cannot add more credit defined as per the Total Credit');
        } else if (this.addedCredit < this.totalCredit) {
            this.showErrorToast('Please select credits as per defined in the Sem');
        } else {
            this.showSpinner = true;
            setTimeout(() => {
                this.showSuccessToast('Data saved successfully!!!');
                this.closeModal('');
                this.showSpinner = false;
            }, 1000);
        }
    }

    // Show error toast
    showErrorToast(error) {
        const evt = new ShowToastEvent({
            title: error,
            message: '', // Display the error message
            variant: 'error',
            mode: 'dismissable', // Toast will be dismissable
        });
        this.dispatchEvent(evt);
    }

    showSuccessToast(msg) {
        const evt = new ShowToastEvent({
            title: msg,
            message: '', // Display the error message
            variant: 'success',
            mode: 'dismissable', // Toast will be dismissable
        });
        this.dispatchEvent(evt);
    }

    closeModal(event) {
        this.dispatchEvent(new CloseActionScreenEvent());
    }

}