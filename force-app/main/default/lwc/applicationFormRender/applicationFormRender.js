/**
 * @description       LWC: ApplicationFormRender
 *                    Renders a configurable multi-section Application Form dynamically from
 *                    JSON metadata stored in Salesforce. Supports data prefill, repeatable
 *                    sections, lookup search, file uploads, and step-by-step navigation.
 *
 * @author            Shashank Mishra
 * @since             2025-10-29
 * @lastModifiedBy    Shashank Mishra
 * @dependencies      ApplicationFormHelper Apex class
 */
import { LightningElement, wire, track,api } from 'lwc';
import getActiveForm from '@salesforce/apex/ApplicationFormHelper.getActiveForm';
import getApplicationData from '@salesforce/apex/ApplicationFormHelper.getApplicationData';
import getLatestApplicationScript from '@salesforce/apex/ApplicationFormHelper.getLatestApplicationScript';
import getApplicationDataWithCorrections from '@salesforce/apex/ApplicationCorrectionModal.getApplicationDataWithCorrections'
import saveApplicationScriptToFile from '@salesforce/apex/ApplicationFormHelper.saveApplicationScriptToFile';
import createApplication from '@salesforce/apex/ApplicationFormHelper.createApplication';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { CurrentPageReference } from 'lightning/navigation';
import searchLookup from '@salesforce/apex/ApplicationFormHelper.searchLookup';
import uploadFile from '@salesforce/apex/ApplicationFormHelper.uploadFile';
import deleteFile from '@salesforce/apex/ApplicationFormHelper.deleteFile';

export default class ApplicationFormRender extends LightningElement {
    @track formMetadata = [];
    @track stepperGroups = [];
    @api programCode;
    @track isLoading = true;
    @track isAppdataexist = false;
    @track showThankyou = false;

    @api accData;

    /**
     * @wire(CurrentPageReference)
     * @description Reads the `c__programCode` parameter from the current page URL.
     * This allows the form to auto-load configuration for a specific program.
     */
    // Capture programCode from URL
    @wire(CurrentPageReference)
    getPageRef(pageRef) {
        if (pageRef && pageRef.state && pageRef.state.c__programCode) {
            this.programCode = pageRef.state.c__programCode;
            console.log('Program code:', this.programCode);
        }
    }

    gotScriptData = false;
    @track correctionMap;
     @track correctionList = null;
    connectedCallback() {
        this.isLoading = true;

        getApplicationDataWithCorrections({ programCode: this.programCode })
            .then(result => {
                console.log('OUTPUT getApplicationDataWithCorrections: ',JSON.stringify(result));
                if (result) {
                    if(result.status){
                        this.correctionList=[];
                        const app = result.application;
                        this.correctionList = result.corrections || [];
                    }
                   

                    // 🔹 Convert corrections list into a lookup map for quick access
                    // this.correctionMap = {};
                    // corrections.forEach(c => {
                    //     this.correctionMap[c.Field_API__c.toLowerCase()] = c;
                    // });

                    // 🔹 Get the script JSON from app.Script__c (ContentVersion)
                    //return getApplicationScriptById({ applicationId: app.Id });
                }
            })
            .catch(error => {
                console.error('Error loading application data:', error);
            })
            .finally(() => {
                this.isLoading = false;
            });
    }

    /**
     * @wire(getApplicationData)
     * @description Attempts to retrieve an existing application record
     * for the given program.  If a previous submission exists, it loads
     * the stored JSON (`script__c`) or, if newer, the latest ContentVersion
     * JSON via `getLatestApplicationScript`.  Otherwise, it falls back
     * to fetching the active form template.
     *
     * @param {Object} data - The returned record from Apex (may contain script__c).
     */
    @wire(getApplicationData, { programCode: '$programCode' })
    wiredForm({ data }) {
        console.log('getApplicationData data: ', data);
        if (data != null && data != undefined) {
            if(data.script__c!=null && data.script__c!=undefined){
                this.isLoading=true;
                this.isAppdataexist = true;
                getLatestApplicationScript({ programCode: this.programCode })
                .then(result => {
                    if (result) {
                        try {
                            const parsed = JSON.parse(result);
                            console.log('Loaded JSON from ContentVersion:', JSON.stringify(parsed));
                            this.initializeFromParsed(parsed, true);
                            this.gotScriptData = true;
                            this.isLoading = false;
                        } catch (e) {
                            console.error('Error parsing JSON from ContentVersion:', e);
                            this.getActiveFormJs();
                            this.isLoading=false;
                        }
                    } else {
                        this.getActiveFormJs();
                        this.isLoading=true;
                    }
                })
                .catch(error => {
                    console.error('Error fetching JSON file:', error);
                    this.getActiveFormJs();
                    this.isLoading=true;
                });
            }else{
                 this.getActiveFormJs();
            }
        } else {
            this.getActiveFormJs();
        }
    }
    

