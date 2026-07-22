import { LightningElement, track, api } from 'lwc';
import getAllPicklistsForObjects from '@salesforce/apex/AcademicFormController.getAllPicklistsForObjects';
import validatePayload from '@salesforce/apex/AcademicFormController.validatePayload';

export default class AfAcademicDetailsContainer extends LightningElement {
    
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
    
    @track education = {
        tenth: {},
        twelfth: {},
        diploma: {},
        graduation: {},
        graduationDetails: {},
        haveAcademicBreak: {},
        after10: {},
        semester: {},
        havePostGrad : {},
        postGraduation: {},
        postGraduationDetails: {},
        postSemester: {},
        haveProfessionalQualification: {},
        professionalQualification: {}, // sequential 1..3 rows
        extraCurricular: {},
        importantCertification: {},
        publications: {},
    };

    // renderModel sections split for academic (10th/12th/diploma) and graduation
    @track academicSections = []; // array of section renderModels
    @track graduationSections = []; // array of section renderModels
    @track postGraduationSections = [];
    @track professionalQualification = [];
    @track academicDetailsFooterSections = [];

    // metadata (source) - stored internally
    metadata = {};
    picklistCache = {};
    dependentCache = {};

    connectedCallback() {
        this._buildMetadataSkeleton();
        // load picklists & dependent map then build renderModel
        getAllPicklistsForObjects({ objectApiNames: ['Academic_Detail__c'] })
            .then(data => {
                console.log('gotAllPicklistsForObjects '+JSON.stringify(data));
                // Process the new structured response
                if (data && data.length > 0) {
                    const bundle = data[0]; // Get the first (and only) bundle for Academic__c
                    if (bundle && bundle.defaultSet) {
                        // Convert to flat structure for easy access
                        this.picklistCache = {};
                        this.dependentCache = {};
                        
                        for (const [fieldApiName, fieldSet] of Object.entries(bundle.defaultSet)) {
                            // Store all picklist options
                            this.picklistCache[fieldApiName] = fieldSet.options.map(option => ({
                                label: option.label,
                                value: option.value
                                // Note: validForBase64 is null in current Apex implementation
                            }));
                            
                            // If this is a dependent field, store the dependency info
                            if (fieldSet.dependent && fieldSet.controllingFieldApiName) {
                                // Store the controlling field relationship for later use
                                this.dependentCache[fieldApiName] = {
                                    controllingField: fieldSet.controllingFieldApiName,
                                    options: fieldSet.options
                                };
                            }
                        }

                    }
                }
                // Since we now use getAllPicklistsForObjects which includes dependent picklist data,
                // we don't need to call getDependentPicklistMap separately
                this._injectPicklists();
                this._buildRenderModelAll();
                this.fetchForm();
            })
            .catch(err => {
                console.warn('picklist load failed', err);
                this._injectPicklists();
                this._buildRenderModelAll();
            });
    }

    needPostGradSemYearWise = true;

