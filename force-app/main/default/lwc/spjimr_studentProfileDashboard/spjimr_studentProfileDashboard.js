import { LightningElement, track, api, wire } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getUserInfo from '@salesforce/apex/StudentProfileDashboardController.getUserInfo';
import getWithdrawalWindowStatus from '@salesforce/apex/StudentProfileDashboardController.getWithdrawalWindowStatus';
import fetchEmergencyDetails from '@salesforce/apex/StudentProfileDashboardController.fetchEmergencyDetails';
import saveEmergencyContact from '@salesforce/apex/StudentProfileDashboardController.saveEmergencyContact';
import uploadProfilePhoto from '@salesforce/apex/StudentProfileDashboardController.uploadProfilePhoto';
import getProfilePhotoBase64 from '@salesforce/apex/StudentProfileDashboardController.getProfilePhotoBase64';
import logo from '@salesforce/resourceUrl/Site_Logo';
import programDetailsIcon from '@salesforce/resourceUrl/Program_Details';
import financeIcon from '@salesforce/resourceUrl/Finance_Icon';
import mentorIcon from '@salesforce/resourceUrl/Mentor_Icon';
import projectIcon from '@salesforce/resourceUrl/Project_Icon';
import ticketIcon from '@salesforce/resourceUrl/Ticket_Icon';
import studentDetailsIcon from '@salesforce/resourceUrl/Student_Details';
import navbarIcon from '@salesforce/resourceUrl/Navbar_Icon';
import profileDummy from '@salesforce/resourceUrl/Profile_Dummy';
import attendanceIcon from '@salesforce/resourceUrl/Attendance_Icon';
import examsIcon from '@salesforce/resourceUrl/Exams_Icon';
import academicsIcon from '@salesforce/resourceUrl/Academics_Icon';
import servicesIcon from '@salesforce/resourceUrl/Services_Icon';
import hostelIcon from '@salesforce/resourceUrl/Hostel_Icon';
import logoutIcon from '@salesforce/resourceUrl/Logout_Icon';

const PHOTO_UPLOAD_SUCCESS_MESSAGE = 'Photo uploaded successfully.';

/** Shown only when Program Cohort Instructions__c is blank */
const FALLBACK_PHOTO_UPLOAD_INSTRUCTION =
    'Upload instructions have not been set for your batch. Please use a clear passport-style photo (JPG or PNG), then click OK / Proceed to choose your file.';

const NA_LABEL = 'N/A';

export default class Spjimr_studentProfileDashboard extends LightningElement {
    // PROFILE_WINDOW_EVALUATE_INTERVAL_MS = 30000; // commented out: SPJIMR_ProgramCohortTrigger now sends notifications when the window opens
    // PROFILE_WINDOW_REFRESH_INTERVAL_MS = 60000;  // commented out: SPJIMR_ProgramCohortTrigger now sends notifications when the window opens
    _profileWindowIsActive = false;
    _profileWindowStartMs = null;
    _profileWindowEndMs = null;
    // SE-1156: Request Withdrawal button window state
    @track isWithinBatchPeriod = false;
    @track hasBatchDates = false;
    withdrawalBatchStartDate = null;
    withdrawalBatchEndDate = null;
    // _profileWindowRefreshTimer = null;   // commented out: polling replaced by trigger-based notifications
    // _profileWindowEvaluateTimer = null;  // commented out: polling replaced by trigger-based notifications
    // Navigation state
     @track selectedMenuItem = 'studentDetails';
    @track isSidebarOpen = true; // Sidebar open by default
    siteLogoIcon = logo;
    navbarIcon = navbarIcon;
    profileDummyIcon = profileDummy;

    programDetailsIconResource = programDetailsIcon;
    financeIconResource = financeIcon;
    mentorIconResource = mentorIcon;
    projectIconResource = projectIcon;
    ticketIconResource = ticketIcon;
    studentDetailsIconResource = studentDetailsIcon;
    // Static resource icons for the 7 menu items
    attendanceIconResource = attendanceIcon;
    examsIconResource = examsIcon;
    academicsIconResource = academicsIcon;
    servicesIconResource = servicesIcon;
    hostelIconResource = hostelIcon;
    logoutIconResource = logoutIcon;
    @api siteLogo;
    @api menuIcon;
    @api ticketIcon;
    @api projectIcon;
    @api mentorIcon;
    @api financeIcon;
    @api programDetailsIcon;
    @api studentDetailsIcon;
    @api attendanceIcon;
    @api examsIcon;
    @api academicsIcon;
    @api servicesIcon;
    @api hostelIcon;
    @api reportsIcon;
    @api logoutIcon;  
    @track preQua  

