import { LightningElement,track,api } from 'lwc';
import getApplicationScriptById from '@salesforce/apex/ApplicationCorrectionModal.getApplicationScriptById';
import saveCorrectionRequests from '@salesforce/apex/ApplicationCorrectionModal.saveCorrectionRequests';

export default class ApplicationCorrectionModal extends LightningElement {
    @track formSections = []; // Holds parsed JSON
    @track selectedCorrections = []; // Holds what staff selects
    @track isLoading=false;
    @api recordId;

    connectedCallback(){
        getApplicationScriptById({ applicationId: this.recordId })
        .then(result => {
            if (result) {
                try {
                    const parsed = JSON.parse(result);
                    console.log('Loaded JSON from Application:', parsed);
                    this.initializeFromParsed(parsed, true);
                    // this.gotScriptData = true;
                } catch (e) {
                    console.error('Error parsing JSON from Application:', e);
                }
            } 
        })
        .catch(error => {
            console.error('Error fetching Application JSON:', error);
        })
        .finally(() => {
            this.isLoading = false;
        });

    }

    initializeFromParsed(parsed) {
    try {
            console.log('result if'+JSON.stringify(this.accData));
            
            this.formMetadata = parsed.map((sec) => {
                
                console.log('result if 1.1 '+Object.keys(result));
                console.log('result if 1.2 '+sec.objectapiName);
                // Find matching SObject (case-insensitive)
                const matchedObjectKey = Object.keys(result).find(
                    (key) => key.toLowerCase() === sec?.objectapiName?.toLowerCase()
                );

                console.log('result if 2');

                const sObjectData = matchedObjectKey ? result[matchedObjectKey] : {};

                const clonedSection = {
                    ...sec,
                    fields: sec.fields.map((field) => {
                        // Match field name (case-insensitive)
                        const matchedFieldKey = Object.keys(sObjectData || {}).find(
                            (key) => key.toLowerCase() === field.apiName.toLowerCase()
                        );

                        // Only add value if a match exists
                        if (matchedFieldKey) {
                            return {
                                ...field,
                                value: sObjectData[matchedFieldKey]
                            };
                        }

                        console.log('result if 3');

                        // Return field as-is if no match
                        return { ...field };
                    })
                };
                console.log('result if 4');
                return clonedSection;
            });

            console.log('this.formMetadata '+this.formMetadata);
        } catch (error) {
            console.error('Error fetching user person account info:', error);
        }
    }

    handleFieldSelect(event) {
    const { section, field, row } = event.target.dataset;
    const checked = event.target.checked;

    const correction = {
        Section_Object_API__c: section,
        Field_API__c: field,
        Row_Index__c: row ? parseInt(row, 10) : null
    };

    if (checked) {
        this.selectedCorrections.push(correction);
    } else {
        this.selectedCorrections = this.selectedCorrections.filter(
            c => !(c.Section_Object_API__c === section && c.Field_API__c === field && c.Row_Index__c === (row ? parseInt(row, 10) : null))
        );
    }
}

handleRemarkChange(event) {
    const { section, field, row } = event.target.dataset;
    const remark = event.target.value;

    const correction = this.selectedCorrections.find(
        c => c.Section_Object_API__c === section && c.Field_API__c === field && c.Row_Index__c === (row ? parseInt(row, 10) : null)
    );
    if (correction) correction.Staff_Remark__c = remark;
}

handleSave() {
    saveCorrectionRequests({
        appId: this.recordId,
        correctionsJson: JSON.stringify(this.selectedCorrections)
    })
        .then(() => {
            this.showToast('Correction Requests created successfully!');
            this.closeModal();
        })
        .catch(error => {
            console.error(error);
        });
}


}