/**
 * @description       LWC for dynamic configuration of an Application Form.
 *                    Enables administrators to:
 *                    - Fetch and display SObject fields dynamically
 *                    - Build configurable form sections
 *                    - Drag and drop fields into sections
 *                    - Set dependencies and validations
 *                    - Save form configuration as JSON linked to a Program
 *
 * @author            Shashank Mishra
 * 
 */

import { LightningElement, track, wire } from 'lwc';

// Apex method imports
import getApplicationFields from '@salesforce/apex/ApplicationFormHelper.getApplicationFields';
// import getObjectList from '@salesforce/apex/ApplicationFormHelper.getObjectList';
import saveForm from '@salesforce/apex/ApplicationFormHelper.saveForm';
import getDocumentList from '@salesforce/apex/ApplicationFormHelper.getDocumentList';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getProgramList from  '@salesforce/apex/ApplicationFormHelper.getProgramList';
import getActiveFormById from  '@salesforce/apex/ApplicationFormHelper.getActiveFormById';

export default class ApplicationFormConfigurator extends LightningElement {
    @track object='Personal_Detail__c';
    @track isLoading=false;
    @track fields = [];
     @track activeSections = []; // tracks opened accordion sections
    @track objectsOptions = [
        {
            label: 'Application',
            value: 'Application__c'
        },
        {
            label: 'Personal Summary',
            value: 'Personal_Summary__c'
        },
        {
            label: 'Personal Details',
            value: 'Personal_Detail__c'
        },
        {
            label: 'Program Details',
            value: 'Program_Detail__c'
        },
        {
            label: 'Personal Information- Address for Correspondence',
            value: 'Address_Information_Application__c'
        },
        {
            label: 'Professional Qualification',
            value: 'Professional_Qualification__c'
        },
        {
            label: 'Academic Details',
            value: 'Academic_Detail__c'
        },
        {
            label: 'Graduation Details - Semester wise details',
            value: 'Graduation_Details_Semester_wise__c'
        },
        {
            label: 'Competitive Exam Details',
            value: 'Competitive_Exam_Details__c'
        },
        {
            label: 'Competitive Exam GMAT Focus Edition',
            value: 'Competitive_Exam_GMAT_Focus_Edition__c'
        },
        {
            label: 'Work Experience',
            value: 'Work_Experience__c'
        },
        {
            label: 'Functional Areas you worked in',
            value: 'Functional_Areas_That_You_Have_Worked_In__c'
        },
        {
            label: 'General Details',
            value: 'General_Detail__c'
        },
        {
            label: 'Venture',
            value: 'Venture__c'
        },
        {
            label: 'Family Details',
            value: 'Family__c'
        },
        {
            label: 'Family Background',
            value: 'Family_Background__c'
        },
        {
            label: 'Family Business',
            value: 'Family_Business_Company_Details_Sales__c'
        }
        ,
        {
            label: 'Information Source',
            value: 'Information_Source__c'
        },
        {
            label: 'Mentor Details',
            value: 'Mentor_Details__c'
        },
        {
            label: 'Document Library',
            value: 'Document__c'
        },
        {
            label: 'Awards and Accolades',
            value: 'Awards_and_Accolades__c'
        },
        {
            label: 'Versatility',
            value: 'Versatility__c'
        },
        {
            label: 'Declaration',
            value: 'Declaration__c'
        },
        {
            label: 'Versatility & Achievements - Responsibilities Shouldered',
            value: 'ResponsibilityShouldered__c'
        }
    ];
    @track tempfields = [];
    @track sections = [];
    searchKey = '';
    draggedField;

    /**
     * @description Invoked once component is inserted into the DOM.
     *              Loads default object fields initially.
     */

    connectedCallback(){
        this.getApplicationFieldsJs();
    }

    //get program list
    // ===============================================
    // 🎓 Program List Wire Adapter
    // ===============================================

    /**
     * @description Fetches list of available Programs from Apex.
     * Populates the Program dropdown.
     */
    @track programList