    //work experience
    @track orgName;
    @track experience;
    @track workDuration;
    /** Sum of all PersonEmployment periods (from Apex). */
    @track totalWorkExperience = '';

    // Student Information
    @track studentName = 'John Steve';
    @track studentEmail = '';
    @track rollNumber = '';
    @track programName = '';
    @track programCode = '';
    @track batchName = '';
    @track studentGender = '';
    @track currentTerm = 'Term 2';
    @track status = 'Accepted';
    @track credits = '372';
    @track points = '41';
    @track prevQualification='';
    @track graduationYear ='';
    @track marks = '';
    @track term = '';
    @track address = '';
    @track isEmergencyModalOpen = false;
    emergencyDetails = [];
    wiredEmergencyDetailsResult;
    @track parentRecord = null;
    @track guardianRecord = null;
    @track isEditModalOpen = false;
    @track editRecordType = ''; // 'parent' or 'guardian'
    @track editRecordId = null;
    @track editFormData = {
        name: '',
        relationship: '',
        phone: '',
        alternateNumber: '',
        address: ''
    };
    @track isLoading = false;
   
    
    
    @track accountId = null;
    @track profilePhotoUrl = null; // Set when we have isActive & is_profile_photo image
    @track showUploadPhotoButton = false;
    @track isPhotoUploadInstructionModalOpen = false;
    /** From Program Cohort Instructions__c (getUserInfo.photoUploadInstruction) */
    @track photoUploadInstructionText = '';
    @track photoUploadSuccessVisible = false;
    _photoUploadSuccessHideTimer = null;
    
    // Personal Details
    @track dateOfBirth = '';
    @track gender = 'Male';
    
    // Contact Info
    @track mobileNumber = '';
    @track email = 'John@gmail.com';
    // @track address = 'Plot no 20, johny street, Bengaluru, Karnataka - 600811';
    
    // Academic Background
    
    
    // Fees Section
    @track applicationFee = '₹1,000';
    @track paymentStatus = 'Pending';
    @track dueDate = '12/03/2025';
    
   
     @track isVisible = false;

    showTooltip() {
        this.isVisible = true;
    }

    hideTooltip() {
        this.isVisible = false;
    }
    @wire(fetchEmergencyDetails)
    wiredEmergencyDetails(result) {
        this.wiredEmergencyDetailsResult = result;
        const { data, error } = result;
        if (data) {
            this.emergencyDetails = data;
            console.log('Emergency Details:', data);
            // Separate parent and guardian records
            this.processEmergencyDetails(data);
        } else if (error) {
            this.emergencyDetails = [];
            this.parentRecord = null;
            this.guardianRecord = null;
            console.error('Error fetching emergency details:', error);
        }
    }

    processEmergencyDetails(details) {
        // Reset records
        this.parentRecord = null;
        this.guardianRecord = null;
        
        // Find parent and guardian records based on Relationship__c field
        if (details && details.length > 0) {
            for (let record of details) {
                const relationship = record.Relationship__c ? record.Relationship__c.toLowerCase().trim() : '';
                // Check for parent type record
                if (relationship === 'parent' || relationship.includes('parent')) {
                    // If multiple parent records exist, keep the first one
                    if (!this.parentRecord) {
                        this.parentRecord = record;
                    }
                } 
                // Check for guardian picklist record
                else if (relationship === 'guardian' || relationship === 'local guardian' || relationship.includes('guardian')) {
                    // If multiple guardian records exist, keep the first one
                    if (!this.guardianRecord) {
                        this.guardianRecord = record;
                    }
                }
            }
        }
    }

    get hasParentRecord() {
        return this.parentRecord !== null;
    }

    get hasGuardianRecord() {
        return this.guardianRecord !== null;
    }

    get hasRecords() {
        return this.emergencyDetails.length > 0;
    }

    get relationshipOptions() {
        return [
            { label: 'Parent', value: 'Parent' },
            { label: 'Guardian', value: 'Guardian' }
        ];
    }

    get editModalTitle() {
        // Show "Create contact" when there's no record ID (creating new), "Edit contact" when editing existing
        return this.editRecordId ? 'Edit contact' : 'Create contact';
    }

