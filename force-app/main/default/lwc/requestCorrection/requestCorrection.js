import { LightningElement, track, api } from 'lwc';
import getApplicationScriptById from '@salesforce/apex/ApplicationCorrectionModal.getApplicationScriptById';
import saveCorrectionRequests from '@salesforce/apex/ApplicationCorrectionModal.saveCorrectionRequests';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

export default class RequestCorrection extends LightningElement {
    @track formSections = [];           // Holds parsed JSON
    @track selectedCorrections = [];    // Holds selected corrections
    @track isLoading = true;
    @api recordId;

    connectedCallback() {
        
        setTimeout(() => {
            getApplicationScriptById({ applicationId: this.recordId })
            .then(result => {
                if (result) {
                    try {
                        const parsed = JSON.parse(result);
                        console.log('Loaded JSON from Application:', parsed);
                        this.initializeFromParsed(parsed);
                    } catch (e) {
                        console.error('Error parsing JSON:', e);
                    }
                } else {
                    console.warn('No script data found.');
                }
            })
            .catch(error => {
                console.error('Error fetching Application JSON:', error);
            })
            .finally(() => {
                this.isLoading = false;
            });
            this.isLoading = false;
        }, 2000);
        
        
        
    }

    initializeFromParsed(parsed) {
        try {
            // Just clone the JSON structure for rendering
            this.formSections = parsed.map(sec => ({
                ...sec,
                fields: sec.fields.map(fld => ({ ...fld, isSelected: false }))
            }));
            console.log('Form sections initialized:', this.formSections);
        } catch (error) {
            console.error('Error initializing form sections:', error);
        }
    }

    handleFieldSelect(event) {
        const { section, field, row ,sectionlabel,fieldlabel} = event.target.dataset;
        const checked = event.target.checked;

        // Update formSections (to toggle isSelected flag)
        this.formSections = this.formSections.map(sec => {
            if (sec.objectapiName === section) {
                if (sec.repeatable && sec.rows) {
                    sec.rows = sec.rows.map((r, index) => {
                        if (index == row) {
                            return r.map(f => {
                                if (f.apiName === field) {
                                    f.isSelected = checked;
                                }
                                return f;
                            });
                        }
                        return r;
                    });
                } else {
                    sec.fields = sec.fields.map(f => {
                        if (f.apiName === field) f.isSelected = checked;
                        return f;
                    });
                }
            }
            return sec;
        });

        // Update selectedCorrections array
        const correction = {
            Section_Object_API__c: section,
            Field_API__c: field,
            Field_Label__c: fieldlabel,
            Section_Label__c: sectionlabel,
            Row_Index__c: row ? parseInt(row, 10) : null
        };

        if (checked) {
            this.selectedCorrections.push(correction);
        } else {
            this.selectedCorrections = this.selectedCorrections.filter(
                c =>
                    !(
                        c.Section_Object_API__c === section &&
                        c.Field_API__c === field &&
                        c.Row_Index__c === (row ? parseInt(row, 10) : null)
                    )
            );
        }

        console.log('Selected Corrections:', JSON.stringify(this.selectedCorrections));
    }

    handleRemarkChange(event) {
        const { section, field, row } = event.target.dataset;
        const remark = event.target.value;

        const correction = this.selectedCorrections.find(
            c =>
                c.Section_Object_API__c === section &&
                c.Field_API__c === field &&
                c.Row_Index__c === (row ? parseInt(row, 10) : null)
        );

        if (correction) correction.Staff_Remark__c = remark;
    }

    handleSave() {
        if (!this.selectedCorrections.length) {
            this.showToast('No fields selected', 'Please select at least one field to correct.', 'warning');
            return;
        }

        this.isLoading = true;
        console.log('JSON.stringify(this.selectedCorrections) ',JSON.stringify(this.selectedCorrections));
        
        saveCorrectionRequests({
            appId: this.recordId,
            correctionsJson: JSON.stringify(this.selectedCorrections)
        })
            .then(() => {
                this.showToast('Success', 'Correction requests created successfully!', 'success');
                this.closeModal();
            })
            .catch(error => {
                console.error('Error saving corrections:', error);
                this.showToast('Error', error.body?.message || 'Error saving corrections', 'error');
            })
            .finally(() => {
                this.isLoading = false;
            });
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    closeModal() {
        const closeEvent = new CustomEvent('close');
        this.dispatchEvent(closeEvent);
    }
}