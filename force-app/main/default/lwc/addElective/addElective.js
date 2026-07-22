import { LightningElement,api,wire,track } from 'lwc';
import getGradeMap from '@salesforce/apex/addElectiveController.getGradeMap';
import getGradeTerms from '@salesforce/apex/addElectiveController.getGradeTerms';
import getGradeMinor from '@salesforce/apex/addElectiveController.getGradeMinor';
import getLectureList_mandatory from '@salesforce/apex/addElectiveController.getLectureList_mandatory';
import getLectureList_elective from '@salesforce/apex/addElectiveController.getLectureList_elective';
import getMajorLectureList_mandatory from '@salesforce/apex/addElectiveController.getMajorLectureList_mandatory';
import getMajorLectureList_elective from '@salesforce/apex/addElectiveController.getMajorLectureList_elective';
import saveElectiveDataList from '@salesforce/apex/addElectiveController.saveElectiveDataList';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

export default class AddElective extends LightningElement {
    @api recordId;
    grade;
    term;
    totalCredit = 0;
    addedCredit = 0;
    balanceCredit = 0;
    @track gradeOptions;
    @track termOptions;
    @track showSpinner=false;


     connectedCallback() {
        this.showSpinner=true;
         setTimeout(() => {
            this.fetchGrades();
            this.showSpinner=false;
        }, 2000);
        
    }
    @track majorgradeOptions=[];
    @track changeMajorgradeOptions=[];
    @track major;
    fetchGrades() {
        console.log('this.recordId : ',this.recordId);
        getGradeMap({ studentId: this.recordId })
            .then((result) => {
                console.log('getGradeMap result : ',JSON.stringify(result));
                // Map the result to combobox options
                this.gradeOptions = result.map((item) => ({
                    label: item.value,
                    value: item.id,
                    level: item.level
                }));
                this.majorgradeOptions=this.gradeOptions;
                this.major=this.majorgradeOptions[0].value;
                console.log('this.gradeOptions result : ',JSON.stringify(this.gradeOptions));
                console.log('this.gradeOptions result : ',JSON.stringify(this.major));
                console.log('this.gradeOptions result : ',JSON.stringify(this.majorgradeOptions));

                getGradeMinor({programId:this.majorgradeOptions[0].level})
                .then((res)=>{
                    console.log('res ',res);
                    var temp=[];
                    temp = res.map((item) => ({
                        label: item.value,
                        value: item.id
                    }));

                    this.changeMajorgradeOptions = temp.filter(item => item.label !=this.majorgradeOptions[0].label);
                    console.log('this.minorOptions result : ',JSON.stringify(this.changeMajorgradeOptions));
                    
                })
                
            })
            .catch((error) => {
                this.error = error;
                console.error('Error fetching grades:', error);
            });
    }

    
    @track minor;
    @track minorOptions;
    @track isChangeMajor = false;
    handleCheckboxChange(event) {
        this.isChangeMajor = event.target.checked;
        console.log('this.majorgradeOptions[0].level ',this.majorgradeOptions[0].level);
        console.log('this.majorgradeOptions[0].label ',this.majorgradeOptions[0].label);
        
        
    }

    @track minorgradId='';
    handleMinorGradeChange(event) {
        const selectedGradeId = event.detail.value;
        this.minorgradId=event.detail.value;
        console.log('Selected Grade ID:', selectedGradeId);
        this.fetchTerms(selectedGradeId);
    }

   


    @track gradId='';
    @track gradName='';
    handleGradeChange(event) {
        const selectedGradeId = event.detail.value;
        this.gradId=event.detail.value;
        console.log('Selected Grade ID:', selectedGradeId);
        // this.fetchTerms(selectedGradeId);

        getGradeMinor({programId:this.majorgradeOptions[0].level})
        .then((res)=>{
            console.log('res ',res);
            
            this.minorOptions = res.map((item) => ({
                label: item.value,
                value: item.id
            }));

            this.minorOptions = this.minorOptions.filter(item => item.label !=this.majorgradeOptions[0].label && item.value!=this.gradId);
            console.log('this.minorOptions result : ',JSON.stringify(this.minorOptions));
            
        })
    }

    @track major_mandatorytableData=[];
    @track major_electivetableData=[];
    @track mpreselectedRowIds=[];
    @track npreselectedRowIds=[];
    @track majTerm;
    @track minTerm=null;
    
