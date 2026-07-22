import { LightningElement } from 'lwc';
import getSessions from '@salesforce/apex/LeaveRequestController.getSessions';
import saveLeaveRequest from '@salesforce/apex/LeaveRequestController.saveLeaveRequest';
import uploadFiles from '@salesforce/apex/LeaveRequestController.uploadFiles';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

export default class LeaveApplication extends LightningElement {

    fromDate = '';
    toDate   = '';
    leaveType;
    reason;

    sessions = [];
    showModal = false;
    isLoading = false;
    showSuccess = false;

    selectedFiles = [];
    errorMessage = '';

    uploadedFiles = [];

    // Lightbox properties — Image
    showLightbox = false;
    lightboxImageUrl = '';
    lightboxImageName = '';

    // ✅ NEW — Lightbox properties — PDF
    showPdfLightbox = false;
    lightboxPdfUrl = '';
    lightboxPdfName = '';
  

    // Minimum = current date-time (prevents past selection)
    get todayDateString() {
        try {
            const now = new Date();
            const pad = (n) => String(n).padStart(2, '0');
            return `${now.getFullYear()}-${pad(now.getMonth()+1)}-${pad(now.getDate())}`;
        } catch(e) {
            return '';
        }
    }
    
    get minDateTime() {
        try {
            const now = new Date();
            const pad = (n) => String(n).padStart(2, '0');
            return `${now.getFullYear()}-${pad(now.getMonth()+1)}-${pad(now.getDate())}T${pad(now.getHours())}:${pad(now.getMinutes())}`;
        } catch(e) {
            return '';
        }
    }
    
    get minToDateTime() {
        try {
            return this.fromDate ? this.fromDate : this.minDateTime;
        } catch(e) {
            return '';
        }
    }
    
    get nowString() {
        try {
            const now = new Date();
            const pad = (n) => String(n).padStart(2, '0');
            return `${now.getFullYear()}-${pad(now.getMonth()+1)}-${pad(now.getDate())}T${pad(now.getHours())}:${pad(now.getMinutes())}`;
        } catch(e) {
            return '';
        }
    }

    // Getter for preview section visibility
    get hasUploadedFiles() {
        return this.uploadedFiles.length > 0;
    }

    triggerFileUpload() {
        const fileInput = this.template.querySelector('.hidden-input');
        if (fileInput) {
            fileInput.click();
        }
    }

    handleFileChange(event) {
        const files = Array.from(event.target.files);

        // Max 3 files validation with auto-clear after 2 seconds
        const totalFiles = this.uploadedFiles.length + files.length;
        if (totalFiles > 3) {
            this.errorMessage = `You can upload maximum 3 files only. You already have ${this.uploadedFiles.length} file(s) uploaded.`;
            event.target.value = '';

            // Auto clear error after 2 seconds
            setTimeout(() => {
                this.errorMessage = '';
            }, 2000);

            return;
        }

        this.selectedFiles = [...this.selectedFiles, ...files];

        if (this.selectedFiles.length > 0) {
            this.errorMessage = '';
        }

        files.forEach(file => {
            const reader = new FileReader();
            const isImage = file.type.startsWith('image/');
            const isPdf = file.type === 'application/pdf';
            const isOther = !isImage && !isPdf; // ✅ NEW

            reader.onload = (e) => {
                this.uploadedFiles = [
                    ...this.uploadedFiles,
                    {
                        id: `${file.name}-${Date.now()}-${Math.random()}`,
                        name: file.name,
                        dataUrl: e.target.result,
                        isImage: isImage,
                        isPdf: isPdf,
                        isOther: isOther // ✅ NEW
                    }
                ];
            };

            reader.readAsDataURL(file);
        });

        event.target.value = '';
    }

    handleRemoveFile(event) {
        const id = event.currentTarget.dataset.id;
        const removedFile = this.uploadedFiles.find(f => f.id === id);

        this.uploadedFiles = this.uploadedFiles.filter(f => f.id !== id);

        if (removedFile) {
            const index = this.selectedFiles.findIndex(f => f.name === removedFile.name);
            if (index !== -1) {
                const updated = [...this.selectedFiles];
                updated.splice(index, 1);
                this.selectedFiles = updated;
            }
        }
    }

    // Opens image lightbox with clicked image
    handleImageClick(event) {
        this.lightboxImageUrl  = event.currentTarget.dataset.url;
        this.lightboxImageName = event.currentTarget.dataset.name;
        this.showLightbox = true;
    }

