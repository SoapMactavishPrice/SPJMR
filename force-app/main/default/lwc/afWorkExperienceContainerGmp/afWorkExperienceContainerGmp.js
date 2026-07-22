import { LightningElement, track, api } from 'lwc';
import fetchDynamic from '@salesforce/apex/ApFormDataController.fetchDynamic';
import saveChildren from '@salesforce/apex/ApFormDataController.saveChildren';
import saveParents from '@salesforce/apex/ApFormDataController.saveParents';
import updateStage from '@salesforce/apex/ApFormDataController.updateStage';

import { ShowToastEvent } from "lightning/platformShowToastEvent";
import { buildErrorSummary } from "c/applicationFormService";
import getAllPicklistsForObjects from '@salesforce/apex/AcademicFormController.getAllPicklistsForObjects';

import { validateNumber } from "c/applicationFormService";

import { context as context } from './context';

export default class AfWorkExperienceContainerGmp extends LightningElement {

    isLoading = true; // Start spinner immediately

    application = { Id: 'a0EC10000048Qd1MAE' };
    
    _applicationId;
    
    @api
    set applicationId(value) {
        this._applicationId = value;
        this.application.Id = value;   // <-- assign to your class-level property
    }
    
    get applicationId() {
        return this._applicationId;
    }

    picklistCache = {};
    dependentCache = {};

    @track work = {
        haveWorkExperience : {},
        workExperience: { isSequential: false },
        totalExperienceSummary : {},
        graduationDetails: {},
        haveCareerBreak : {},
        careerBreak: { isSequential: false },
        totalCareerBreakSummary: {},
    };


    metadata = {};
    @track sectionModel = [];

    async connectedCallback() {
        this._buildMetadataSkeleton();

        try {
            const data = await getAllPicklistsForObjects({ objectApiNames: ['Work_Experience__c'] })
            if (data && data.length > 0) {
                const bundle = data[0];

                this.picklistCache = {};
                this.dependentCache = {};

                // Flatten picklist structure
                if (bundle && bundle.defaultSet) {
                    for (const [api, fieldSet] of Object.entries(bundle.defaultSet)) {
                        this.picklistCache[api] = fieldSet.options.map(o => ({
                            label: o.label,
                            value: o.value
                        }));
                    }
                }
            }

            this._injectPicklists();
            this._buildRenderModelAll();

            await this.fetchForm();
        } catch (err) {
            console.warn('Picklist fetch failed', err);
            this._injectPicklists();
            this._buildRenderModelAll();
            await this.fetchForm();
        } finally {
            this.isLoading = false;
        }
    }

    _applyReadOnlyMode() {
        if (!this.isReadOnly) return;

        Object.values(this.metadata).forEach(section => {
            if (!section.fields) return;
            section.fields.forEach(f => {
                f.readOnly = true;
            });
        });
    }



