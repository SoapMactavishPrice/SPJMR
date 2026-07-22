import { LightningElement, api, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

import getApplicationId from '@salesforce/apex/ApplicationSectionDataController.getApplicationId';
import fetchAllSections from '@salesforce/apex/ApplicationSectionDataController.fetchAllSections';
import fetchExistingRequestKeys from '@salesforce/apex/ApplicationChangeRequestController.fetchExistingRequestKeys';
import saveChangeRequests from '@salesforce/apex/ApplicationChangeRequestController.saveChangeRequests';

export default class ApplicationVerificationWizard extends LightningElement {
    @api recordId;

    @track sectionList = [];
    @track activeSectionIndex = 0;

    loading = true;
    errorMessage;

    applicationId;
    existingKeys = new Set();

    /* ================= FIELD ORDER + HEADER CONFIG ================= */

    fieldConfigMap = {
        basicDetails: {
            order: [
                'First_Name__c',
                'Middle_Name__c',
                'Last_Name__c',
                'Title__c',
                'Gender__c',
                'Date_of_Birth_As_Per_10th_Marksheet__c',
                'Primary_E_mail__c',
                'Alternate_E_mail__c',
                'Mobile_Number__c',
                'Alternate_Mobile_Number__c',
                'WhatsApp_Mobile_Number__c',
                'GuardianName__c',
                'GuardianMobile__c',
                'GuardianEmail__c',
                'GuardianOccupation__c'
            ],
            headerFields: ['First_Name__c']
        },

        tenth: {
            order: [
                'School_Institute__c',
                'Board_University__c',
                'MonthAndYearOfPassing__c',
                'Marking_Scheme__c',
                'Maximum_Marks__c',
                'Obtained_Marks__c'
            ],
            headerFields: ['School_Institute__c']
        },

        twelfth: {
            order: [
                'School_Institute__c',
                'Board_University__c',
                'MonthAndYearOfPassing__c',
                'Marking_Scheme__c',
                'Maximum_Marks__c',
                'Obtained_Marks__c'
            ],
            headerFields: ['School_Institute__c']
        },

        diploma: {
            order: [
                'School_Institute__c',
                'Board_University__c',
                'MonthAndYearOfPassing__c',
                'Maximum_Marks__c',
                'Obtained_Marks__c'
            ],
            headerFields: ['School_Institute__c']
        },

        ug: {
            order: [
                'School_Institute__c',
                'Board_University__c',
                'MonthAndYearOfPassing__c',
                'Maximum_Marks__c',
                'Obtained_Marks__c'
            ],
            headerFields: ['School_Institute__c']
        },

        pg: {
            order: [
                'School_Institute__c',
                'Board_University__c',
                'MonthAndYearOfPassing__c',
                'Maximum_Marks__c',
                'Obtained_Marks__c'
            ],
            headerFields: ['School_Institute__c']
        },

        workExperience: {
            order: [
                'Name_of_Organisation__c',
                'Designation__c',
                'Start_Date__c',
                'End_Date__c',
                'Gross_Annual_CTC__c',
                'Responsibilities__c'
            ],
            headerFields: ['Name_of_Organisation__c']
        }
    };

    /* ================= INIT ================= */

    connectedCallback() {
        this.init();
    }

    async init() {
        this.loading = true;
        this.errorMessage = null;

        try {
            this.applicationId = await getApplicationId({ verificationId: this.recordId });
            if (!this.applicationId) throw new Error('Application not found');

            const keys = await fetchExistingRequestKeys({ applicationId: this.applicationId });
            this.existingKeys = new Set(keys || []);

            const json = await fetchAllSections({ applicationId: this.applicationId });
            const data = JSON.parse(json);

            this.sectionList = this.buildSections(data);
            this.activeSectionIndex = 0;
        } catch (e) {
            console.error(e);
            this.errorMessage = e?.body?.message || e.message;
            this.sectionList = [];
        } finally {
            this.loading = false;
        }
    }

    /* ================= SECTION CONFIG ================= */

    get sectionConfig() {
        return [
            { key: 'application', label: 'Application', objectApi: 'Application__c' },
            { key: 'basicDetails', label: 'Personal Details', objectApi: 'Personal_Detail__c' },

            { key: 'tenth', label: '10th Details', objectApi: 'Academic_Detail__c' },
            { key: 'twelfth', label: '12th Details', objectApi: 'Academic_Detail__c' },
            { key: 'diploma', label: 'Diploma Details', objectApi: 'Academic_Detail__c' },
            { key: 'ug', label: 'UG Details', objectApi: 'Academic_Detail__c' },
            { key: 'pg', label: 'PG Details', objectApi: 'Academic_Detail__c' },

            { key: 'entranceExams', label: 'Entrance Exams', objectApi: 'Competitive_Exam_Details__c', child: true },
            { key: 'workExperience', label: 'Work Experience', objectApi: 'Work_Experience__c', child: true }
        ];
    }

    /* ================= BUILD SECTIONS ================= */

    buildSections(data) {
        return this.sectionConfig.map(sec => {
            const block = data[sec.key];
            const items = [];

            if (!block) return { ...sec, items };

            /* ---------- PARENT ---------- */
            if (!sec.child) {
                const config = this.fieldConfigMap[sec.key] || {};
                const order = config.order || Object.keys(block);
                const headers = config.headerFields || [];

                order.forEach(api => {
                    if (!Object.prototype.hasOwnProperty.call(block, api)) return;
                    if (!api.endsWith('__c')) return;

                    const key = `${sec.label}|${api}|0`;
                    const alreadyRequested = this.existingKeys.has(key);

                    items.push(this.makeFieldItem({
                        key,
                        fieldApi: api,
                        fieldLabel: this.toLabel(api),
                        value: block[api],
                        rowIndex: 0,
                        isHeader: headers.includes(api),
                        disabled: alreadyRequested,
                        alreadyRequested
                    }));
                });

                if (['diploma', 'ug', 'pg'].includes(sec.key)) {
                    this.injectSemesterMarks(items, sec, data);
                }
            }

            /* ---------- CHILD ---------- */
            if (sec.child) {
                Object.entries(block).forEach(([idx, row]) => {
                    if (idx === 'isSequential') return;

                    const config = this.fieldConfigMap[sec.key] || {};
                    const order = config.order || Object.keys(row);
                    const headers = config.headerFields || [];

                    order.forEach(api => {
                        if (!Object.prototype.hasOwnProperty.call(row, api)) return;
                        if (!api.endsWith('__c')) return;

                        const key = `${sec.label}|${api}|${idx}`;
                        const alreadyRequested = this.existingKeys.has(key);

                        items.push(this.makeFieldItem({
                            key,
                            fieldApi: api,
                            fieldLabel: this.toLabel(api),
                            value: row[api],
                            rowIndex: idx,
                            isHeader: headers.includes(api),
                            disabled: alreadyRequested,
                            alreadyRequested
                        }));
                    });
                });
            }

            return { ...sec, items };
        });
    }

    /* ================= ITEM FACTORIES ================= */

    makeFieldItem({
        key,
        fieldApi,
        fieldLabel,
        value,
        rowIndex,
        isHeader = false,
        disabled = false,
        alreadyRequested = false,
        indentLevel = 0
    }) {
        const rowClass = [
            'row',
            alreadyRequested ? 'alreadyRequested' : '',
            isHeader ? 'headerRow' : '',
            indentLevel === 1 ? 'indent1' : '',
            indentLevel === 2 ? 'indent2' : ''
        ].filter(Boolean).join(' ');

        return {
            key,
            fieldApi,
            fieldLabel,
            value,
            rowIndex,
            selected: false,
            remark: '',
            showRemark: false,
            disabled,
            alreadyRequested,
            isHeader,
            isHeaderOnly: false,
            rowClass
        };
    }

    makeHeaderRow({ key, label, indentLevel = 0 }) {
        const rowClass = [
            'headerOnlyRow',
            indentLevel === 1 ? 'indent1' : '',
            indentLevel === 2 ? 'indent2' : ''
        ].filter(Boolean).join(' ');

        return {
            key,
            label,
            disabled: true,
            selected: false,
            remark: '',
            showRemark: false,
            isHeaderOnly: true,
            rowClass
        };
    }

    /* ================= SEMESTER FIX ================= */

   injectSemesterMarks(items, sec, data) {
    const semBlock = data?.semesterMarksByAcademic;
    if (!semBlock) return;

    // ✅ Determine Academic Id based on current section
    let academicId;
    if (sec.key === 'diploma') {
        academicId = data?.diploma?.Id;
    } else if (sec.key === 'ug') {
        academicId = data?.ug?.Id;
    } else if (sec.key === 'pg') {
        academicId = data?.pg?.Id;
    }

    if (!academicId) return;

    const semesters = semBlock[academicId];
    if (!semesters) {
        items.push(this.makeHeaderRow({
            key: `${sec.label}|SEM_NONE|0`,
            label: 'Semester-wise Marks (No records found)'
        }));
        return;
    }

    /* ===== Section Header ===== */
    items.push(this.makeHeaderRow({
        key: `${sec.label}|SEM_SECTION|0`,
        label: 'Semester-wise Marks'
    }));

    /* ===== Semester Rows ===== */
    Object.entries(semesters).forEach(([rowKey, sem], index) => {

        items.push(this.makeHeaderRow({
            key: `${sec.label}|SEM_HEADER|${rowKey}`,
            label: sem.Year_Semester_Name__c || `Semester ${index + 1}`,
            indentLevel: 1
        }));

        items.push(this.makeFieldItem({
            key: `${sec.label}|Obtained_Marks_SGPA__c|${rowKey}`,
            fieldApi: 'Obtained_Marks_SGPA__c',
            fieldLabel: 'Obtained Marks / SGPA',
            value: sem.Obtained_Marks_SGPA__c,
            rowIndex: index,
            indentLevel: 2
        }));

        items.push(this.makeFieldItem({
            key: `${sec.label}|Maximum_Marks_SGPA__c|${rowKey}`,
            fieldApi: 'Maximum_Marks_SGPA__c',
            fieldLabel: 'Maximum Marks / SGPA',
            value: sem.Maximum_Marks_SGPA__c,
            rowIndex: index,
            indentLevel: 2
        }));
    });
}


    /* ================= NAV ================= */

    handleSectionClick(e) {
        this.activeSectionIndex = Number(e.currentTarget.dataset.index);
    }

    get computedSections() {
        return this.sectionList.map((s, i) => ({
            ...s,
            css: i === this.activeSectionIndex ? 'sectionItem active' : 'sectionItem'
        }));
    }

    get activeSection() {
        return this.sectionList[this.activeSectionIndex];
    }

    /* ================= TOGGLES ================= */

    handleToggle(e) {
        const key = e.target.dataset.key;
        const item = this.activeSection.items.find(i => i.key === key);
        if (!item || item.disabled) return;

        item.selected = e.target.checked;
        item.showRemark = item.selected;
        if (!item.selected) item.remark = '';
        this.refresh();
    }

    handleRemarkChange(e) {
        const key = e.target.dataset.key;
        const item = this.activeSection.items.find(i => i.key === key);
        if (!item) return;

        item.remark = e.target.value;
        this.refresh();
    }

    refresh() {
        this.sectionList = this.sectionList.map(s => ({
            ...s,
            items: s.items.map(i => ({ ...i }))
        }));
    }

    /* ================= SAVE ================= */

    async handleSave() {
        const payload = [];

        try {
            this.sectionList.forEach(sec => {
                sec.items.forEach(it => {
                    if (it.isHeaderOnly) return;
                    if (it.selected && !it.disabled) {
                        if (!it.remark?.trim()) {
                            throw new Error(`Remark required for ${it.fieldLabel}`);
                        }
                        payload.push({
                            sectionLabel: sec.label,
                            sectionObjectApi: sec.objectApi,
                            fieldLabel: it.fieldLabel,
                            fieldApi: it.fieldApi,
                            currentValue: String(it.value ?? ''),
                            remark: it.remark,
                            rowIndex: Number(it.rowIndex || 0)
                        });
                    }
                });
            });

            if (!payload.length) {
                this.toast('Info', 'No fields selected', 'info');
                return;
            }

            await saveChangeRequests({
                verificationId: this.recordId,
                requestJson: JSON.stringify(payload)
            });

            this.toast('Success', 'Change Requests created successfully', 'success');
            await this.init();

        } catch (e) {
            console.error(e);
            this.toast('Error', e.message, 'error');
        }
    }

    /* ================= UTIL ================= */

    toLabel(api) {
        return api.replace('__c', '').replace(/_/g, ' ');
    }

    toast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}