    get currentRelationshipOptions() {
        // Return only the relevant option based on record type
        if (this.editRecordType === 'parent') {
            return [{ label: 'Parent', value: 'Parent' }];
        } else if (this.editRecordType === 'guardian') {
            return [{ label: 'Guardian', value: 'Guardian' }];
        }
        // Fallback to all options (shouldn't happen in normal flow)
        return this.relationshipOptions;
    }

    get isRelationshipReadOnly() {
        // Make relationship field read-only for both parent and guardian contacts
        return this.editRecordType === 'parent' || this.editRecordType === 'guardian';
    }
    
    get menuItemsWithIcons() {
        return this.menuItems.map(item => {
            let iconUrl = null;
            
            // Map all menu items to their static resources
            switch(item.id) {
                case 'studentDetails':
                    iconUrl = this.studentDetailsIconResource;
                    break;
                case 'programDetails':
                    iconUrl = this.programDetailsIconResource;
                    break;
                case 'attendance':
                    iconUrl = this.attendanceIconResource;
                    break;
                case 'exams':
                    iconUrl = this.examsIconResource;
                    break;
                case 'academics':
                    iconUrl = this.academicsIconResource;
                    break;
                case 'finance':
                    iconUrl = this.financeIconResource;
                    break;
                case 'services':
                    iconUrl = this.servicesIconResource;
                    break;
                case 'mentorship':
                    iconUrl = this.mentorIconResource;
                    break;
                case 'hostel':
                    iconUrl = this.hostelIconResource;
                    break;
                case 'reports':
                    iconUrl = this.logoutIconResource;
                    break;
                case 'project':
                    iconUrl = this.projectIconResource;
                    break;
                case 'tickets':
                    iconUrl = this.ticketIconResource;
                    break;
                case 'logout':
                    iconUrl = this.logoutIconResource;
                    break;
                default:
                    iconUrl = null;
            }
            
            return {
                ...item,
                iconUrl: iconUrl
            };
        });
    }

    // Handle image error - log error and hide broken image
    handleImageError(event) {
        const img = event.target;
        const imageUrl = img.src;
        console.error('Failed to load CMS image:', imageUrl);
        // Hide the broken image
        img.style.display = 'none';
        // Note: CMS images require proper configuration for guest users
        // See CMS_GUEST_ACCESS_SETUP.md for configuration steps
    }
    
    // Handle menu item click
    handleMenuClick(event) {
        const menuId = event.currentTarget.dataset.id;
        if (menuId === 'logout') {
            this.handleLogout();
        } else {
            this.selectedMenuItem = menuId;
            // Update selected state and CSS class
            this.menuItems = this.menuItems.map(item => ({
                ...item,
                isSelected: item.id === menuId,
                cssClass: item.id === menuId ? 'nav-item selected' : 'nav-item'
            }));
        }
    }
     // Event Handlers
    handleEmergencyContact() {
        this.isEmergencyModalOpen = true;
    }
    
    closeEmergencyModal() {
        // Close Emergency Contact modal and edit modal if open
        this.isEmergencyModalOpen = false;
        this.isEditModalOpen = false;
    }

    handleCreateParent() {
        this.editRecordType = 'parent';
        this.editRecordId = null;
        this.editFormData = {
            name: '',
            relationship: 'Parent',
            phone: '',
            alternateNumber: '',
            address: ''
        };
        // Close emergency modal and open edit modal
        this.isEmergencyModalOpen = false;
        this.isEditModalOpen = true;
    }

    handleCreateGuardian() {
        this.editRecordType = 'guardian';
        this.editRecordId = null;
        this.editFormData = {
            name: '',
            relationship: 'Guardian',
            phone: '',
            alternateNumber: '',
            address: ''
        };
        // Close emergency modal and open edit modal
        this.isEmergencyModalOpen = false;
        this.isEditModalOpen = true;
    }

    handleEditParent() {
        if (this.parentRecord) {
            this.editRecordType = 'parent';
            this.editRecordId = this.parentRecord.Id;
            this.editFormData = {
                name: this.parentRecord.Name || '',
                relationship: this.parentRecord.Relationship__c || 'Parent',
                phone: this.parentRecord.Phone__c || '',
                alternateNumber: this.parentRecord.Alternate_Number__c || '',
                address: this.parentRecord.Address__c || ''
            };
            // Close emergency modal and open edit modal
            this.isEmergencyModalOpen = false;
            this.isEditModalOpen = true;
        }
    }

