import { LightningElement, api, track } from 'lwc';
import getCurrentUserRole from '@salesforce/apex/LeaveApprovalActionController.getCurrentUserRole';
import processLeaveAction from '@salesforce/apex/LeaveApprovalActionController.processLeaveAction';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

export default class LeaveApprovalActionPanel extends LightningElement {

    @api recordId;

    @track role;
    @track decision;
    @track routeToDeputy = false;
    @track remarks = '';
    @track isLoading = false;

    // 🔥 Manager extra checkboxes
    @track eligibleForMakeup = false;
    @track notEligibleForMakeup = false;
    @track incomplete = false;

    connectedCallback(){
        this.loadRole();
    }

    // ================= LOAD ROLE =================

    loadRole(){
        getCurrentUserRole({ leaveId: this.recordId })
        .then(result => {
            this.role = result;
        })
        .catch(error => {
            console.error(error);
            this.showToast('Error','Unable to load role','error');
        });
    }

    // ================= ROLE CHECKS =================

    get isProgrammeOffice(){
        return this.role === 'Programme Office';
    }

    get isManager(){
        return this.role === 'Manager';
    }

    get isDeputy(){
        return this.role === 'Deputy Chairperson';
    }

    get isManagerOrDeputy(){
        return this.isManager || this.isDeputy;
    }

    get isRouteDisabled(){
        return this.decision !== 'Approved';
    }

    // ================= OPTIONS =================

    // 🟣 Programme Office radio options
    get poDecisionOptions(){
        return [
            { label: 'Approve & Forward', value: 'APPROVE_FORWARD' },
            { label: 'Reject', value: 'REJECT' }
        ];
    }

    // 🔘 Manager radio options
    get mainDecisionOptions(){
        return [
            { label: 'Approved (Sanctioned Leave)', value: 'Approved' },
            { label: 'Not Approved', value: 'Not Approved' }
        ];
    }

    // ================= PROGRAMME OFFICE =================

    handlePODecision(event){
        this.decision = event.detail.value;
    }

    // ================= MANAGER / DEPUTY =================

    handleDecision(event){
        this.decision = event.detail.value;

        // Reset route if not Approved
        if(this.decision !== 'Approved'){
            this.routeToDeputy = false;
        }
    }

    handleEligible(event){
        this.eligibleForMakeup = event.target.checked;
    }

    handleNotEligible(event){
        this.notEligibleForMakeup = event.target.checked;
    }

    handleIncomplete(event){
        this.incomplete = event.target.checked;
    }

    handleDeputy(event){
        this.routeToDeputy = event.target.checked;
    }

    handleRemarks(event){
        this.remarks = event.target.value;
    }

    // ================= MAIN ACTION =================

    handleProcess(){

        if(this.isLoading){
            return;
        }

        // 🔴 Validation
        if(!this.remarks || this.remarks.trim() === ''){
            this.showToast('Error','Remarks are required','error');
            return;
        }

        if(this.isProgrammeOffice && !this.decision){
            this.showToast('Error','Please select Approve or Reject','error');
            return;
        }

        if(this.isManagerOrDeputy && !this.decision){
            this.showToast('Error','Please select a decision','error');
            return;
        }

        if(this.routeToDeputy && this.decision !== 'Approved'){
            this.showToast('Error','Route to Deputy allowed only when Approved','error');
            return;
        }

        this.isLoading = true;

        processLeaveAction({
            leaveId: this.recordId,
            decision: this.decision,
            routeToDeputy: this.routeToDeputy,
            remarks: this.remarks
        })
        .then(() => {
            this.showToast('Success','Processed successfully','success');

            setTimeout(() => {
                window.location.reload();
            }, 800);
        })
        .catch(error => {
            console.error(error);

            let message = 'Processing failed';

            if(error?.body?.message){
                message = error.body.message;
            } else if(Array.isArray(error?.body)){
                message = error.body.map(e => e.message).join(', ');
            }

            this.showToast('Error', message, 'error');
        })
        .finally(() => {
            this.isLoading = false;
        });
    }

    // ================= TOAST =================

    showToast(title, message, variant){
        this.dispatchEvent(
            new ShowToastEvent({ title, message, variant })
        );
    }
}