    /* ------------------------------------------------------------
       METADATA (grid layout + field definitions)
    ------------------------------------------------------------- */
    _buildMetadataSkeleton() {
        const cs = 12;

        this.metadata.haveWorkExperience = {
            key: 'haveWorkExperience',
            title: 'Work Experience',
            columnSystem: 12,
            rows: [
                {
                    columns: [
                        { width: 3, fields: ['HasWorkExperience__c'] }
                    ]
                }
            ],
            fields: [
                {
                    api: 'HasWorkExperience__c',
                    type: 'radio',
                    label: 'Do you have work experience?',
                    required: true,
                    options: [
                        { label: 'Yes', value: 'Yes' },
                        { label: 'No', value: 'No' }
                    ]
                }
            ]
        };

        this.metadata.workExperienceNote = {
            key: 'workExperienceNote',
            type: 'note',
            text: `
            * Work experience includes only paid full-time work after graduation. Articleship/Apprenticeship/Internship that is part of a course is not counted.<br>
            * <b>Please list your professional history in reverse chronological order</b> (starting with your most recent or current role first).
            `
        };

        this.metadata.workExperience = {
            key: 'workExperience',
            title: 'Work Experience Details',
            columnSystem: cs,

            rows: [
                // ---------- ROW 1 ----------
                {
                    columns: [
                        { width: 2, fields: ['Name_of_Organisation__c'] },
                        { width: 2, fields: ['Designation__c'] },
                        { width: 3, fields: ['Start_Date__c'] },
                        { width: 3, fields: ['End_Date__c'] }
                    ]
                },

                // ---------- ROW 2 ----------
                {
                    columns: [
                        { width: 2, fields: ['Gross_Annual_CTC__c'] },
                        { width: 3, fields: ['Experience_In_Months__c'] },
                        { width: 4, fields: ['Responsibilities__c'] },
                    ]
                }
            ],

            fields: [
                { api:'Name_of_Organisation__c', type:'text', label:'Name of Organization', maxlength: '255' },
                { api:'Designation__c', type:'text', label:'Designation', maxlength: '255' },
                { api:'Gross_Annual_CTC__c', type:'currency', label:'Gross Annual Salary in Rupees', step:0.01, max: '999999999999' },
                { api:'Responsibilities__c', type:'textarea', label:'Responsibilities & Functions', maxlength: '255' },
                { 
                    api:'Start_Date__c', 
                    type:'monthyear', 
                    label:'Start Date', 
                    min: (() => {
                        const d = new Date();
                        d.setFullYear(d.getFullYear() - 20);
                        return d.toISOString().split('T')[0];
                        }
                    )(),
                    max:new Date().toISOString().split('T')[0] 
                },
                { 
                    api:'End_Date__c', 
                    type:'monthyear', 
                    label:'End Date',
                    min: (() => {
                        const d = new Date();
                        d.setFullYear(d.getFullYear() - 20);
                        return d.toISOString().split('T')[0];
                        }
                    )(),
                    max:new Date().toISOString().split('T')[0] 
                },
                { api:'Experience_In_Months__c', type:'number', label:'Experience (Months)', readOnly:true, helpText: "Any overlapping career break period will automatically be deducted from the total experience."  }
            ]
        };

        this.metadata.totalExperienceSummary = {
            key: 'totalExperienceSummary',
            title: 'Total Industry Experience',
            columnSystem: 12,
            rows: [
                {
                    columns: [
                        { width: 3, fields: ['TotalIndustryExperience__c'] }
                    ]
                }
            ],
            fields: [
                {
                    api:'TotalIndustryExperience__c',
                    type:'number',
                    label:'Total industry experience (months)',
                    readOnly:true
                }
            ]
        };

        this.metadata.haveCareerBreak = {
            key: 'haveCareerBreak',
            title: 'Career Break',
            columnSystem: 12,
            rows: [
                {
                    columns: [
                        { width: 3, fields: ['HasCareerBreak__c'] }
                    ]
                }
            ],
            fields: [
                {
                    api: 'HasCareerBreak__c',
                    type: 'radio',
                    label: 'Do you have career break?',
                    required: true,
                    options: [
                        { label: 'Yes', value: 'Yes' },
                        { label: 'No', value: 'No' }
                    ]
                }
            ]
        };

        this.metadata.careerBreakNote = {
            key: 'careerBreakNote',
            type: 'note',
            text: `
            * Please list your career breaks in reverse chronological order 
            (starting with your most recent break first).<br>
            * Each break must be earlier than the previous one entered above.
            `
        };

        this.metadata.careerBreak = {
            key: 'careerBreak',
            title: 'Career Break Details',
            columnSystem: cs,

            rows: [
                // ---------- ROW 1 ----------
                {
                    columns: [
                        { width: 3, fields: ['StartDate__c'] },
                        { width: 3, fields: ['EndDate__c'] },
                        { width: 3, fields: ['CareerBreakInMonths__c'] },
                    ]
                },
            ],

            fields: [
                { 
                    api:'StartDate__c', 
                    type:'monthyear', 
                    label:'Start Date', 
                    min: (() => {
                        const d = new Date();
                        d.setFullYear(d.getFullYear() - 20);
                        return d.toISOString().split('T')[0];
                        }
                    )(),
                    max:new Date().toISOString().split('T')[0] 
                },
                { 
                    api:'EndDate__c', 
                    type:'monthyear', 
                    label:'End Date', 
                    min: (() => {
                        const d = new Date();
                        d.setFullYear(d.getFullYear() - 20);
                        return d.toISOString().split('T')[0];
                        }
                    )(),
                    max:new Date().toISOString().split('T')[0] 
                },
                { api:'CareerBreakInMonths__c', type:'number', label:'Career Break (Months)', readOnly:true }
            ]
        };

        this.metadata.totalCareerBreakSummary = {
            key: 'totalCareerBreakSummary',
            title: 'Total Career Break',
            columnSystem: 12,
            rows: [
                {
                    columns: [
                        { width: 6, fields: ['CareerBreakReason__c'] },
                        { width: 3, fields: ['TotalCareerBreak__c'] }
                    ]
                }
            ],
            fields: [
                {
                    api: 'CareerBreakReason__c',
                    type: 'textarea',
                    label: 'Reason',
                    maxWords: 50, 
                    maxlength:"32768",
                    visibleWhen: { 'haveCareerBreak.HasCareerBreak__c': 'Yes' },
                    requiredWhen: { 'haveCareerBreak.HasCareerBreak__c': 'Yes' }
                },
                {
                    api:'TotalCareerBreak__c',
                    type:'number',
                    label:'Total career break (months)',
                    readOnly:true
                }
            ]
        };
    }

    _injectPicklists() {
        const merge = (sectionKey) => {
            const sec = this.metadata[sectionKey];
            if (!sec || !sec.fields) return;

            sec.fields.forEach(f => {
                if (this.picklistCache[f.api]) {
                    f.options = this.picklistCache[f.api];
                }
            });
        };

        merge('workExperience');
        //merge('careerBreak'); Important. Need to implement
    }


    /* ------------------------------------------------------------
       Initialize 5 empty rows
    ------------------------------------------------------------- */
    _initializeRows() {
        this.work.workExperience = { isSequential: false };
        for (let i = 1; i <= 5; i++) {
            this.work.workExperience[i] = { Id: null,  };
        }

        this.work.careerBreak = { isSequential: false };
        for (let i = 1; i <= 3; i++) {
            this.work.careerBreak[i] = { Id: null,  };
        }
    }


