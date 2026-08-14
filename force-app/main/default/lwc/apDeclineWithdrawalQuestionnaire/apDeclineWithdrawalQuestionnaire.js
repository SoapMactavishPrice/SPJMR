import { api } from 'lwc';
import LightningModal from 'lightning/modal';
import LightningConfirm from 'lightning/confirm';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getApplicationDetailsForQuestionnaire from '@salesforce/apex/ApAccountProgramController.getApplicationDetailsForQuestionnaire';
import saveDeclineWithdrawalQuestionnaire from '@salesforce/apex/ApAccountProgramController.saveDeclineWithdrawalQuestionnaire';

// ── Institute options ────────────────────────────────────────────────────────
const INSTITUTE_OPTIONS = [
    { label: 'IIM A',                                   value: 'IIM A' },
    { label: 'IIM B',                                   value: 'IIM B' },
    { label: 'IIM C',                                   value: 'IIM C' },
    { label: 'IIM L',                                   value: 'IIM L' },
    { label: 'IIM K',                                   value: 'IIM K' },
    { label: 'IIM I',                                   value: 'IIM I' },
    { label: 'FMS',                                     value: 'FMS' },
    { label: 'XLRI',                                    value: 'XLRI' },
    { label: 'ISB',                                     value: 'ISB' },
    { label: 'MDI',                                     value: 'MDI' },
    { label: 'New IIMs',                                value: 'New IIMs' },
    { label: 'IIM Mumbai',                              value: 'IIM Mumbai' },
    { label: 'Going abroad for further studies',        value: 'Going abroad for further studies' },
    { label: 'Joining some other B-School',             value: 'Joining some other B-School' },
    { label: 'Not joining a B-School this year',        value: 'Not joining a B-School this year' },
    { label: 'None of the above',                       value: 'None of the above' },
    { label: 'Other',                                   value: 'Other' }
];

// ── Reason options ───────────────────────────────────────────────────────────
const REASON_OPTIONS = [
    { label: 'Perceived brand',                                         value: 'Perceived brand' },
    { label: 'Ranking',                                                 value: 'Ranking' },
    { label: 'Lower fees',                                              value: 'Lower fees' },
    { label: 'Better return on investment',                             value: 'Better return on investment' },
    { label: 'Better placements - type of roles being offered',         value: 'Better placements - type of roles being offered' },
    { label: 'Flexibility of choosing specialization/concentration in the 2nd year', value: 'Flexibility of choosing specialization/concentration in the 2nd year' },
    { label: 'Quality of teaching-learning',                            value: 'Quality of teaching-learning' },
    { label: 'Extent and nature of international exchange',             value: 'Extent and nature of international exchange' },
    { label: 'Want to work, before pursuing MBA education',             value: 'Want to work, before pursuing MBA education' },
    { label: 'Got a promotion at work',                                 value: 'Got a promotion at work' },
    { label: 'Closer to home',                                          value: 'Closer to home' },
    { label: 'Financial constraints',                                   value: 'Financial constraints' },
    { label: 'Want to appear for entrance exams next year to improve my scores', value: 'Want to appear for entrance exams next year to improve my scores' },
    { label: 'Any other',                                               value: 'Any other' }
];

const PLACEMENT_VALUE  = 'Better placements - type of roles being offered';
const ANY_OTHER_VALUE  = 'Any other';
const OTHER_INSTITUTE  = 'Other';
const MAX_REASONS      = 2;

export default class ApDeclineWithdrawalQuestionnaire extends LightningModal {

    // ── pre-populated read-only fields ───────────────────────────────────────
    applicantName   = '';
    applicationIdText = '';
    applicantEmail  = '';

    // ── form state ───────────────────────────────────────────────────────────
    selectedInstitute         = '';
    otherInstituteName        = '';
    selectedReasons           = [];   // array of selected reason values
    reasonsForChoicePlacementRoles = '';
    reasonsForChoiceOther     = '';
    anyOtherInformation       = '';