    @wire(getProgramList)
    wiredObjectList({ data, error }) {
        if (data) {
            //Original list of program
            var recs=[];
            data.forEach(element => {
                var obj={};
                obj.label=element.Name;
                obj.value=element.Id;
                recs.push(obj);
            });
            this.programList = recs;
        } else if (error) {
            this.showToast('Error', error.body.message, 'error');
        }
    }

     // ===============================================
    // 🧩 Section Management
    // ===============================================

    /**
     * @description Adds a new section to the form configuration.
     * @param {String} labelvar - Section label.
     * @param {String} objectapiname - Related SObject API name.
     */

    addSection(labelvar,objectapiname) {
        console.log('labelvar ',labelvar);
        console.log('objectapiname ',objectapiname);

        const allowMultipleSection = ['Academic_Detail__c','Work_Experience__c'];
        
        // ✅ Check if section already exists
        const alreadyExists = this.sections.some(
            section => section.objectapiName === objectapiname && !allowMultipleSection.includes(section.objectapiName)
        );

        if (alreadyExists) {
            this.showToast('',`Section is already exists`,'info');
            return;
        }
         // Build fieldsOptions for each section
        this.sections = [
            ...this.sections,
            { id: Date.now().toString()+labelvar, label: labelvar,objectapiName:objectapiname,isQuestSection:false,repeatable:false, fields: [],fieldOptions:[],relatedtoSection:'',isHidden:false }
        ];
        // console.log('this.sections ',JSON.stringify(this.sections));
        // auto-expand newly added section
        // this.activeSections = [...this.activeSections, Date.now().toString()+labelvar];
        this.activeSections = [Date.now().toString()+labelvar];
        // console.log(JSON.stringify(this.activeSections));
    }

    /**
     * @description Deletes a section from the configuration.
     *               Also unselects its fields from the available list.
     * @param {Event} event - Event containing section id.
     */
    deleteSection(event) {
        console.log();
        
        const sectionIndex = this.sections.findIndex(s => s.id === event.target.dataset.id);
        console.log('sectionIndex ',sectionIndex);
        console.log('sectionIndex ',JSON.stringify(this.tempfields));
        
        if (sectionIndex !== -1) {
            const fields=this.sections[sectionIndex].fields;
            fields.forEach(field => {
                this.tempfields.find(f => f.apiName === field.apiName).isSelected=false;
            });
            this.sections.splice(sectionIndex, 1);
             console.log('this.sections ',JSON.stringify(this.sections));
        }
        this.activeSections = this.activeSections.filter(secId => secId !== event.target.dataset.id);

        
    }

    /**
     * @description Removes a single field from a specific section.
     * @param {Event} event - Contains section and field identifiers.
     */

    removeSectionFields(event) {
        // console.log('event.target.dataset.secid ',event.target.dataset.secid);
        // console.log('event.target.dataset.fieldid ',event.target.dataset.fieldid);
        
      const sectionIndex = this.sections.findIndex(s => s.id === event.target.dataset.secid);
      const fieldIndex = this.sections[sectionIndex].fields.findIndex(s => s.id === event.target.dataset.fieldid);
    //    console.log('event.target.dataset.secid ',sectionIndex);
    //     console.log('event.target.dataset.fieldid ',fieldIndex);
        
        if (sectionIndex !== -1) {
            this.sections[sectionIndex].fields.splice(fieldIndex, 1);
        }
        this.tempfields.find(f => f.apiName === event.target.dataset.apiname).isSelected=false;
        
    }

    // ===============================================
    // 🖱️ Drag & Drop Field Handling
    // ===============================================

    /**
     * @description Captures the field being dragged.
     * @param {Event} event - Drag start event with field API name.
     */

    handleDragStart(event) {
        const api = event.target.dataset.api;
        this.draggedField = this.fields.find(f => f.apiName === api);
        console.log('draggedField ',this.draggedField);
        
    }

    /**
     * @description Allows field drop in a valid target section.
     * @param {Event} event - Drag over event.
     */

    allowDrop(event) {
        event.preventDefault();
    }