    // Build metadata skeleton and default columnSystem per section
    _buildMetadataSkeleton() {
        const mkFields = (arr) => arr.slice();
        this.metadata = {};

        // per-section columnSystem recommended values
        const cs = {
            tenth:12, after10:12, twelfth:12, diploma:16, graduation:12, graduationDetails:12, semester:30, havePostGrad:12, postGraduation:12, postGraduationDetails:12, postSemester:30
        };

        // Tenth
        this.metadata.tenth = {
            key: 'tenth',
            title: '10th Academic Details',
            columnSystem: cs.tenth,
            rows: [
                { columns: [ { width:3, fields:['Board_University__c'] }, { width:3, fields:['School_Institute__c'] }, { width:2, fields:['Examination_ID__c'] }, { width:4, fields:['MonthAndYearOfPassing__c'] } ] },
                { columns: [ { width:2, fields:['Marking_Scheme__c'] }, { width:2, fields:['Percentage__c'] }, { width:2, fields:['Maximum_Marks__c'] }, { width:2, fields:['Obtained_Marks__c'] }, { width:2, fields:['Conversion_Factor__c'] }, { width:2, fields:[] } ] }
            ],
            fields: [
                { api:'Board_University__c', type:'text', label:'Board/University', required:true },
                { api:'School_Institute__c', type:'text', label:'School/Institute', required:true },
                { api:'Examination_ID__c', type:'text', label:'Examination ID' },
                { api:'MonthAndYearOfPassing__c', type:'monthyear', startYear:2005, label:'Month & Year of Passing', required:true},
                { api:'Marking_Scheme__c', type:'picklist', label:'Marking Scheme' },
                { api:'Maximum_Marks__c', type:'number', label:'Maximum Marks/CGPA' },
                { api:'Obtained_Marks__c', type:'number', label:'Obtained Marks/CGPA', onChange:'recalcPercentage' },
                { api:'Conversion_Factor__c', type:'number', label:'Conversion Factor' },
                { api:'Percentage__c', type:'number', label:'Percentage', readOnly:true, calculate:'computePercentage', minPercentage:55 }
            ]
        };

        // after10 virtual
        this.metadata.after10 = {
            key: 'after10',
            title: 'After 10th Qualification',
            columnSystem: cs.after10,
            rows: [ { columns: [ { width:12, fields:['AfterTen__c'] } ] } ],
            fields: [ { api:'AfterTen__c', type:'radio', label:'', options:[ {label:'12th',value:'12th'},{label:'Diploma',value:'diploma'},{label:'Both',value:'both'} ] } ]
        };

        // Twelfth = copy of tenth
        this.metadata.twelfth = JSON.parse(JSON.stringify(this.metadata.tenth));
        this.metadata.twelfth.key = 'twelfth';
        this.metadata.twelfth.fields[3].startYear = 2008;
        this.metadata.twelfth.title = '12th Academic Details';
        this.metadata.twelfth.columnSystem = cs.twelfth;

        // Diploma
        this.metadata.diploma = {
            key: 'diploma',
            title: 'Diploma Details',
            columnSystem: cs.diploma,
            rows: [
                { columns: [ { width:4, fields:['Board_University__c'] }, { width:4, fields:['School_Institute__c'] }, { width:4, fields:['Diploma_Name__c'] }, { width:4, fields:['MonthAndYearOfPassing__c'] } ] },
                { columns: [ { width:3, fields:['Marking_Scheme__c'] }, { width:3, fields:['Maximum_Marks__c'] }, { width:3, fields:['Obtained_Marks__c'] }, { width:3, fields:['Percentage__c'] } ] }
            ],
            fields: [
                { api:'Board_University__c', type:'text', label:'Board/University' },
                { api:'School_Institute__c', type:'text', label:'School/Institute' },
                { api:'Diploma_Name__c', type:'text', label:'Diploma Name' },
                { api:'MonthAndYearOfPassing__c', type:'monthyear', label:'Month & Year of Passing', required:true },
                { api:'Marking_Scheme__c', type:'picklist', label:'Marking Scheme' },
                { api:'Maximum_Marks__c', type:'number', label:'Maximum Marks/CGPA' },
                { api:'Obtained_Marks__c', type:'number', label:'Obtained Marks/CGPA', onChange:'recalcPercentage' },
                { api:'Conversion_Factor__c', type:'number', label:'Conversion Factor' },
                { api:'Percentage__c', type:'number', label:'Percentage', readOnly:true, calculate:'computePercentage' }
            ]
        };

        this.metadata.haveAcademicBreak = {
            key: 'haveAcademicBreak',
            title: 'Academic Break',
            columnSystem: 12,
            rows: [
                {
                    columns: [
                        { width: 3, fields: ['HasAcademicBreak__c'] },
                        { width: 2, fields: ['AcademicBreakYear__c'] },
                        { width: 7, fields: ['AcademicBreakReason__c'] }
                    ]
                }
            ],
            fields: [
                {
                    api: 'HasAcademicBreak__c',
                    type: 'radio',
                    label: 'Do you have an academic break?',
                    options: [
                        { label: 'Yes', value: 'Yes' },
                        { label: 'No', value: 'No' }
                    ],
                    required: true
                },
                {
                    api: 'AcademicBreakYear__c',
                    type: 'text',
                    label: 'In Which Year?',
                    visibleWhen: { 'haveAcademicBreak.HasAcademicBreak__c': 'Yes' }                
                },
                {
                    api: 'AcademicBreakReason__c',
                    type: 'textarea',
                    label: 'Reason',
                    maxWords: 50,
                    visibleWhen: { 'haveAcademicBreak.HasAcademicBreak__c': 'Yes' },
                    requiredWhen: { 'haveAcademicBreak.HasAcademicBreak__c': 'Yes' }
                }
            ]
        };


        // Graduation
        this.metadata.graduation = {
            key:'graduation',
            title:'Graduation Details',
            columnSystem: cs.graduation,
            rows: [
                { columns: [ { width:3, fields:['State__c'] }, { width:3, fields:['Board_University__c'] }, { width:3, fields:['School_Institute__c'] }, { width:3, fields:['Mode_of_Study__c'] } ] },
                { columns: [ { width:4, fields:['Degree__c'] }, { width:4, fields:['Specilization__c'] }, { width:2, fields:['Degree_Type__c'] }, { width:2, fields:['Pattern_of_Examination__c'] } ] },
                { columns: [ { width:3, fields:['Result_Status__c'] } ] }
            ],
            fields: [
                { api:'State__c', type:'picklist', label:'State' },
                { api:'Board_University__c', type:'text', label:'Board/University' },
                { api:'School_Institute__c', type:'text', label:'School/Institute'},
                { api:'Mode_of_Study__c', type:'picklist', label:'Mode of Study' },
                { api:'Degree__c', type:'picklist', label:'Degree' },
                { api:'Specilization__c', type:'lookup', label:'Specialization', objectApi:'Specialisation_Master__c'},
                { api:'Degree_Type__c', type:'picklist', label:'Degree Type' },
                { api:'Pattern_of_Examination__c', type:'picklist', label:'Pattern Of Examination' },
                { api:'Result_Status__c', type:'picklist', label:'UG Result Status' },
            ]
        };

        // Graduation details (marks)
        this.metadata.graduationDetails = {
            key:'graduationDetails',
            title:'Graduation Marks',
            columnSystem: cs.graduationDetails,
            rows: [
                { columns: [ { width:4, fields:['MonthAndYearOfCommencement__c'] }, { width:4, fields:['MonthAndYearOfPassing__c'] }, { width:4, fields:['Marking_Scheme__c'] } ] },
                { columns: [ { width:3, fields:['Maximum_Marks__c'] }, { width:3, fields:['Obtained_Marks__c'] }, { width:3, fields:['Conversion_Factor__c'] }, { width:3, fields:['Percentage__c'] } ] }
            ],
            fields: [
                { api:'MonthAndYearOfCommencement__c', type:'monthyear', label:'Month & Year Of Commencement', required:true },
                { api:'MonthAndYearOfPassing__c', type:'monthyear', label:'Month & Year Of Passing', required:true },
                { api:'Marking_Scheme__c', type:'picklist', label:'Marking Scheme' },
                { api:'Maximum_Marks__c', type:'number', label:'Maximum Marks/CGPA' },
                { api:'Obtained_Marks__c', type:'number', label:'Obtained Marks/CGPA', onChange:'recalcGraduationPercentage' },
                { api:'Conversion_Factor__c', type:'number', label:'Conversion Factor' },
                { api:'Percentage__c', type:'number', label:'Graduation Percentage', readOnly:true, calculate:'computeGraduationPercentage' },
            ]
        };

        // Semester: two rows of 10 sem columns plus spacing -> using columnSystem from metadata
        const semColsMax = [];
        const semColsObt = [];
        for (let i=1;i<=10;i++) {
            semColsMax.push({ width:2, fields:['Maximum_Marks_SGPA__c'] }); // using width 2 to fit 30 columns system
            semColsObt.push({ width:2, fields:['Obtained_Marks_SGPA__c'] });
        }
        // add spacers if needed
        this.metadata.semester = {
            key: 'semester',
            title: 'Semester Wise Details',
            columnSystem: cs.semester,
            rows: [
                { columns: semColsMax },
                { columns: semColsObt }
            ],
            fields: [
                ...Array.from({length:10}, (_,i) => ({ api:'Maximum_Marks_SGPA__c', sequence:i+1, type:'number', label:`Sem ${i+1} Max` })),
                ...Array.from({length:10}, (_,i) => ({ api:'Obtained_Marks_SGPA__c', sequence:i+1, type:'number', label:`Sem ${i+1} Obt` }))
            ]
        };

        console.log('Semester Wise Details '+JSON.stringify(this.metadata.semester.fields));

        // Year-wise: two rows of 5 year columns (Max/Obt) using same 30-column system
        const yearColsMax = [];
        const yearColsObt = [];
        for (let i=1;i<=5;i++) {
            yearColsMax.push({ width:6, fields:['Maximum_Marks_SGPA__c'] }); // 5 * 6 = 30
            yearColsObt.push({ width:6, fields:['Obtained_Marks_SGPA__c'] });
        }
        this.metadata.year = {
            key: 'year',
            title: 'Year Wise Details',
            columnSystem: cs.semester,
            rows: [
                { columns: yearColsMax },
                { columns: yearColsObt }
            ],
            fields: [
                ...Array.from({length:5}, (_,i) => ({ api:'Maximum_Marks_SGPA__c', sequence:i+1, type:'number', label:`Year ${i+1} Max` })),
                ...Array.from({length:5}, (_,i) => ({ api:'Obtained_Marks_SGPA__c', sequence:i+1, type:'number', label:`Year ${i+1} Obt` }))
            ]
        };

        //show post grad?
        this.metadata.havePostGrad = {
            key:'havePostGrad',
            title:'Any Post Graduation?',
            columnSystem: cs.havePostGrad,
            rows: [
                { columns: [ { width:3, fields:['AnyPostGraduation__c'] } ] }
            ],
            fields: [
                { api:'AnyPostGraduation__c', type:'picklist' }
            ]
        };

        // Post Graduation
        this.metadata.postGraduation = {
            key:'postGraduation',
            title:'Post Graduation Details',
            columnSystem: cs.postGraduation,
            rows: [
                { columns: [ { width:3, fields:['State__c'] }, { width:3, fields:['Board_University__c'] }, { width:3, fields:['School_Institute__c'] }, { width:3, fields:['Mode_of_Study__c'] } ] },
                { columns: [ { width:4, fields:['Degree__c'] }, { width:4, fields:['Specilization__c'] }, { width:2, fields:['Degree_Type__c'] }, { width:2, fields:['Pattern_of_Examination__c'] } ] },
                { columns: [ { width:3, fields:['Result_Status__c'] } ] }
            ],
            fields: [
                { api:'State__c', type:'picklist', label:'State' },
                { api:'Board_University__c', type:'text', label:'Board/University' },
                { api:'School_Institute__c', type:'text', label:'School/Institute'},
                { api:'Mode_of_Study__c', type:'picklist', label:'Mode of Study' },
                { api:'Degree__c', type:'picklist', label:'Degree' },
                { api:'Specilization__c', type:'lookup', label:'Specialization', objectApi:'Specialisation_Master__c'},
                { api:'Degree_Type__c', type:'picklist', label:'Degree Type' },
                { api:'Pattern_of_Examination__c', type:'picklist', label:'Pattern Of Examination' },
                { api:'Result_Status__c', type:'picklist', label:'PG Result Status' }
            ]
        };

        // Post Graduation details (marks)
        this.metadata.postGraduationDetails = {
            key:'postGraduationDetails',
            title:'Post Graduation Marks',
            columnSystem: cs.postGraduationDetails,
            rows: [
                { columns: [ { width:4, fields:['MonthAndYearOfCommencement__c'] }, { width:4, fields:['MonthAndYearOfPassing__c'] }, { width:4, fields:['Marking_Scheme__c'] } ] },
                { columns: [ { width:3, fields:['Maximum_Marks__c'] }, { width:3, fields:['Obtained_Marks__c'] }, { width:3, fields:['Conversion_Factor__c'] }, { width:3, fields:['Percentage__c'] } ] }
            ],
            fields: [
                { api:'MonthAndYearOfCommencement__c', type:'monthyear', label:'Month & Year Of Commencement', required:true },
                { api:'MonthAndYearOfPassing__c', type:'monthyear', label:'Month & Year Of Passing', required:true },
                { api:'Marking_Scheme__c', type:'picklist', label:'Marking Scheme' },
                { api:'Maximum_Marks__c', type:'number', label:'Maximum Marks/CGPA' },
                { api:'Obtained_Marks__c', type:'number', label:'Obtained Marks/CGPA', onChange:'recalcPostGraduationPercentage' },
                { api:'Conversion_Factor__c', type:'number', label:'Conversion Factor' },
                { api:'Percentage__c', type:'number', label:'Post Graduation Percentage', readOnly:true, calculate:'computePostGraduationPercentage' },
            ]
        };

        if(this.needPostGradSemYearWise){
            // Post Semester: two rows of 10 sem columns plus spacing -> using columnSystem from metadata
            const postSemColsMax = [];
            const postSemColsObt = [];
            for (let i=1;i<=10;i++) {
                postSemColsMax.push({ width:2, fields:['Maximum_Marks_SGPA__c'] }); // using width 2 to fit 30 columns system
                postSemColsObt.push({ width:2, fields:['Obtained_Marks_SGPA__c'] });
            }
            // add spacers if needed
            this.metadata.postSemester = {
                key: 'postSemester',
                title: 'Post Semester Wise Details',
                columnSystem: cs.postSemester,
                rows: [
                    { columns: postSemColsMax },
                    { columns: postSemColsObt }
                ],
                fields: [
                    ...Array.from({length:10}, (_,i) => ({ api:'Maximum_Marks_SGPA__c', sequence:i+1, type:'number', label:`Sem ${i+1} Max` })),
                    ...Array.from({length:10}, (_,i) => ({ api:'Obtained_Marks_SGPA__c', sequence:i+1, type:'number', label:`Sem ${i+1} Obt` }))
                ]
            };

            // Post Year-wise: two rows of 5 year columns (Max/Obt) using same 30-column system
            const postYearColsMax = [];
            const postYearColsObt = [];
            for (let i=1;i<=5;i++) {
                postYearColsMax.push({ width:6, fields:['Maximum_Marks_SGPA__c'] }); // 5 * 6 = 30
                postYearColsObt.push({ width:6, fields:['Obtained_Marks_SGPA__c'] });
            }
            this.metadata.postYear = {
                key: 'postYear',
                title: 'Post Year Wise Details',
                columnSystem: cs.postSemester,
                rows: [
                    { columns: postYearColsMax },
                    { columns: postYearColsObt }
                ],
                fields: [
                    ...Array.from({length:5}, (_,i) => ({ api:'Maximum_Marks_SGPA__c', sequence:i+1, type:'number', label:`Year ${i+1} Max` })),
                    ...Array.from({length:5}, (_,i) => ({ api:'Obtained_Marks_SGPA__c', sequence:i+1, type:'number', label:`Year ${i+1} Obt` }))
                ]
            };

        }

        this.metadata.haveProfessionalQualification = {
            key: 'haveProfessionalQualification',
            title: 'Do you have any Professional Qualification?',
            columnSystem: 12,
            rows: [
                { columns: [ { width:3, fields:['HasProfessionalQualification__c'] } ] }
            ],
            fields: [
                {
                    api:'HasProfessionalQualification__c',
                    type:'radio',
                    label:'',
                    options: [
                        { label:'Yes', value:'Yes' },
                        { label:'No', value:'No' }
                    ]
                }
            ]
        };

        // Build 3 rows of 7 columns per row
        const pqRows = [];

        for (let i = 1; i <= 3; i++) {
            pqRows.push({
                columns: [
                    { width: 2, fields: ['Name_of_Qualification__c'] },
                    { width: 2, fields: ['Name_of_Institute__c'] },
                    { width: 1, fields: ['Rank_Achieved__c'] },
                    { width: 1, fields: ['Level_Achieved__c'] },
                    { width: 2, fields: ['Total_Max_Marks__c'] },
                    { width: 2, fields: ['Marks_Obtained__c'] },
                    { width: 2, fields: ['Percentage__c'] }
                ]
            });
        }

        this.metadata.professionalQualification = {
            key: 'professionalQualification',
            title: 'Professional Qualifications (If Any)',
            columnSystem: 12,
            rows: pqRows,
            fields: [
                ...Array.from({ length: 3 }, (_, i) => ({ api:'Name_of_Qualification__c', sequence:i+1, type:'text', label:'Qualification' })),
                ...Array.from({ length: 3 }, (_, i) => ({ api:'Name_of_Institute__c', sequence:i+1, type:'text', label:'Institute' })),
                ...Array.from({ length: 3 }, (_, i) => ({ api:'Rank_Achieved__c', sequence:i+1, type:'text', label:'Rank' })),
                ...Array.from({ length: 3 }, (_, i) => ({ api:'Level_Achieved__c', sequence:i+1, type:'text', label:'Level' })),
                ...Array.from({ length: 3 }, (_, i) => ({ api:'Total_Max_Marks__c', sequence:i+1, type:'number', label:'Total Max Marks' })),
                ...Array.from({ length: 3 }, (_, i) => ({ api:'Marks_Obtained__c', sequence:i+1, type:'number', label:'Marks Obtained' })),
                ...Array.from({ length: 3 }, (_, i) => ({ api:'Percentage__c', sequence:i+1, type:'number', label:'Percentage' }))
            ]
        };

        this.metadata.extraCurricular = {
            key: 'extraCurricular',
            title: 'Extra-Curricular Activities',
            columnSystem: 12,
            rows: [
                { columns: [
                    { width: 12, fields: ['ExtraCurricularActivities__c'] }
                ]}
            ],
            fields: [
                { api:'ExtraCurricularActivities__c', type:'textarea', label:'Share details of any extra-curricular activities?', maxWords: 500 }
            ]
        };

        this.metadata.importantCertification = {
            key: 'importantCertification',
            title: 'Important Certification/Programme (If Any)',
            columnSystem: 12,
            rows: [
                { columns: [
                    { width: 12, fields:['CertificationDetails__c'] }
                ]}
            ],
            fields: [
                { api:'CertificationDetails__c', type:'textarea', label:'If yes, please specify (Max. 50 words)', maxWords: 50 }
            ]
        };

        this.metadata.publications = {
            key: 'publications',
            title: 'Publications (If Any)',
            columnSystem: 12,
            rows: [
                { columns: [
                    { width: 12, fields:['Publications__c'] }
                ]}
            ],
            fields: [
                { api:'Publications__c', type:'text', label:'Any publications?' }
            ]
        };

    }