    _buildSectionRenderModel(sectionKey) {
        const meta = this.metadata[sectionKey];
        if (!meta) return null;

        const cs = meta.columnSystem || 12;

        const section = {
            key: meta.key,
            title: meta.title,
            rows: []
        };

        // read the correct section data
        const secData = this.work[sectionKey] || {};

        // SPECIAL: single-row sections (radio, totals)
        if (['haveWorkExperience', 'totalExperienceSummary', 'haveCareerBreak', 'totalCareerBreakSummary'].includes(sectionKey)) {

            (meta.rows || []).forEach((metaRow, rIdx) => {
                const rowStyle =
                    `display:grid;grid-template-columns:repeat(${cs},1fr);` +
                    `gap:8px;margin-bottom:12px;`;

                const renderRow = {
                    key: `${sectionKey}-row-${rIdx}`,
                    style: rowStyle,
                    columns: []
                };

                metaRow.columns.forEach((col, cIdx) => {
                    const span = col.width || cs;
                    const renderCol = {
                        key: `${sectionKey}-col-${rIdx}-${cIdx}`,
                        widthStyle: `grid-column: span ${span};`,
                        fields: []
                    };

                    (col.fields || []).forEach(api => {
                        const fieldMeta =
                            (meta.fields || []).find(f => f.api === api) ||
                            { api, type: 'text' };

                        const value = secData[api] ?? null;

                        renderCol.fields.push({
                            key: `${sectionKey}-${api}-${rIdx}`,
                            meta: fieldMeta,
                            value
                        });
                    });

                    renderRow.columns.push(renderCol);
                });

                section.rows.push(renderRow);
            });

            return section;
        }

        // Special NOTE section (no rows, only text block)
        if (meta.type === 'note') {
            return {
                key: meta.key,
                title: null,
                rows: [
                    {
                        key: meta.key + '-note',
                        style: '',
                        columns: [
                            {
                                key: meta.key + '-col',
                                widthStyle: 'grid-column: span 12;',
                                fields: [
                                    {
                                        key: meta.key + '-text',
                                        meta: { type: 'note' },
                                        value: meta.text
                                    }
                                ]
                            }
                        ]
                    }
                ]
            };
        }



        // ----------------------------------------------------
        // MULTI-ROW WORK EXPERIENCE (1..5 rows)
        // ----------------------------------------------------
        const seqList = Object.keys(secData)
            .map(k => Number(k))
            .filter(k => !isNaN(k))
            .sort((a, b) => a - b);

        if (seqList.length === 0) seqList.push(1);

        seqList.forEach(seq => {
            const rec = secData[seq] || {};

            (meta.rows || []).forEach((metaRow, rIdx) => {
                const rowStyle =
                    `display:grid;grid-template-columns:repeat(${cs},1fr);` +
                    `gap:8px;margin-bottom:12px;`;

                const renderRow = {
                    key: `${sectionKey}-row-${seq}-${rIdx}`,
                    style: rowStyle,
                    columns: []
                };

                // sequence numbering
                const seqCol = {
                    key: `${sectionKey}-seqcol-${seq}-${rIdx}`,
                    widthStyle: `grid-column: span 1;`,
                    fields: [{
                        key: `${sectionKey}-seq-label-${seq}-${rIdx}`,
                        meta: { type: 'label', label: rIdx === 0 ? seq : '' },
                        value: rIdx === 0 ? seq : null
                    }]
                };
                renderRow.columns.push(seqCol);

                // normal columns
                metaRow.columns.forEach((col, cIdx) => {
                    const span = col.width || cs;

                    const renderCol = {
                        key: `${sectionKey}-col-${seq}-${rIdx}-${cIdx}`,
                        widthStyle: `grid-column: span ${span};`,
                        fields: []
                    };

                    (col.fields || []).forEach((api) => {

                        const requiredFieldsMap = {
                            workExperience : [
                                'Name_of_Organisation__c',
                                'Designation__c',
                                'Start_Date__c',
                                'End_Date__c'
                            ],
                            careerBreak : [
                                'StartDate__c',
                                'EndDate__c'
                            ]
                        };

                        let isRequired = false;

                        if (requiredFieldsMap[sectionKey]?.includes(api)) {

                            // Row 1 → always required
                            if (seq === 1) {
                                isRequired = true;
                            }

                            // Row 2+ → required only if row is active
                            else if (this._isRowActive(sectionKey, seq)) {
                                isRequired = true;
                            }
                        }

                        const baseMeta =
                            (meta.fields || []).find(f => f.api === api && f.sequence === seq) ||
                            (meta.fields || []).find(f => f.api === api) ||
                            { api, type: 'text' };

                        const fieldMeta = {
                            ...baseMeta,
                            required: isRequired
                        };

                        const value = rec[api] ?? null;

                        renderCol.fields.push({
                            key: `${sectionKey}-${api}-${seq}-${rIdx}`,
                            meta: { ...fieldMeta, sequence: seq },
                            value
                        });
                    });

                    renderRow.columns.push(renderCol);
                });

                section.rows.push(renderRow);
            });
        });

        return section;
    }

    _isRowActive(sectionKey, seq) {
        const rec = this.work[sectionKey]?.[seq];
        if (!rec) return false;

        const activationFieldsMap = {
            workExperience: [
                'Name_of_Organisation__c',
                'Designation__c',
                'Start_Date__c',
                'End_Date__c',
                'Responsibilities__c',
                'Gross_Annual_CTC__c'
            ],
            careerBreak: [
                'StartDate__c',
                'EndDate__c'
            ]
        };

        const activationFields = activationFieldsMap[sectionKey] || [];

        return activationFields.some(field =>
            rec[field] !== null &&
            rec[field] !== '' &&
            rec[field] !== undefined
        );
    }


    _buildRenderModelAll() {
        const list = [];

        list.push(this._buildSectionRenderModel('workExperienceNote'));

        // 1. Do you have work experience?
        list.push(this._buildSectionRenderModel('haveWorkExperience'));

        const hasWork = this.work.haveWorkExperience?.HasWorkExperience__c === 'Yes';
        const hasCareerBreak = this.work.haveCareerBreak?.HasCareerBreak__c === 'Yes';

        // 2. Work experience rows (only if Yes)
        if (hasWork) {
            list.push(this._buildSectionRenderModel('workExperience'));

            // 3. Total experience summary
            list.push(this._buildSectionRenderModel('totalExperienceSummary'));

            list.push(this._buildSectionRenderModel('haveCareerBreak'));

            // 3. career break (only if Yes)
            if(hasCareerBreak){

                list.push(this._buildSectionRenderModel('careerBreakNote'));

                list.push(this._buildSectionRenderModel('careerBreak'));

                // Total career break summary
                list.push(this._buildSectionRenderModel('totalCareerBreakSummary'));
            }
            
        }
        
        this.sectionModel = list;        
    }

    _recomputeTotalIndustryExperience() {
        const workMonths = new Set();
        const careerBreakMonths = new Set();
        const appEnd = this._parseYearMonth(
            this.application?.Application_End_Date__c
        );

        for (let seq = 1; seq <= 5; seq++) {
            const rec = this.work.workExperience[seq];
            if (!rec?.Start_Date__c) continue;

            let endSource = rec.End_Date__c;
            if (!endSource) {
                const today = new Date();
                const yyyy = today.getFullYear();
                const mm = String(today.getMonth() + 1).padStart(2, '0');
                endSource = `${yyyy}-${mm}`;
            }

            this._addCoveredMonths(workMonths, rec.Start_Date__c, endSource, appEnd);
        }

        for (let seq = 1; seq <= 3; seq++) {
            const rec = this.work.careerBreak[seq];
            if (!rec?.StartDate__c || !rec?.EndDate__c) continue;

            this._addCoveredMonths(careerBreakMonths, rec.StartDate__c, rec.EndDate__c, appEnd);
        }

        let total = 0;
        workMonths.forEach(monthIndex => {
            if (!careerBreakMonths.has(monthIndex)) {
                total++;
            }
        });

        // Store inside summary section
        if (!this.work.totalExperienceSummary) {
            this.work.totalExperienceSummary = {};
        }

        this.work.totalExperienceSummary.TotalIndustryExperience__c = total;
    }