    handleEditGuardian() {
        if (this.guardianRecord) {
            this.editRecordType = 'guardian';
            this.editRecordId = this.guardianRecord.Id;
            this.editFormData = {
                name: this.guardianRecord.Name || '',
                relationship: this.guardianRecord.Relationship__c || 'Guardian',
                phone: this.guardianRecord.Phone__c || '',
                alternateNumber: this.guardianRecord.Alternate_Number__c || '',
                address: this.guardianRecord.Address__c || ''
            };
            // Close emergency modal and open edit modal
            this.isEmergencyModalOpen = false;
            this.isEditModalOpen = true;
        }
    }

    handleInputChange(event) {
        const field = event.target.dataset.field;
        let value = event.target.value;
        if (field === 'phone' || field === 'alternateNumber') {
            value = value.replace(/\D/g, '').slice(0, 10);
        }
        this.editFormData[field] = value;
        const input = event.target;
        if (input && typeof input.setCustomValidity === 'function') {
            input.setCustomValidity('');
            input.reportValidity();
        }
    }

    validatePhone(value) {
        if (!value || typeof value !== 'string') return false;
        const trimmed = value.trim();
        return /^\d{10}$/.test(trimmed);
    }

    validateEmergencyForm() {
        const name = (this.editFormData.name || '').trim();
        const relationship = (this.editFormData.relationship || '').trim();
        const phone = (this.editFormData.phone || '').trim();
        const alternateNumber = (this.editFormData.alternateNumber || '').trim();
        const address = (this.editFormData.address || '').trim();

        const nameInput = this.template.querySelector('.emergency-edit-name');
        const relationshipInput = this.template.querySelector('.emergency-edit-relationship');
        const phoneInput = this.template.querySelector('.emergency-edit-phone');
        const alternateInput = this.template.querySelector('.emergency-edit-alternate');
        const addressInput = this.template.querySelector('.emergency-edit-address');

        let allValid = true;
        const messages = [];

        // Primary Contact Name - required
        if (!name) {
            if (nameInput) nameInput.setCustomValidity('Primary Contact Name is required.');
            messages.push('Primary Contact Name is required.');
            allValid = false;
        } else {
            if (nameInput) nameInput.setCustomValidity('');
        }

        // Relationship - required
        if (!relationship) {
            if (relationshipInput) relationshipInput.setCustomValidity('Relationship is required.');
            messages.push('Relationship is required.');
            allValid = false;
        } else {
            if (relationshipInput) relationshipInput.setCustomValidity('');
        }

        // Mobile Number - required, exactly 10 digits only
        if (!phone) {
            if (phoneInput) phoneInput.setCustomValidity('Mobile Number is required.');
            messages.push('Mobile Number is required.');
            allValid = false;
        } else if (phone.length > 10) {
            if (phoneInput) phoneInput.setCustomValidity('Mobile number must be exactly 10 digits (numbers only).');
            messages.push('Mobile number must be exactly 10 digits (numbers only).');
            allValid = false;
        } else if (!this.validatePhone(phone)) {
            if (phoneInput) phoneInput.setCustomValidity('Mobile number must be exactly 10 digits (numbers only).');
            messages.push('Mobile number must be exactly 10 digits (numbers only).');
            allValid = false;
        } else {
            if (phoneInput) phoneInput.setCustomValidity('');
        }

        // Alternate Number - optional, if provided must be exactly 10 digits only
        if (alternateNumber && alternateNumber.length > 10) {
            if (alternateInput) alternateInput.setCustomValidity('Alternate number must be exactly 10 digits (numbers only).');
            messages.push('Alternate number must be exactly 10 digits (numbers only).');
            allValid = false;
        } else if (alternateNumber && !this.validatePhone(alternateNumber)) {
            if (alternateInput) alternateInput.setCustomValidity('Alternate number must be exactly 10 digits (numbers only).');
            messages.push('Alternate number must be exactly 10 digits (numbers only).');
            allValid = false;
        } else {
            if (alternateInput) alternateInput.setCustomValidity('');
        }

        // Address - required and max 250 characters
        if (!address) {
            if (addressInput) addressInput.setCustomValidity('Address is required.');
            messages.push('Address is required.');
            allValid = false;
        } else if (address.length > 250) {
            if (addressInput) addressInput.setCustomValidity('Address cannot be more than 250 characters.');
            messages.push('Address cannot be more than 250 characters.');
            allValid = false;
        } else {
            if (addressInput) addressInput.setCustomValidity('');
        }

        // Report validity on all so inline errors show
        [nameInput, relationshipInput, phoneInput, alternateInput, addressInput].forEach((el) => {
            if (el && typeof el.reportValidity === 'function') el.reportValidity();
        });

        if (!allValid) {
            this.dispatchEvent(new ShowToastEvent({
                title: 'Validation Error',
                message: messages[0] || 'Please fill all required fields correctly.',
                variant: 'error',
                mode: 'sticky'
            }));
        }
        return allValid;
    }