    // inject picklists from picklistCache into metadata fields
    _injectPicklists() {
        const pick = this.picklistCache || {};
        const toOptions = arr => (arr || []).map(x => ({ label: x.label || x.Label || x, value: x.value || x.Value || x }));
        const setOptions = (sectionKey, api, options) => {
            const f = (this.metadata[sectionKey].fields || []).find(x => x.api.toLowerCase() === api.toLowerCase());
            if (f) f.options = options;
        };
        setOptions('tenth','Marking_Scheme__c', toOptions(pick.Marking_Scheme__c));
        setOptions('twelfth','Marking_Scheme__c', toOptions(pick.Marking_Scheme__c));
        setOptions('diploma','Diploma_Name__c', toOptions(pick.Diploma_Name__c));
        setOptions('diploma','Marking_Scheme__c', toOptions(pick.Marking_Scheme__c));
        setOptions('graduation','Mode_of_Study__c', toOptions(pick.Mode_of_Study__c));
        setOptions('graduation','Degree__c', toOptions(pick.Degree__c));
        setOptions('graduation','Degree_Type__c', toOptions(pick.Degree_Type__c));
        setOptions('graduation','Pattern_of_Examination__c', toOptions(pick.Pattern_of_Examination__c));
        setOptions('graduation','Result_Status__c', toOptions(pick.Result_Status__c));
        setOptions('graduation','State__c', toOptions(pick.State__c));
        setOptions('graduationDetails','Marking_Scheme__c', toOptions(pick.Marking_Scheme__c));
        setOptions('postGraduation','Mode_of_Study__c', toOptions(pick.Mode_of_Study__c));
        setOptions('postGraduation','Degree__c', toOptions(pick.Degree__c));
        setOptions('postGraduation','Degree_Type__c', toOptions(pick.Degree_Type__c));
        setOptions('postGraduation','Pattern_of_Examination__c', toOptions(pick.Pattern_of_Examination__c));
        setOptions('postGraduation','Result_Status__c', toOptions(pick.Result_Status__c));
        setOptions('havePostGrad','AnyPostGraduation__c', toOptions(pick.AnyPostGraduation__c));
        setOptions('postGraduation','State__c', toOptions(pick.State__c));
        setOptions('postGraduationDetails','Marking_Scheme__c', toOptions(pick.Marking_Scheme__c));
        
        // Set up dependent picklist relationships
        // For specialization, we need to ensure it gets all available options
        const specMeta = (this.metadata.graduation.fields || []).find(f => f.api === 'Specilization__c');
        if (specMeta) {
            const allSpecOptions = this.picklistCache[specMeta.api] || [];
            if (allSpecOptions && allSpecOptions.length > 0) {
                specMeta.options = allSpecOptions;
            }
        }
    }