    _reComputeTotalCareerBreak() {
        let total = 0;

        for (let seq = 1; seq <= 3; seq++) {
            const rec = this.work.careerBreak[seq];
            if (!rec) continue;
            
            const m = Number(rec.CareerBreakInMonths__c || 0);
            if (!isNaN(m)) total += m;
        }

        // Store inside summary section
        if (!this.work.totalCareerBreakSummary) {
            this.work.totalCareerBreakSummary = {};
        }

        this.work.totalCareerBreakSummary.TotalCareerBreak__c = total;
    }

    get renderModel() {
        return this.sectionModel;
    }

    /* ------------------------------------------------------------
       Field Change Handler
    ------------------------------------------------------------- */
    handleSectionFieldChange(e) {
        const { api, value, sectionKey, sequence } = e.detail;

        // Handle "Do you have work experience?" section
        if (sectionKey === 'haveWorkExperience') {
            this.work.haveWorkExperience[api] = value;

            // When No is selected → clear everything
            if (value === 'No') {

                //clear expweience
                // 1️⃣ Collect ids to delete
                const deleteList = [];
                for (let i = 1; i <= 5; i++) {
                    const rec = this.work.workExperience[i];
                    if (rec && rec.Id) {
                        deleteList.push(rec.Id);
                    }
                }

                // 2️⃣ Save this list in container state
                this.work.workExperienceDeleted = deleteList;

                // 3️⃣ Clear all rows
                this.work.workExperience = { isSequential: false };
                for (let i = 1; i <= 5; i++) {
                    this.work.workExperience[i] = { Id: null };
                }

                // 4️⃣ Reset total experience
                this.work.totalExperienceSummary = {
                    TotalIndustryExperience__c: 0
                };

                //clear career break
                this.work.haveCareerBreak = { HasCareerBreak__c: 'No' };

                //clear expweience
                // 1️⃣ Collect ids to delete
                const cbDeleteList = [];
                for (let i = 1; i <= 3; i++) {
                    const rec = this.work.careerBreak[i];
                    if (rec && rec.Id) {
                        cbDeleteList.push(rec.Id);
                    }
                }

                // 2️⃣ Save this list in container state
                this.work.careerBreakDeleted = cbDeleteList;

                // 3️⃣ Clear all rows
                this.work.careerBreak = { isSequential: false };
                for (let i = 1; i <= 3; i++) {
                    this.work.careerBreak[i] = { Id: null };
                }

                // 4️⃣ Reset total experience
                this.work.totalCareerBreakSummary = {
                    ...this.work.totalCareerBreakSummary,
                    TotalCareerBreak__c: 0
                };
            
            }

            this._buildRenderModelAll();
            return;
        }

        // Handle career break grid
        if (sectionKey === 'haveCareerBreak') {
            this.work.haveCareerBreak[api] = value;

            // When No is selected → clear everything
            if (value === 'No') {

                //clear expweience
                // 1️⃣ Collect ids to delete
                const deleteList = [];
                for (let i = 1; i <= 3; i++) {
                    const rec = this.work.careerBreak[i];
                    if (rec && rec.Id) {
                        deleteList.push(rec.Id);
                    }
                }

                // 2️⃣ Save this list in container state
                this.work.careerBreakDeleted = deleteList;

                // 3️⃣ Clear all rows
                this.work.careerBreak = { isSequential: false };
                for (let i = 1; i <= 3; i++) {
                    this.work.careerBreak[i] = { Id: null };
                }

                // 4️⃣ Reset total experience
                this.work.totalCareerBreakSummary = {
                    ...this.work.totalCareerBreakSummary,
                    TotalCareerBreak__c: 0
                };
            }


            this._buildRenderModelAll();
            return;
        }

        if (sectionKey === 'totalCareerBreakSummary') {
            this.work.totalCareerBreakSummary[api] = value;
            this._buildRenderModelAll();
            return;
        }


        // Handle main work experience grid
        if (sectionKey === 'workExperience') {
            this.work.workExperience[sequence] =
                this.work.workExperience[sequence] || {};
            this.work.workExperience[sequence][api] = value;

            if (api === 'Start_Date__c' || api === 'End_Date__c') {
                this._recomputeExperienceMonths(sequence);
                this._recomputeTotalIndustryExperience();
            }

            this._buildRenderModelAll();
            return;
        }

        // Handle main career break grid
        if (sectionKey === 'careerBreak') {
            this.work.careerBreak[sequence] =
                this.work.careerBreak[sequence] || {};
            this.work.careerBreak[sequence][api] = value;

            if (api === 'StartDate__c' || api === 'EndDate__c') {
                this._recomputeCareerBreakMonths(sequence);
                this._reComputeTotalCareerBreak();

                // 🔥 Recalculate all work rows because break changed
                for (let i = 1; i <= 5; i++) {
                    this._recomputeExperienceMonths(i);
                }

                // Recalculate total experience after adjustment
                this._recomputeTotalIndustryExperience();
            }

            this._buildRenderModelAll();
            return;
        }

        // Nothing else to handle
    }


    /* ------------------------------------------------------------
       Month Calculation
    ------------------------------------------------------------- */
    _parseYearMonth(val) {
        if (!val) return null;
        const m = String(val).match(/(\d{4})-(\d{2})/);
        return m ? { y:Number(m[1]), m:Number(m[2]) } : null;
    }

