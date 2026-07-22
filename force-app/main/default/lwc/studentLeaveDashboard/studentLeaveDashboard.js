import { LightningElement, wire, track } from 'lwc';
import getStudentLeaves from '@salesforce/apex/LeaveApprovalActionController.getStudentLeaves';
import updateLeave from '@salesforce/apex/LeaveApprovalActionController.updateLeave';
import uploadFile from '@salesforce/apex/LeaveApprovalActionController.uploadFile';
import isStudentPortalLeaveModuleEnabled from '@salesforce/apex/StudentProfileDashboardController.isStudentPortalLeaveModuleEnabled';

import USER_ID from '@salesforce/user/Id';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { refreshApex } from '@salesforce/apex';
import getFilesWithData from '@salesforce/apex/LeaveApprovalActionController.getFilesWithData';

export default class StudentLeaveDashboard extends LightningElement {

    // ================= FEATURE TOGGLE =================
    /** Defaults true until wire resolves (matches Apex default when CMDT record is absent). */
    @track leaveModuleEnabled = true;

    @wire(isStudentPortalLeaveModuleEnabled)
    wiredLeaveModuleEnabled({ data }) {
        if (data !== undefined && data !== null) {
            this.leaveModuleEnabled = data === true;
        }
    }

    get showLeaveDashboard() {
        return this.leaveModuleEnabled === true;
    }

    // ================= DATA =================
    @track leaves = [];
    wiredResult;
    @track existingFiles = [];
    resubmittedIds = {};
    @track showSuccessToast = false;
    // ================= MODAL =================
    @track showModal = false;
    @track selectedLeaveId;

    // ================= FORM =================
    @track startDate;
    @track endDate;
    @track leaveType;
    @track remarks;

    // ================= FILE =================
    fileData;
    @track showImagePreview = false;
@track previewImageUrl;

handleImageClick(event) {
    this.previewImageUrl = event.target.dataset.url;
    this.showImagePreview = true;
}

closeImagePreview() {
    this.showImagePreview = false;
    this.previewImageUrl = null;
}

    // ================= PICKLIST =================
    leaveTypeOptions = [
        { label: 'Marriage Leave', value: 'Marriage Leave' },
        { label: 'Medical Leave', value: 'Medical Leave' },
        { label: 'Emergency Leave', value: 'Emergency Leave' },
        { label: 'Other', value: 'Other' }
    ];

    // ================= FETCH =================
    @wire(getStudentLeaves, { userId: USER_ID })
    wiredLeaves(result) {
        this.wiredResult = result;

        if (result.data) {
            this.leaves = result.data.map(item => {

                let status = item.Status__c ? item.Status__c.toLowerCase() : '';
            
                let isIncomplete = status.includes('incomplete');
            
                let remarkText = '-';
            
                // ✅ Show remark only for final statuses
                if (status.includes('approved') || 
                    status.includes('rejected') || 
                    status.includes('incomplete')) {
            
                        if (item.Approver_Remarks__c) {
                            remarkText = item.Approver_Remarks__c;
                        }
                }
            
                let alreadyResubmitted = !!this.resubmittedIds[item.Id];

                return {
                    ...item,
                    isEditable: isIncomplete && !alreadyResubmitted,
                    isResubmitted: alreadyResubmitted,
                    displayStatus: this.getDisplayStatus(item),
                    statusClass: this.getStatusClass(item.Status__c),
                    remarksDisplay: remarkText,
                    formattedStartDate: this.formatDateTime(item.Start_Date__c),  // ✅ ADD
                    formattedEndDate: this.formatDateTime(item.End_Date__c) 
                };
            });
        } else if (result.error) {
            console.error(result.error);
        }
    }

    get hasLeaves() {
        return this.leaves && this.leaves.length > 0;
    }
    closeModal() {
        this.showModal = false;
    
        // close image preview also
        this.showImagePreview = false;
        this.previewImageUrl = null;
    
        // reset form
        this.selectedLeaveId = null;
        this.startDate = null;
        this.endDate = null;
        this.leaveType = null;
        this.remarks = null;
        this.fileData = null;
        this.existingFiles = [];
    }
    // ================= STATUS DISPLAY =================
    getDisplayStatus(item) {

        let status = item.Status__c;
    
        if (!status) return '';
    
        // Optional beautify
        if (status.includes('Pending')) {
            return '⏳ ' + status;
        }
    
        if (status.includes('Approved')) {
            return '✅ ' + status;
        }
    
        if (status.includes('Rejected')) {
            return '❌ ' + status;
        }
    
        if (status.includes('Incomplete')) {
            return '⚠️ ' + status;
        }
    
        return status;
    }
    // ================= STATUS COLOR =================
    getStatusClass(status) {
        if (!status) return 'pending';

        const val = status.toLowerCase();

        if (val === 'approved') return 'approved';
        if (val === 'rejected') return 'rejected';
        if (val.includes('incomplete')) return 'pending';

        return 'pending';
    }