    // Build renderModel from metadata + values
    _buildRenderModelAll() {

        const after10 = this.education.after10;

        // Always include 10th and After10
        const list = [
            this._buildSectionRenderModel('tenth'),
            this._buildSectionRenderModel('after10')
        ];

        // Show 12th?
        if (after10.AfterTen__c === '12th' || after10.AfterTen__c === 'both') {
            list.push(this._buildSectionRenderModel('twelfth'));
        }

        // Show Diploma?
        if (after10.AfterTen__c === 'diploma' || after10.AfterTen__c === 'both') {
            list.push(this._buildSectionRenderModel('diploma'));
        }

        this.academicSections = list;

        // Conditionally include Semester vs Year sections based on pattern
        const patternVal = (this.education.graduation && this.education.graduation.Pattern_of_Examination__c) || '';
        const degreeTypeVal = (this.education.graduation && this.education.graduation.Degree_Type__c) || '';
        const isYearWise = patternVal && patternVal.toLowerCase().includes('year');
        const isSemWise = patternVal && patternVal.toLowerCase().includes('sem');

        // Parse degree type: expected labels "3 Years" / "4 Years" / "5 Years"
        const yearsFromDegreeType = (() => {
            const m = (degreeTypeVal || '').toString().match(/([3-5])\s*year/gi);
            if (!m) return null;
            const digit = (degreeTypeVal.match(/([3-5])/)||[])[1];
            return digit ? parseInt(digit, 10) : null;
        })();

        // Helper to build a sliced copy of a grid section (metadata) according to required count,
        // and mark only rendered fields as required so generic validation applies.
        const buildSlicedGridSection = (baseKey, countYears) => {
            const base = this.metadata[baseKey];
            if (!base) return null;
            const clone = JSON.parse(JSON.stringify(base));
            if (baseKey === 'year') {
                const maxYears = Math.min(countYears || 0, 5);
                clone.rows = [
                    { ...clone.rows[0], columns: clone.rows[0].columns.slice(0, maxYears) },
                    { ...clone.rows[1], columns: clone.rows[1].columns.slice(0, maxYears) }
                ];
                clone.fields = clone.fields.filter(f => {
                    const m = f.api.match(/^year(\d+)(Max|Obt)$/);
                    return m ? parseInt(m[1],10) <= maxYears : true;
                }).map(f => ({ ...f, required: true, type: f.type }));
            } else if (baseKey === 'semester') {
                const semCount = Math.min((countYears || 0) * 2, 10);
                clone.rows = [
                    { ...clone.rows[0], columns: clone.rows[0].columns.slice(0, semCount) },
                    { ...clone.rows[1], columns: clone.rows[1].columns.slice(0, semCount) }
                ];
                clone.fields = clone.fields.filter(f => {
                    const m = f.api.match(/^sem(\d+)(Max|Obt)$/);
                    return m ? parseInt(m[1],10) <= semCount : true;
                }).map(f => ({ ...f, required: true, type: f.type }));
            }
            return clone;
        };

        // Decide dynamic grid (slice + required) based on pattern + degree type
        let dynamicGridMeta = null;
        if (yearsFromDegreeType) {
            if (isYearWise) {
                dynamicGridMeta = buildSlicedGridSection('year', yearsFromDegreeType);
            } else if (isSemWise) {
                dynamicGridMeta = buildSlicedGridSection('semester', yearsFromDegreeType);
            }
        }

        // Temporarily swap metadata with dynamic clone for render model build
        let restoreKey = null;
        let originalMeta = null;
        if (dynamicGridMeta) {
            restoreKey = dynamicGridMeta.key;
            originalMeta = this.metadata[restoreKey];
            this.metadata[restoreKey] = dynamicGridMeta;
        }

        const abVal = this.education.haveAcademicBreak?.HasAcademicBreak__c || '';
        let academicBreakSection = this._buildSectionRenderModel('haveAcademicBreak');

        this.graduationSections = [
            academicBreakSection,
            this._buildSectionRenderModel('graduation'),
            this._buildSectionRenderModel('graduationDetails'),
            this._buildSectionRenderModel('havePostGrad'),
            isYearWise ? this._buildSectionRenderModel('year') : (isSemWise ? this._buildSectionRenderModel('semester') : null)
        ].filter(Boolean);

        // Check if we should show Post Graduation sections
        const anyPostGraduation = (this.education.havePostGrad && this.education.havePostGrad.AnyPostGraduation__c) || '';
        const showPostGraduation = anyPostGraduation === 'Yes';

        // Build Post Graduation sections if needed
        let postGraduationSections = [];
        if (showPostGraduation) {
            console.log('Post Graduation sections should be shown');
            // Determine if Post Graduation should use Year or Semester based on Pattern_of_Examination__c
            console.log(JSON.stringify(this.education.postGraduation));
            console.log(JSON.stringify(this.education.postGraduation.Pattern_of_Examination__c));
            const postPatternVal = (this.education.postGraduation && this.education.postGraduation.Pattern_of_Examination__c) || '';
            const postDegreeTypeVal = (this.education.postGraduation && this.education.postGraduation.Degree_Type__c) || '';
            console.log('postPatternVal'+ postPatternVal);
            console.log('postDegreeTypeVal', postDegreeTypeVal);
            const isPostYearWise = postPatternVal && postPatternVal.toLowerCase().includes('year');
            const isPostSemWise = postPatternVal && postPatternVal.toLowerCase().includes('sem');

            // Parse degree type: expected labels "3 Years" / "4 Years" / "5 Years"
            const postYearsFromDegreeType = (() => {
                const m = (postDegreeTypeVal || '').toString().match(/([3-5])\s*year/gi);
                if (!m) return null;
                const digit = (postDegreeTypeVal.match(/([3-5])/)||[])[1];
                return digit ? parseInt(digit, 10) : null;
            })();

            // Helper to build a sliced copy of a grid section (metadata) according to required count,
            // and mark only rendered fields as required so generic validation applies.
            const buildPostSlicedGridSection = (baseKey, countYears) => {
                const base = this.metadata[baseKey];
                if (!base) return null;
                const clone = JSON.parse(JSON.stringify(base));
                console.log('baseKey', baseKey, 'countYears', countYears);
                if (baseKey === 'postYear') {
                    const maxYears = Math.min(countYears || 0, 5);
                    clone.rows = [
                        { ...clone.rows[0], columns: clone.rows[0].columns.slice(0, maxYears) },
                        { ...clone.rows[1], columns: clone.rows[1].columns.slice(0, maxYears) }
                    ];
                    clone.fields = clone.fields.filter(f => {
                        const m = f.api.match(/^year(\d+)(Max|Obt)$/);
                        return m ? parseInt(m[1],10) <= maxYears : true;
                    }).map(f => ({ ...f, required: true, type: f.type }));
                } else if (baseKey === 'postSemester') {
                    const semCount = Math.min((countYears || 0) * 2, 10);
                    clone.rows = [
                        { ...clone.rows[0], columns: clone.rows[0].columns.slice(0, semCount) },
                        { ...clone.rows[1], columns: clone.rows[1].columns.slice(0, semCount) }
                    ];
                    clone.fields = clone.fields.filter(f => {
                        const m = f.api.match(/^sem(\d+)(Max|Obt)$/);
                        return m ? parseInt(m[1],10) <= semCount : true;
                    }).map(f => ({ ...f, required: true, type: f.type }));
                }
                return clone;
            };

            // Decide dynamic grid (slice + required) based on pattern + degree type
            let postDynamicGridMeta = null;
            console.log('isPostYearWise', isPostYearWise, 'isPostSemWise', isPostSemWise, 'postYearsFromDegreeType', postYearsFromDegreeType);
            if (postYearsFromDegreeType && this.needPostGradSemYearWise) {
                if (isPostYearWise) {
                    postDynamicGridMeta = buildPostSlicedGridSection('postYear', postYearsFromDegreeType);
                } else if (isPostSemWise) {
                    postDynamicGridMeta = buildPostSlicedGridSection('postSemester', postYearsFromDegreeType);
                }
            }

            // Temporarily swap metadata with dynamic clone for render model build
            let postRestoreKey = null;
            let postOriginalMeta = null;
            if (postDynamicGridMeta) {
                postRestoreKey = postDynamicGridMeta.key;
                postOriginalMeta = this.metadata[postRestoreKey];
                this.metadata[postRestoreKey] = postDynamicGridMeta;
            }

            postGraduationSections = [
                this._buildSectionRenderModel('postGraduation'),
                this._buildSectionRenderModel('postGraduationDetails'),
                isPostYearWise && this.needPostGradSemYearWise ? this._buildSectionRenderModel('postYear') : (isPostSemWise && this.needPostGradSemYearWise ? this._buildSectionRenderModel('postSemester') : null)
            ].filter(Boolean);

            // Restore original metadata after building render model to avoid permanent mutation
            if (postRestoreKey) {
                this.metadata[postRestoreKey] = postOriginalMeta;
            }
        }

        // Store the post graduation sections for rendering
        this.postGraduationSections = postGraduationSections;

        // Show Professional Qualification toggle always

        let pqList = [];
        pqList.push(this._buildSectionRenderModel('haveProfessionalQualification'));

        // If Yes → show 3-row grid
        const hasPQ = (this.education.haveProfessionalQualification && this.education.haveProfessionalQualification.HasProfessionalQualification__c) || '';
        if (hasPQ === 'Yes') {
            pqList.push(this._buildSectionRenderModel('professionalQualification'));
        }

        this.professionalQualification = pqList;

        this.academicDetailsFooterSections = [
            this._buildSectionRenderModel('extraCurricular'),
            this._buildSectionRenderModel('importantCertification'),
            this._buildSectionRenderModel('publications')
        ];

        // Restore original metadata after building render model to avoid permanent mutation
        if (restoreKey) {
            this.metadata[restoreKey] = originalMeta;
        }
    }