    handleSaveEmergencyContact() {
        if (!this.validateEmergencyForm()) {
            return;
        }

        this.isLoading = true;
        
        const name = (this.editFormData.name || '').trim();
        const phone = (this.editFormData.phone || '').trim();
        const alternateNumber = (this.editFormData.alternateNumber || '').trim();
        const address = (this.editFormData.address || '').trim();

        saveEmergencyContact({
            recordId: this.editRecordId,
            name,
            relationship: this.editFormData.relationship,
            phone,
            alternateNumber,
            address
        })
        .then(result => {
            console.log('Emergency contact saved successfully:', result);
            this.isEditModalOpen = false;
            this.dispatchEvent(new ShowToastEvent({
                title: 'Success',
                message: 'Emergency contact saved successfully.',
                variant: 'success'
            }));
            // Refresh emergency details
            return refreshApex(this.wiredEmergencyDetailsResult);
        })
        .then(() => {
            // Reopen emergency modal after saving
            this.isEmergencyModalOpen = true;
        })
        .catch(error => {
            console.error('Error saving emergency contact:', error);
            const errMsg = (error.body && error.body.message) ? error.body.message : (error.message || 'Failed to save emergency contact.');
            this.dispatchEvent(new ShowToastEvent({
                title: 'Error Saving Contact',
                message: errMsg,
                variant: 'error',
                mode: 'sticky'
            }));
        })
        .finally(() => {
            this.isLoading = false;
        });
    }

    closeEditModal() {
        this.isEditModalOpen = false;
        // Reset form data
        this.editFormData = {
            name: '',
            relationship: '',
            phone: '',
            alternateNumber: '',
            address: ''
        };
        this.editRecordId = null;
        this.editRecordType = '';
        // Reopen emergency modal
        this.isEmergencyModalOpen = true;
    }
    
    handleLogout() {
        console.log('Logout clicked');
        window.dispatchEvent(new CustomEvent('studentlogout'));
        sessionStorage.clear();
        localStorage.clear();
        sessionStorage.setItem('studentLogout', '1');
        const redirectUrl = encodeURIComponent('/student/login?');
        window.location.replace(`/student/secur/logout.jsp?retURL=${redirectUrl}`);
    }
 
    
    handleDownloadCertificate(event) {
        event.preventDefault();
        // Handle certificate download
        console.log('Download Certificate clicked');
        // Add your logic here
    }
    
    handleUploadDocuments() {
        // Handle upload documents button click
        console.log('Upload Documents clicked');
        // Add your logic here
    }
    
    handlePayAcademicFee() {
        // Handle pay academic fee button click
        console.log('Pay Academic Fee clicked');
        // Add your logic here
    }
    
    handleChangeSpecialization() {
        // Handle change of specialization button click
        console.log('Change of Specialization clicked');
        // Add your logic here
    }

    // SE-1156: load the withdrawal batch window for the current student
    loadWithdrawalWindow() {
        getWithdrawalWindowStatus()
            .then(result => {
                if (result) {
                    this.isWithinBatchPeriod = result.isWithinBatchPeriod === true;
                    this.hasBatchDates = result.hasBatchDates === true;
                    this.withdrawalBatchStartDate = result.batchStartDate || null;
                    this.withdrawalBatchEndDate = result.batchEndDate || null;
                } else {
                    this.isWithinBatchPeriod = false;
                    this.hasBatchDates = false;
                }
            })
            .catch(error => {
                // eslint-disable-next-line no-console
                console.error('getWithdrawalWindowStatus error', error);
                this.isWithinBatchPeriod = false;
                this.hasBatchDates = false;
            });
    }

    // SE-1156: button is enabled only inside the batch period
    get isWithdrawalDisabled() {
        return !this.isWithinBatchPeriod;
    }