    _toMonthIndex(ym) {
        if (!ym) return null;
        return ym.y * 12 + ym.m;
    }

    _addCoveredMonths(targetSet, startSource, endSource, appEnd = null) {
        const start = this._parseYearMonth(startSource);
        const end = this._parseYearMonth(endSource);

        if (!start || !end) return;

        let startIndex = this._toMonthIndex(start);
        let endIndex = this._toMonthIndex(end);

        if (appEnd) {
            endIndex = Math.min(endIndex, this._toMonthIndex(appEnd));
        }

        if (startIndex > endIndex) return;

        for (let monthIndex = startIndex; monthIndex <= endIndex; monthIndex++) {
            targetSet.add(monthIndex);
        }
    }

    _recomputeExperienceMonths(seq) {
        const rec = this.work.workExperience[seq] || {};

        const s = this._parseYearMonth(rec.Start_Date__c);

        if (!s) {
            rec.Experience_In_Months__c = null;
            return;
        }

        // 1️⃣ If End Date exists → use it
        // 2️⃣ If blank → use current date
        let endSource = rec.End_Date__c;

        if (!endSource) {
            const today = new Date();
            const yyyy = today.getFullYear();
            const mm = String(today.getMonth() + 1).padStart(2, '0');
            endSource = `${yyyy}-${mm}`;
        }

        const e = this._parseYearMonth(endSource);

        if (!e) {
            rec.Experience_In_Months__c = null;
            return;
        }

        // 3️⃣ Parse Application_End_Date__c (DateTime safe)
        const appEnd = this._parseYearMonth(
            this.application?.Application_End_Date__c
        );

        let effectiveEnd = e;

        // 4️⃣ Cap at Application_End_Date__c if needed
        if (appEnd) {
            const workEndVal = e.y * 12 + e.m;
            const appEndVal  = appEnd.y * 12 + appEnd.m;

            if (workEndVal > appEndVal) {
                effectiveEnd = appEnd;
            }
        }

        const months =
            (effectiveEnd.y - s.y) * 12 +
            (effectiveEnd.m - s.m) +
            1;

        const workMonths = months >= 0 ? months : 0;

        // 5️⃣ Subtract overlapping career break months
        let overlapMonths = 0;

        for (let i = 1; i <= 3; i++) {
            const br = this.work.careerBreak[i];
            if (!br?.StartDate__c || !br?.EndDate__c) continue;

            const brStart = this._parseYearMonth(br.StartDate__c);
            const brEnd   = this._parseYearMonth(br.EndDate__c);
            if (!brStart || !brEnd) continue;

            let brStartVal = brStart.y * 12 + brStart.m;
            let brEndVal   = brEnd.y * 12 + brEnd.m;

            const appEndVal = appEnd ? (appEnd.y * 12 + appEnd.m) : null;

            if (appEndVal && brEndVal > appEndVal) {
                brEndVal = appEndVal;
            }

            const workStartVal = s.y * 12 + s.m;
            const workEndVal   = effectiveEnd.y * 12 + effectiveEnd.m;

            if (brEndVal < workStartVal || brStartVal > workEndVal) {
                continue;
            }

            const overlapStart = Math.max(workStartVal, brStartVal);
            const overlapEnd   = Math.min(workEndVal, brEndVal);

            overlapMonths += overlapEnd - overlapStart + 1;
        }

        rec.Experience_In_Months__c = Math.max(0, workMonths - overlapMonths);

    }


    _recomputeCareerBreakMonths(seq) {
        const rec = this.work.careerBreak[seq] || {};

        const s = this._parseYearMonth(rec.StartDate__c);
        if (!s) {
            rec.CareerBreakInMonths__c = null;
            return;
        }

        const e = this._parseYearMonth(rec.EndDate__c);
        if (!e) {
            rec.CareerBreakInMonths__c = null;
            return;
        }

        const appEnd = this._parseYearMonth(
            this.application?.Application_End_Date__c
        );

        let effectiveEnd = e;

        // 🔥 Cap at Application_End_Date__c
        if (appEnd) {
            const breakEndVal = e.y * 100 + e.m;
            const appEndVal = appEnd.y * 100 + appEnd.m;

            if (breakEndVal > appEndVal) {
                effectiveEnd = appEnd;
            }
        }

        const startVal = s.y * 100 + s.m;
        const endVal = effectiveEnd.y * 100 + effectiveEnd.m;

        if (startVal > endVal) {
            rec.CareerBreakInMonths__c = 0;
            return;
        }

        const months =
            (effectiveEnd.y - s.y) * 12 +
            (effectiveEnd.m - s.m) +
            1;

        rec.CareerBreakInMonths__c = months >= 0 ? months : 0;
    }

    _normalizeMonthYear(val) {

        if (val == null) return null;

        // always string
        val = String(val).trim();
        if (!val) return null;

        let normalized = null;

        // Case 1: YYYY-MM → expand to YYYY-MM-01
        if (/^\d{4}-\d{2}$/.test(val)) {
            normalized = `${val}-01`;
        }
        // Case 2: start with YYYY-MM-DD (any further content ignored)
        else if (/^\d{4}-\d{2}-\d{2}/.test(val)) {
            normalized = val.substring(0, 10); // YYYY-MM-DD
        }

        // If invalid format
        if (!normalized) {
            return null;
        }

        // ⭐ Return final required format YYYY-MM-DD HH:mm:ss
        return `${normalized} 00:00:00`;

    }

    static LOCKED_APPLICATION_STATUSES = ['Paid'];
    static UNLOCK_ASSIGNMENT_STATUSES = ['Change Requested'];

    get isReadOnly() {
        return AfWorkExperienceContainerGmp.LOCKED_APPLICATION_STATUSES.includes(this.application?.Application_Status__c) &&
            !AfWorkExperienceContainerGmp.UNLOCK_ASSIGNMENT_STATUSES.includes(this.application?.Assignment_Status__c);
    }
    