    _buildSectionRenderModel(sectionKey) {
        const meta = this.metadata[sectionKey];
        console.log('this.metadata['+sectionKey+'] '+JSON.stringify(this.metadata[sectionKey]));
        if (!meta) return null;
        const cs = meta.columnSystem || 12;
        const section = {
            key: meta.key || sectionKey,
            title: meta.title || sectionKey,
            rows: []
        };

        // ------------------------------------------------------------
        // SPECIAL: PROFESSIONAL QUALIFICATION (3 rows max)
        // ------------------------------------------------------------
        const edSec = this.education[sectionKey];
        if (edSec && typeof edSec === 'object' && edSec.isSequential === false) {

            const section = {
                key: meta.key || sectionKey,
                title: meta.title || sectionKey,
                rows: []
            };

            const rowStyle =
                `display:grid;grid-template-columns:repeat(${cs},1fr);` +
                `gap:8px;margin-bottom:12px;`;

            // Only sequence 1..3
            [1,2,3].forEach(seq => {
                const rec = edSec[seq] || {};

                // Use only FIRST metadata row for PQ
                const metaRow = meta.rows[0];

                const renderRow = {
                    key: `${sectionKey}-row-${seq}`,
                    style: rowStyle,
                    columns: []
                };

                metaRow.columns.forEach((col, cIdx) => {
                    const span = col.width ? Number(col.width) : cs;

                    const renderCol = {
                        key: `${sectionKey}-col-${seq}-${cIdx}`,
                        widthStyle: `grid-column: span ${span};`,
                        fields: []
                    };

                    col.fields.forEach(api => {
                        const fieldMeta =
                            meta.fields.find(f => f.api === api && f.sequence === seq) ||
                            meta.fields.find(f => f.api === api) ||
                            { api, label: api, type: 'text' };

                        renderCol.fields.push({
                            key: `${sectionKey}-${api}-${seq}`,
                            meta: { ...fieldMeta, sequence: seq },
                            value: rec[api] || null
                        });
                    });

                    renderRow.columns.push(renderCol);
                });

                section.rows.push(renderRow);
            });

            return section;
        }



        
        // compute style for rows: use CSS grid template columns based on column system
        const rowStyle = `display: grid; grid-template-columns: repeat(${cs}, 1fr); gap:8px; margin-bottom:8px;`;
        // for each meta row, create render row
        (meta.rows || []).forEach((r, rIdx) => {
            const renderRow = { key: `${section.key}-row-${rIdx}`, style: rowStyle, columns: [] };
            (r.columns || []).forEach((col, cIdx) => {
                // compute widthStyle based on span value relative to cs
                const span = col.width && Number(col.width) >= 1 ? Number(col.width) : cs;
                const widthStyle = `grid-column: span ${span};`;
                const renderCol = { key: `${section.key}-col-${rIdx}-${cIdx}`, header: col.header || null, widthStyle, fields: [] };
                // Track global sequence at section level
                section._apiCounts = section._apiCounts || {};

                (col.fields || []).forEach(fieldApi => {

                    // Increment occurrence count for this API
                    section._apiCounts[fieldApi] = (section._apiCounts[fieldApi] || 0) + 1;
                    const seq = section._apiCounts[fieldApi];

                    // Try matching correct meta (API + sequence)
                    let fieldMeta = (meta.fields || []).find(
                        f => f.api === fieldApi && Number(f.sequence) === Number(seq)
                    );

                    // If not found, fallback to FIRST meta with same API (preserves real type)
                    if (!fieldMeta) {
                        fieldMeta = (meta.fields || []).find(f => f.api === fieldApi);
                    }

                    // If still not found, final fallback
                    if (!fieldMeta) {
                        fieldMeta = { api: fieldApi, sequence: seq, label: fieldApi, type: 'text' };
                    }

                    console.log("FIELD", fieldApi, "SEQ", seq, "META", JSON.stringify(fieldMeta));
                    console.log(
                        'BEFORE GETVALUE',
                        'sectionKey =', sectionKey,
                        'fieldApi =', fieldApi,
                        'sequence =', seq,
                        'educationSection =', JSON.stringify(this.education[sectionKey])
                    );

                    const value = this._getValueForField(sectionKey, fieldApi, seq);

                    renderCol.fields.push({
                        key: `${section.key}-${fieldApi}-${seq}`,
                        meta: { ...fieldMeta, sequence: seq },
                        value
                    });
                });


                renderRow.columns.push(renderCol);
            });
            section.rows.push(renderRow);
        });
        return section;
    }

    _getValueForField(sectionKey, api, sequence) {
        // Professional Qualification (non-sequential numeric keys)
        if (sectionKey === 'professionalQualification') {
            if (!sequence) return null;
            return ((this.education.professionalQualification || {})[sequence] || {})[api] || null;
        }


        // Sections that use numeric row-based sequential storage
        const seqSections = ['semester', 'year', 'postSemester', 'postYear'];

        // If it's a sequential grid section → return value for that row (sequence = numeric row key)
        if (seqSections.includes(sectionKey) && sequence) {
            return ((this.education[sectionKey] || {})[sequence] || {})[api] || null;
        }

        // normal single-row section
        return (this.education[sectionKey] || {})[api] || null;
    }


