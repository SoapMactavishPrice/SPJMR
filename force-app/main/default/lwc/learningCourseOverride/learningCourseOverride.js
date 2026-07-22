import { LightningElement } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { createRecord } from 'lightning/uiRecordApi';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

import LEARNING_OBJECT from '@salesforce/schema/Learning';
import LEARNING_NAME from '@salesforce/schema/Learning.Name';

export default class LearningCourseOverride extends NavigationMixin(LightningElement) {

    handleSubmit(event) {

        event.preventDefault();

        const fields = event.detail.fields;
        const courseName = fields.Name;

        // STEP 1 — Create Learning
        const learningFields = {};
        learningFields[LEARNING_NAME.fieldApiName] = courseName;

        const learningInput = {
            apiName: LEARNING_OBJECT.objectApiName,
            fields: learningFields
        };

        createRecord(learningInput)
            .then(learningRecord => {

                // STEP 2 — Inject LearningId
                fields.LearningId = learningRecord.id;

                // STEP 3 — Submit LearningCourse
                this.template
                    .querySelector('lightning-record-edit-form')
                    .submit(fields);

            })
            .catch(error => {
                this.showToast('Error', 'Error creating Learning', 'error');
                console.error(error);
            });
    }

    handleSuccess(event) {

        this.showToast('Success', 'Course Created Successfully', 'success');

        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId: event.detail.id,
                objectApiName: 'LearningCourse',
                actionName: 'view'
            }
        });
    }

    handleError(event) {
        console.error(event.detail);
        this.showToast('Error', 'Error saving Course', 'error');
    }

    showToast(title, message, variant) {
        this.dispatchEvent(
            new ShowToastEvent({
                title: title,
                message: message,
                variant: variant
            })
        );
    }
}