    noneOptionForPicklist = { label: 'None', value: '' }

    /**
     * @description Handles dropping of a field into a section.
     * Updates that section’s field list and field options.
     * @param {Event} event - Drop event with section info.
     */
    handleDrop(event) {
    event.preventDefault();
    const sectionId = event.target.dataset.id;
    const sectionIndex = this.sections.findIndex(sec => sec.id === sectionId);

     // Update field options correctly using map
    //  console.log('sectionIndex ',JSON.stringify(this.fields));
             
        this.sections[sectionIndex].fieldOptions = [
            this.noneOptionForPicklist,
            ...this.fields.map(field => ({
                label: field.label,
                value: field.apiName
            }))
        ];
        
        // console.log('sectionIndex ',this.sections[sectionIndex].fieldOptions);
         this.sections[sectionIndex].isHidden = this.sections[sectionIndex].label.includes('Semester') ?true:false;
    if (sectionIndex !== -1 && this.draggedField) {
        const newField = {
            id: Date.now().toString(),
            apiName: this.draggedField.apiName,
            label: !this.draggedField.isDocument ?this.draggedField.label:'Upload '+this.draggedField.label,
            description: this.draggedField?.description,
            type: this.draggedField.type,
            isFileUpload: this.draggedField.isDocument,
            isPicklist: this.draggedField.type === 'PICKLIST',
            isEditDisabled: this.draggedField.isCalculated,
            isLookup: this.draggedField.type === 'REFERENCE',
            isQuestion:this.draggedField.apiName== 'question__c'?true:false,
            isAnswer:this.draggedField.apiName== 'answer__c'?true:false,
            isQualification: this.draggedField.apiName === 'qualifications__c',
            questionText:'',
            options: this.draggedField.type === 'PICKLIST' ? (this.draggedField.options || []) : [],
            dependencies:false,
            validation: {
                required: false,
                minLength: null,
                maxLength: null,
                pattern: null,
                dependency: { fieldApi: '', expectedValue: '' },
                dependencyValuesOptions: []
            }
        };

        // 👉 Lookup support
        if (this.draggedField.type === 'REFERENCE') {
            newField.lookupObject = this.draggedField.referenceTo || null;   // Apex must send this
            newField.displayField = this.draggedField.displayField || 'Name';
        }


        this.sections[sectionIndex].fields = [
            ...this.sections[sectionIndex].fields,
            newField
        ];
        // console.log('this.draggedFieldIndex ',this.draggedFieldIndex);
        
        this.fields.find(f => f.apiName === this.draggedField.apiName).isSelected=true;
        const fieldToAddIndex = this.tempfields.findIndex(f => f.apiName === this.draggedField.apiName);
        console.log('fieldToAddIndex ',fieldToAddIndex);
        if (fieldToAddIndex > -1) {
            const updatedField = {
                ...this.tempfields[fieldToAddIndex],
                isSelected: true
            };
            this.tempfields = [
                ...this.tempfields.slice(0, fieldToAddIndex),
                updatedField,
                ...this.tempfields.slice(fieldToAddIndex + 1)
            ];
        }
        // console.log('Updated tempfields:', JSON.stringify(this.tempfields));
        console.log('sections:', JSON.stringify(this.sections));
        
    }
}

    /**
     * @description Updates the label for a given section.
     * @param {Event} event - Input change event with section id.
     */
    handleSectionLabelChange(event) {
        const id = event.target.dataset.id;
        const sectionIndex = this.sections.findIndex(s => s.id === id);
        if (sectionIndex !== -1) {
            this.sections[sectionIndex].label = event.target.value;
            if(this.sections[sectionIndex].objectapiName ==undefined){
                this.sections[sectionIndex].objectapiName = event.target.value;
            }
        }
    }