    // handle field change events from children
    handleSectionFieldChange(e) {
        const { api, value, fieldMeta, sectionKey, sequence } = e.detail;
        console.log('handleSectionFieldChange 0 ', api, value, JSON.stringify(fieldMeta), sectionKey);
        if (api === 'AfterTen__c') {
            // set value in virtual location
            this.education.after10[api] = value;

            if (!(value === '12th' || value === 'both')) {
                this.education.twelfth = {};
            }

            if (!(value === 'diploma' || value === 'both')) {
                this.education.diploma = {};
            }


            // rebuild renderModel to reflect visibility changes
            this._buildRenderModelAll();
            return;
        }
        // find which section contains this api in metadata
        if (!sectionKey) {
            console.log('handleSectionFieldChange: no section found for api', api);
            if (api.startsWith('sem')) {
                this.education.semester = this.education.semester || {};
                this.education.semester[api] = value;
                this._buildRenderModelAll();
                return;
            }
            if (api.startsWith('year')) {
                this.education.year = this.education.year || {};
                this.education.year[api] = value;
                this._buildRenderModelAll();
                return;
            }
            return;
        }
        console.log('handleSectionFieldChange 1 ', sectionKey, api, value);
        if(sectionKey == 'postSemester' || sectionKey == 'postYear' || sectionKey == 'year' || sectionKey == 'semester') {
            this.education[sectionKey] = this.education[sectionKey] || {};
            this.education[sectionKey].isSequential = true;
            console.log('handleSectionFieldChange 2 ', JSON.stringify(this.education[sectionKey]));
            this.education[sectionKey][sequence] = this.education[sectionKey][sequence] || {};
            this.education[sectionKey][sequence][api] = value;
            console.log('handleSectionFieldChange 3 ', JSON.stringify(this.education[sectionKey]));
        } else if (!['professionalQualification','semester','year','postSemester','postYear'].includes(sectionKey)) {
            this.education[sectionKey] = this.education[sectionKey] || {};
            this.education[sectionKey][api] = value;
        }

        if (sectionKey === 'haveProfessionalQualification' && api === 'HasProfessionalQualification__c') {
            this.education.haveProfessionalQualification = {
                HasProfessionalQualification__c: value
            };
            if (value !== 'Yes') {
                this.education.professionalQualification = {};
            }
            this._buildRenderModelAll();
            return;
        }


        // PROFESSIONAL QUALIFICATION (non-sequential keyed by record Id)
        if (sectionKey === 'professionalQualification') {
            const pq = this.education.professionalQualification || {};

            pq.isSequential = false;

            // All PQ rows use numeric sequence keys (1..3)
            const seq = Number(sequence);

            if (!seq || seq < 1 || seq > 3) return;

            pq[seq] = pq[seq] || {};
            pq[seq][api] = value;

            this.education.professionalQualification = pq;
            this._buildRenderModelAll();
            return;
        }


        // if degree changed update dependent specialization options in metadata and renderModel
        if (sectionKey === 'graduation' && api === 'Degree__c') {
            const degVal = value;
            // Look for dependent options based on the controlling field value
            const specMeta = (this.metadata.graduation.fields || []).find(f => f.api === 'Specilization__c');
            if (specMeta && specMeta.dependsOn) {
                // Get all available options for the dependent field
                const allOptions = this.picklistCache[specMeta.api] || [];
                
                // For dependent picklists, we should preserve the validForBase64 data to filter options
                // However, since we're not parsing validForBase64 properly, we'll reset the options
                // This is a limitation of the current implementation
                if (allOptions && allOptions.length > 0) {
                    // Reset to all options for now - in a full implementation we would filter
                    // based on the controlling field value using validForBase64 data
                    specMeta.options = allOptions;
                }
            }
        }

        // run hooks if any
        if (fieldMeta && fieldMeta.onChange && typeof this[fieldMeta.onChange] === 'function') {
            this[fieldMeta.onChange](sectionKey, api, value);
        }

        // recompute calculations for that section and rebuild renderModel
        this._runSectionCalculations(sectionKey);
        this._buildRenderModelAll();
    }

    _runSectionCalculations(sectionKey) {
        const sec = this.metadata[sectionKey];
        if (!sec || !sec.fields) return;
        for (const f of sec.fields) {
            if (f.calculate && typeof this[f.calculate] === 'function') {
                const val = this[f.calculate](sectionKey, f.api);
                this.education[sectionKey] = this.education[sectionKey] || {};
                this.education[sectionKey][f.api] = val;
            }
        }
    }

    // generic compute percentage used by tenth/twelfth/diploma
    computePercentage(sectionKey, api) {
        const secData = this.education[sectionKey] || {};
        const scheme = secData.Marking_Scheme__c || '';
        const max = Number(secData.Maximum_Marks__c || 0);
        const obtained = Number(secData.Obtained_Marks__c || 0);
        const conv = Number(secData.Conversion_Factor__c || 10);
        if (scheme === 'CGPA') {
            if (!isNaN(obtained)) return (obtained * (conv || 10)).toFixed(2);
            return '';
        } else {
            if (max > 0 && !isNaN(obtained)) return ((obtained / max) * 100).toFixed(2);
            return '';
        }
    }

    recalcPercentage(sectionKey, api, value) {
        this._runSectionCalculations(sectionKey);
        this._buildRenderModelAll();
    }

    computeGraduationPercentage(sectionKey, api) {
        const sec = this.education.graduationDetails || {};
        const scheme = sec.Marking_Scheme__c || '';
        const max = Number(sec.Maximum_Marks__c || 0);
        const obtained = Number(sec.Obtained_Marks__c || 0);
        const conv = Number(sec.Conversion_Factor__c || 10);
        if (scheme === 'CGPA') {
            if (!isNaN(obtained)) return (obtained * (conv || 10)).toFixed(2);
            return '';
        } else {
            if (max > 0 && !isNaN(obtained)) return ((obtained / max) * 100).toFixed(2);
            return '';
        }
    }

    recalcGraduationPercentage(sectionKey, api, value) {
        this._runSectionCalculations('graduationDetails');
        this._buildRenderModelAll();
    }

    computePostGraduationPercentage(sectionKey, api) {
        const sec = this.education.postGraduationDetails || {};
        const scheme = sec.Marking_Scheme__c || '';
        const max = Number(sec.Maximum_Marks__c || 0);
        const obtained = Number(sec.Obtained_Marks__c || 0);
        const conv = Number(sec.Conversion_Factor__c || 10);
        if (scheme === 'CGPA') {
            if (!isNaN(obtained)) return (obtained * (conv || 10)).toFixed(2);
            return '';
        } else {
            if (max > 0 && !isNaN(obtained)) return ((obtained / max) * 100).toFixed(2);
            return '';
        }
    }

    recalcPostGraduationPercentage(sectionKey, api, value) {
        this._runSectionCalculations('postGraduationDetails');
        this._buildRenderModelAll();
    }

