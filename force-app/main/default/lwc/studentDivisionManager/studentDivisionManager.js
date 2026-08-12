import { LightningElement, api, track } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import previewDistribution from '@salesforce/apex/StudentDivisionDistributorV2.previewDistribution';
import confirmDistribution from '@salesforce/apex/StudentDivisionDistributorV2.confirmDistribution';
import validate from '@salesforce/apex/StudentDivisionDistributorV2.validateDistribution';
import modal from "@salesforce/resourceUrl/custommodalcss";
import { loadStyle } from 'lightning/platformResourceLoader';

export default class StudentDivisionManager extends NavigationMixin(LightningElement) {
    @api recordId;
    @track rows;
    @track message;
    @track warnings = [];
    @track isValid = true;
    @track isPreviewMode = false;
    @track isLoading = false;

    // Raw enrollmentId -> divisionId map returned by the last preview (a
    // plain object of {enrollmentId: divisionId}). Sent back to
    // confirmDistribution unchanged so what gets saved is exactly what the
    // user reviewed on screen.
    pendingAssignments = {};

    // Work Experience Bucket labels per the process document, keyed to
    // match the "0".."3" keys computeWeBucket() sends from Apex.
    static WE_BUCKET_LABELS = {
        '0': '0-1 ',
        '1': '>1-2 ',
        '2': '>2-3 ',
        '3': '>3 '
    };

    columns = [
        { label: 'Division', fieldName: 'divisionAutoNumber' },
        { label: 'Division Name', fieldName: 'divisionName' },
        { label: 'Total', fieldName: 'total', type: 'number' },
        { label: 'Male', fieldName: 'male', type: 'number' },
        { label: 'Female', fieldName: 'female', type: 'number' },
        { label: 'Tech', fieldName: 'tech', type: 'number' },
        { label: 'Non-Tech', fieldName: 'nonTech', type: 'number' },
        {
            label: 'Work Experience Bucket',
            fieldName: 'weBuckets',
            typeAttributes: {
                class: 'slds-line-clamp',
                text: { fieldName: 'weBuckets' },
            },
            wrapText: true,
            type: 'text',
            cellAttributes: { class: 'specialisation-cell' },
            initialWidth: 280
        },
        {
            label: 'Specialisations',
            fieldName: 'specialisations',
            typeAttributes: {
                class: 'slds-line-clamp',
                text: { fieldName: 'specialisations' },
            },
            wrapText: true,
            type: 'text',
            cellAttributes: { class: 'specialisation-cell' },
            initialWidth: 300
        }
    ];

    connectedCallback() {
        loadStyle(this, modal);
    }

    get previewButtonLabel() {
        return this.isPreviewMode ? 'Preview Again' : 'Preview Distribution';
    }

    get hasWarnings() {
        return this.warnings && this.warnings.length > 0;
    }

    // Runs the algorithm and shows the proposed allocation WITHOUT saving it.
    handlePreview() {
        this.isLoading = true;
        this.message = '';

        previewDistribution({ termId: this.recordId })
            .then(res => {
                this.isValid = res.isValid !== false;
                this.warnings = res.warnings || [];
                this.message = res.message || '';
                this.rows = this.formatDivisionRows(res.divisions);
                this.pendingAssignments = res.assignments || {};
                this.isPreviewMode = true;
            })
            .catch(e => {
                this.message = e.body?.message || e.message || 'Error generating preview';
                this.rows = [];
                this.warnings = [];
                this.isValid = false;
                this.isPreviewMode = false;
                this.pendingAssignments = {};
            })
            .finally(() => {
                this.isLoading = false;
            });
    }

    // Commits the previewed allocation exactly as shown, then shows a
    // success toast and returns to the Term record page.
    handleConfirm() {
        if (!this.pendingAssignments || Object.keys(this.pendingAssignments).length === 0) {
            this.isValid = false;
            this.message = 'Nothing to confirm - generate a preview first';
            return;
        }

        this.isLoading = true;

        confirmDistribution({ assignments: this.pendingAssignments })
            .then(result => {
                if (result && result.success) {
                    this.isPreviewMode = false;
                    this.pendingAssignments = {};
                    this.dispatchEvent(new ShowToastEvent({
                        title: 'Success',
                        message: result.message || 'Distribution saved successfully',
                        variant: 'success'
                    }));
                    this.navigateToTerm();
                    return;
                }

                // Save failed (or nothing new to save) - keep the preview on
                // screen and surface exactly why, instead of pretending it
                // worked or hiding the real error.
                this.isValid = false;
                this.warnings = (result && result.errors) || [];
                this.message = (result && result.message) || 'Error saving distribution';
            })
            .catch(e => {
                this.isValid = false;
                this.message = e.body?.message || e.message || 'Error saving distribution';
            })
            .finally(() => {
                this.isLoading = false;
            });
    }

    // Returns to the Term record page this component is placed on.
    // objectApiName is left out deliberately - the navigation service
    // resolves the object type from recordId, so this works regardless of
    // what the Term object is actually called in this org.
    navigateToTerm() {
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId: this.recordId,
                actionName: 'view'
            }
        });
    }

    // Discards the preview without saving anything.
    handleCancel() {
        this.isPreviewMode = false;
        this.pendingAssignments = {};
        this.rows = [];
        this.warnings = [];
        this.isValid = true;
        this.message = 'Preview discarded. No changes were saved.';
    }

    // Reads back the currently SAVED distribution (used both for the
    // "View Current Distribution" button and to refresh after a confirm).
    handleValidate() {
        return validate({ termId: this.recordId })
            .then(res => {
                this.isValid = res.isValid || false;
                this.warnings = res.warnings || [];
                this.rows = this.formatDivisionRows(res.divisions);
                this.message =res.message || '';
            })
            .catch(e => {
                this.message = e.body?.message || e.message || 'Error validating distribution';
                this.rows = [];
                this.warnings = [];
                this.isValid = false;
            });
    }

    // Shared formatter: turns DivisionDTO[] (from either preview or
    // validate) into datatable rows.
    formatDivisionRows(divisions) {
        if (!divisions || !Array.isArray(divisions)) {
            return [];
        }

        return divisions.map(div => {
            let specString = 'None';
            if (div.specialisationCounts && Object.keys(div.specialisationCounts).length > 0) {
                specString = Object.entries(div.specialisationCounts)
                    .map(([name, count]) => `${name}: ${count}`)
                    .join(', ');
            }

            let weString = 'None';
            if (div.weBucketCounts && Object.keys(div.weBucketCounts).length > 0) {
                weString = Object.entries(div.weBucketCounts)
                    .sort(([bucketA], [bucketB]) => Number(bucketA) - Number(bucketB))
                    .map(([bucket, count]) => `${StudentDivisionManager.WE_BUCKET_LABELS[bucket] || bucket}: ${count}`)
                    .join(', ');
            }

            return {
                divisionId: div.divisionId,
                divisionAutoNumber: div.divisionAutoNumber,
                divisionName: div.divisionName,
                total: div.total || 0,
                male: div.male || 0,
                female: div.female || 0,
                tech: div.tech || 0,
                nonTech: div.nonTech || 0,
                weBuckets: weString,
                specialisations: specString
            };
        });
    }
}