    /**
     * @description Updates qualification value for a qualification-type field.
     * @param {Event} event - Change event for qualification dropdown.
     */
    handleQualificationChange(event){
         const id = event.target.dataset.secid;
        const sectionIndex = this.sections.findIndex(s => s.id === id);
        const fieldIndex = this.sections[sectionIndex].fields.findIndex(s => s.id === event.target.dataset.fieldid);
        if (sectionIndex !== -1) {
            this.sections[sectionIndex].fields[fieldIndex].value=event.target.value;
        }
        console.log('===> ',JSON.stringify(this.sections));
        
    }

     /**
     * @description Updates question text for a specific field in a section.
     * @param {Event} event - Input event with section & field identifiers.
     */

    handleQuestionChange(event){
        // console.log('event.target.dataset.secid ',event.target.dataset.secid);
        // console.log('event.target.dataset.fieldid ',event.target.dataset.fieldid);
        
      const sectionIndex = this.sections.findIndex(s => s.id === event.target.dataset.secid);
      const fieldIndex = this.sections[sectionIndex].fields.findIndex(s => s.id === event.target.dataset.fieldid);
    //    console.log('event.target.dataset.secid ',sectionIndex);
    //     console.log('event.target.dataset.fieldid ',fieldIndex);
        
        if (sectionIndex !== -1) {
            this.sections[sectionIndex].fields[fieldIndex].questionText=event.target.value;
        }
    }

    /**
     * @description Updates validation settings (required, min/max length) for a specific field.
     * @param {Event} event - Input event containing section & field IDs.
     */

     handleValidationChange(event) {
            const sectionId = event.target.dataset.secid;
            const fieldId = event.target.dataset.fieldid;
            
            this.sections = this.sections.map(section => {
                if (section.id === sectionId) {
                    section.fields = section.fields.map(f => {
                        if (f.id === fieldId) {
                            if (event.target.type === 'checkbox') {
                                f.validation.required = event.target.checked;
                            } else if (event.target.type === 'number') {
                                if(event.target.dataset.len =='maxlength'){
                                    f.validation.maxLength = parseInt(event.target.value, 10);
                                }else if(event.target.dataset.len =='minlength'){
                                    f.validation.minLength = parseInt(event.target.value, 10);
                                }
                            }
                        }
                        return f;
                    });
                }
                return section;
            });
        }

    /**
     * @description Handles dependent field selection.
     * Builds dependency metadata and possible value options dynamically.
     * @param {Event} event - Picklist change event.
     */
    // handleDependencyChange(event) {
    //     const sectionId = event.target.dataset.secid;
    //     const fieldId = event.target.dataset.fieldid;
    //     const depFieldC = event.detail.value;

    //     this.sections = this.sections.map(section => {
    //         if (section.id === sectionId) {

    //              const depField = section.fields.find(f => f.apiName === depFieldC);
    //             console.log('depField ',JSON.stringify(depField));
                
    //             section.fields = section.fields.map(f => {
    //                 if (f.id === fieldId) {
    //                     f.validation.dependency = { fieldApi: event.detail.value, expectedValues: [] };

    //                     // Build value options dynamically for that field
    //                     f.validation.dependencyValuesOptions =depField && depField.isPicklist ? depField.options : [];
    //                     f.dependencies=true;
    //                 }
    //                 return f;
    //             });
    //         }
    //         return section;
    //     });

    //     //  console.log('this.sections ',JSON.stringify(this.sections));
    // }

    handleDependencyChange(event) {
        const sectionId = event.target.dataset.secid;
        const fieldId = event.target.dataset.fieldid;
        const depFieldC = event.detail.value;

        this.sections = this.sections.map(section => {
            if (section.id === sectionId) {
                const depField = section.fields.find(f => f.apiName === depFieldC);

                section.fields = section.fields.map(f => {
                    if (f.id === fieldId) {
                        // None / blank selected → reset dependency safely
                        if (!depFieldC || depFieldC === '' || depFieldC === 'None') {
                            f.validation.dependency = { fieldApi: null, expectedValues: [] };
                            f.validation.dependencyValuesOptions = [];
                            f.dependencies = false;
                        } else {
                            f.validation.dependency = {
                                fieldApi: depFieldC,
                                expectedValues: []
                            };
                            f.validation.dependencyValuesOptions =
                                depField && depField.isPicklist ? depField.options : [];
                            f.dependencies = true;
                        }
                    }
                    return f;
                });
            }
            return section;
        });
    }