    // SE-1156: contextual tooltip explaining button state
    get withdrawalTooltip() {
        if (this.isWithinBatchPeriod) {
            return 'Raise a request to withdraw from your programme.';
        }
        if (this.hasBatchDates) {
            return `Withdrawal requests can only be raised during your batch period (${this.formatWithdrawalDate(this.withdrawalBatchStartDate)} - ${this.formatWithdrawalDate(this.withdrawalBatchEndDate)}).`;
        }
        return 'Withdrawal requests are not available for your batch.';
    }

    formatWithdrawalDate(dateStr) {
        if (!dateStr) {
            return '';
        }
        const parsed = new Date(dateStr);
        if (isNaN(parsed.getTime())) {
            return dateStr;
        }
        return parsed.toLocaleDateString('en-GB', { day: '2-digit', month: 'short', year: 'numeric' });
    }

    // SE-1156: entry point only; the withdrawal request form is delivered in a later ticket
    handleRequestWithdrawal() {
        this.dispatchEvent(new ShowToastEvent({
            title: 'Request Withdrawal',
            message: 'The withdrawal request form will be available soon.',
            variant: 'info'
        }));
    }
    
    // Toggle sidebar visibility
    handleToggleSidebar() {
        this.isSidebarOpen = !this.isSidebarOpen;
    }
    
    // Computed property for sidebar class
    get sidebarClass() {
        return this.isSidebarOpen ? 'sidebar sidebar-open' : 'sidebar sidebar-closed';
    }
    
    // Computed property for main content class
    get mainContentClass() {
        return this.isSidebarOpen ? 'main-content main-content-with-sidebar' : 'main-content main-content-full';
    }

    get isStudentDetailsSection() {
        return this.selectedMenuItem === 'studentDetails';
    }

    get isAttendanceSection() {
        return this.selectedMenuItem === 'attendance';
    }

    // Fetch current user's name when component loads
    connectedCallback() {
        console.log('connectcallback of dashboard');
        this.loadUserName();
        this.loadWithdrawalWindow();
        // this.startProfileWindowTimers(); // commented out: SPJIMR_ProgramCohortTrigger now notifies users; initial window state is evaluated once via loadUserName()
    }

    disconnectedCallback() {
        // this.stopProfileWindowTimers(); // commented out: polling timers no longer started
        if (this._photoUploadSuccessHideTimer) {
            clearTimeout(this._photoUploadSuccessHideTimer);
            this._photoUploadSuccessHideTimer = null;
        }
    }

    // Load user info (name, email, gender) from Apex
    loadUserName() {
        getUserInfo()
            .then(result => {
                if (result) {
                    console.log('result::', result);
                    this.studentName = result.fullName;
                    this.studentEmail = result.email || '';
                    this.studentGender = result.gender || '';
                    this.dateOfBirth = result.dateOfBirth;
                    this.rollNumber = result.rollNumber || '';
                    this.programName = result.programName || '';
                    this.programCode = result.programCode || '';
                    this.batchName = result.batchName || '';
                    this.mobileNumber = result.mobileNumber || '';
                    this.prevQualification = result.prevQualification || '';
                    this.graduationYear = result.graduationYear || '';
                    this.orgName = result.orgName || '';
                    this.workDuration = result.workDuration || '';
                    this.totalWorkExperience = result.totalWorkExperience || '';
                    this.experience = result.experience || '';
                    this.marks = result.marks || '';
                    this.term = result.term || '';
                    this.address = result.address || '';
                    this.accountId = result.accountId || null;
                    this.photoUploadInstructionText = result.photoUploadInstruction || '';
                    this.updateProfileWindowState(result);
                    if (this.accountId) {
                        this.loadProfilePhoto();
                    }
                } else {
                    this.photoUploadInstructionText = '';
                    this.updateProfileWindowState(null);
                }
            })
            .catch(error => {
                console.error('Error fetching user info:', error);
                this.photoUploadInstructionText = '';
                this.updateProfileWindowState(null);
            });
    }

    // startProfileWindowTimers() — commented out: SPJIMR_ProgramCohortTrigger now sends notifications when the
    // window opens; upload-button visibility is evaluated once on page load via loadUserName() → updateProfileWindowState().
    // startProfileWindowTimers() {
    //     this.stopProfileWindowTimers();
    //     this._profileWindowEvaluateTimer = setInterval(() => {
    //         this.evaluateUploadPhotoVisibility();
    //     }, this.PROFILE_WINDOW_EVALUATE_INTERVAL_MS);
    //     this._profileWindowRefreshTimer = setInterval(() => {
    //         this.loadUserName();
    //     }, this.PROFILE_WINDOW_REFRESH_INTERVAL_MS);
    // }