    // validation
    validateAll() {
        // Clear existing client-side errors in child composites
        const academicCmp = this.template.querySelector('c-af-academic-details');
        const graduationCmp = this.template.querySelector('c-af-graduation-details');
        const postGraduationCmp = this.template.querySelector('c-af-post-graduation-details');
        academicCmp && academicCmp.applyErrors({});
        graduationCmp && graduationCmp.applyErrors({});
        postGraduationCmp && postGraduationCmp.applyErrors({});

        const after10Val = this.education.after10.AfterTen__c; // fix undefined variable bug

        // Build error maps per section: { [api]: 'message' }
        const errorMaps = {
            tenth: {},
            twelfth: {},
            diploma: {},
            graduation: {},
            graduationDetails: {},
            postGraduation: {},
            postGraduationDetails: {},
            professionalQualification: {}
        };

        console.log('this.education ', JSON.stringify(this.education));

        // Helper to set missing errors
        const addMissing = (sectionKey, fieldMeta, sectionTitle) => {
            const secData = this.education[sectionKey] || {};

            // Sequential section → validate each row
            if (secData.isSequential) {
                const errors = {};
                Object.keys(secData)
                    .filter(k => k !== 'isSequential')
                    .forEach(seq => {
                        const row = secData[seq];
                        const val = row ? row[fieldMeta.api] : '';

                        if (fieldMeta.required && (val === '' || val === null || val === undefined)) {
                            errors[`${fieldMeta.api}__${seq}`] =
                                `${fieldMeta.label || fieldMeta.api} (Row ${seq}) is required`;
                        }
                        
                    });

                // Merge row errors into main map
                Object.assign(errorMaps[sectionKey], errors);
                return;
            }

            // Normal one-row section
            const val = secData[fieldMeta.api];
            if (fieldMeta.required && (val === '' || val === null || val === undefined)) {
                errorMaps[sectionKey][fieldMeta.api] =
                    `${fieldMeta.label || fieldMeta.api} is required`;
            }

            if (fieldMeta.api === 'Percentage__c' && fieldMeta.minPercentage) {
                const intVal = parseFloat(secData[fieldMeta.api]);

                if (!isNaN(intVal) && intVal < fieldMeta.minPercentage) {
                    errorMaps[sectionKey][fieldMeta.api] =
                        `Percentage must be at least ${fieldMeta.minPercentage}%`;
                }
            }
        };


        // Base sections
        ['tenth','graduation','graduationDetails'].forEach(key => {
            const sec = this.metadata[key];
            if (!sec || !sec.fields) return;
            sec.fields.forEach(f => addMissing(key, f, sec.title));
        });

        // Conditional sections
        if (after10Val === '12th') {
            const sec = this.metadata.twelfth;
            if (sec && sec.fields) {
                sec.fields.forEach(f => addMissing('twelfth', f, '12th'));
            }
        }
        if (after10Val === 'diploma') {
            const sec = this.metadata.diploma;
            if (sec && sec.fields) {
                sec.fields.forEach(f => addMissing('diploma', f, 'Diploma'));
            }
        }

        if (after10Val === 'both') {
            const secTwelfth = this.metadata.twelfth;
            if (secTwelfth && secTwelfth.fields) {
                secTwelfth.fields.forEach(f => addMissing('twelfth', f, '12th'));
            }

            const secDiploma = this.metadata.diploma;
            if (secDiploma && secDiploma.fields) {
                secDiploma.fields.forEach(f => addMissing('diploma', f, 'Diploma'));
            }
        }

        const hasPQ = this.education.haveProfessionalQualification?.HasProfessionalQualification__c;
        if (hasPQ === 'Yes') {
            const sec = this.metadata.professionalQualification;
            sec.fields.forEach(f => addMissing('professionalQualification', f, 'Professional Qualification'));
        }


        console.log('errorMaps ', JSON.stringify(errorMaps));

        // Check if we should validate Post Graduation sections
        const anyPostGraduation = (this.education.havePostGrad && this.education.havePostGrad.AnyPostGraduation__c) || '';
        const showPostGraduation = anyPostGraduation === 'Yes';

        if (showPostGraduation) {
            // Add validation for Post Graduation sections
            ['postGraduation','postGraduationDetails'].forEach(key => {
                const sec = this.metadata[key];
                if (!sec || !sec.fields) return;
                sec.fields.forEach(f => addMissing(key, f, sec.title));
            });
        }

        // Apply errors down to relevant children
        if (academicCmp) {
            // tenth always present
            academicCmp.applyErrors(errorMaps.tenth,'tenth');
            // twelfth/diploma conditionally
            console.log('after10Val ', after10Val);
            if (after10Val === '12th') {
                academicCmp.applyErrors(errorMaps.twelfth,'twelfth');
            }
            if (after10Val === 'diploma') {
                academicCmp.applyErrors(errorMaps.diploma,'diploma');
            }
            if (after10Val === 'both') {
                academicCmp.applyErrors(errorMaps.twelfth,'twelfth');
                academicCmp.applyErrors(errorMaps.diploma,'diploma');
            }
        }
        if (graduationCmp) {
            graduationCmp.applyErrors(errorMaps.graduation);
            graduationCmp.applyErrors(errorMaps.graduationDetails);
        }
        if (postGraduationCmp && showPostGraduation) {
            postGraduationCmp.applyErrors(errorMaps.postGraduation);
            postGraduationCmp.applyErrors(errorMaps.postGraduationDetails);
        }

        // Aggregate message for summary
        const flatErrors = []
            .concat(Object.values(errorMaps.tenth))
            .concat(Object.values(errorMaps.twelfth))
            .concat(Object.values(errorMaps.diploma))
            .concat(Object.values(errorMaps.graduation))
            .concat(Object.values(errorMaps.graduationDetails))
            .concat(Object.values(errorMaps.postGraduation))
            .concat(Object.values(errorMaps.postGraduationDetails));

        if (flatErrors.length) {
            return false;
        }

        // Server-side validation
        validatePayload({ education: this.education })
            .then(serverErrors => {
                if (serverErrors && serverErrors.length) {
                    // eslint-disable-next-line no-alert
                    alert('Server validation errors:\\n' + serverErrors.join('\\n'));
                } else {
                    // eslint-disable-next-line no-alert
                    alert('Validation passed');
                }
            }).catch(e => console.warn('server validation failed', e));
        return true;
    }

    save() {
        if (!this.validateAll()) return;
        console.log('Saving payload', JSON.stringify({ education: this.education }));

        this.saveForm(this.application?.Id, this.education);
        // eslint-disable-next-line no-alert
        alert('Saved (demo). Check console for payload.');
    }

    /* ============================================================
       FETCH FORM DATA
       ============================================================ */
    async fetchForm() {
        const request = this.buildFetchPayload(this.application?.Id);
        const response = await fetchDynamic({
            requestJson: JSON.stringify(request)
        });

        this.education = response;

        // ===== NORMALIZE PROFESSIONAL QUALIFICATION =====
        {
            const pq = this.education.professionalQualification;
            if (pq && typeof pq === 'object' && pq.isSequential === false) {
                const norm = { isSequential: false };
                let seq = 1;

                Object.keys(pq)
                    .filter(k => k !== 'isSequential')
                    .forEach(k => {
                        norm[seq] = { Id: k, ...pq[k] };
                        seq++;
                    });

                // always pad to max 3 rows
                while (seq <= 3) {
                    norm[seq] = { Id: null };
                    seq++;
                }

                this.education.professionalQualification = norm;
            }
        }

        // Ensure every metadata section exists in this.education
        Object.keys(this.metadata).forEach(key => {
            if (!this.education[key]) {
                this.education[key] = {};
            }
        });

        console.log('Fetched payload', JSON.stringify(response, null, 2));
        this._buildRenderModelAll();
        return response;
    }

    /* ============================================================
       SAVE FORM (PARENTS → CHILDREN)
       ============================================================ */
    async saveForm() {
        // 1. Build parent payload
        const parentPayload = this.buildParentSavePayload(this.education);

        // 2. Save parents (updates, inserts, deletes)
        const parentIds = await saveParents({
            applicationId: this.application?.Id,
            payloadJson: JSON.stringify(parentPayload)
        });

        console.log('Saved parents', JSON.stringify(parentIds, null, 2));

        // 3. Build child payload
        const childPayload = this.buildChildSavePayload(
            this.education,
            parentIds,
            this.application?.Id
        );



        // 4. Save children (updates, inserts, deletes)
        await saveChildren({
            payloadJson: JSON.stringify(childPayload)
        });

        // 5. Clear deleted lists
        context.children.forEach(c => {
            const delKey = c.logicalName + 'Deleted';
            if (this.education[delKey]) this.education[delKey] = [];
        });

        await this.fetchForm();

        return parentIds;
    }

    /* ============================================================
       BUILD FETCH PAYLOAD
       ============================================================ */
    buildFetchPayload(applicationId, parentIds = {}) {
        const out = { parents: [], children: [] };

        // ----- Parents -----
        context.parents.forEach(p => {
            out.parents.push({
                logicalName: p.logicalName,
                sobject: p.sobject,
                fields: p.fieldsToQuery,
                recordName: p.recordName,
                filters: [
                    { field: 'Name', value: p.recordName },
                    { field: context.parentLookupField, value: applicationId }
                ]
            });
        });

        // ----- Children -----
        context.children.forEach(c => {
            const filters = c.parentRecordName
                ? [
                    // child of academic detail → use ONLY parent lookup after server resolution
                    { field: c.parentLookupField, value: null }
                ]
                : [
                    // PQ → direct child of application
                    { field: c.parentLookupField, value: applicationId }
                ];



            out.children.push({
                logicalName: c.logicalName,
                sobject: c.sobject,
                fields: c.fieldsToQuery,
                filters,
                childKeyField: c.childKeyField,
                useSequenceKey: c.useSequenceKey,
                parentRecordName : c.parentRecordName
            });

        });

        return out;
    }

    /**
     * Normalize a single parent block before saving:
     * - Keep only allowed fields
     * - Normalize values (number, date, monthyear)
     * - If parent is disabled (toggle OFF), keep it blank but do not delete
     */
    normalizeParentBeforeSave(sectionKey, block) {
        const p = context.parents.find(x => x.logicalName === sectionKey);
        if (!p) return block;

        const allowed = new Set(p.fieldsToQuery);
        const metaSec = this.metadata[sectionKey] || {};
        const metaFields = metaSec.fields || [];

        const clean = {};

        Object.keys(block || {}).forEach(api => {
            if (!allowed.has(api)) return;
            const val = block[api];

            const fieldMeta = metaFields.find(f => f.api === api);
            clean[api] = this._normalizeValue(api, val, fieldMeta);
        });

        return clean;
    }


    /**
     * Build parent save payload with correct parent CRUD behavior:
     * - INSERT if no Id and user entered data
     * - UPDATE if Id exists (even if data is blank)
     * - Never delete parent records automatically
     */
    buildParentSavePayload(formData) {
        const out = {};
        if (!formData) return out;

        context.parents.forEach(p => {
            const sectionKey = p.logicalName;
            const block = formData[sectionKey] || {};

            // Normalize parent fields first
            const cleanFields = this.normalizeParentBeforeSave(sectionKey, block);

            // Determine if this parent has ANY meaningful data
            const hasData = Object.keys(cleanFields).some(api => {
                const val = cleanFields[api];
                return val !== null && val !== '' && val !== undefined;
            });

            // Parent handling:
            // ✔ If there is ANY data → save the parent (insert or update)
            // ✔ If blank but had an Id → still save (update to blank)
            // ✔ If blank and no Id → skip writing entirely (never insert blank)
            const shouldWrite =
                hasData ||
                (cleanFields.Id && cleanFields.Id !== null && cleanFields.Id !== undefined);

            if (!shouldWrite) {
                // Skip completely blank unsaved parent sections
                return;
            }

            out[sectionKey] = {
                sobject: p.sobject,
                recordName: p.recordName,
                fields: cleanFields
            };
        });

        console.log('buildParentSavePayload (patched)', JSON.stringify(out, null, 2));
        return out;
    }

