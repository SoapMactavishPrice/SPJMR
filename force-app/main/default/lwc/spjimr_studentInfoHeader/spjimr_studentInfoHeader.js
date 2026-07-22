import { LightningElement, track } from 'lwc';
import getUserInfo from '@salesforce/apex/StudentProfileDashboardController.getUserInfo';
import getProfilePhotoBase64 from '@salesforce/apex/StudentProfileDashboardController.getProfilePhotoBase64';
import profileDummy from '@salesforce/resourceUrl/Profile_Dummy';

const NA_LABEL = 'N/A';

export default class Spjimr_studentInfoHeader extends LightningElement {
    @track studentName = '';
    @track rollNumber = '';
    @track programName = '';
    @track programCode = '';
    @track term = '';
    @track profilePhotoUrl = null;
    profileDummyIcon = profileDummy;
    accountId = null;

    connectedCallback() {
        this.loadUserName();
    }

    get displayProfileImageUrl() {
        return this.profilePhotoUrl || this.profileDummyIcon;
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
    get displayProgramCode() {
        return this.formatNA(this.programCode);
    }
    get displayTerm() {
        return this.formatNA(this.term);
    }

    loadUserName() {
        getUserInfo()
            .then((result) => {
                if (result) {
                    this.studentName = result.fullName || '';
                    this.rollNumber = result.rollNumber || '';
                    this.programName = result.programName || '';
                    this.programCode = result.programCode || '';
                    this.term = result.term || '';
                    this.accountId = result.accountId || null;
                    if (this.accountId) {
                        this.loadBannerProfilePhoto();
                    } else {
                        this.profilePhotoUrl = null;
                    }
                }
            })
            .catch((error) => {
                // eslint-disable-next-line no-console
                console.error('spjimr_studentInfoHeader getUserInfo error', error);
            });
    }

    loadBannerProfilePhoto() {
        if (!this.accountId) {
            this.profilePhotoUrl = null;
            return;
        }
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

    handleBannerPhotoError() {
        this.profilePhotoUrl = null;
    }
}