    /**
     * @description Handles expected picklist value(s) for dependency.
     * @param {Event} event - Multi-select picklist event.
     */
    handleExpectedValueChange(event) {
        const sectionId = event.target.dataset.secid;
        const fieldId = event.target.dataset.fieldid;
        const selectedValues = event.detail.value; // array if multiple

        this.sections = this.sections.map(section => {
            if (section.id === sectionId) {
                section.fields = section.fields.map(f => {
                    if (f.id === fieldId && f.dependencies) {
                        f.validation.dependency.expectedValues = selectedValues;
                    }
                    return f;
                });
            }
            return section;
        });
        //  console.log('this.sections ',JSON.stringify(this.sections));
    }

    
    /**
     * @description Handles SObject selection change and reloads fields.
     * @param {Event} event - Object dropdown change event.
     */
    handleObjectChange(event){
        console.log('callin g');
        
        this.object=event.target.value;
        this.getApplicationFieldsJs();
        
    }

     /**
     * @description Handles Program selection and loads its existing configuration (if any).
     * @param {Event} event - Program dropdown change event.
     */
    @track programVal;
    handleprgoramChange(event){
        this.isLoading=true;
        this.programVal=event.target.value;
        this.getActiveFormByIdJs();
      
    }

    /**
     * @description Fetches active form configuration JSON for selected Program.
     * Decodes HTML entities and parses JSON into usable sections.
     */
    async getActiveFormByIdJs() {
        this.isLoading = true;
        try {
            // ⏳ wait for server response
            const data = await getActiveFormById({ programId: this.programVal });
            console.log('getActiveFormByIdJs ', data);
            // Decode HTML entities
            let decoded = data
                .replace(/&quot;/g, '"')
                .replace(/&amp;/g, '&')
                .replace(/&#39;/g, "'");
            console.log('decoded ', decoded);
            // Parse JSON
            let parsed = JSON.parse(decoded);
            console.log('parsed ', parsed);

            // Inject fieldOptions into each section
            let secExist = parsed.map(sec => ({
                ...sec,
                fieldOptions: [
                    this.noneOptionForPicklist,
                    ...this.fields.map(field => ({
                        label: field.label,
                        value: field.apiName
                    }))
                ]
            }));


            // Assign to sections after waiting
            this.sections = secExist;
            console.log('getActiveFormByIdJs ', JSON.stringify(this.sections));

            // Now wait for getApplicationFieldsJs() to finish
            this.getApplicationFieldsJs();
            setTimeout(() => {
                this.isLoading = false;
            }, 2000);
        } catch (e) {
            // console.error('Error parsing or fetching JSON: ', e);
            this.isLoading = false;
        }
    }
    @track allSearchFields=[];

    /**
     * @description Fetches fields for the selected SObject.
     * Supports both standard form objects and Document objects.
     */
    getApplicationFieldsJs() {
    if (this.object === 'Document__c') {
        getDocumentList()
            .then(data => {
                console.log('data ', JSON.stringify(data));

                const fieldsWithObject = data.map(field => {
                    return {
                        ...field,
                        objectName: this.object,
                        // isSelected: this.sections.some(sec =>
                        //     sec.fields.some(sf => sf.apiName === field.apiName)
                        // )
                    };
                });

                // merge unique fields
                this.fields = [
                    ...this.fields,
                    ...fieldsWithObject.filter(
                        newField =>
                            !this.fields.some(
                                existing =>
                                    existing.apiName === newField.apiName &&
                                    existing.objectName === newField.objectName
                            )
                    )
                    .map(newField => {
                        // Check if this new field already exists in any section
                        const found = this.sections?.some(sec =>
                            sec.fields.some(sf => sf.apiName === newField.apiName)
                        );

                        return {
                            ...newField,
                            isSelected: found || false
                        };
                    })
                ];

                // tempfields only for this object
                this.tempfields = this.fields.filter(
                    f => f.objectName === this.object
                );

                this.allSearchFields=this.tempfields;
                // console.log('this.fields ', JSON.stringify(this.fields));
                // console.log('this.tempfields ', JSON.stringify(this.tempfields));
            })
            .catch(error => {
                console.log('error ', error);
                this.error = error;
            });
    } else {
        getApplicationFields({ objectvar: this.object })
            .then(data => {
                if (!this.fields) {
                    this.fields = [];
                }
                // console.log('getApplicationFields ', JSON.stringify(this.sections));
                
                const fieldsWithObject = data.map(field => {
                    return {
                        ...field,
                        objectName: this.object,
                        isSelected: this.sections.some(sec =>
                            sec.fields.some(sf => sf.apiName === field.apiName)
                        )
                    };
                });
                // console.log('getApplicationFields ', JSON.stringify(fieldsWithObject));

                // merge unique fields
                this.fields = [
                    ...this.fields,
                    ...fieldsWithObject.filter(
                        newField =>
                            !this.fields.some(
                                existing =>
                                    existing.apiName === newField.apiName &&
                                    existing.objectName === newField.objectName
                            )
                    )
                    .map(newField => {
                        // Check if this new field already exists in any section
                        const found = this.sections?.some(sec =>
                            sec.fields.some(sf => sf.apiName === newField.apiName)
                        );

                        return {
                            ...newField,
                            isSelected: found || false
                        };
                    })
                ];
                console.log('this.tempfields ', JSON.stringify(this.fields));
                // tempfields only for this object
                this.tempfields = this.fields.filter(
                    f => f.objectName === this.object
                );

                // console.log('this.fields ', JSON.stringify(this.fields));
                // console.log('this.tempfields ', JSON.stringify(this.tempfields));
                this.allSearchFields=this.tempfields;

                // add default section
                if (this.object === 'Application__c') {
                    this.addSection('Personal Details', this.object);
                } else {
                    const sectionname = this.objectsOptions.find(
                        row => row.value == this.object
                    );
                    this.addSection(sectionname.label, this.object);
                }
            })
            .catch(error => {
                this.showToast('Error', error.body.message, 'error');
            });
    }
}

    /**
     * @description Filters field list dynamically based on search input.
     * @param {Event} event - Search input change event.
     */
    handleSearchChange(event) {
        this.searchKey = event.target.value.trim().toLowerCase();
        if (!this.searchKey) {
            this.tempfields = this.allSearchFields;
        } else {
            this.tempfields = this.allSearchFields.filter(field =>
                field?.label?.toLowerCase().includes(this.searchKey) ||
                (field?.description && field?.description?.toLowerCase().includes(this.searchKey))
            );
        }
    }

    /**
     * @description Persists current form configuration to server as JSON.
     * Removes UI-only properties before serialization.
     */
    saveForm() {
        try {
            // const formJson = JSON.stringify(this.sections);
            // console.log('formJson ',formJson);
            // remove fieldOptions at section level and inside fields
            const cleanSections = this.sections.map(({ fieldOptions, ...section }) => {
                return {
                    ...section,
                    fields: section.fields.map(({ fieldOptions, ...field }) => {
                        return field;
                    })
                };
            });

            const formJson = JSON.stringify(cleanSections);
            console.log('formJson ', formJson);
            saveForm({
                name: 'Application Form',
                htmlBody: formJson,
                programId:this.programVal
            })
                .then(() => {
                    this.showToast('Saved', 'Form Saved as JSON!', 'success');
                })
                .catch(error => {
                    this.showToast('Error', error.body.message, 'error');
                });
        } catch (err) {
            this.showToast('Error', err.message, 'error');
        }
    }

    /**
     * @description Displays a standard Lightning Toast notification.
     * @param {String} title - Toast header text.
     * @param {String} message - Toast body text.
     * @param {String} variant - Type (success, error, info, warning).
     */
    showToast(title, message, variant) {
        this.dispatchEvent(
            new ShowToastEvent({
                title,
                message,
                variant
            })
        );
    }

    /**
     * @description Adds a field manually to a section when user clicks "Add" instead of dragging.
     * Ensures the same object and field uniqueness logic as drag-drop.
     * @param {Event} event - Click event containing dataset.api and dataset.sectionname.
     */
    handleAddField(event) {
        const apiName = event.target.dataset.api;
        const sectionName = event.target.dataset.sectionname;

        const fieldToAdd = this.fields.find(f => f.apiName === apiName);
        // console.log('this.tempfields ',JSON.stringify(this.tempfields));
        
        if (!fieldToAdd) return;

        const sectionIndex = this.sections.findIndex(sec => sec.objectapiName === sectionName);
        if (sectionIndex === -1) return;

        // console.log('sectionIndex ',JSON.stringify(this.fields));
        // Update field options correctly using map
        this.sections[sectionIndex].fieldOptions = [
            this.noneOptionForPicklist,
            ...this.fields.map(field => ({
                label: field.label,
                value: field.apiName
            }))
        ];
         this.sections[sectionIndex].isHidden = this.sections[sectionIndex].label.includes('Semester') ?true:false;
        // console.log('this.sections[sectionIndex].fieldOptions ',JSON.stringify(this.sections[sectionIndex].fieldOptions));
        

        // Create new field object
        const newField = {
            id: Date.now().toString(),
            apiName: fieldToAdd.apiName,
            description: !fieldToAdd.isDocument ?fieldToAdd.description:'Upload '+fieldToAdd.label,
            label: !fieldToAdd.isDocument ?fieldToAdd.label:'Upload '+fieldToAdd.label,
            type: fieldToAdd.type,
            isFileUpload: fieldToAdd.isDocument,
            isPicklist: fieldToAdd.type === 'PICKLIST',
            isEditDisabled: fieldToAdd.isCalculated,
            isLookup: fieldToAdd.type === 'REFERENCE',
            isQuestion: fieldToAdd.apiName === 'question__c',
            isAnswer: fieldToAdd.apiName === 'answer__c',
            isQualification: fieldToAdd.apiName === 'qualifications__c',
            questionText: '',
            options: fieldToAdd.type === 'PICKLIST' ? (fieldToAdd.options || []) : [],
            dependencies: false,
            validation: {
                required: false,
                minLength: null,
                maxLength: null,
                pattern: null,
                dependency: { fieldApi: '', expectedValue: '' },
                dependencyValuesOptions: []
            },
            ...(fieldToAdd.type === 'REFERENCE' && {
                lookupObject: fieldToAdd.referenceTo || null,
                displayField: fieldToAdd.displayField || 'Name'
            })
            
        };

       

        // Push new field into section fields
        this.sections[sectionIndex].fields = [
            ...this.sections[sectionIndex].fields,
            newField,
            
        ];
        // mark as selected
        // ✅ Correct way: clone and replace instead of direct mutation
        this.fields.find(f => f.apiName === apiName).isSelected=true;
        const fieldToAddIndex = this.tempfields.findIndex(f => f.apiName === apiName);
        // console.log('fieldToAddIndex ',fieldToAddIndex);
        if (fieldToAddIndex > -1) {
            const updatedField = {
                ...this.tempfields[fieldToAddIndex],
                isSelected: true
            };
            this.tempfields = [
                ...this.tempfields.slice(0, fieldToAddIndex),
                updatedField,
                ...this.tempfields.slice(fieldToAddIndex + 1)
            ];
        }

        console.log('sections:', JSON.stringify(this.sections));
    }

     /**
     * @description Duplicates all existing fields in a section as new "question" fields.
     * Used to dynamically create question-answer pair layouts.
     * @param {Event} event - Click event with dataset.sectionname.
     */
    addQuestion(event) {
        console.log('event.target.dataset.sectionname ',event.target.dataset.sectionname);
        const sectionname = event.target.dataset.sectionname;
        const sectionIndex = this.sections.findIndex(sec => sec.objectapiName === sectionname);
        if (sectionIndex === -1) return;

        const fieldAllToAdd = this.sections[sectionIndex].fields;
        console.log('fieldToAdd ',JSON.stringify(fieldAllToAdd));
        //add all fields again in the section
        fieldAllToAdd.forEach(fieldToAdd => {
            console.log('fieldToAdd ',JSON.stringify(fieldToAdd));
            const newField = {
            id: Date.now().toString(),
            apiName: fieldToAdd.apiName,
            label: fieldToAdd.label,
            description: fieldToAdd?.description,
            type: fieldToAdd.type,
            isPicklist: fieldToAdd.type === 'PICKLIST',
            isEditDisabled: fieldToAdd.isCalculated,
            isFileUpload: fieldToAdd.isDocument,
            isLookup: fieldToAdd.type === 'REFERENCE',
            isQuestion:fieldToAdd.apiName== 'question__c'?true:false,
            isAnswer:fieldToAdd.apiName== 'answer__c'?true:false,
            questionText:'',
            options: fieldToAdd.type === 'PICKLIST' ? (fieldToAdd.options || []) : [],
            dependencies:false,
            validation: {
                required: false,
                minLength: null,
                maxLength: null,
                pattern: null,
                dependency: { fieldApi: '', expectedValue: '' },
                dependencyValuesOptions: []
            }
        };

        this.sections[sectionIndex].fields = [
            ...this.sections[sectionIndex].fields,
            newField
        ];
        });


        
        //  console.log('this.sections ',JSON.stringify(this.sections));
    }

    draggedFieldIndex = null;
    draggedSectionId = null;

    /**
     * @description Captures the index and section of a field being dragged within a section.
     * Enables intra-section reordering.
     * @param {Event} event - Drag start event containing field index and section id.
     */
    handleFieldDragStart(event) {
        this.draggedFieldIndex = parseInt(event.currentTarget.dataset.index, 10);
        this.draggedSectionId = event.currentTarget.dataset.secid;
        console.log('draggedFieldIndex ',this.draggedFieldIndex);
        console.log('draggedSectionId ',this.draggedSectionId);
        
    }

    /**
     * @description Handles drop event when reordering fields within a section.
     * Moves the dragged field to the new target position.
     * @param {Event} event - Drop event containing target field index and section id.
     */
    handleFieldDrop(event) {
        event.preventDefault();

        const targetIndex = parseInt(event.currentTarget.dataset.index, 10);
        const targetSectionId = event.currentTarget.dataset.secid;

        console.log('targetIndex ',this.targetIndex);
        console.log('targetSectionId ',this.targetSectionId);

        // Only reorder if dropping in the same section
        if (this.draggedSectionId === targetSectionId) {
            const sectionIndex = this.sections.findIndex(s => s.id === targetSectionId);
            if (sectionIndex !== -1) {
                const fields = [...this.sections[sectionIndex].fields];

                // Remove dragged field and insert at target
                const [movedField] = fields.splice(this.draggedFieldIndex, 1);
                fields.splice(targetIndex, 0, movedField);

                this.sections[sectionIndex].fields = fields;
            }
        }

        this.draggedFieldIndex = null;
        this.draggedSectionId = null;
    }

    /**
     * @description Toggles repeatable or question-section attributes.
     * @param {Event} event - Checkbox change event.
     */
    handleSectionRequiredChange(event){
        const sectionIndex = this.sections.findIndex(s => s.id === event.target.dataset.id);
        if (sectionIndex !== -1) {
            this.sections[sectionIndex].repeatable = event.target.checked;
            this.sections[sectionIndex].isQuestSection = this.sections[sectionIndex].objectapiName === 'Personal_Summary__c' ? true : false;
        }
    }

     /**
     * @description Toggles repeatable or question-section attributes.
     * @param {Event} event - Checkbox change event.
     */
    handleRelatedToChange(event){
        const sectionIndex = this.sections.findIndex(s => s.id === event.target.dataset.id);
        if (sectionIndex !== -1) {
            this.sections[sectionIndex].relatedtoSection = event.target.value;
        }
    }
    
}