    // ── UI state ─────────────────────────────────────────────────────────────
    isLoaded          = false;
    isSubmitDisabled  = true;
    isSaving          = false;
    instituteError    = '';
    reasonsError      = '';

    // ── internal ─────────────────────────────────────────────────────────────
    _content;
    _applicationRecordId = '';   // Salesforce record Id (18-char)
    _type = 'Withdrawal';         // 'Withdrawal' | 'Decline'

    // ── @api content setter ──────────────────────────────────────────────────
    @api
    get content() {
        return this._content;
    }

    set content(value) {
        this._content = value;
        this._applicationRecordId = value?.applicationId || '';
        this._type = value?.type || 'Withdrawal';
        this._loadApplicationDetails();
    }

    // ── Computed: dynamic title & type guard ─────────────────────────────────
    get modalTitle()      { return this._type === 'Decline' ? 'Decline Questionnaire' : 'Withdrawal Questionnaire'; }
    get isWithdrawnType() { return this._type === 'Withdrawal'; }

    // ── Computed: institute options with checked state ───────────────────────
    get instituteOptions() {
        return INSTITUTE_OPTIONS.map(o => ({
            ...o,
            checked: o.value === this.selectedInstitute
        }));
    }

    // ── Computed: reason options with checked + disabled state ───────────────
    get reasonOptions() {
        const maxReached = this.selectedReasons.length >= MAX_REASONS;
        return REASON_OPTIONS.map(o => {
            const checked = this.selectedReasons.includes(o.value);
            return {
                ...o,
                checked,
                // disable unchecked options when max is reached
                disabled: !checked && maxReached
            };
        });
    }

    // ── Conditional visibility ───────────────────────────────────────────────
    get isOtherInstitute()    { return this.selectedInstitute === OTHER_INSTITUTE; }
    get isPlacementSelected() { return this.selectedReasons.includes(PLACEMENT_VALUE); }
    get isAnyOtherReason()    { return this.selectedReasons.includes(ANY_OTHER_VALUE); }

    // ── Apex fetch ───────────────────────────────────────────────────────────
    _loadApplicationDetails() {
        if (!this._applicationRecordId) return;
        getApplicationDetailsForQuestionnaire({ applicationId: this._applicationRecordId })
            .then(result => {
                this.applicantName    = result.applicantName  || '';
                this.applicationIdText = result.applicationId  || '';
                this.applicantEmail   = result.applicantEmail  || '';
                this.isLoaded = true;
            })
            .catch(err => {
                console.error('Error fetching application details', JSON.stringify(err));
                this.isLoaded = true;
            });
    }

    // ── Handlers ─────────────────────────────────────────────────────────────

    handleInstituteChange(event) {
        this.selectedInstitute = event.target.value;
        // Clear other-institute text if a different option is now selected
        if (this.selectedInstitute !== OTHER_INSTITUTE) {
            this.otherInstituteName = '';
        }
        this.instituteError = '';
        this._validate();
    }

    handleOtherInstituteChange(event) {
        this.otherInstituteName = event.detail.value;
        this._validate();
    }

    handleReasonChange(event) {
        const val     = event.target.dataset.value;
        const checked = event.target.checked;

        if (checked) {
            if (this.selectedReasons.length >= MAX_REASONS) {
                // Prevent selecting more than 2 — uncheck it immediately
                event.target.checked = false;
                return;
            }
            this.selectedReasons = [...this.selectedReasons, val];
        } else {
            this.selectedReasons = this.selectedReasons.filter(r => r !== val);
            // Clear related specify fields if deselected
            if (val === PLACEMENT_VALUE) this.reasonsForChoicePlacementRoles = '';
            if (val === ANY_OTHER_VALUE) this.reasonsForChoiceOther = '';
        }
        this.reasonsError = '';
        this._validate();
    }