    handleTermChange(event) {
        const selectedTermId = event.detail.value;
        this.minTerm=event.detail.value;
        console.log('Selected Term ID:', selectedTermId);

         // Find the selected Grade in allGrades and get its credit
        const selectedGrade = this.termOptions.find((term) => term.value === selectedTermId);
        const selectedMajorGrade = this.termOptionstemp.find((term) => term.label === selectedGrade.label);
        this.majTerm=selectedMajorGrade.value;
        console.log('OUTPUT : selectedGrade',JSON.stringify(selectedGrade));
        console.log('OUTPUT : selectedMajorGrade',JSON.stringify(selectedMajorGrade));
        if (selectedGrade && selectedMajorGrade) {
            this.totalCredit = selectedGrade.credits+selectedMajorGrade.credits || 0; // Default to 0 if no credit is found
        } else {
            this.totalCredit = 320;
        }
        this.showSpinner=true;
        getLectureList_mandatory({gradeId:this.minorgradId,termId:selectedTermId})
        .then((res)=>{
            console.log('res : ',res);
            this.showSpinner=false;
           
            res.forEach(element => {
                this.addedCredit=this.addedCredit+element.Credits__c;
            });
            
            console.log('this.preselectedRowIds ',JSON.stringify(this.mpreselectedRowIds));
            this.minor_mandatorytableData=res;
            
        })
        .catch((err)=>{
             this.showSpinner=false;
        })

        getLectureList_elective({gradeId:this.minorgradId,termId:selectedTermId})
        .then((res)=>{
            console.log('res : ',res);
            this.showSpinner=false;
            this.minor_electivetableData=res;
        })
        .catch((err)=>{
             this.showSpinner=false;
        })

        // console.log('OUTPUT : this.majorgradeOptions[0].value',JSON.stringify(this.majorgradeOptions[0].value));
        // console.log('OUTPUT : this.majorgradeOptions[0].value',JSON.stringify(selectedMajorGrade.value));
        getMajorLectureList_mandatory({gradeId:this.gradId,termId:selectedMajorGrade.value})
        .then((res)=>{
            console.log('getMinorLectureList : ',res);
            this.showSpinner=false;
            res.forEach(element => {
                this.addedCredit=this.addedCredit+element.Credits__c;
            });
            this.balanceCredit=this.totalCredit-this.addedCredit;
            console.log('this.preselectedRowIds ',JSON.stringify(this.npreselectedRowIds));
            this.major_mandatorytableData=res;

           
        })
        .catch((err)=>{
             this.showSpinner=false;
        })

        getMajorLectureList_elective({gradeId:this.gradId,termId:selectedMajorGrade.value})
        .then((res)=>{
            console.log('getMinorLectureList : ',res);
            this.showSpinner=false;
            this.major_electivetableData=res;
        })
        .catch((err)=>{
             this.showSpinner=false;
        })
         setTimeout(() => {
            this.balanceCredit=this.totalCredit-this.addedCredit;
        }, 2000);
        this.totalCredit=320;

    }
    @track termOptionstemp;
    fetchTerms(gradevar) {
        getGradeTerms({ gradeId: gradevar })
            .then((result) => {
                // Map the result to combobox options
                 console.log('getGradeMap result : ',JSON.stringify(result));
                this.termOptions = result.map((item) => ({
                    label: item.value,
                    value: item.id,
                    credits: item.Total_Credits__c
                }));
                console.log('termOptions result : ',JSON.stringify(this.termOptions));
            })
            .catch((error) => {
                this.error = error;
                console.error('Error fetching terms:', error);
            });

        getGradeTerms({ gradeId: this.gradId })
        .then((result) => {
            // Map the result to combobox options
                console.log('getGradeMap result : ',JSON.stringify(result));
            this.termOptionstemp = result.map((item) => ({
                label: item.value,
                value: item.id,
                credits: item.Total_Credits__c
            }));
            console.log('termOptionstemp result : ',JSON.stringify(this.termOptionstemp));
            this.totalCredit=320;
        })
        .catch((error) => {
            this.error = error;
            console.error('Error fetching terms:', error);
        });

    }

    // gradeOptions = [
    //     { label: 'A', value: 'A' },
    //     { label: 'B', value: 'B' },
    //     { label: 'C', value: 'C' },
    //     { label: 'D', value: 'D' },
    //     { label: 'F', value: 'F' }
    // ];
    // termOptions = [
    //     { label: 'Fall', value: 'Fall' },
    //     { label: 'Spring', value: 'Spring' },
    //     { label: 'Summer', value: 'Summer' }
    // ];