    // Closes image lightbox and resets values
    closeLightbox() {
        this.showLightbox = false;
        this.lightboxImageUrl = '';
        this.lightboxImageName = '';
    }

    // ✅ NEW — Opens PDF lightbox with clicked PDF
    // ✅ FIXED — Opens PDF in new tab using object URL (bypasses Salesforce CSP)
handlePdfClick(event) {
    const dataUrl = event.currentTarget.dataset.url;
    const name    = event.currentTarget.dataset.name;

    // Convert base64 dataUrl back to Blob, then open as object URL
    const byteString = atob(dataUrl.split(',')[1]);
    const mimeType   = dataUrl.split(',')[0].split(':')[1].split(';')[0];
    const byteArray  = new Uint8Array(byteString.length);

    for (let i = 0; i < byteString.length; i++) {
        byteArray[i] = byteString.charCodeAt(i);
    }

    const blob      = new Blob([byteArray], { type: mimeType });
    const objectUrl = URL.createObjectURL(blob);

    window.open(objectUrl, '_blank');
}



    // ✅ NEW — For doc/docx and other non-previewable files — triggers browser download
    handleOtherFileClick(event) {
        const url  = event.currentTarget.dataset.url;
        const name = event.currentTarget.dataset.name;
        const a = document.createElement('a');
        a.href = url;
        a.download = name;
        a.click();
    }

    // Prevents backdrop click from firing when clicking inner container
    stopPropagation(event) {
        event.stopPropagation();
    }

    /* ===============================
       INPUT HANDLERS
    =============================== */

    handleFromDate(event) {
        try {
            const selected = event.target.value;
            if (!selected) return;
    
            if (selected < this.todayDateString) {
                this.fromDateOnly  = '';
                event.target.value = '';
                this.errorMessage  = 'From date cannot be in the past.';
                setTimeout(() => { this.errorMessage = ''; }, 3000);
                return;
            }
    
            this.fromDateOnly = selected;
            if (this.fromTimeOnly) {
                this.fromDate = `${this.fromDateOnly}T${this.fromTimeOnly}`;
            }
    
            if (this.toDate && this.toDate <= this.fromDate) {
                this.toDate     = '';
                this.toDateOnly = '';
                this.toTimeOnly = '';
                this.errorMessage = 'To date/time cannot be before or equal to From date/time.';
                setTimeout(() => { this.errorMessage = ''; }, 3000);
            }
        } catch(e) {
            console.error('handleFromDate error:', e);
        }
    }
    handleFromTime(event) {
        try {
    
            console.log('FROM TIME PICKER VALUE =', event.target.value);
    
            this.fromTimeOnly = event.target.value.substring(0, 5);
    
            console.log('fromTimeOnly =', this.fromTimeOnly);
    
            if (this.fromDateOnly && this.fromTimeOnly) {
                this.fromDate = `${this.fromDateOnly}T${this.fromTimeOnly}`;
                console.log('fromDate =', this.fromDate);
            }
    
            if (this.toDate && this.toDate <= this.fromDate) {
                this.toDate     = '';
                this.toDateOnly = '';
                this.toTimeOnly = '';
                this.errorMessage = 'To date/time must be after From date/time.';
                setTimeout(() => { this.errorMessage = ''; }, 3000);
            }
    
        } catch(e) {
            console.error('handleFromTime error:', e);
        }
    }
    handleToDate(event) {
        try {
            const selected = event.target.value;
            if (!selected) return;
    
            if (selected < this.todayDateString) {
                this.errorMessage  = 'To date cannot be in the past.';
                this.toDateOnly    = '';
                event.target.value = '';
                setTimeout(() => { this.errorMessage = ''; }, 3000);
                return;
            }
    
            this.toDateOnly = selected;
            if (this.toTimeOnly) {
                this.toDate = `${this.toDateOnly}T${this.toTimeOnly}`;
            }
    
            if (this.fromDate && this.toDate && this.toDate <= this.fromDate) {
                this.errorMessage = 'Invalid date range: To date/time must be after From date/time.';
                this.toDate     = '';
                this.toDateOnly = '';
                this.toTimeOnly = '';
                event.target.value = '';
                setTimeout(() => { this.errorMessage = ''; }, 3000);
                return;
            }
    
            this.errorMessage = '';
        } catch(e) {
            console.error('handleToDate error:', e);
        }
    }
    handleToTime(event) {
        try {
    
            console.log('================================');
            console.log('TO TIME PICKER VALUE =', event.target.value);
    
            this.toTimeOnly = event.target.value.substring(0, 5);
    
            console.log('toTimeOnly =', this.toTimeOnly);
            console.log('toDateOnly =', this.toDateOnly);
    
            if (this.toDateOnly && this.toTimeOnly) {
                this.toDate = `${this.toDateOnly}T${this.toTimeOnly}`;
            }
    
            console.log('toDate =', this.toDate);
            console.log('fromDate =', this.fromDate);
            console.log('================================');
    
            if (this.fromDate && this.toDate <= this.fromDate) {
    
                if (this.toDate === this.fromDate) {
                    this.errorMessage = 'To time must be different from From time on the same day.';
                } else {
                    this.errorMessage = 'Invalid date range: To date/time must be after From date/time.';
                }
    
                this.toDate = '';
                this.toTimeOnly = '';
    
                setTimeout(() => {
                    this.errorMessage = '';
                }, 3000);
            }
    
        } catch(e) {
            console.error('handleToTime error:', e);
        }
    }
    handleLeaveType(event) {
        this.leaveType = event.target.value;
    }