    // stopProfileWindowTimers() — commented out: no timers are started anymore
    // stopProfileWindowTimers() {
    //     if (this._profileWindowEvaluateTimer) {
    //         clearInterval(this._profileWindowEvaluateTimer);
    //         this._profileWindowEvaluateTimer = null;
    //     }
    //     if (this._profileWindowRefreshTimer) {
    //         clearInterval(this._profileWindowRefreshTimer);
    //         this._profileWindowRefreshTimer = null;
    //     }
    // }

    updateProfileWindowState(userInfo) {
        const isActive = userInfo && userInfo.profileWindowIsActive === true;
        const startRaw = userInfo ? userInfo.profileWindowStartTime : null;
        const endRaw = userInfo ? userInfo.profileWindowEndTime : null;
        this._profileWindowStartMs = startRaw ? Date.parse(startRaw) : null;
        this._profileWindowEndMs = endRaw ? Date.parse(endRaw) : null;
        this._profileWindowIsActive = isActive;
        this.evaluateUploadPhotoVisibility();
    }

    evaluateUploadPhotoVisibility() {
        if (this._profileWindowIsActive !== true) {
            this.showUploadPhotoButton = false;
            return;
        }
        if (!Number.isFinite(this._profileWindowStartMs) || !Number.isFinite(this._profileWindowEndMs)) {
            this.showUploadPhotoButton = false;
            return;
        }
        const now = Date.now();
        this.showUploadPhotoButton = now >= this._profileWindowStartMs && now <= this._profileWindowEndMs;
    }

    get displayProfileImageUrl() {
        return this.profilePhotoUrl || this.profileDummyIcon;
    }

    handleProfilePhotoError() {
        this.profilePhotoUrl = null;
    }

    loadProfilePhoto() {
        if (!this.accountId) return;
        getProfilePhotoBase64({ accountId: this.accountId })
            .then((dataUrl) => {
                if (dataUrl && typeof dataUrl === 'string' && dataUrl.startsWith('data:image')) {
                    this.profilePhotoUrl = dataUrl;
                } else {
                    this.profilePhotoUrl = null;
                }
            })
            .catch(() => {
                this.profilePhotoUrl = null;
            });
    }

    get photoUploadInstructionRichHtml() {
        const t = (this.photoUploadInstructionText || '').trim();
        if (t.length > 0) {
            return t;
        }
        return `<p>${this.escapeHtml(FALLBACK_PHOTO_UPLOAD_INSTRUCTION).replace(/\n/g, '<br/>')}</p>`;
    }