    /* ------------------------------------------------------------
       FETCH
    ------------------------------------------------------------- */
    async fetchForm() {

        const request = { parents: [], children: [] };

        context.parents.forEach(p => {
            if (p.logicalName === 'application') {
                request.parents.push({
                    logicalName: p.logicalName,
                    sobject: p.sobject,
                    fields: p.fieldsToQuery,
                    filters: [
                        { field: 'Id', value: this.application.Id }
                    ]
                });
            } else if(p.recordName) {
                request.parents.push({
                    logicalName: p.logicalName,
                    sobject: p.sobject,
                    fields: p.fieldsToQuery,
                    filters: [
                        { field: 'Name', value: p.recordName },
                        { field: context.parentLookupField, value: this.application.Id }
                    ]
                });
            }
        });

        context.children.forEach(c => {
            request.children.push({
                logicalName: c.logicalName,
                sobject: c.sobject,
                fields: c.fieldsToQuery,
                useSequenceKey : c.useSequenceKey,
                childKeyField: c.childKeyField,
                filters: [
                    {
                        field: c.parentLookupField,   // Application__c
                        value: this.application.Id
                    }
                ]
            });
        });


        try {
            const response = await fetchDynamic({
                requestJson: JSON.stringify(request)
            });

            if (response && response.application) {
                this.application.Application_Status__c = response?.application?.Application_Status__c;
                this.application.Assignment_Status__c = response?.application?.Assignment_Status__c;
                this.application.Application_End_Date__c = response?.application?.Batch__r.Application_End_Date__c;

                this._updateDynamicNotes();

                this.work.haveWorkExperience = {
                    HasWorkExperience__c: response.application.HasWorkExperience__c
                };
                this.work.totalExperienceSummary = {
                    TotalIndustryExperience__c:
                        response.application.TotalIndustryExperience__c
                };
                this.work.haveCareerBreak = {
                    HasCareerBreak__c: response.application.HasCareerBreak__c
                };
                this.work.totalCareerBreakSummary = {
                    TotalCareerBreak__c: response.application.TotalCareerBreak__c,
                    CareerBreakReason__c: response.application.CareerBreakReason__c
                };

            }

            if(response && response.graduationDetails) {
                this.work.graduationDetails = response?.graduationDetails;
            }

            if (response && response.workExperience) {

                // 1️⃣ Convert object to array
                let records = Object.keys(response.workExperience)
                    .filter(k => k !== 'isSequential')
                    .map(k => response.workExperience[k]);

                // 2️⃣ Sort by reverse chronology (latest first)
                records.sort((a, b) =>
                    (b.Start_Date__c || '').localeCompare(a.Start_Date__c || '')
                );

                // 3️⃣ Re-map into sequential rows
                this.work.workExperience = { isSequential: false };

                let seq = 1;

                records.forEach(rec => {
                    if (seq <= 5) {
                        this.work.workExperience[seq] = rec;
                        this._recomputeExperienceMonths(seq);
                        seq++;
                    }
                });

                this._recomputeTotalIndustryExperience();

                // 4️⃣ Fill remaining rows
                while (seq <= 5) {
                    this.work.workExperience[seq] = { Id: null };
                    seq++;
                }
            }

            if (response && response.careerBreak) {
                this.work.careerBreak = { isSequential:false };

                // Convert object → array
                let records = Object.keys(response.careerBreak)
                    .filter(k => k !== 'isSequential')
                    .map(k => response.careerBreak[k]);

                // Sort reverse chronological (latest break first)
                records.sort((a, b) =>
                    (b.StartDate__c || '').localeCompare(a.StartDate__c || '')
                );

                // Rebuild sequential UI structure
                this.work.careerBreak = { isSequential: false };

                let seq = 1;

                records.forEach(rec => {
                    if (seq <= 3) {
                        this.work.careerBreak[seq] = rec;
                        this._recomputeCareerBreakMonths(seq);
                        seq++;
                    }
                });

                this._reComputeTotalCareerBreak();


                // Fill remaining empty rows
                while (seq <= 3) {
                    this.work.careerBreak[seq] = { Id: null };
                    seq++;
                }


            }
        } catch (err) {
            console.warn('Fetch failed', err);
        }

        // 🔥 Final recalculation after both work + career break are loaded
        for (let i = 1; i <= 5; i++) {
            this._recomputeExperienceMonths(i);
        }

        this._recomputeTotalIndustryExperience();

        this._applyReadOnlyMode();
        this._buildRenderModelAll();
    }

    _updateDynamicNotes() { 
        const appEndRaw = this.application.Application_End_Date__c;

        // If batch end date exists → use it
        // If not → fallback to today
        const effectiveDate = appEndRaw
            ? new Date(appEndRaw)
            : new Date();

        // Format as DD Mon YYYY (e.g., 31 Mar 2026)
        const formattedDate = effectiveDate.toLocaleDateString('en-GB', {
            day: '2-digit',
            month: 'short',
            year: 'numeric'
        });

        // 🔥 Update Work Experience Note
        this.metadata.workExperienceNote.text = `
* Work experience includes only paid full-time work after graduation. Articleship/Apprenticeship/Internship that is part of a course is not counted.<br>
* <b>Please list your professional history in reverse chronological order</b> (starting with your most recent or current role first).<br>
* Experience is calculated up to ${formattedDate}.
        `;

        // 🔥 Update Career Break Note
        this.metadata.careerBreakNote.text = `
* Please list your career breaks in reverse chronological order (starting with your most recent break first).<br>
* Career break duration is calculated up to ${formattedDate}.
        `;
    }