    handleReason(event) {
        this.reason = event.target.value;
    }

    handleFilePreview(event) {
        const url = event.currentTarget.dataset.url;
        window.open(url, '_blank');
    }

    /* ===============================
       APPLY BUTTON
    =============================== */

    async handleApply() {

        if (!this.fromDate || !this.toDate) {
            this.showToast('Error', 'Please select From and To date & time', 'error');
            return;
        }
        
        // Past date guard
        if (this.fromDate && this.fromDate.slice(0, 10) < this.todayDateString) {
            this.errorMessage = 'From date cannot be in the past.';
            this.fromDate = '';
            setTimeout(() => { this.errorMessage = ''; }, 3000);
            return;
        }
        
        if (this.toDate && this.toDate.slice(0, 10) < this.todayDateString) {
            this.errorMessage = 'To date cannot be in the past.';
            this.toDate = '';
            setTimeout(() => { this.errorMessage = ''; }, 3000);
            return;
        }

// Extra safety guard
if (this.toDate <= this.fromDate) {
    this.errorMessage = 'Invalid date range: To date/time must be after From date/time.';
    setTimeout(() => { this.errorMessage = ''; }, 3000);
    return;
}

        if (!this.leaveType) {
            this.showToast('Error', 'Please select Leave Type', 'error');
            return;
        }
        if (!this.reason || this.reason.trim() === '') {
            this.errorMessage = 'Please enter a reason for leave';
            setTimeout(() => {
                this.errorMessage = '';
            }, 3000);
            return;
        }
        if (!this.selectedFiles || this.selectedFiles.length === 0) {
            this.errorMessage = 'Please upload document before applying leave';
            return;
        }

        this.errorMessage = '';
        this.isLoading = true;

        try {
            console.log('===== LWC DATE DEBUG =====');
            console.log('fromDateOnly =', this.fromDateOnly);
            console.log('fromTimeOnly =', this.fromTimeOnly);
            console.log('fromDate =', this.fromDate);
            
            console.log('toDateOnly =', this.toDateOnly);
            console.log('toTimeOnly =', this.toTimeOnly);
            console.log('toDate =', this.toDate);
            
            console.log('Sending Start =', this.fromDate.substring(0, 16) + ':00');
            console.log('Sending End =', this.toDate.substring(0, 16) + ':00');

            const result = await getSessions({
                startDate : this.fromDate.substring(0, 16) + ':00',
                 endDate   : this.toDate.substring(0, 16)   + ':00',
            });
            const sessionsArray = Array.isArray(result) ? result : [];

            if (sessionsArray.length > 0) {

                this.sessions = sessionsArray.map(item => {

                    const start = new Date(item.startTime);
                    const end = new Date(item.endTime);

                    const formattedDate = start.toLocaleDateString('en-GB', {
                        day: 'numeric',
                        month: 'short',
                        year: 'numeric'
                    });

                    const formattedStartTime = start.toLocaleTimeString([], {
                        hour: 'numeric',
                        minute: '2-digit',
                        hour12: true
                    });

                    const formattedEndTime = end.toLocaleTimeString([], {
                        hour: 'numeric',
                        minute: '2-digit',
                        hour12: true
                    });

                    return {
                        enrollmentId: item.enrollmentId,
                        sessionId: item.sessionId,
                        sessionName: item.sessionName,
                        attendance: item.attendance,
                        startTimeFormatted: `${formattedDate} - ${formattedStartTime}`,
                        endTimeFormatted: formattedEndTime
                    };
                });

                this.showModal = true;

            } else {
                await this.createLeave([]);
            }

        } catch (error) {
            this.handleError(error);
        } finally {
            this.isLoading = false;
        }
    }