    escapeHtml(text) {
        return String(text || '')
            .replace(/&/g, '&amp;')
            .replace(/</g, '&lt;')
            .replace(/>/g, '&gt;')
            .replace(/"/g, '&quot;');
    }

    handleUploadPhotoClick() {
        this.isPhotoUploadInstructionModalOpen = true;
    }

    handlePhotoUploadInstructionCancel() {
        this.isPhotoUploadInstructionModalOpen = false;
    }

    handlePhotoUploadInstructionProceed() {
        this.isPhotoUploadInstructionModalOpen = false;
        // Defer opening the file dialog until after the modal closes (browser UX).
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        setTimeout(() => {
            this.template.querySelector('input.profile-photo-input')?.click();
        }, 0);
    }

    handleProfilePhotoFileChange(event) {
        const file = event.target.files && event.target.files[0];
        if (!file) return;
        const ext = (file.name || '').split('.').pop().toLowerCase();
        if (!['jpg', 'jpeg', 'png'].includes(ext)) {
            this.dispatchEvent(new ShowToastEvent({
                title: 'Invalid format',
                message: 'Only JPG, JPEG, and PNG are allowed.',
                variant: 'error'
            }));
            event.target.value = '';
            return;
        }
        if (!this.accountId) {
            this.dispatchEvent(new ShowToastEvent({
                title: 'Error',
                message: 'Account context not available.',
                variant: 'error'
            }));
            event.target.value = '';
            return;
        }
        const reader = new FileReader();
        reader.onload = () => {
            const base64 = (reader.result || '').split(',')[1] || '';
            this.isLoading = true;
            uploadProfilePhoto({
                accountId: this.accountId,
                base64Data: base64,
                fileName: file.name,
                userName: this.studentName,
                rollNumber: this.rollNumber
            })
                .then(() => {
                    this.showPhotoUploadSuccessMessage();
                    this.loadProfilePhoto();
                    // Platform toast works in many LEX pages; Experience Cloud often ignores it from nested LWCs.
                    queueMicrotask(() => {
                        this.dispatchEvent(
                            new ShowToastEvent({
                                title: 'Success',
                                message: PHOTO_UPLOAD_SUCCESS_MESSAGE,
                                variant: 'success',
                                mode: 'dismissable'
                            })
                        );
                    });
                })
                .catch((err) => {
                    const msg = (err.body && err.body.message) ? err.body.message : (err.message || 'Upload failed.');
                    this.dispatchEvent(new ShowToastEvent({
                        title: 'Upload failed',
                        message: msg,
                        variant: 'error'
                    }));
                })
                .finally(() => {
                    this.isLoading = false;
                    event.target.value = '';
                });
        };
        reader.readAsDataURL(file);
    }

    showPhotoUploadSuccessMessage() {
        if (this._photoUploadSuccessHideTimer) {
            clearTimeout(this._photoUploadSuccessHideTimer);
            this._photoUploadSuccessHideTimer = null;
        }
        this.photoUploadSuccessVisible = true;
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        this._photoUploadSuccessHideTimer = setTimeout(() => {
            this.photoUploadSuccessVisible = false;
            this._photoUploadSuccessHideTimer = null;
        }, 10000);
    }

    dismissPhotoUploadSuccess() {
        if (this._photoUploadSuccessHideTimer) {
            clearTimeout(this._photoUploadSuccessHideTimer);
            this._photoUploadSuccessHideTimer = null;
        }
        this.photoUploadSuccessVisible = false;
    }

    get photoUploadSuccessMessage() {
        return PHOTO_UPLOAD_SUCCESS_MESSAGE;
    }

    formatNA(value) {
        if (value === null || value === undefined) {
            return NA_LABEL;
        }
        const s = String(value).trim();
        return s.length ? s : NA_LABEL;
    }

    get displayStudentName() {
        return this.formatNA(this.studentName);
    }
    get displayRollNumber() {
        return this.formatNA(this.rollNumber);
    }
    get displayProgramName() {
        return this.formatNA(this.programName);
    }
    get displayDateOfBirth() {
        return this.formatNA(this.dateOfBirth);
    }
    get displayStudentGender() {
        return this.formatNA(this.studentGender);
    }
    get displayMobileNumber() {
        return this.formatNA(this.mobileNumber);
    }
    get displayStudentEmail() {
        return this.formatNA(this.studentEmail);
    }
    get displayAddress() {
        return this.formatNA(this.address);
    }
    get displayPrevQualification() {
        return this.formatNA(this.prevQualification);
    }
    get displayGraduationYear() {
        return this.formatNA(this.graduationYear);
    }
    get displayMarks() {
        return this.formatNA(this.marks);
    }
    get displayOrgName() {
        return this.formatNA(this.orgName);
    }
    get displayWorkDuration() {
        return this.formatNA(this.workDuration);
    }
    get displayTotalWorkExperience() {
        return this.formatNA(this.totalWorkExperience);
    }
    get displayExperience() {
        return this.formatNA(this.experience);
    }

    get parentDisplayName() {
        return this.formatNA(this.parentRecord?.Name);
    }
    get parentDisplayRelationship() {
        return this.formatNA(this.parentRecord?.Relationship__c);
    }
    get parentDisplayPhone() {
        return this.formatNA(this.parentRecord?.Phone__c);
    }
    get parentDisplayAlternate() {
        return this.formatNA(this.parentRecord?.Alternate_Number__c);
    }
    get parentDisplayAddress() {
        return this.formatNA(this.parentRecord?.Address__c);
    }

    get guardianDisplayName() {
        return this.formatNA(this.guardianRecord?.Name);
    }
    get guardianDisplayRelationship() {
        return this.formatNA(this.guardianRecord?.Relationship__c);
    }
    get guardianDisplayPhone() {
        return this.formatNA(this.guardianRecord?.Phone__c);
    }
    get guardianDisplayAlternate() {
        return this.formatNA(this.guardianRecord?.Alternate_Number__c);
    }
    get guardianDisplayAddress() {
        return this.formatNA(this.guardianRecord?.Address__c);
    }
}