    /* ------------------------------------------------------------
       VALIDATION
    ------------------------------------------------------------- */
    validateAll() {
        const meta = this.metadata.workExperience;
        const errors = {
            workExperience: {},
            careerBreak: {}
        };

        for (let seq = 1; seq <= 5; seq++) {
            const rec = this.work.workExperience[seq] || {};
            const prev = this.work.workExperience[seq - 1];

            // Required field validation

            meta.fields.forEach(f => {

                const requiredFields = [
                    'Name_of_Organisation__c',
                    'Designation__c',
                    'Start_Date__c',
                    'End_Date__c'
                ];

                let isRequired = false;

                if (requiredFields.includes(f.api)) {

                    if (seq === 1) {
                        isRequired = true;
                    } else if (this._isRowActive('workExperience', seq)) {
                        isRequired = true;
                    }
                }
                
                if (isRequired && !rec[f.api] && this.work.haveWorkExperience.HasWorkExperience__c === 'Yes') {
                    errors.workExperience[`${f.api}__${seq}`] =
                        `${f.label} is required`;
                }

                if ((f.type === 'number' || f.type === 'currency') && rec[f.api]) {

                    const err = validateNumber(f, rec[f.api]);
                    if (err) {
                        errors.workExperience[`${f.api}__${seq}`] = err;
                    }
                }
            });

            const graduationPassingDate = this.work?.graduationDetails?.MonthAndYearOfPassing__c;

            // Work > Graduation validation
            if (
                graduationPassingDate&& 
                rec.Start_Date__c &&
                this._normalizeMonthYear(graduationPassingDate) >
                this._normalizeMonthYear(rec.Start_Date__c) 
                
            ) {
                errors.workExperience[`Start_Date__c__${seq}`] =
                    `Start Date should be greater than Graduation passed out Date ${graduationPassingDate}`;
                continue;
            }

            // Start > End validation
            if (
                rec.Start_Date__c &&
                rec.End_Date__c &&
                this._normalizeMonthYear(rec.Start_Date__c) >
                this._normalizeMonthYear(rec.End_Date__c)
            ) {
                errors.workExperience[`Start_Date__c__${seq}`] =
                    'Start Date cannot be greater than End Date';
                continue;
            }

            // Reverse chronology (latest → earliest)
            if (
                seq !== 1 &&
                rec.End_Date__c &&
                prev?.Start_Date__c &&
                this._normalizeMonthYear(rec.End_Date__c) >
                this._normalizeMonthYear(prev.Start_Date__c)
            ) {
                errors.workExperience[`End_Date__c__${seq}`] =
                    'End date must be earlier than the previous work experience start date';
            }

        }

        const careerBreakMeta = this.metadata.careerBreak;

        for (let seq = 1; seq <= 3; seq++) {
            const rec = this.work.careerBreak[seq] || {};
            const prev = this.work.careerBreak[seq - 1];

            // Required field validation

            careerBreakMeta.fields.forEach(f => {

                const requiredFields = ['StartDate__c', 'EndDate__c'];

                let isRequired = false;

                if (requiredFields.includes(f.api)) {

                    if (seq === 1) {
                        isRequired = true;
                    }
                    else if (this._isRowActive('careerBreak', seq)) {
                        isRequired = true;
                    }
                }

                if (
                    isRequired &&
                    !rec[f.api] &&
                    this.work.haveCareerBreak?.HasCareerBreak__c === 'Yes'
                ) {
                    errors.careerBreak[`${f.api}__${seq}`] =
                        `${f.label} is required`;
                }
            });

            // Start > End validation
            if (
                rec.StartDate__c &&
                rec.EndDate__c &&
                this._normalizeMonthYear(rec.StartDate__c) >
                this._normalizeMonthYear(rec.EndDate__c)
            ) {
                errors.careerBreak[`StartDate__c__${seq}`] =
                    'Start Date cannot be greater than End Date';
                continue;
            }

            // Reverse chronology (latest → earliest)
            if (
                seq !== 1 &&
                rec.EndDate__c &&
                prev?.StartDate__c &&
                this._normalizeMonthYear(rec.EndDate__c) >=
                this._normalizeMonthYear(prev.StartDate__c)
            ) {
                errors.careerBreak[`EndDate__c__${seq}`] =
                    'End date must be earlier than the previous career break start date';
            }
        }

        // 🔥 Career break cannot be before earliest work start date
        let earliestWorkStart = null;

        for (let i = 5; i >= 1; i--) {
            const w = this.work.workExperience[i];
            if (w?.Start_Date__c) {
                earliestWorkStart = this._normalizeMonthYear(w.Start_Date__c);
                break;
            }
        }

        if (earliestWorkStart) {
            for (let seq = 1; seq <= 3; seq++) {
                const br = this.work.careerBreak[seq];
                if (!br?.StartDate__c) continue;

                const breakStart = this._normalizeMonthYear(br.StartDate__c);

                if (breakStart < earliestWorkStart) {
                    errors.careerBreak[`StartDate__c__${seq}`] =
                        'Career break cannot be before your first work experience start date';
                }
            }
        }

        const cmp = this.template.querySelector('c-af-work-experience');
        if (cmp && typeof cmp.applyErrors === 'function') {
            const flatErrors = {
                ...errors.workExperience,
                ...errors.careerBreak
            };
            cmp.applyErrors(flatErrors);
        }

        const hasErrors =
            Object.keys(errors.workExperience).length > 0 ||
            Object.keys(errors.careerBreak).length > 0;

        if (hasErrors) {
            const errorMessage = buildErrorSummary(errors, this.metadata);
            if (errorMessage) {
                this.dispatchEvent(new ShowToastEvent({
                    title: 'Error',
                    message: errorMessage,
                    variant: 'error',
                    mode: 'sticky'
                }));
            }
        }

        return !hasErrors;
    }