    /* ===============================
       PROCEED BUTTON (Popup)
    =============================== */

    async handleProceed() {
        this.isLoading = true;
        try {
            const sessionEnrollmentIds = this.sessions
                .filter(item => item.enrollmentId)
                .map(item => item.enrollmentId);

            const leaveId = await saveLeaveRequest({
                startDate : this.fromDate.substring(0, 16) + ':00',
                endDate   : this.toDate.substring(0, 16)   + ':00',
                leaveType: this.leaveType,
                remark: this.reason,
                sessionEnrollmentIds: sessionEnrollmentIds,
                uploadedFileIds: []
            });

            if (this.selectedFiles.length > 0) {
                await this.uploadSelectedFiles(leaveId);
            }

            this.showModal = false;
            this.isLoading = false;
            this.showSuccess = true;

            setTimeout(() => {
                window.location.reload();
            }, 3000);

        } catch (error) {
            this.isLoading = false;
            this.handleError(error);
        }
    }

    /* ===============================
       COMMON LEAVE CREATION
    =============================== */

    async createLeave(sessionEnrollmentIds) {
        try {
            const leaveId = await saveLeaveRequest({
                startDate : this.fromDate.substring(0, 16) + ':00',
endDate   : this.toDate.substring(0, 16)   + ':00',
                leaveType: this.leaveType,
                remark: this.reason,
                sessionEnrollmentIds: sessionEnrollmentIds,
                uploadedFileIds: []
            });

            if (this.selectedFiles.length > 0) {
                await this.uploadSelectedFiles(leaveId);
            }

            this.showModal = false;
            this.isLoading = false;
            this.showSuccess = true;

            setTimeout(() => {
                window.location.reload();
            }, 3000);

        } catch (error) {
            this.isLoading = false;
            this.handleError(error);
        }
    }

    /* ===============================
       UTIL METHODS
    =============================== */

    closeModal() {
        this.showModal = false;
    }

    resetForm() {

        fromDate     = '';
        toDate       = '';
        fromDateOnly = '';
        fromTimeOnly = '';
        toDateOnly   = '';
        toTimeOnly   = '';
        this.leaveType = null;
        this.reason = null;
        this.sessions = [];
        this.selectedFiles = [];
        this.uploadedFiles = [];

        // Reset image lightbox on form reset
        this.showLightbox = false;
        this.lightboxImageUrl = '';
        this.lightboxImageName = '';

        // ✅ NEW — Reset PDF lightbox on form reset

        const fileInput = this.template.querySelector('.hidden-input');
        if (fileInput) {
            fileInput.value = null;
        }

        this.showModal = false;
    }

    showToast(title, message, variant) {
        this.dispatchEvent(
            new ShowToastEvent({
                title,
                message,
                variant,
                mode: 'dismissable'
            })
        );
    }

    handleError(error) {
        console.error(error);
        this.showToast(
            'Error',
            error?.body?.message || 'Something went wrong',
            'error'
        );
    }

    async uploadSelectedFiles(leaveId) {

        try {

            const fileNames = [];
            const base64List = [];

            for (let file of this.selectedFiles) {

                if (file.size > 3000000) {
                    this.showToast('Error', 'File size should be less than 3MB', 'error');
                    return;
                }

                const base64 = await this.convertToBase64(file);

                fileNames.push(file.name);
                base64List.push(base64.split(',')[1]);
            }

            await uploadFiles({
                leaveId: leaveId,
                fileNames: fileNames,
                base64DataList: base64List
            });

        } catch (error) {
            console.error('Upload Error:', error);
            this.showToast(
                'Error',
                error?.body?.message || 'File upload failed',
                'error'
            );
            throw error;
        }
    }

    convertToBase64(file) {
        return new Promise((resolve, reject) => {

            const reader = new FileReader();

            reader.onload = () => {
                resolve(reader.result);
            };

            reader.onerror = error => {
                reject(error);
            };

            reader.readAsDataURL(file);
        });
    }
}