    columnsMan = [
        
        {
            label: 'Lecture Name',
            fieldName: 'Lecture_Name_v1__c',
            type: 'text',
            sortable: true,
            cellAttributes: { alignment: 'left' }, // Align to the start
            // initialWidth: 
        },
        {
            label: 'Credit Assigned',
            fieldName: 'Credits__c',
            type: 'number',
            sortable: true,
            cellAttributes: { alignment: 'left' }, // Align to the start
            initialWidth: 10
        }
    ];

    columnsElec = [
        {
            label: '',
            type: 'checkbox',
            fieldName: 'id',
            sortable: false,
            cellAttributes: { alignment: 'left' }, // Align to the start
            initialWidth: 10
        },
        {
            label: 'Lecture Name',
            fieldName: 'Lecture_Name_v1__c',
            type: 'text',
            sortable: true,
            cellAttributes: { alignment: 'left' }, // Align to the start
            // initialWidth: 
        },
        {
            label: 'Credit Assigned',
            fieldName: 'Credits__c',
            type: 'number',
            sortable: true,
            cellAttributes: { alignment: 'left' }, // Align to the start
            initialWidth: 10
        }
    ];

    @track minor_mandatorytableData = [];
    @track minor_electivetableData = [];

    @track selectedRows='';
    handleRowSelection(event) {
        this.selectedRows = event.detail.selectedRows;
        console.log('Selected Rows:', JSON.stringify(this.selectedRows));
        this.addedCredit = this.addedCredit+this.selectedRows.reduce((acc, row) => acc + row.Credits__c, 0);

        // Recalculate Balance Credit
        this.balanceCredit = this.totalCredit - this.addedCredit;
    }

    updateTotalCredit() {
        if (this.grade && this.term) {
            // Simple example: Set Total Credit based on Grade and Term
            if (this.grade === 'A') {
                this.totalCredit = 4;
            } else if (this.grade === 'B') {
                this.totalCredit = 3;
            } else if (this.grade === 'C') {
                this.totalCredit = 2;
            } else if (this.grade === 'D') {
                this.totalCredit = 1;
            } else {
                this.totalCredit = 0; // For 'F'
            }

            this.balanceCredit = this.totalCredit - this.addedCredit;

        }
    }

    handleSave() {
        this.showSpinner=true;
        if(this.balanceCredit ==0){
        saveElectiveDataList({studId:this.recordId,electiveDataList:this.selectedRows,majorg:this.gradId ,majtermId:this.majTerm,mintermId:this.minTerm,  minorg:this.minorgradId})
        .then((res)=>{
             this.showSpinner=false;
            console.log('OUTPUT : res ',res);
            if(res){
                const evt = new ShowToastEvent({
                    title: 'Success',
                    message: 'Hurry', // Display the error message
                    variant: 'success',
                    mode: 'dismissable', // Toast will be dismissable
                });
                this.dispatchEvent(evt);
                window.location.href='/lightning/r/Account/'+this.recordId+'/view';
            }else{
                this.showErrorToast('Something went wrong!');
            }
        })
        }else{
            this.showErrorToast('Balance Credit should be zero');
            this.showSpinner=false;
        }
        /*if (this.grade && this.term) {
            // Perform save logic here, e.g., call Apex or just log the values
            // console.log('Grade:', this.grade);
            // console.log('Term:', this.term);
            // You can also dispatch a custom event to communicate with the parent component if needed
            //alert(`Saved: Grade: ${this.grade}, Term: ${this.term}`);

        } else {
            //alert('Both Grade and Term are required!');
        }*/



        // const selectedRows = this.template.querySelector('lightning-datatable').getSelectedRows();
        // if (selectedRows.length > 0) {
        //     console.log('Selected Rows to Save:', selectedRows);
        //     alert('Selected rows have been saved.');
        // } else {
        //     alert('Please select at least one row to save.');
        // }
    }

    // Show error toast
    showErrorToast(error) {
        const evt = new ShowToastEvent({
            title: 'Error',
            message: error, // Display the error message
            variant: 'error',
            mode: 'dismissable', // Toast will be dismissable
        });
        this.dispatchEvent(evt);
    }

}