    _findFieldMetaForParent(sectionKey, api) {
        const sec = this.metadata[sectionKey];
        if (!sec || !sec.fields) return null;
        return sec.fields.find(f => f.api === api) || null;
    }

    _normalizeValue(api, val, fieldMeta) {
        if (!fieldMeta) return val;

        // NUMBER
        if (fieldMeta.type === 'number') {
            const n = Number(val);
            return isNaN(n) ? null : n;
        }

        if (fieldMeta?.type === 'monthyear') {
            console.log('monthyear val ', val);

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
                console.log('invalid monthyear val', val);
                return null;
            }

            // ⭐ Return final required format YYYY-MM-DD HH:mm:ss
            return `${normalized} 00:00:00`;
        }




        // DATE (full date)
        if (fieldMeta.type === 'date') {
            if (!val) return null;

            // enforce yyyy-MM-dd only
            const d = new Date(val);
            if (isNaN(d)) return null;

            // Format back to yyyy-MM-dd
            return d.toISOString().substring(0, 10);
        }


        // BOOLEAN (controlled by metadata)
        if (fieldMeta.isBoolean) {
            return (val === true || val === 'true');
        }

        // Everything else stays as-is
        return val;
    }

    // Determine if a row contains ANY meaningful data (besides Id)
    _hasData(row, allowedFields, sectionKey) {
        const childMeta = context.children.find(c => c.logicalName === sectionKey);
        const zeroIsBlank = childMeta?.zeroIsBlank === true;

        return Object.keys(row).some(api => {
            if (api === 'Id') return false;
            if (!allowedFields.has(api)) return false;

            const v = row[api];

            // Treat 0 as blank only if context says so
            if (zeroIsBlank && v === 0) return false;

            return v !== null && v !== '' && v !== undefined;
        });
    }

    /**
     * Normalize a child row BEFORE CRUD logic:
     * - Keep only allowed fields (based on context.children.fieldsToQuery)
     * - Trim all strings
     * - Convert "" or whitespace-only → null
     * - Normalize monthyear and date fields
     * - Convert number-like values to numbers
     * - Ensure output is safe for Apex (no invalid date, no wrong types)
     *
     * Returns a brand-new, sanitized row.
     */
    normalizeChildBeforeSave(sectionKey, rawRow) {
        if (!rawRow) return {};

        const childMeta = context.children.find(c => c.logicalName === sectionKey);
        if (!childMeta) return rawRow;

        // Allowed = fieldsToQuery + Id + sequence key field
        const allowed = new Set(
            childMeta.fieldsToQuery.concat([childMeta.childKeyField, 'Id'])
        );

        const metaSec = this.metadata[sectionKey] || {};
        const metaFields = metaSec.fields || [];

        const clean = {};

        Object.keys(rawRow).forEach(api => {
            if (!allowed.has(api)) return;

            let val = rawRow[api];

            // 1) Convert undefined → null
            if (val === undefined) val = null;

            // 2) Trim strings
            if (typeof val === 'string') {
                val = val.trim();
            }

            // 3) Convert "" → null
            if (val === '') val = null;

            // 4) Find field metadata for normalization
            const fieldMeta = metaFields.find(f => f.api === api);

            // 5) Use global value normalizer (handles monthyear, date, number)
            val = this._normalizeValue(api, val, fieldMeta);

            clean[api] = val;
        });

        return clean;
    }


    /* ============================================================
       BUILD CHILD SAVE PAYLOAD
       ============================================================ */
    buildChildSavePayload(formData, parentIds, applicationId) {
        const out = {};
        if (!formData) return out;

        context.children.forEach(c => {
            const block = formData[c.logicalName];
            if (!block) return;

            const rows = [];
            const deleted = [];

            Object.keys(block)
                .filter(k => k !== 'isSequential')
                .forEach(k => {
                    const rawRow = block[k];
                    const row = this.normalizeChildBeforeSave(c.logicalName, rawRow);

                    if (!row) return;

                    const allowed = new Set(c.fieldsToQuery.concat([c.childKeyField, 'Id']));

                    const hasId = !!row.Id;
                    const hasData = this._hasData(row, allowed, c.logicalName);

                    // 🔥 RULE 1: NEW ROW, NO DATA → ignore
                    if (!hasId && !hasData) {
                        return;
                    }

                    // 🔥 RULE 2: NEW ROW + DATA → INSERT
                    if (!hasId && hasData) {
                        const newRow = {};

                        // Only allowed fields
                        Object.keys(row).forEach(api => {
                            if (allowed.has(api)) newRow[api] = row[api];
                        });

                        // Normalize number / monthyear formats
                        const metaSec = this.metadata[c.logicalName] || {};
                        const metaFields = metaSec.fields || [];

                        Object.keys(newRow).forEach(api => {
                            const fieldMeta = metaFields.find(f => f.api === api);
                            newRow[api] = this._normalizeValue(api, newRow[api], fieldMeta);
                        });

                        // Sequence key if required
                        if (c.useSequenceKey && c.childKeyField) {
                            newRow[c.childKeyField] = k;
                        }

                        const parentId = c.parentRecordName
                            ? (parentIds[c.parentRecordName]
                                || (formData[c.parentRecordName] && formData[c.parentRecordName].Id)
                                || applicationId)
                            : applicationId;


                        rows.push({
                            sobject: c.sobject,
                            parentLookupField: c.parentLookupField,
                            childKeyField: c.childKeyField,
                            useSequenceKey: c.useSequenceKey,
                            parentId,
                            fields: newRow,
                            Id: null // INSERT
                        });

                        return;
                    }

                    // 🔥 RULE 3: HAS ID + NO DATA → DELETE
                    if (hasId && !hasData) {
                        deleted.push(row.Id);
                        return;
                    }

                    // 🔥 RULE 4: HAS ID + DATA → UPDATE
                    if (hasId && hasData) {
                        const updateFields = {};

                        Object.keys(row).forEach(api => {
                            if (allowed.has(api)) updateFields[api] = row[api];
                        });

                        const metaSec = this.metadata[c.logicalName] || {};
                        const metaFields = metaSec.fields || [];

                        Object.keys(updateFields).forEach(api => {
                            const fieldMeta = metaFields.find(f => f.api === api);
                            updateFields[api] = this._normalizeValue(api, updateFields[api], fieldMeta);
                        });

                        if (c.useSequenceKey && c.childKeyField) {
                            updateFields[c.childKeyField] = k;
                        }

                        const parentId = c.parentRecordName
                            ? parentIds[c.parentRecordName]
                            : applicationId;

                        rows.push({
                            sobject: c.sobject,
                            parentLookupField: c.parentLookupField,
                            childKeyField: c.childKeyField,
                            useSequenceKey: c.useSequenceKey,
                            parentId,
                            fields: updateFields,
                            Id: row.Id // UPDATE
                        });
                    }
                });

            const deletedArr = (formData[c.logicalName + 'Deleted'] || []).concat(deleted);

            out[c.logicalName] = {
                sobject: c.sobject,
                parentLookupField: c.parentLookupField,
                childKeyField: c.childKeyField,
                useSequenceKey: c.useSequenceKey,
                rows,
                deletedIds: deletedArr
            };
        });

        console.log('buildChildSavePayload', JSON.stringify(out, null, 2));
        return out;
    }


    /* ============================================================
       MARK ROW AS DELETED (helper)
       ============================================================ */
    deleteChildRow(logicalName, rowId) {
        if (!this.education[logicalName + 'Deleted']) {
            this.education[logicalName + 'Deleted'] = [];
        }
        this.education[logicalName + 'Deleted'].push(rowId);

        delete this.education[logicalName][rowId];
    }
}

import fetchDynamic from '@salesforce/apex/AcademicController.fetchDynamic';
import saveParents from '@salesforce/apex/AcademicController.saveParents';
import saveChildren from '@salesforce/apex/AcademicController.saveChildren';

import { context } from './context';