    // ================= EDIT =================
    handleEdit(event) {
        const recordId = event.target.dataset.id;
        const rec = this.leaves.find(l => l.Id === recordId);
    
        this.selectedLeaveId = recordId;
        this.startDate = rec.Start_Date__c;
        this.endDate = rec.End_Date__c;
        this.leaveType = rec.Leave_Type__c;
        this.remarks = rec.Reason__c;
    
        this.fileData = null;
    
        // 🔥 CLEAR
        this.existingFiles = [];
    
        // 🔥 FETCH FILES
        getFilesWithData({ recordId: recordId })
        .then(result => {
        
            this.existingFiles = result.map(file => {

                let isImage = ['png','jpg','jpeg','gif','webp'].includes(file.extension.toLowerCase());
            
                return {
                    id: file.id,
                    name: file.name,
                    isImage: isImage,
                    url: 'data:image/' + file.extension + ';base64,' + file.data
                };
            });
        
        })
        .catch(error => {
            console.error(error);
        });
        this.showModal = true;
    }

    // ================= INPUT =================
    handleStartDate(e) { this.startDate = e.target.value; }
    handleEndDate(e) { this.endDate = e.target.value; }
    handleLeaveType(e) { this.leaveType = e.target.value; }
    handleRemarks(e) { this.remarks = e.target.value; }

    // ================= FILE =================
    handleFileChange(event) {
        const file = event.target.files[0];
        if (!file) return;

        const reader = new FileReader();

        reader.onloadend = () => {
            this.fileData = {
                filename: file.name,
                base64: reader.result.split(',')[1]
            };

            console.log('File ready:', this.fileData);
        };

        reader.readAsDataURL(file);
    }

    // ================= SAVE =================
    handleSave() {

        if (!this.startDate || !this.endDate || !this.leaveType) {
            this.showToast('Error', 'Please fill all required fields', 'error');
            return;
        }

        let uploadPromise = Promise.resolve();

        if (this.fileData && this.fileData.base64) {
            uploadPromise = uploadFile({
                recordId: this.selectedLeaveId,
                fileName: this.fileData.filename,
                base64Data: this.fileData.base64
            });
        }

        uploadPromise
        .then(() => {
            return updateLeave({
                leaveId: this.selectedLeaveId,
                startDate: this.startDate,
                endDate: this.endDate,
                leaveType: this.leaveType,
                remarks: this.remarks
            });
        })
        .then(() => {
            this.resubmittedIds = { ...this.resubmittedIds, [this.selectedLeaveId]: true };        
            this.showModal = false;
        
            // ✅ Show custom toast
            this.showSuccessToast = true;
            setTimeout(() => {
                this.showSuccessToast = false;
            }, 4000);
            
            return refreshApex(this.wiredResult);
        
        })
        .then(() => {
            this.selectedLeaveId = null;
            this.startDate = null;
            this.endDate = null;
            this.leaveType = null;
            this.remarks = null;
            this.fileData = null;
        })
        .catch(error => {
            console.error('ERROR:', error);
            this.showToast('Error', error?.body?.message || 'Something went wrong', 'error');
        });
    }

    // ================= TOAST =================
    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
    handlePreview(event) {
        const url = event.target.dataset.url;
        window.open(url, '_blank');
    }
    
    // ================= CUSTOM TOAST =================
    closeToast() {
        this.showSuccessToast = false;
    }
    // ================= DATE FORMATTER =================
formatDateTime(dateStr) {
    if (!dateStr) return '-';
    const date = new Date(dateStr);
    const day = String(date.getDate()).padStart(2, '0');
    const month = String(date.getMonth() + 1).padStart(2, '0');
    const year = date.getFullYear();
    let hours = date.getHours();
    const minutes = String(date.getMinutes()).padStart(2, '0');
    const ampm = hours >= 12 ? 'PM' : 'AM';
    hours = hours % 12 || 12;  // convert 0 → 12
    const formattedHours = String(hours).padStart(2, '0');
    return `${day}/${month}/${year} ${formattedHours}:${minutes} ${ampm}`;
}
}