    handlePlacementSpecifyChange(event) {
        this.reasonsForChoicePlacementRoles = event.detail.value;
        this._validate();
    }

    handleOtherReasonSpecifyChange(event) {
        this.reasonsForChoiceOther = event.detail.value;
        this._validate();
    }

    handleAnyOtherInfoChange(event) {
        this.anyOtherInformation = event.detail.value;
    }

    handleCancel() {
        this.close(null);
    }

    async handleSubmit() {
        if (!this._runValidation()) return;

        const confirmed = await LightningConfirm.open({
            message: this._type === 'Decline'
                ? 'Click OK to confirm you want to decline this offer.'
                : 'Click OK to confirm you want to withdraw your acceptance.',
            variant: 'headerless',
            label: this._type === 'Decline' ? 'Decline Confirmation' : 'Withdraw Confirmation'
        });

        if (!confirmed) return;

        this.isSaving = true;
        this.isSubmitDisabled = true;

        try {
            await saveDeclineWithdrawalQuestionnaire({
                applicationId                 : this._applicationRecordId,
                applicantName                 : this.applicantName,
                applicationIdText             : this.applicationIdText,
                applicantEmailId              : this.applicantEmail,
                whichInstituteAreYouJoining   : this.selectedInstitute,
                otherInstituteName            : this.isOtherInstitute ? this.otherInstituteName : '',
                reasonsForYourChoice          : this.selectedReasons.join(';'),
                reasonsForChoicePlacementRoles: this.isPlacementSelected ? this.reasonsForChoicePlacementRoles : '',
                reasonsForChoiceOther         : this.isAnyOtherReason    ? this.reasonsForChoiceOther         : '',
                anyOtherInformation           : this.anyOtherInformation,
                type                          : this._type
            });
            this.close(true);
        } catch (err) {
            console.error('Error saving questionnaire', JSON.stringify(err));
            this.dispatchEvent(new ShowToastEvent({
                title: 'Error',
                message: err?.body?.message || 'Could not save questionnaire. Please try again.',
                variant: 'error',
                mode: 'dismissable'
            }));
            this.isSubmitDisabled = false;
        } finally {
            this.isSaving = false;
        }
    }

    // ── Validation helpers ───────────────────────────────────────────────────

    _validate() {
        let valid = true;

        // Institute required
        if (!this.selectedInstitute) {
            valid = false;
        }
        // Other institute required if "Other" selected
        if (this.isOtherInstitute && !this.otherInstituteName?.trim()) {
            valid = false;
        }
        // At least 1 reason required (spec says "two main reasons" but treating as mandatory selection ≥1)
        if (this.selectedReasons.length === 0) {
            valid = false;
        }
        // Placement roles specify required if that reason is selected
        if (this.isPlacementSelected && !this.reasonsForChoicePlacementRoles?.trim()) {
            valid = false;
        }
        // Any other reason specify required if that reason is selected
        if (this.isAnyOtherReason && !this.reasonsForChoiceOther?.trim()) {
            valid = false;
        }

        this.isSubmitDisabled = !valid;
    }

    _runValidation() {
        let valid = true;

        if (!this.selectedInstitute) {
            this.instituteError = 'Please select an institute.';
            valid = false;
        } else {
            this.instituteError = '';
        }

        if (this.isOtherInstitute && !this.otherInstituteName?.trim()) {
            valid = false;
        }

        if (this.selectedReasons.length === 0) {
            this.reasonsError = 'Please select at least one reason.';
            valid = false;
        } else {
            this.reasonsError = '';
        }

        if (this.isPlacementSelected && !this.reasonsForChoicePlacementRoles?.trim()) {
            valid = false;
        }

        if (this.isAnyOtherReason && !this.reasonsForChoiceOther?.trim()) {
            valid = false;
        }

        this.isSubmitDisabled = !valid;
        return valid;
    }
}