    /* ------------------------------------------------------------
       SAVE (children only)
    ------------------------------------------------------------- */
    @api async saveForm() {
        if(this.isReadOnly) return true;

        if(this.work?.haveCareerBreak?.HasCareerBreak__c === 'No'){
            this.work.totalCareerBreakSummary.TotalCareerBreak__c = 0;
            this.work.totalCareerBreakSummary.CareerBreakReason__c = '';
        }

        this.isLoading = true;
        if (!this.validateAll()) {
            this.isLoading = false;
            return false;
        }

        try {
            await saveParents({
                applicationId: this.application.Id,
                payloadJson: JSON.stringify({
                    application: {
                        sobject: "Application__c",
                        fields: {
                            Id: this.application.Id,
                            TotalIndustryExperience__c: 
                                this.work?.totalExperienceSummary?.TotalIndustryExperience__c || 0,
                            HasWorkExperience__c: 
                                this.work?.haveWorkExperience?.HasWorkExperience__c || '' ,
                            HasCareerBreak__c: 
                                this.work?.haveCareerBreak?.HasCareerBreak__c || '' ,
                            TotalCareerBreak__c: 
                                this.work?.totalCareerBreakSummary?.TotalCareerBreak__c || 0,
                            CareerBreakReason__c: 
                                this.work?.totalCareerBreakSummary?.CareerBreakReason__c || ''
                        }
                    }
                })
            });

            const childPayload = {};
            const c = context.children[0];

            let rows = [];
            let deleted = this.work.workExperienceDeleted || [];

            for (let seq = 1; seq <= 5; seq++) {
                const row = this.work.workExperience[seq];
                const hasId = !!row.Id;

                // If record is already scheduled for deletion, skip it
                if (hasId && deleted.includes(row.Id)) {
                    continue;
                }

                const hasData = Object.keys(row).some(k =>
                    k !== 'Id' && row[k] !== null && row[k] !== ''
                );

                // 1) Normalize row values based on metadata
                Object.keys(row).forEach(api => {
                    const fieldMeta = this.metadata.workExperience.fields.find(f => f.api === api);

                    if (fieldMeta?.type === 'monthyear') {
                        row[api] = this._normalizeMonthYear(row[api]);
                    }

                    if (fieldMeta?.type === 'number') {
                        const n = Number(row[api]);
                        row[api] = isNaN(n) ? null : n;
                    }

                    // Currency formatting: always 2 decimals
                    if (fieldMeta?.type === 'currency') {
                        let val = row[api];

                        if (val === null || val === undefined || val === '') {
                            row[api] = null;
                        } else {
                            val = Number(val);
                            row[api] = isNaN(val) ? null : Number(val.toFixed(2));
                        }
                    }

                    
                });

                // 2) Build clean row based on fieldsToQuery
                const allowed = new Set(c.fieldsToQuery);
                let cleanRow = {};

                Object.keys(row).forEach(api => {

                    if (allowed.has(api)) {
                        cleanRow[api] = row[api];
                    }
                });

                if (!hasId && !hasData) continue;     // ignore
                if (!hasId && hasData) {               
                    let row = {
                        sobject: c.sobject,
                        parentLookupField: c.parentLookupField,
                        parentId: this.application.Id,
                        fields: cleanRow,
                        Id: null
                    };
                    rows.push(row);
                    continue;
                }
                if (hasId && !hasData) {
                    deleted.push(cleanRow.Id);
                    continue;
                }
                if (hasId && hasData) {
                    rows.push({
                        sobject: c.sobject,
                        parentLookupField: c.parentLookupField,
                        parentId: this.application.Id,
                        fields: cleanRow,
                        Id: row.Id
                    });
                }
            }

            childPayload[c.logicalName] = {
                sobject: c.sobject,
                parentLookupField: c.parentLookupField,
                rows,
                deletedIds: deleted
            };

            //career break
            const careerBreakContext = context.children[1];

            let cbRows = [];
            let cbDeleted = this.work.careerBreakDeleted || [];

            for (let seq = 1; seq <= 3; seq++) {
                const row = this.work.careerBreak[seq];
                const hasId = !!row.Id;

                // If record is already scheduled for deletion, skip it
                if (hasId && cbDeleted.includes(row.Id)) {
                    continue;
                }

                const hasData = Object.keys(row).some(k =>
                    k !== 'Id' && row[k] !== null && row[k] !== ''
                );

                // 1) Normalize row values based on metadata
                Object.keys(row).forEach(api => {
                    const fieldMeta = this.metadata.careerBreak.fields.find(f => f.api === api);

                    if (fieldMeta?.type === 'monthyear') {
                        row[api] = this._normalizeMonthYear(row[api]);
                    }

                    if (fieldMeta?.type === 'number') {
                        const n = Number(row[api]);
                        row[api] = isNaN(n) ? null : n;
                    }
                    
                });

                // 2) Build clean row based on fieldsToQuery
                const allowed = new Set(careerBreakContext.fieldsToQuery);
                let cleanRow = {};

                Object.keys(row).forEach(api => {

                    if (allowed.has(api)) {
                        cleanRow[api] = row[api];
                    }
                });

                if (!hasId && !hasData) continue;     // ignore
                if (!hasId && hasData) {               
                    let row = {
                        sobject: careerBreakContext.sobject,
                        parentLookupField: careerBreakContext.parentLookupField,
                        parentId: this.application.Id,
                        fields: cleanRow,
                        Id: null
                    };
                    cbRows.push(row);
                    continue;
                }
                if (hasId && !hasData) {
                    cbDeleted.push(cleanRow.Id);
                    continue;
                }
                if (hasId && hasData) {
                    cbRows.push({
                        sobject: careerBreakContext.sobject,
                        parentLookupField: careerBreakContext.parentLookupField,
                        parentId: this.application.Id,
                        fields: cleanRow,
                        Id: row.Id
                    });
                }
            }

            childPayload[careerBreakContext.logicalName] = {
                sobject: careerBreakContext.sobject,
                parentLookupField: careerBreakContext.parentLookupField,
                rows: cbRows,
                deletedIds: cbDeleted
            };

            await saveChildren({
                payloadJson: JSON.stringify(childPayload)
            });

            await updateStage({ 
                applicationId: this.application.Id, 
                newStage: 'Work Experience' 
            });

            this.dispatchEvent(new ShowToastEvent({
                title: 'Success',
                message: 'Saved successfully',
                variant: 'success',
            }));
            await this.fetchForm();

            return true;
        } catch (e) {
            console.warn('save failed', e);
            return false;
        } finally {
            this.isLoading = false;
        }
        
    }
}