     /**
     * @description Retrieves the active published Application Form template
     * for the given program. The template is stored in `Form_HTML__c` as
     * JSON string, which is decoded and parsed for rendering.
     */
    getActiveFormJs() {
        getActiveForm({ programCode: this.programCode })
            .then(data => {
                if (data && !this.gotScriptData) {
                    let decoded = data.Form_HTML__c
                        .replace(/&quot;/g, '"')
                        .replace(/&amp;/g, '&')
                        .replace(/&#39;/g, "'");
                    try {
                        let parsed = JSON.parse(decoded);
                        console.log('Form_HTML__c ', JSON.stringify(parsed));
                        console.log('app if(data) imper');
                        this.initializeFromParsed(parsed, false);
                    } catch (e) {
                        console.error('Error parsing JSON from active form: ', e, decoded);
                    }
                }
            })
            .catch(error => {
                console.error('Error fetching active form: ', error);
                this.isLoading = false;
            });
    }

    /**
     * @description Initializes component state (`formMetadata`, stepper, etc.)
     * from parsed JSON.  Optionally merges pre-existing account data into
     * the fields when rendering the form for the first time.
     *
     * @param {Object[]} parsed - Parsed JSON sections.
     * @param {Boolean} isAppData - True if loading saved application data.
     */
    initializeFromParsed(parsed, isAppData) {
        // keep parsed as base formMetadata
        // clone and ensure arrays/flags exist
        // this.formMetadata = parsed.map((sec) => {
        //     return { ...sec }; // do not mutate original parsed object
        // });


        if(!isAppData && this.accData) {
            try {
                const result = this.accData;
                console.log('result '+JSON.stringify(this.accData));
                if (result && Object.keys(result).length > 0) {
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
                }
            } catch (error) {
                console.error('Error fetching user person account info:', error);
            }
        } else {
            this.formMetadata = [];
            this.formMetadata = parsed.map((sec) => {
                return { ...sec }; // do not mutate original parsed object
            });
        }
        

        

        // Prepare repeatable rows for sections right away
        this.prepareRepeatableRows();

        // Build stepper groups and activate first step (or preserve if available)
        this.buildStepperGroups();

        // If none active, activate first
        this.setFirstStepActive();

        this.isLoading = false;
        console.log('initializeFromParsed ',JSON.stringify(this.formMetadata));
    }

    /**
     * @description Prepares repeatable sections in the form metadata.
     * Adds runtime structures (`rows`) for repeatable or "questionnaire" type sections.
     * This allows the UI to render one or more rows of inputs per section.
     */
    prepareRepeatableRows() {
        if (!this.formMetadata) return;

        this.formMetadata = this.formMetadata.map(section => {
            // Quest-style repeatable (special handling)
            if (section.repeatable && section.isQuestSection) {
                let rows = [];
                let currentRow = {};
                section.fields.forEach(f => {
                    if (f.isQuestion) {
                        // push previous row if exists
                        if (Object.keys(currentRow).length > 0) {
                            rows.push(currentRow);
                        }
                        currentRow = {};
                        currentRow[f.apiName] = f.questionText || '';
                    } else {
                        if (f.isLookup) {
                            // lookup storing id + name
                            currentRow[f.apiName] = { id: null, name: null };
                        } else if (f.isAnswer) {
                            currentRow[f.apiName] = '';
                            // store field id to map answers back later
                            currentRow[f.id] = f.id;
                        } else {
                            currentRow[f.apiName] = '';
                        }
                    }
                });
                if (Object.keys(currentRow).length > 0) rows.push(currentRow);
                return { ...section, rows: rows };
            } else if (section.repeatable) {
                // Normal repeatable: start with one empty row of field objects
                return { ...section, rows: [this.createEmptyRow(section.fields)] };
            }
            return section;
        });
    }

    /**
     * @description Creates a single empty row structure for repeatable sections.
     * Initializes all field values to empty strings or defaults.
     * @param {Array} fields - Array of field metadata.
     * @returns {Array} Array of cloned field objects with runtime "value" key.
     */
    createEmptyRow(fields) {
        // return an array of field objects (deep copy) with runtime "value"
        return fields.map(f => {
            return { ...f, value:f.value!=''?f.value:'' };
        });
    }

    /**
     * Build stepperGroups from formMetadata using relatedtoSection
     * - Root sections (no relatedtoSection) become a step
     * - Sections with relatedtoSection are appended to the step of that parent
     * - Preserves previously active step if possible
     */
    buildStepperGroups() {
    // No metadata -> no steps
    if (!this.formMetadata) {
        this.stepperGroups = [];
        return;
    }

    // Preserve previously active step (if re-rendering)
    const prevActiveLabel = (this.stepperGroups.find(g => g.isActive) || {}).stepLabel;

    const groups = {};
    const ordered = [];

    // -------------------------------
    // FIRST PASS: Create groups for root sections
    // -------------------------------
    this.formMetadata.forEach(sec => {
        const key = sec.objectapiName || sec.id || sec.label;
        if (!sec.relatedtoSection || String(sec.relatedtoSection).trim() === '') {
            // Create a new group (label preferred)
            if (!groups[key]) {
                groups[key] = {
                    stepLabel: sec.label || sec.objectapiName || key,
                    sections: [sec],
                    stepClass: '',
                    isActive: false
                };
                ordered.push(groups[key]);
            } else {
                groups[key].sections.push(sec);
            }
        }
    });

    // -------------------------------
    // SECOND PASS: Attach child sections to parent
    // -------------------------------
    this.formMetadata.forEach(sec => {
        if (sec.relatedtoSection && String(sec.relatedtoSection).trim() !== '') {
            const parentKey = sec.relatedtoSection.trim();

            if (groups[parentKey]) {
                // Add to existing parent group
                groups[parentKey].sections.push(sec);
            } else {
                // Parent not found — create placeholder group (using label)
                console.warn(`⚠️ Parent not found for section "${sec.label}" (relatedTo: ${parentKey})`);
                groups[parentKey] = {
                    stepLabel: sec.label || sec.objectapiName || parentKey,
                    sections: [sec],
                    stepClass: '',
                    isActive: false
                };
                ordered.push(groups[parentKey]);
            }
        }
    });

    // -------------------------------
    // THIRD PASS: Handle any leftover/unattached sections
    // -------------------------------
    this.formMetadata.forEach(sec => {
        const isAdded = ordered.some(g => g.sections.includes(sec));
        if (!isAdded) {
            const key = sec.objectapiName || sec.id || sec.label;
            const grp = {
                stepLabel: sec.label || sec.objectapiName || key,
                sections: [sec],
                stepClass: '',
                isActive: false
            };
            ordered.push(grp);
        }
    });

    // -------------------------------
    // RESTORE PREVIOUS ACTIVE STEP
    // -------------------------------
    if (prevActiveLabel) {
        ordered.forEach(g => {
            g.isActive = g.stepLabel === prevActiveLabel;
        });
    }

    // -------------------------------
    // DEFAULT ACTIVE STEP (FIRST ONE)
    // -------------------------------
    if (!ordered.some(g => g.isActive) && ordered.length > 0) {
        ordered[0].isActive = true;
    }

    // Assign the final ordered groups
    this.stepperGroups = ordered;

    // -------------------------------
    // UPDATE CSS CLASSES
    // -------------------------------
    this.updateStepClasses();

    // Debug: print generated steps
    console.log('✅ Stepper Groups:', this.stepperGroups.map(g => g.stepLabel));
}

    /**
     * @description Ensures the first step is active if none are active.
     * Used immediately after building the stepper groups.
     */
    setFirstStepActive() {
        if (!this.stepperGroups || this.stepperGroups.length === 0) return;
        // if none active, activate first
        if (!this.stepperGroups.some(g => g.isActive)) {
            this.stepperGroups = this.stepperGroups.map((g, i) => {
                return { ...g, isActive: i === 0 };
            });
        } else {
            // ensure only one active
            let found = false;
            this.stepperGroups = this.stepperGroups.map((g, i) => {
                if (g.isActive && !found) {
                    found = true;
                    return { ...g, isActive: true };
                }
                return { ...g, isActive: false };
            });
        }
        this.updateStepClasses();
    }

    /** @description Returns total number of steps in the stepper. */
    get totalSteps() {
        return this.stepperGroups ? this.stepperGroups.length : 0;
    }

    /** @description Returns index of the currently active step. */
    get activeStepIndex() {
        if (!this.stepperGroups) return -1;
        return this.stepperGroups.findIndex(g => g.isActive);
    }

    /** @description Returns true if user is on the first step. */
    get isFirstStep() {
        const idx = this.activeStepIndex;
        return idx === 0 || idx === -1;
    }

    /** @description Returns true if user is on the last step. */
    get isLastStep() {
        const idx = this.activeStepIndex;
        return idx === this.totalSteps - 1;
    }

    
    /**
    * @description Validates all inputs within the currently active step.
    * Uses Lightning base component validity where available and shows messages.
    * Returns true if all inputs are valid; otherwise false.
    */
    validateCurrentStep() {
        try {
            const idx = this.activeStepIndex;
            if (idx === -1) return true; // nothing active yet

            const activeGroup = this.stepperGroups[idx];
            if (!activeGroup || !activeGroup.sections || activeGroup.sections.length === 0) {
                return true;
            }

            // Collect all inputs that belong to any section of the active group.
            const sectionIds = activeGroup.sections
                .filter(s => !s.isHidden)
                .map(s => s.id)
                .filter(Boolean);

            // Query all elements rendered for these sections.
            // We filter to elements that support checkValidity/reportValidity.
            let elements = [];
            sectionIds.forEach(secId => {
                const els = this.template.querySelectorAll(`[data-section="${secId}"]`);
                elements = elements.concat(Array.from(els));
            });

            // Deduplicate nodes (in case of any overlaps)
            const uniq = Array.from(new Set(elements));

            // Consider only Lightning base inputs/comboboxes that support validity API
            const inputs = uniq.filter(el => typeof el.reportValidity === 'function' && typeof el.checkValidity === 'function');

            // Run validation: first check, then report to surface messages
            let allValid = true;
            inputs.forEach(input => {
                const isValid = input.checkValidity();
                if (!isValid) {
                    allValid = false;
                }
            });
            // Always call reportValidity on all inputs in the active step to show any issues
            inputs.forEach(input => {
                try { input.reportValidity(); } catch (e) {}
            });

            return allValid;
        } catch (e) {
            // Fail-open to avoid blocking in case of unexpected issues, but log for troubleshooting
            console.error('validateCurrentStep error: ', e);
            return true;
        }
    }

     /**
     * @description Moves the user to the next step in the form.
     * Blocks navigation if required fields in the current step are not filled/invalid.
     */
    nextStep() {

        // Validate current step before moving forward
        const valid = this.validateCurrentStep();
        if (!valid) {
            this.showToast('Validation', 'Please complete all required fields before proceeding.', 'error');
            return;
        }

        let idx = this.activeStepIndex;
        if (idx < this.totalSteps - 1) {
            this.stepperGroups = this.stepperGroups.map((g, i) => ({ ...g, isActive: i === idx + 1 }));
            this.updateStepClasses();
        }
    }

    /**
     * @description Moves the user to the previous step in the form.
     */
    prevStep() {
        let idx = this.activeStepIndex;
        if (idx > 0) {
            this.stepperGroups = this.stepperGroups.map((g, i) => ({ ...g, isActive: i === idx - 1 }));
            this.updateStepClasses();
        }
    }

    /**
     * @description Updates visual progress classes (active/completed)
     * for Lightning stepper UI.
     */
    updateStepClasses() {
        const activeIdx = this.activeStepIndex;
        this.stepperGroups = this.stepperGroups.map((grp, idx) => {
            let stepClass = 'slds-progress__item';
            if (idx < activeIdx) stepClass += ' slds-is-completed';
            else if (idx === activeIdx) stepClass += ' slds-is-active';
            return { ...grp, stepClass };
        });
    }

    /* ------------------------
       Handlers (copied & integrated)
       ------------------------ */

    addRow(event) {
        const sectionId = event.target.dataset.section;
        this.formMetadata = this.formMetadata.map(section => {
            if (section.id === sectionId) {
                section.rows = [...(section.rows || []), this.createEmptyRow(section.fields)];
            }
            return section;
        });
        // force re-render
        this.formMetadata = [...this.formMetadata];
        // structure unchanged, but keep groups up-to-date
        this.buildStepperGroups();
    }

    removeRow(event) {
        const sectionId = event.target.dataset.section;
        const rowIndex = parseInt(event.target.dataset.row, 10);
        this.formMetadata = this.formMetadata.map(section => {
            if (section.id === sectionId) {
                if (Array.isArray(section.rows)) {
                    section.rows.splice(rowIndex, 1);
                    section.rows = [...section.rows];
                }
            }
            return section;
        });
        this.formMetadata = [...this.formMetadata];
        this.buildStepperGroups();
    }

    /**
     * @description Handles all form field changes.
     * Updates values inside repeatable or non-repeatable sections dynamically.
     * Includes dependency logic (e.g., field visibility or reset conditions).
     * 
     * @param {Event} event - Input or change event from a form field.
     */
    handleInputChange(event) {
    const sectionId = event.target.dataset.section;
    const rowIndex = event.target.dataset.row;
    const apiName = event.target.dataset.api;
    const value = event.detail ? event.detail.value : event.target.value;
    const fieldId = event.target.dataset.id;

    // --- Update field values ---
    this.formMetadata = this.formMetadata.map(section => {
        if (section.id === sectionId) {
            if (section.repeatable && section.isQuestSection) {
                const rows = section.rows || [];
                section.fields.forEach(fld => {
                    rows.forEach(row => {
                        if (fieldId && row[fld.id] && String(fieldId) === String(row[fld.id])) {
                            row['answer__c'] = value;
                        }
                    });
                });
            } else if (section.repeatable) {
                section.rows = section.rows.map((row, rIdx) => {
                    if (rIdx == rowIndex) {
                        row = row.map(fieldObj => {
                            try {
                                if (
                                    fieldObj.validation &&
                                    fieldObj.validation.dependency &&
                                    fieldObj.validation.dependency.fieldApi == apiName
                                ) {
                                    if (fieldObj.validation.dependency.expectedValues == value) {
                                        fieldObj.dependencies = false;
                                    } else {
                                        fieldObj.dependencies = true;
                                        fieldObj.value = '';
                                    }
                                }
                            } catch (e) {}

                            if (fieldObj.apiName === apiName) {
                                return { ...fieldObj, value: value };
                            }
                            return fieldObj;
                        });
                    }
                    return row;
                });
            } else {
                // Non-repeatable sections
                section.fields = section.fields.map(f => {
                    try {
                        if (
                            f.validation &&
                            f.validation.dependency &&
                            f.validation.dependency.fieldApi == apiName
                        ) {
                            if (f.validation.dependency.expectedValues == value) {
                                f.dependencies = false;
                            } else {
                                f.dependencies = true;
                                f.value = '';
                            }
                        }
                    } catch (e) {}

                    if (f.apiName === apiName) {
                        return { ...f, value: value };
                    }
                    return f;
                });
            }
        }
        return section;
    });

    /**
     * ----------------------------------------------------------
     * PATTERN OF EXAMINATION — DYNAMIC SEMESTER/YEAR GENERATION
     * ----------------------------------------------------------
     */
    // STEP 2️⃣ — Only proceed if pattern_of_examination__c changed
    if (apiName !== 'pattern_of_examination__c') {
        this.formMetadata = [...this.formMetadata];
        this.buildStepperGroups();
        return;
    }

    if (apiName === 'pattern_of_examination__c') {
    const currentSection = this.formMetadata.find(sec => sec.id === sectionId);
    if (!currentSection || !currentSection.rows?.length) return;

    const currentRow = currentSection.rows[rowIndex] || currentSection.rows[0];

    const qualificationValue =
        currentRow.find(f => f.apiName === 'qualifications__c')?.value || '';
    const degreeValue =
        currentRow.find(f => f.apiName === 'degree_type__c')?.value || '';
    const patternValue =
        currentRow.find(f => f.apiName === 'pattern_of_examination__c')?.value || value;

    console.log(
        `🧩 Pattern Changed: Qualification=${qualificationValue}, Degree=${degreeValue}, Pattern=${patternValue}`
    );

    // Determine number of years
    let yearCount = 0;
    if (degreeValue?.includes('3 Year')) yearCount = 3;
    else if (degreeValue?.includes('4 Year')) yearCount = 4;
    else if (degreeValue?.includes('5 Year')) yearCount = 5;
    else if (qualificationValue === 'Post Graduation') yearCount = 2;

    // 🧩 Update the shared "Graduation Details Semester wise" section
    this.formMetadata = this.formMetadata.map(sec => {
        if (sec.label.includes('Semester/Year')) {
            let updatedRows = sec.rows || [];

            // 🧹 STEP 1 — Remove rows for current qualification
            updatedRows = updatedRows.filter(r => {
                const q = r.find(f => f.apiName === 'qualifications__c');
                return !q || q.value !== qualificationValue; // remove matching qualification
            });

            // 🧹 STEP 2 — Remove any row without qualification (cleanup)
            updatedRows = updatedRows.filter(r => {
                const q = r.find(f => f.apiName === 'qualifications__c');
                return q && q.value && q.value.trim() !== '';
            });

            // 🧱 STEP 3 — Build new rows for current qualification
            const semNames = [];
            if (patternValue === 'Semesterwise') {
                for (let i = 1; i <= yearCount * 2; i++) semNames.push(`Semester ${i}`);
            } else if (patternValue === 'Yearwise') {
                for (let i = 1; i <= yearCount; i++) semNames.push(`Year ${i}`);
            }

            const newRows = semNames.map(sem => {
                const row = this.createEmptyRow(
                    sec.fields.map(f => {
                        if (f.apiName === 'year_semester_name__c') return { ...f, value: sem };
                        if (f.apiName === 'qualifications__c') return { ...f, value: qualificationValue };
                        return { ...f, value: '' };
                    })
                );
                row.__parent__ = 'Academic_Detail__c';
                return row;
            });

            // 🧩 STEP 4 — Merge valid existing rows + new ones
            const finalRows = [...updatedRows, ...newRows];

            const shouldShow =
                patternValue &&
                ['Graduation', 'Post Graduation'].includes(qualificationValue);

            return { ...sec, rows: finalRows, isHidden: !shouldShow };
        }

        return sec;
    });
}

    // ✅ Final refresh + rebuild
    this.formMetadata = [...this.formMetadata];
    console.log('📘 Updated Form Metadata:', JSON.stringify(this.formMetadata));
    this.buildStepperGroups();
}

    /**
     * @description Handles lookup field searches dynamically.
     * Invokes Apex to search related records and populates suggestions.
     * 
     * @param {Event} event - Input event triggered when typing in a lookup field.
     */
    handleLookupSearch(event) {
        console.log('handleLookupSearch called');
        
        const apiName = event.target.dataset.api;
        const fieldId = event.target.dataset.id;
        const sectionId = event.target.dataset.section;
        const rowIndex = event.target.dataset.row;
        let searchKey = event.target.value;

        const section = this.formMetadata.find(s => s.id === sectionId);
        if (!section) return;
        // const field = section.fields.find(f => f.id === fieldId);
        // 🔹 Determine field source (repeatable row or direct fields)
        let field;
        if (section.repeatable && section.rows && section.rows[rowIndex]) {
            field = section.rows[rowIndex].find(f => f.id === fieldId);
        } else {
            field = section.fields.find(f => f.id === fieldId);
        }

        if (!field) return;

        if (!searchKey || searchKey.length === 0) {
            field.searchResults = false;
            this.formMetadata = [...this.formMetadata];
        } else {
            searchLookup({ searchKey, objectApi: field.lookupObject, displayField: field.displayField })
                .then(results => {
                    console.log('searchLookup ',JSON.stringify(results));
                    if(results.length>0){
                        field.searchResults=true;
                    }else{
                        field.searchResults=false;
                    }
                    field.searchResults = results.map(r => ({ label: r[field.displayField], value: r.Id }));
                    this.formMetadata = [...this.formMetadata];
                    console.log('searchLookup ',JSON.stringify(this.formMetadata));
                })
                .catch(err => {
                    console.error('Lookup error', err);
                });
        }
    }

    /**
     * @description Handles user selection from lookup search results.
     * Sets selected record Id and label into the target field.
     */
    handleLookupSelect(event) {
        const sectionId = event.currentTarget.dataset.section;
        const rowIndex = event.currentTarget.dataset.row;
        const apiName = event.currentTarget.dataset.api;
        const value = event.currentTarget.dataset.value;
        const label = event.currentTarget.dataset.label;
        const fieldId = event.currentTarget.dataset.id;

        this.formMetadata = this.formMetadata.map(section => {
            if (section.id === sectionId) {
                if (section.repeatable && section.isQuestSection) {
                    var secFields = section.fields;
                    var rows = section.rows || [];
                    secFields.forEach(fld => {
                        rows.forEach(row => {
                            if (fieldId && row[fld.id] && String(fieldId) === String(row[fld.id])) {
                                row['answer__c'] = value;
                            }
                        });
                    });
                } else if (section.repeatable) {
                    section.rows = section.rows.map((row, rIdx) => {
                        if (rIdx == rowIndex) {
                            // row is an array of field objects
                            row = row.map(f => {
                                if (f.id === fieldId || f.apiName === apiName) {
                                    return { ...f, value: value, displayValue: label, searchResults: false };
                                }
                                return f;
                            });
                        }
                        return row;
                    });
                } else {
                    section.fields = section.fields.map(f => {
                        if (f.apiName === apiName) {
                            return { ...f, value: value, displayValue: label, searchResults:false  };
                        }
                        return f;
                    });
                }
            }
            return section;
        });

        // Force re-render after a slight delay to ensure UI updates
        setTimeout(() => {
            this.formMetadata = [...this.formMetadata];
            this.buildStepperGroups();
            console.log('Payload after lookup select:', JSON.stringify(this.formMetadata));
        }, 200);
    }
    handleSearchInput(event){
        console.log('handleSearchInput called');
        
        const value = event.currentTarget.value;
         const sectionId = event.currentTarget.dataset.section;
       
        if (value === '') {
             this.formMetadata = this.formMetadata.map(section => {
            if (section.id === sectionId) {
                section.fields = section.fields.map(f => {
                        if (f.apiName === apiName) {
                            return { ...f, value: value, displayValue: label, searchResults:false  };
                        }
                        return f;
                    });
            }
            return section;
        });
        }
    }

     /**
     * @description Handles file selection, reads the content, and sends to Apex for upload.
     * 
     * @param {Event} event - File input change event.
     */
    handleFileChange(event) {
        const apiName = event.target.dataset.api;
        const file = event.target.files[0]; // single file selection
        if (!file) return;

        const reader = new FileReader();
        reader.onload = () => {
            const base64 = reader.result.split(',')[1];
            const fileData = {
                name: file.name,
                type: file.type,
                size: file.size,
                base64: base64,
                id: ''
            };
            this.uploadFileJS(apiName, fileData);
        };
        reader.readAsDataURL(file);

        // clear selection so same file can be uploaded again
        event.target.value = null;
    }

    /**
     * @description Uploads a file to Salesforce via Apex and updates UI once complete.
     * 
     * @param {String} apiName - API name of the field where file belongs.
     * @param {Object} fileD - File metadata (name, type, base64, etc.)
     */
    uploadFileJS(apiName, fileD) {
        uploadFile({ fileData: JSON.stringify(fileD) })
            .then(result => {
                this.showToast('File Added', fileD.name, 'success');
                this.addFileToField(apiName, fileD, result);
            })
            .catch(error => {
                console.error('Error uploading file: ', error);
                this.showToast('File Upload Error', (error.body && error.body.message) || 'Upload failed', 'error');
            });
    }

    /**
     * @description Adds uploaded file data to corresponding field in metadata.
     */
    addFileToField(apiName, fileData, value) {
        try {
            const publicurl = value.split('_')[0];
            const documentId = value.split('_')[1];
            fileData.id = documentId;

            this.formMetadata = this.formMetadata.map(section => {
                section.fields = section.fields.map(fld => {
                    if (fld.apiName === apiName) {
                        if (!fld.uploadedFiles) fld.uploadedFiles = [];
                        fld.uploadedFiles = [...fld.uploadedFiles, fileData];
                        return { ...fld, value: publicurl };
                    }
                    return fld;
                });
                return section;
            });

            this.formMetadata = [...this.formMetadata];
        } catch (e) {
            console.error('addFileToField error', e);
        }
    }

    /**
     * @description Removes uploaded file from Salesforce and local form metadata.
     * 
     * @param {Event} event - Click event containing file index and document Id.
     */
    removeFile(event) {
        const apiName = event.target.dataset.api;
        const dataid = event.target.dataset.id;
        const index = parseInt(event.target.dataset.index, 10);

        this.formMetadata = this.formMetadata.map(section => {
            section.fields = section.fields.map(fld => {
                if (fld.apiName === apiName && fld.uploadedFiles) {
                    fld.uploadedFiles = fld.uploadedFiles.filter((_, i) => i !== index);
                    fld.value = '';
                }
                return fld;
            });
            return section;
        });
        this.formMetadata = [...this.formMetadata];

        deleteFile({ fileId: dataid })
            .then(() => {
                this.showToast('File Removed', 'File removed successfully', 'success');
            })
            .catch(error => {
                console.error('Error deleting file: ', error);
                this.showToast('File Remove Error', (error.body && error.body.message) || 'Delete failed', 'error');
            });
    }

    /**
     * @description Helper method to show standard Lightning toast notifications.
     * 
     * @param {String} title - Toast title.
     * @param {String} message - Toast message body.
     * @param {String} variant - Toast style (success, error, warning, info).
     */
    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    /**
     * @description Builds final payload JSON from formMetadata and submits to Apex.
     * Groups data by objectApiName and supports repeatable sections.
     */
    handleSubmit() {
    this.isLoading=true;
    let payload = {};

    this.formMetadata.forEach(section => {

        // Case 1: repeatable → its own object
        if (section.repeatable) {
            const objApi = section.objectapiName;

            if (!payload[objApi]) {
                payload[objApi] = [];
            }

            if (section.isQuestSection) {
                (section.rows || []).forEach(row => {
                    let record = {};
                    Object.keys(row).forEach(k => {
                        const val = row[k];
                        if (k && val !== undefined && val !== null) {
                            record[k] = { value: val, dataType: null };
                        }
                    });

                    // if it has a related parent → add helper
                    if (section.relatedtoSection) {
                        record["__parent__"] = section.relatedtoSection;
                    }

                    payload[objApi].push(record);
                });
            } else {
                (section.rows || []).forEach(row => {
                    let record = {};
                    (row || []).forEach(fieldObj => {
                        if(fieldObj.isEditDisabled){
                            return;
                        }
                        // console.log('fieldObj: ', fieldObj)
                        let val = fieldObj.value !== undefined ? fieldObj.value : null;
                        if (val !== null && val !== '') {
                            record[fieldObj.apiName] = {
                                value: val,
                                dataType: fieldObj.type || null
                            };
                        }
                    });

                    if (section.relatedtoSection) {
                        record["__parent__"] = section.relatedtoSection;
                        // 👇 Pass qualification type if available (e.g., Graduation / Post Graduation)
                        if (row.__qualificationType__) {
                            record['__qualificationType__'] = row.__qualificationType__;
                        }

                        // add qualification picklist field
                        const qualField = row.find(f => f.apiName === 'qualifications__c');
                        if (qualField && qualField.value) {
                            record['qualifications__c'] = {
                                value: qualField.value,
                                dataType: 'PICKLIST'
                            };
                        }
                    }

                    payload[objApi].push(record);
                });
            }
        }

        // Case 2: non-repeatable → merge into parent
        else {
            const objApi = section.relatedtoSection && section.relatedtoSection.trim() !== ''
                ? section.relatedtoSection
                : section.objectapiName;

            if (!payload[objApi]) {
                payload[objApi] = [{}]; // one record
            }

            let currentRecord = payload[objApi][0];

            (section.fields || []).forEach(f => {
                if(f.isEditDisabled){
                    return;
                }
                let val = f.value !== undefined ? f.value : null;
                if (val !== null && val !== '') {
                    currentRecord[f.apiName] = {
                        value: val,
                        dataType: f.type || null
                    };
                }
            });
        }
    });

    console.log('Final Payload ===> ', JSON.stringify(payload));
    console.log(' this.formMetadata ===> ', JSON.stringify(this.formMetadata));

    createApplication({
        payload: JSON.stringify(payload),
        programCode: this.programCode,
        datascript: JSON.stringify(this.formMetadata)
    })
        .then((res) => {
            if(res =='true'){
                this.dispatchEvent(new ShowToastEvent({
                title: 'Success',
                message: 'Application submitted successfully',
                variant: 'success'
            }));
            this.isLoading=false;
            this.showThankyou = true;
            }else{
                 this.isLoading=false;
                    this.dispatchEvent(new ShowToastEvent({
                    title: 'Error',
                    message: res,
                    variant: 'error'
                }));
            }
            
        })
        .catch(err => {
            console.error('Error creating application: ', err);
            this.isLoading=false;
            this.dispatchEvent(new ShowToastEvent({
                title: 'Error',
                message: err && err.body ? err.body.message : (err && err.message) || 'Unknown error',
                variant: 'error'
            }));
        });
}

}