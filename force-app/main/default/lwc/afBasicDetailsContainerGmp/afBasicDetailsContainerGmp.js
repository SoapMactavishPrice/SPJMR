import { LightningElement, api, track } from "lwc";
import fetchDynamic from "@salesforce/apex/ApFormDataController.fetchDynamic";
import saveParents from "@salesforce/apex/ApFormDataController.saveParents";
import updateStage from '@salesforce/apex/ApFormDataController.updateStage';
import getCountryPhoneOptions from '@salesforce/apex/ApFormDataController.getCountryPhoneOptions';

import getAllPicklistsForObjects from "@salesforce/apex/AcademicFormController.getAllPicklistsForObjects";
import { updateRecord } from "lightning/uiRecordApi";

import { context } from "./context";
import { ShowToastEvent } from "lightning/platformShowToastEvent";

import { buildErrorSummary, validateMinMaxDate, convertToTitleCase } from "c/applicationFormService";


export default class AfBasicDetailsContainerGmp extends LightningElement {

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

    @track basic = {}; // root model

    metadata = {};
    @track sectionModel = [];

    picklistCache = {};
    dependentCache = {};

    ageReferenceDate = '';

    /* ------------------------------------------------------------
       LIFECYCLE
    ------------------------------------------------------------ */
    async connectedCallback() {

        try {
            const countryOpts = await getCountryPhoneOptions();
            this._setCountryOptionsOnTelFields(countryOpts || []);
            const data = await getAllPicklistsForObjects({ objectApiNames: ["Personal_Detail__c"] });
            if (data && data.length && data[0].defaultSet) {
                const bundle = data[0];
                this.picklistCache = {};
                this.dependentCache = {};

                for (const [api, field] of Object.entries(bundle.defaultSet)) {
                    this.picklistCache[api] = (field.options || []).map(o => ({
                        label: o.label,
                        value: o.value
                    }));
                    if (field.dependent && field.controllingFieldApiName) {
                        this.dependentCache[api] = {
                            controllingField: field.controllingFieldApiName,
                            options: field.options
                        };
                    }
                }
            }
            this._buildMetadataSkeleton();
            this._applyCountryOptionsToMetadata();
            this._injectPicklists();
            if (this.application?.Id) await this.fetchForm(this.application.Id);
            else {
                this.reviseFieldConfigs();
                this._buildRenderModelAll();
            }                
        } catch (error) {
            this._buildMetadataSkeleton();
            this._applyCountryOptionsToMetadata();
            this._injectPicklists();
            if (this.application?.Id) await this.fetchForm(this.application.Id);
            else {
                this.reviseFieldConfigs();
                this._buildRenderModelAll();
            }
        } finally {
            this.isLoading = false;
        }       
    }

    handleDocsFetched(event) {
        const { documentId, files, api, sectionKey } = event.detail;

        // Ensure section exists
        if (!this.basic[sectionKey]) {
            this.basic[sectionKey] = {};
        }

        // Assign the ContentDocumentId into the correct field
        this.basic[sectionKey][api] = files?.length > 0 ? documentId : undefined;

    }


    /* ------------------------------------------------------------
       METADATA
    ------------------------------------------------------------ */
    _buildMetadataSkeleton() {

        this.metadata = {

            /* ------------------------------
               PERSONAL
            ------------------------------ */
            personalDetails: {
                key: "personalDetails",
                title: "Personal Details",
                columnSystem: 12,
                        note: {
                            api: "SECTION_NOTE",
                            type: "note",
                            text: `
<span style="color:#e53935; font-weight:bold;">
    Note: Please enter your Name as per passport
</span>
                            `
                        },
                rows: [
                    {
                        columns: [
                            { width: 2, fields: ["Title__c"] },
                            { width: 4, fields: ["First_Name__c"] },
                            { width: 3, fields: ["Middle_Name__c"] },
                            { width: 3, fields: ["Last_Name__c"] }
                        ]
                    },
                    {
                        columns: [
                            { width: 4, fields: ["Gender__c"] },
                            { width: 4, fields: ["Date_of_Birth_As_Per_10th_Marksheet__c"] },
                            { width: 4, fields: ["Age_as_on_Customisable_Date__c"] }
                        ]
                    },
                    {
                        columns: [
                            { width: 3, fields: ["Nationality__c"] },
                            { width: 3, fields: ["HavePassport__c"] },
                            { width: 3, fields: ["PassportNumber__c"] },
                            { width: 3, fields: ["PassportApplicationNumber__c"] },
                            { width: 3, fields: ["AadhaarCardNumber__c"] }
                        ]
                    }
                ],
                fields: [
                    { api:'SECTION_NOTE', type:'note' },
                    { api: "Title__c", type: "picklist", label: "Title", required: true },
                    { api: "First_Name__c", type: "text", label: "First Name", required: true, maxlength: '255' },
                    { api: "Middle_Name__c", type: "text", label: "Middle Name", maxlength: '255' },
                    { api: "Last_Name__c", type: "text", label: "Last Name", required: true, maxlength: '255' },

                    { api: "Gender__c", type: "picklist", label: "Gender", required: true },

                    { api: "Date_of_Birth_As_Per_10th_Marksheet__c", type: "date", min:"1995-1-1", label: "Date of Birth", required: true },
                    { api: "Age_as_on_Customisable_Date__c", type: "text", label: "Age as on: __refDate__", readOnly: true },
                    { api: "Nationality__c", type: "picklist", label: "Nationality", required: true },
                    { api: "HavePassport__c", type: "picklist", label: "Do you have a Passport?", required: true, visibleWhen: { "otherResources.isIndianNational": true }, },
                    { api: "PassportNumber__c", type: "text", label: "Passport Number", maxlength: '25', pattern:"^[A-Z0-9<]{3,20}$", required: true, visibleWhen: { "otherResources.showPassportField": true }, },
                    { api: "PassportApplicationNumber__c", type: "text", label: "Passport Application Number", maxlength: '35', pattern:"^[A-Za-z0-9]{10,20}$", required: true, visibleWhen: { "otherResources.showPassportApplicationNo": true }, },
                    { api: "AadhaarCardNumber__c", type: "text", label: "Aadhaar Card Number", maxlength: '80', pattern:"^[2-9][0-9]{11}$",required: true, visibleWhen: { "otherResources.isIndianNational": true }, },
                ]
            },

            photoUpload: {
                key: "photoUpload",
                title: "Photograph Upload",
                columnSystem: 12,
                noteInline: true,

                rows: [
                    {
                        columns: [
                            // LEFT SIDE — Upload
                            { width: 4, fields: ["PassportPhoto__c"] },

                            // RIGHT SIDE — Note
                            { width: 8, fields: ["PHOTO_UPLOAD_NOTE"] }
                        ]
                    }
                ],

                fields: [
                    { 
                        api: "PassportPhoto__c", 
                        type: "file", 
                        label: "Upload Your Recent Passport Size Photograph", 
                        required: true,
                        docCode: 'PASSPORT_PHOTO',
                        accept: ['.jpg','.png','.jpeg'],
                        uploadEngine: "custom",
                        maxFiles: 1,
                        maxFileSizeMb: 1
                    },

                    {
                        api: "PHOTO_UPLOAD_NOTE",
                        type: "note",
                        text: `
            <div>
                <ul style="margin:0; padding-left:20px;">
                    <li>Photographs should be in JPEG or PNG format, 150px wide × 200px tall.</li>
                    <li>File size must not exceed <b>1 MB</b>.</li>
                    <li>Photo should have a white or lightly coloured background.</li>
                    <li>Eyes should be open and clearly visible.</li>
                    <li>Face must be straight, centered and fully visible.</li>
                    <li>Photograph should not be more than 6 months old.</li>
                    <li>Photographs where the candidate is wearing a cap or sunglasses will be rejected.</li>
                </ul>
            </div>`
                    }
                ]
            },


            /* ------------------------------
               CONTACT
            ------------------------------ */
            contactDetails: {
                key: "contactDetails",
                title: "Contact Details",
                columnSystem: 12,
                rows: [
                    {
                        columns: [
                            { width: 4, fields: ["Primary_E_mail__c"] },
                            { width: 4, fields: ["Alternate_E_mail__c"] },
                            { width: 4, fields: ["LinkedIn_Profile_URL__c"] },
                        ]
                    },
                    {
                        columns: [
                            { width: 6, fields: ["Mobile_Number__c"] },
                            { width: 6, fields: ["Alternate_Mobile_Number__c"] },
                        ]
                    },
                    {
                        columns: [
                            { width: 6, fields: ["WhatsApp_Mobile_Number__c"] },
                        ]
                    }
                ],
                fields: [
                    { api: "Primary_E_mail__c", type: "email", label: "Email", required: true, readOnly:true, maxlength: '80' },
                    { api: "Alternate_E_mail__c", type: "email", label: "Alternate Email", required: true, maxlength: '80' },
                    { api: "LinkedIn_Profile_URL__c", type: "text", label: "LinkedIn ID", required: true, maxlength: '255' },
                    { api: "Mobile_Number__c", type: "tel", label: "Mobile Number", required: true },
                    { api: "Alternate_Mobile_Number__c", type: "tel", label: "Alternate Mobile", required: true },
                    { api: "WhatsApp_Mobile_Number__c", type: "tel", label: "WhatsApp Number", required: true },
                ]
            },

            parentOrGuardian: {
                key: "parentOrGuardian",
                title: "Family Details",
                columnSystem: 12,
                
                rows: [
                    {
                        columns: [
                            { width: 6, fields: ["ParentOrGuardianDetails__c"] }
                        ]
                    }
                ],
                fields: [
                    { api: "ParentOrGuardianDetails__c", label: "Parent / Guardian Detail", type: "picklist", required: true }
                ]
            },

            /* ------------------------------
               PARENTS
            ------------------------------ */
            parentDetails: {
                key: "parentDetails",
                title: "Parent Details",
                columnSystem: 12,
                rows: [
                    {
                        columns: [
                            { width: 6, fields: ["FatherMotherSelection__c"] }
                        ]
                    },
                    {
                        fluid: true,
                        fields: ["FatherTitle__c", "Father_s_Name__c", "FatherOccupation__c","OtherFatherOccupation__c", "FatherIncome__c", "Father_E_Mail_ID__c", "Parent_s_Mobile_Number__c"]
                    },
                    {
                        fluid: true,
                        fields: ["MotherTitle__c", "Mother_s_Name__c", "MotherOccupation__c","OtherMotherOccupation__c", "MotherIncome__c", "Mother_E_Mail_ID__c", "Mother_s_Mobile_Number__c"]
                    },
                ],
                fields: [
                    { api: "FatherMotherSelection__c", label: "Father / Mother", type: "multipicklist", required: true },

                    { api: "FatherTitle__c", type: "picklist", label: "Father's Title", span:4, required: true, visibleWhen: { "otherResources.showFatherFields": true }, },
                    { api: "Father_s_Name__c", type: "text", label: "Father's Name", span:4, required: true, maxlength: '255', visibleWhen: { "otherResources.showFatherFields": true }, },
                    { api: "FatherOccupation__c", type: "picklist", label: "Father's Occupation", span:4, required: true, visibleWhen: { "otherResources.showFatherFields": true }, },
                    {
                        api: "OtherFatherOccupation__c", 
                        maxlength: '100',
                        type: "text",
                        label: "Enter Father Occupation",
                        shortLabel:'Father Occupation',
                        visibleWhen: [
                            { "parentDetails.FatherOccupation__c": "Other" },
                        ], 
                        span:4,
                        required: true
                    },
                    { api: "FatherIncome__c", type: "picklist", label: "Father's Income",  span:4, required: true, visibleWhen: { "otherResources.showFatherFields": true }, },
                    { api: "Father_E_Mail_ID__c", type: "email", label: "Father's Email", span:4, required: true, maxlength: '80', visibleWhen: { "otherResources.showFatherFields": true }, },
                    { api: "Parent_s_Mobile_Number__c", type: "tel", label: "Father's Number", span:6, required: true, visibleWhen: { "otherResources.showFatherFields": true }, },

                    { api: "MotherTitle__c", type: "picklist", label: "Mother's Title", span:4, required: true, visibleWhen: { "otherResources.showMotherFields": true }, },
                    { api: "Mother_s_Name__c", type: "text", label: "Mother's Name", span:4, required: true, maxlength: '255', visibleWhen: { "otherResources.showMotherFields": true }, },
                    { api: "MotherOccupation__c", type: "picklist", label: "Mother's Occupation", span:4, required: true, visibleWhen: { "otherResources.showMotherFields": true }, },
                    {
                        api: "OtherMotherOccupation__c",
                        type: "text",
                        label: "Enter Mother Occupation",
                        shortLabel:'Mother Occupation',
                        visibleWhen: [
                            { "parentDetails.MotherOccupation__c": "Other" },
                        ], 
                        span:4,
                        required: true, 
                        maxlength: '100'
                    },
                    { api: "MotherIncome__c", type: "picklist", label: "Mother's Income", span:4, required: true, visibleWhen: { "otherResources.showMotherFields": true }, },
                    { api: "Mother_E_Mail_ID__c", type: "email", label: "Mother's Email", span:4, required: true, maxlength: '80', visibleWhen: { "otherResources.showMotherFields": true }, },
                    { api: "Mother_s_Mobile_Number__c", type: "tel", label: "Mother's Number", span:6, required: true, visibleWhen: { "otherResources.showMotherFields": true }, },
                ]
            },

            /* ------------------------------
               GUARDIAN (conditional)
            ------------------------------ */
            guardianDetails: {
                key: "guardianDetails",
                title: "Guardian Details",
                columnSystem: 12,
                layout:"fluid",
                fields: [
                    {
                        api: "GuardianName__c",
                        type: "text",
                        label: "Guardian Name",
                        visibleWhen: { "parentOrGuardian.ParentOrGuardianDetails__c": "Guardian" }, 
                        span:3,
                        required: true, 
                        maxlength: '255'
                    },
                    {
                        api: "GuardianEmail__c",
                        type: "email",
                        label: "Guardian Email",
                        visibleWhen: { "parentOrGuardian.ParentOrGuardianDetails__c": "Guardian" }, 
                        span:4,
                        required: true, 
                        maxlength: '80'
                    },
                    {
                        api: "GuardianMobile__c",
                        type: "tel",
                        label: "Guardian Mobile",
                        visibleWhen: { "parentOrGuardian.ParentOrGuardianDetails__c": "Guardian" }, 
                        span:5,
                        required: true
                    },
                    {
                        api: "GuardianRelationship__c",
                        type: "text",
                        label: "Guardian's Relationship",
                        visibleWhen: { "parentOrGuardian.ParentOrGuardianDetails__c": "Guardian" }, 
                        span:3,
                        required: true, 
                        maxlength: '80'
                    },
                    {
                        api: "GuardianOccupation__c",
                        type: "picklist",
                        label: "Guardian Occupation",
                        visibleWhen: { "parentOrGuardian.ParentOrGuardianDetails__c": "Guardian" }, 
                        span:4,
                        required: true
                    },
                    {
                        api: "OtherGuardianOccupation__c",
                        type: "text",
                        label: "Enter Guardian Occupation",
                        shortLabel:'Guardian Occupation',
                        visibleWhen: [
                            { "parentOrGuardian.ParentOrGuardianDetails__c": "Guardian" },
                            { "guardianDetails.GuardianOccupation__c": "Other" },
                        ], 
                        span:4,
                        required: true,
                        maxlength: '100'
                    }
                ]
            },

            correspondenceAddress: {
                key: "correspondenceAddress",
                title: "Correspondence Address",
                columnSystem: 12,
                rows: [
                    {
                        fluid: true,
                        fields: ["Corr_Country__c", "Corr_State__c", "Corr_City__c", "Other_Corr_City__c"]
                    },
                    {
                        columns: [
                            { width: 4, fields: ["Corr_Address1__c"] },
                            { width: 4, fields: ["Corr_Address2__c"] }
                        ]
                    },
                    {
                        columns: [
                            { width: 3, fields: ["Corr_Ind_Pincode__c"] },
                            { width: 3, fields: ["Corr_Pincode__c"] },
                            { width: 3, fields: ["Is_Permanent_Same__c"] }
                        ]
                    }
                ],
                fields: [
                    { 
                        api: "Corr_Country__c", 
                        type: "lookup", 
                        label: "Correspondence Country",
                        span: 3,
                        required: true, 
                        objectApi: "Country_Master__c",
                    }, // 🔥 will be dynamically injected  },
                    { 
                        api: "Corr_State__c", 
                        type: "lookup", 
                        label: "Correspondence State",
                        span: 3,
                        required: true,
                        objectApi: "State__c",
                        dynamicFilter: "corrState",
                        visibleWhen: { "correspondenceAddress.Corr_Country__c": '__notNull' },
                    },
                    { 
                        api: "Corr_City__c",
                        type: "lookup", 
                        label: "Correspondence District/City",
                        span: 3,
                        required: true,
                        objectApi: "City__c",
                        sortInfo: ['Order__c DESC NULLS LAST'],
                        dynamicFilter: "corrCity",
                        allowOther: true,
                        visibleWhen: { "otherResources.showCorrCityField": true },
                    },
                    { 
                        api: "Other_Corr_City__c", 
                        type: "text", 
                        label: "Other Correspondence District/City", 
                        span: 3,
                        required: true,
                        visibleWhen: { "otherResources.showOtherCorrCityField":true}, 
                        maxlength: '100',
                    },
                    
                    { api: "Corr_Address1__c", type: "text", label: "Address Line 1", required: true, maxlength:"32768" },
                    { api: "Corr_Address2__c", type: "text", label: "Address Line 2", maxlength:"32768" },
                    { 
                        api: "Corr_Pincode__c", 
                        type: "text", 
                        label: "Pincode", 
                        required: true,
                        maxlength: '10',
                        visibleWhen: { "otherResources.showCorrPincodeField": true },
                        helpText:"In case your country doesn't provide pincode/zipcode enter 0" 
                    },
                    { 
                        api: "Corr_Ind_Pincode__c",
                        type: "lookup", 
                        label: "Pincode",
                        required: true,
                        objectApi: "Pincode__c",
                        dynamicFilter: "corrIndPincode",
                        allowOther: true,
                        visibleWhen: { "otherResources.showCorrIndPincodeField": true },
                    },
                    {
                        api: "Is_Permanent_Same__c",
                        type: "radio",
                        label: "Is permanent address same?",
                        options: [
                            { label: "Yes", value: "Yes" },
                            { label: "No", value: "No" }
                        ]
                    }
                ]
            },

            permanentAddress: {
                key: "permanentAddress",
                title: "Permanent Address",
                columnSystem: 12,
                rows: [
                    {
                        fluid: true,
                        fields: ["Perm_Country__c", "Perm_State__c", "Perm_City__c", "Other_Perm_City__c"]
                    },
                    {
                        columns: [
                            { width: 4, fields: ["Perm_Address1__c"] },
                            { width: 4, fields: ["Perm_Address2__c"] }
                        ]
                    },
                    {
                        columns: [
                            { width: 3, fields: ["Perm_Ind_Pincode__c"] },
                            { width: 3, fields: ["Perm_Pincode__c"] },
                        ]
                    }
                ],
                fields: [
                    { 
                        api: "Perm_Country__c", 
                        type: "lookup", 
                        label: "Permanent Country", 
                        required: true, 
                        objectApi: "Country_Master__c",
                    }, // 🔥 will be dynamically injected  },
                    { 
                        api: "Perm_State__c", 
                        type: "lookup", 
                        label: "Permanent State", 
                        required: true,
                        objectApi: "State__c",
                        dynamicFilter: "permState",
                        visibleWhen: [
                            { "correspondenceAddress.Is_Permanent_Same__c": "No"},
                            { "permanentAddress.Perm_Country__c": '__notNull' }
                        ]
                    },
                    { 
                        api: "Perm_City__c",
                        type: "lookup", 
                        label: "Permanent District/City",
                        span: 3,
                        required: true,
                        objectApi: "City__c",
                        sortInfo: ['Order__c DESC NULLS LAST'],
                        dynamicFilter: "permCity",
                        allowOther: true,
                        visibleWhen: { "otherResources.showPermCityField": true },
                    },
                    { 
                        api: "Other_Perm_City__c", 
                        type: "text", 
                        label: "Other Permanent District/City", 
                        required: true,
                        span: 3,
                        visibleWhen: { "otherResources.showOtherPermCityField": true }, 
                        maxlength: '100',
                    },

                    {
                        api: "Perm_Address1__c",
                        type: "text",
                        label: "Address Line 1",
                        required: true, 
                        maxlength:"32768",
                        visibleWhen: { "correspondenceAddress.Is_Permanent_Same__c": "No" }
                    },
                    {
                        api: "Perm_Address2__c",
                        type: "text",
                        label: "Address Line 2",
                        maxlength:"32768",
                        visibleWhen: { "correspondenceAddress.Is_Permanent_Same__c": "No" }
                    },
                    {
                        api: "Perm_Pincode__c",
                        type: "text",
                        label: "Pincode",
                        required: true, 
                        maxlength: '10',
                        helpText:"In case your country doesn't provide pincode/zipcode enter 0",
                        visibleWhen: { "otherResources.showPermPincodeField": true },
                    },
                    { 
                        api: "Perm_Ind_Pincode__c",
                        type: "lookup", 
                        label: "Pincode",
                        required: true,
                        objectApi: "Pincode__c",
                        dynamicFilter: "permIndPincode",
                        allowOther: true,
                        visibleWhen: { "otherResources.showPermIndPincodeField": true },
                    },
                ]
            },

        };
    }

    get showFatherFields() {
        const v = this.basic.parentDetails?.FatherMotherSelection__c || '';
        return v === 'Father' || v === 'Father;Mother';
    }

    get showMotherFields() {
        const v = this.basic.parentDetails?.FatherMotherSelection__c || '';
        return v === 'Mother' || v === 'Father;Mother';
    }

    get isIndianNational() {
        const v = this.basic.personalDetails?.Nationality__c || '';
        return v === 'Indian';
    }

    get showPassportField() {
        const v = this.basic.personalDetails?.HavePassport__c || '';
        return !this.isIndianNational || v === "Yes";
    }

    get showPassportApplicationNo() {
        const v = this.basic.personalDetails?.HavePassport__c || '';
        return this.isIndianNational && v === "No";
    }

    get showCorrCityField() {
        const addr = this.basic.correspondenceAddress || {};
        // India and Non-India: show city once state is selected
        return !!addr.Corr_State__c;
    }


    get showOtherCorrCityField() {
        const addr = this.basic.correspondenceAddress || {};
        const cityIsOther = addr?.Display?.Corr_City__c === 'Other';
        return cityIsOther;
    }

    get showCorrPincodeField() {
        const addr = this.basic.correspondenceAddress || {};
        const isIndia = addr.Display?.Corr_Country__c === 'India';        
        const citySelected = !!addr.Corr_City__c;
        const cityIsOther = citySelected && addr.Display?.Corr_City__c === 'Other';
        const indPinIsOther = addr?.Display?.Corr_Ind_Pincode__c === 'Other';

        if (isIndia) {
            // India → show free-text Corr_Pincode__c when city = Other OR Ind pincode picklist = Other
            return cityIsOther || indPinIsOther;
        } else {
            // Non-India → city selected
            return true;
        }
    }


    get showCorrIndPincodeField() {
        const addr = this.basic.correspondenceAddress || {};

        const isIndia = addr.Display?.Corr_Country__c === 'India';
        const citySelected = !!addr.Corr_City__c;
        const cityIsOther = addr.Display?.Corr_City__c === 'Other';

        // India + city selected + city NOT Other + pincode picklist not "Other"
        return isIndia && citySelected && !cityIsOther
        // && !indPinIsOther;
    }


    get corrState() {
        if (!this.basic.correspondenceAddress?.Corr_Country__c) {
            return null; // disables filtering until country is selected
        }

        return {
            criteria: [
                {
                    fieldPath: 'Country_Master__c',
                    operator: 'eq',
                    value: this.basic.correspondenceAddress.Corr_Country__c
                }
            ]
        };
    }

    

    get corrCity() {
        const addr = this.basic.correspondenceAddress;
        if (!addr?.Corr_State__c) return null;

        return {
            criteria: [
                {
                    fieldPath: 'State__c',
                    operator: 'eq',
                    value: addr.Corr_State__c
                },
                {
                    fieldPath: 'Name',
                    operator: 'eq',
                    value: 'Other'
                },
                {
                    fieldPath: 'Id',
                    operator: 'eq',
                    value: addr.Corr_City__c
                }
            ],
            filterLogic: "1 OR 2 OR 3"
        };
    }

    get corrIndPincode() {
        const addr = this.basic.correspondenceAddress;
        return {
            criteria: [
                {
                    fieldPath: 'City__c',
                    operator: 'eq',
                    value: addr.Corr_City__c
                },
                {
                    fieldPath: 'Name',
                    operator: 'eq',
                    value: 'Other'
                },
                {
                    fieldPath: 'Id',
                    operator: 'eq',
                    value: addr.Corr_Ind_Pincode__c
                }
            ],
            filterLogic: "1 OR 2 OR 3"
        };
    }
    

    get showPermCityField() {
        const perm = this.basic.permanentAddress || {};
        const permEnabled = this.basic.correspondenceAddress?.Is_Permanent_Same__c === 'No';
        if (!permEnabled) return false;
        // India and Non-India: show city once state is selected
        return !!perm.Perm_State__c;
    }

    get showOtherPermCityField() {
        const perm = this.basic.permanentAddress || {};
        const permEnabled = this.basic.correspondenceAddress?.Is_Permanent_Same__c === 'No';
        if (!permEnabled) return false;

        const cityIsOther = perm?.Display?.Perm_City__c === 'Other';
        return cityIsOther;
    }

    get showPermPincodeField() {
        const perm = this.basic.permanentAddress || {};
        const permEnabled = this.basic.correspondenceAddress?.Is_Permanent_Same__c === 'No';
        if (!permEnabled) return false;

        const isIndia = perm.Display?.Perm_Country__c === 'India';
        const citySelected = !!perm.Perm_City__c;
        const cityIsOther = citySelected && perm.Display?.Perm_City__c === 'Other';
        const indPinIsOther = perm?.Display?.Perm_Ind_Pincode__c === 'Other';

        if (isIndia) {
            // India → show free-text Perm_Pincode__c when city = Other OR Ind pincode picklist = Other
            return cityIsOther || indPinIsOther;
        } else {
            // Non-India → city selected
            return true;
        }
    }


    get showPermIndPincodeField() {
        const perm = this.basic.permanentAddress || {};

        const permEnabled =
            this.basic.correspondenceAddress?.Is_Permanent_Same__c === 'No';

        const isIndia =
            perm.Display?.Perm_Country__c === 'India';

        const citySelected =
            !!perm.Perm_City__c;

        const cityIsOther =
            perm.Display?.Perm_City__c === 'Other';

        if (!permEnabled) return false;

        // India + city selected + city NOT Other
        return isIndia && citySelected && !cityIsOther 
    }



    get permState() {
        
        if (!this.basic.permanentAddress?.Perm_Country__c) {
            return null; // disables filtering until country is selected
        }
        return {
            criteria: [
                {
                    fieldPath: 'Country_Master__c',
                    operator: 'eq',
                    value: this.basic.permanentAddress.Perm_Country__c
                }
            ]
        };
    }

    

    get permCity() {
        const addr = this.basic.permanentAddress;
        if (!addr?.Perm_State__c) return null;

        return {
            criteria: [
                {
                    fieldPath: 'State__c',
                    operator: 'eq',
                    value: addr.Perm_State__c
                },
                {
                    fieldPath: 'Name',
                    operator: 'eq',
                    value: 'Other'
                },
                {
                    fieldPath: 'Id',
                    operator: 'eq',
                    value: addr.Perm_City__c
                }
            ],
            filterLogic: "1 OR 2 OR 3"
        };
    }

    get permIndPincode() {
        const addr = this.basic.permanentAddress;
        return {
            criteria: [
                {
                    fieldPath: 'City__c',
                    operator: 'eq',
                    value: addr.Perm_City__c
                },
                {
                    fieldPath: 'Id',
                    operator: 'eq',
                    value: addr.Perm_Ind_Pincode__c
                }
            ],
            filterLogic: "1 OR 2"
        };
    }

    // Inject countryOptions returned from Apex into all tel-type fields
    _setCountryOptionsOnTelFields(countryOpts) {

        // 🔒 persist once at container level
        this._telCountryOptions = countryOpts || [];

        this._applyCountryOptionsToMetadata();
    }

    _applyCountryOptionsToMetadata() {
        if (!this.metadata || !this._telCountryOptions?.length) return;

        const telTargets = [
            { section: 'contactDetails', apis: ['Mobile_Number__c', 'Alternate_Mobile_Number__c', 'WhatsApp_Mobile_Number__c'] },
            { section: 'parentDetails', apis: ['Parent_s_Mobile_Number__c', 'Mother_s_Mobile_Number__c'] },
            { section: 'guardianDetails', apis: ['GuardianMobile__c'] },
        ];

        telTargets.forEach(t => {
            const section = this.metadata[t.section];
            if (!section?.fields) return;

            t.apis.forEach(api => {
                const f = section.fields.find(
                    x => x.api === api && x.type === 'tel'
                );
                if (f) {
                    f.countryOptions = this._telCountryOptions;
                }
            });
        });
    }

    reviseFieldConfigs() {

        if (!this.metadata?.correspondenceAddress || !this.metadata?.permanentAddress || !this.metadata?.personalDetails) {
            return;
        }

        if (this.metadata?.personalDetails) {

            const nationality = this.basic?.personalDetails?.Nationality__c;

            const field = this.metadata.personalDetails.fields.find(
                f => f.api === "PassportNumber__c"
            );

            if (field) {
                field.pattern =
                    nationality === "Indian"
                        ? '^(?=.*[A-Z])[A-Z0-9]{8}$'
                        : '^[A-Z0-9]{3,20}$';
            }
        }



        const isNullOrBlank = v => v === null || v === undefined || v === '';

        /* ----------------------------
        CORRESPONDENCE
        ---------------------------- */
        const corrCountry = this.basic?.correspondenceAddress?.Display?.Corr_Country__c;
        const isCorrIndia = corrCountry === 'India' || isNullOrBlank(corrCountry);
        this.metadata.correspondenceAddress = {
            ...this.metadata.correspondenceAddress,
            fields: this.metadata.correspondenceAddress.fields.map(f => {
                if (!["Corr_State__c","Corr_City__c","Corr_Pincode__c","Corr_Ind_Pincode__c"].includes(f.api)) {
                    return f;
                }
                const updated = { ...f };
                updated.required = isCorrIndia;
                if (f.api === "Corr_Pincode__c") {
                    updated.pattern = isCorrIndia ? '^(0|[0-9]{6})$' : null;   // 🚀 remove pattern completely
                }
                return updated;
            })
        };

        /* ----------------------------
        PERMANENT
        ---------------------------- */
        const permCountry = this.basic?.permanentAddress?.Display?.Perm_Country__c;
        const isPermIndia = permCountry === 'India' || isNullOrBlank(permCountry);
        this.metadata.permanentAddress = {
            ...this.metadata.permanentAddress,
            fields: this.metadata.permanentAddress.fields.map(f => {
                if (!["Perm_State__c","Perm_City__c","Perm_Pincode__c","Perm_Ind_Pincode__c"].includes(f.api)) {
                    return f;
                }
                const updated = { ...f };
                updated.required = isPermIndia;
                if (f.api === "Perm_Pincode__c") {
                    updated.pattern = isPermIndia ? '^(0|[0-9]{6})$' : null;   // 🚀 remove pattern completely
                }
                return updated;
            })
        };
    }


    _injectPicklists() {
        const pick = this.picklistCache || {};
        const toOptions = arr => (arr || []).map(o => ({ label: o.label || o, value: o.value || o }));

        const setOptions = (section, api, values) => {
            const s = this.metadata[section];
            if (!s) return;
            const f = s.fields.find(x => x.api === api);
            if (f) f.options = values;
        };

        setOptions("personalDetails", "Title__c", toOptions(pick.Title__c));
        setOptions("personalDetails", "Gender__c", toOptions(pick.Gender__c));

        setOptions("personalDetails", "Nationality__c", toOptions(pick.Nationality__c));
        setOptions("personalDetails", "HavePassport__c", toOptions(pick.HavePassport__c));

        setOptions("parentDetails", "FatherTitle__c", toOptions(pick.FatherTitle__c));
        setOptions("parentDetails", "MotherTitle__c", toOptions(pick.MotherTitle__c));

        setOptions("parentDetails", "FatherIncome__c", toOptions(pick.FatherIncome__c));
        setOptions("parentDetails", "MotherIncome__c", toOptions(pick.MotherIncome__c));

        setOptions("parentDetails", "FatherOccupation__c", toOptions(pick.FatherOccupation__c));
        setOptions("parentDetails", "MotherOccupation__c", toOptions(pick.MotherOccupation__c));
        setOptions("guardianDetails", "GuardianOccupation__c", toOptions(pick.GuardianOccupation__c));

        setOptions("parentOrGuardian", "ParentOrGuardianDetails__c", toOptions(pick.ParentOrGuardianDetails__c));
        setOptions("parentDetails", "FatherMotherSelection__c", toOptions(pick.FatherMotherSelection__c));


    }

    static LOCKED_APPLICATION_STATUSES = ['Paid'];
    static UNLOCK_ASSIGNMENT_STATUSES = ['Change Requested'];

    get isReadOnly() {
        return AfBasicDetailsContainerGmp.LOCKED_APPLICATION_STATUSES.includes(this.application?.Application_Status__c) &&
            !AfBasicDetailsContainerGmp.UNLOCK_ASSIGNMENT_STATUSES.includes(this.application?.Assignment_Status__c);
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
       FETCH
    ------------------------------------------------------------ */
    async fetchForm(appId) {
        try {

            const request = { parents: [
                {
                    logicalName: 'application',
                    sobject: context.parents.find(p => p.logicalName === 'application').sobject,
                    fields: context.parents.find(p => p.logicalName === 'application').fieldsToQuery,
                    filters: [{ field: 'Id', value: appId }]
                }
            ], children: [] };

            context.parents.forEach(p => {
                if (p.logicalName === 'application') return;
                request.parents.push({
                    logicalName: p.logicalName,
                    sobject: p.sobject,
                    fields: p.fieldsToQuery,
                    filters: [
                        { field: context.parentLookupField, value: appId }
                    ]
                });
            });

            const resp = await fetchDynamic({ requestJson: JSON.stringify(request) });

            const existingPhotoUpload = JSON.parse(JSON.stringify(this.basic?.photoUpload || {}));

            this.application.Application_Status__c = resp?.application?.Application_Status__c;
            this.application.Assignment_Status__c = resp?.application?.Assignment_Status__c;
            this.application.Applicant__c = resp?.application?.Applicant__c;

            this.basic = {
                personalDetails: resp.personalDetails || {},
                photoUpload: existingPhotoUpload,
                contactDetails: resp.contactDetails || {},
                parentOrGuardian: resp.parentOrGuardian || {},
                parentDetails: resp.parentDetails || {},
                guardianDetails: resp.guardianDetails || {},
                correspondenceAddress: resp.correspondenceAddress || {},
                permanentAddress: resp.permanentAddress || {},                
            };


            // default family mode
            if (!this.basic.parentOrGuardian.ParentOrGuardianDetails__c) {
                this.basic.parentOrGuardian.ParentOrGuardianDetails__c = "Parents";
            }

            // default toggle
            if (!this.basic.correspondenceAddress.Is_Permanent_Same__c) {
                this.basic.correspondenceAddress.Is_Permanent_Same__c = "Yes";
            }

            // Age calculation reference date from Cohort
            let refDate = this.basic.personalDetails.Application__r?.Batch__r?.CalculateAgeAsOf__c;

            // If the cohort reference date is missing → fallback to TODAY
            if (!refDate) {
                const today = new Date();
                refDate = today.toISOString().slice(0, 10); // YYYY-MM-DD
            }

            const formattedDate = (dateValue) => {
                if (!dateValue) return '';

                // Split 'YYYY-MM-DD' and create local date (Month is 0-indexed)
                const [year, month, day] = dateValue.split('-').map(Number);
                const date = new Date(year, month - 1, day); 
                
                const dayNum = date.getDate();
                const monthName = date.toLocaleString('default', { month: 'long' });
                const yearFull = date.getFullYear();

                const getOrdinalNum = (n) => {
                    return n + (n > 0 ? ['th', 'st', 'nd', 'rd'][(n > 3 && n < 21) || n % 10 > 3 ? 0 : n % 10] : '');
                };

                return `${getOrdinalNum(dayNum)} ${monthName} ${yearFull}`;
            }

            this.ageReferenceDate = formattedDate(refDate);

            // Update metadata label with real date
            this.metadata.personalDetails.fields = this.metadata.personalDetails.fields.map(f => {
                if (f.api === "Age_as_on_Customisable_Date__c") {
                    return {
                        ...f,
                        label: `Age as on: ${this.ageReferenceDate}`
                    };
                }
                return f;
            });

            // Now compute age
            if (this.basic.personalDetails.Date_of_Birth_As_Per_10th_Marksheet__c) {
                this.basic.personalDetails.Age_as_on_Customisable_Date__c =
                    this._computeAge(
                        refDate,
                        this.basic.personalDetails.Date_of_Birth_As_Per_10th_Marksheet__c
                    );
            }

            this._applyReadOnlyMode();
            this.reviseFieldConfigs();
            this._buildRenderModelAll();

        } catch (e) {
            console.error("fetchForm error", e);
        }
    }

    get contextBlock() {
        return {
            personalDetails: this.basic.personalDetails,
            photoUpload: this.basic.photoUpload,
            contactDetails: this.basic.contactDetails,
            parentOrGuardian: this.basic.parentOrGuardian,
            parentDetails: this.basic.parentDetails,
            guardianDetails: this.basic.guardianDetails,
            correspondenceAddress: this.basic.correspondenceAddress,
            permanentAddress: this.basic.permanentAddress,
            applicationId: this.application?.Id,
            otherResources: {
                showFatherFields:this.showFatherFields,
                showMotherFields:this.showMotherFields,
                isIndianNational:this.isIndianNational,
                showPassportField:this.showPassportField,
                showPassportApplicationNo:this.showPassportApplicationNo,
                
                showCorrCityField:this.showCorrCityField,
                showOtherCorrCityField:this.showOtherCorrCityField,
                showCorrIndPincodeField:this.showCorrIndPincodeField,
                showCorrPincodeField:this.showCorrPincodeField,

                showPermCityField:this.showPermCityField,
                showOtherPermCityField:this.showOtherPermCityField,
                showPermIndPincodeField:this.showPermIndPincodeField,
                showPermPincodeField:this.showPermPincodeField,
                
                        
            }
        };
    }



    /* ------------------------------------------------------------
       RENDER
    ------------------------------------------------------------ */
    _buildRenderModelAll() {
        const keys = [
            "personalDetails",
            "photoUpload",
            "contactDetails",
            "parentOrGuardian",
            "parentDetails",
            "guardianDetails",
            "correspondenceAddress",
            "permanentAddress",
        ];

        const mode = this.basic.parentOrGuardian.ParentOrGuardianDetails__c;
        const permanentToggle = this.basic.correspondenceAddress.Is_Permanent_Same__c;

        this.sectionModel = keys.map(k => {

            // -----------------------------
            // Parent / Guardian logic
            // -----------------------------
            if (!mode) {
                return k === "parentDetails"
                    ? this._buildSectionRenderModel(k)
                    : null;
            }

            if (mode === "Parents" && k === "guardianDetails") return null;
            if (mode === "Guardian" && k === "parentDetails") return null;

            // -----------------------------
            // Permanent Address section gate (ONLY toggle)
            // -----------------------------
            if (k === "permanentAddress" && permanentToggle !== "No") {
                return null;
            }

            return this._buildSectionRenderModel(k);
        }).filter(Boolean);
    }



    _buildSectionRenderModel(sectionKey) {
        const meta = this.metadata[sectionKey];
        if (!meta) return null;
        if (meta?.layout === 'fluid') {
            const sectionData = this.basic[sectionKey] || {};
            return {
                key: meta.key,
                title: meta.title,
                rows: this._buildFluidRows(meta, sectionData)
            };
        }

        const section = {
            key: meta.key,
            title: meta.title,
            rows: []
        };

        /* NOTE ROW (static) */
        if (meta.note && !meta.noteInline) {
            section.rows.push({
                key: `${sectionKey}-note-row`,
                style: `margin-bottom: 10px;`,
                columns: [{
                    key: `${sectionKey}-note-col`,
                    widthStyle: 'grid-column: span 12;',
                    fields: [{
                        key: `${sectionKey}-NOTE`,
                        meta: { ...meta.note, sectionKey },
                        value: meta.note.text
                    }]
                }]
            });
        }

        meta.rows.forEach((r, rIdx) => {

            if (r.fluid === true) {
                section.rows.push(
                    ...this._buildFluidRowFromFieldList(
                        meta,
                        r.fields || [],
                        this.basic[sectionKey] || {},
                        rIdx
                    )
                );
                return;
            }

            const row = {
                key: `${sectionKey}-row-${rIdx}`,
                style: `display:grid;grid-template-columns:repeat(${meta.columnSystem},1fr);gap:8px;margin-bottom:8px;`,
                columns: []
            };

            r.columns.forEach((col, cIdx) => {
                const colObj = {
                    key: `${sectionKey}-col-${rIdx}-${cIdx}`,
                    widthStyle: `grid-column: span ${col.width}`,
                    fields: []
                };

                col.fields.forEach(api => {
                    const fMeta = meta.fields.find(f => f.api === api) || {};
                    let val = null;

                    // For normal fields → from data model
                    if (fMeta.type !== "note") {
                        val = this.basic[sectionKey][api] ?? null;
                    }
                    // For note fields → take text from metadata
                    else {
                        val = fMeta.text || "";
                    }

                    // Clone metadata (so we don't mutate original definition)
                    const metaForRender = { ...fMeta, sectionKey };

                    // ----- ⭐ Inject dynamic filter if defined -----
                    if (metaForRender.dynamicFilter && this[metaForRender.dynamicFilter] !== undefined) {
                        const dyn = this[metaForRender.dynamicFilter];

                        // If it's a function → call it
                        if (typeof dyn === "function") {
                            metaForRender.filter = dyn.call(this);
                        }
                        // If it's a getter → dyn is already the filter object
                        else {
                            metaForRender.filter = dyn;
                        }
                    }

                    colObj.fields.push({
                        key: `${sectionKey}-${api}`,
                        meta: metaForRender,
                        value : val
                    });
                    // -----------------------------------------------

                });

                if (colObj.fields.length) {
                    row.columns.push(colObj);
                }
            });

            section.rows.push(row);
        });

        return section;
    }

    get renderModel() {
        return this.sectionModel;
    }

    /* ------------------------------------------------------------
       NORMALIZE
    ------------------------------------------------------------ */
    _normalizeValue(api, value, fieldMeta = {}) {

        if (fieldMeta.type === "number") {
            if (value === "" || value === null || value === undefined) return null;
            const n = Number(value);
            return isNaN(n) ? null : n;
        }

        if (fieldMeta.type === "date") {
            return value || null;
        }

        if (fieldMeta.type === "radio" || fieldMeta.type === "picklist") {
            return value ? String(value) : null;
        }

        if (typeof value === "string") {
            return value.trim();
        }

        return value;
    }

    handleLookupSet(e){
        const { api, value, displayValue, sectionKey } = e.detail;

        const fieldMeta = this.metadata[sectionKey]?.fields?.find(f => f.api === api);

        const normalized = this._normalizeValue(api, value, fieldMeta);

        this.basic[sectionKey][api] = normalized;
        
        //for others record picker
        this.basic[sectionKey].Display ||= {};
        this.basic[sectionKey].Display[api] = displayValue;

        if(['Corr_Country__c', 'Corr_City__c', 'Corr_Ind_Pincode__c', 'Perm_Country__c', 'Perm_City__c', 'Perm_Ind_Pincode__c'].includes(api)){
            this.reviseFieldConfigs();
            this._handleLookupDrivenRerender(api);
        }
    }

    SECTION_DEPENDENCIES = {
        correspondenceAddress: [
            'Corr_Country__c',
            'Corr_State__c',
            
            'Corr_City__c',
            'Corr_Ind_Pincode__c',
            'Is_Permanent_Same__c'
        ],
        permanentAddress: [
            'Perm_Country__c',
            'Perm_State__c',
            
            'Perm_City__c',
            'Perm_Ind_Pincode__c',
        ]
    };

    _rebuildSections(sectionKeys) {

        // 🛡 First render / safety net
        if (!this.sectionModel || this.sectionModel.length === 0) {
            this.reviseFieldConfigs();
            this._buildRenderModelAll();
            return;
        }

        this.sectionModel = this.sectionModel.map(sec => {
            if (!sectionKeys.includes(sec.key)) {
                return sec; // untouched
            }
            return this._buildSectionRenderModel(sec.key);
        }).filter(Boolean);
    }

    _handleLookupDrivenRerender(api) {
        const affectedSections = [];

        Object.entries(this.SECTION_DEPENDENCIES).forEach(
            ([section, fields]) => {
                if (fields.includes(api)) {
                    affectedSections.push(section);
                }
            }
        );

        // Permanent section visibility depends on correspondence toggle
        if (api === 'Is_Permanent_Same__c') {
            affectedSections.push('permanentAddress');
        }

        if (affectedSections.length) {
            this._rebuildSections([...new Set(affectedSections)]);
        }
    }



    delayOnChangeTimeout;

    handleDelayOnChange(e) {
         if (this.delayOnChangeTimeout) {
            clearTimeout(this.delayOnChangeTimeout);
        }

        this.delayOnChangeTimeout = setTimeout(() => {
            this.handleSectionFieldChange(e)
        }, 100);
    }
        

    /* ------------------------------------------------------------
       FIELD CHANGE
    ------------------------------------------------------------ */
    handleSectionFieldChange(e) {
        let { api, value, displayValue, sectionKey, browserEventType } = e.detail;

        const titleCaseFields = [
            'First_Name__c',
            'Middle_Name__c',
            'Last_Name__c',
            'GuardianName__c',
            'Father_s_Name__c',
            'Mother_s_Name__c'
        ];

        const shouldApplyTitleCase =
            titleCaseFields.includes(api) &&
            typeof value === 'string' &&
            browserEventType === 'blur';

        if (shouldApplyTitleCase) {
            value = convertToTitleCase(value);
        }

        const fieldMeta = this.metadata[sectionKey]?.fields?.find(f => f.api === api);

        const normalized = this._normalizeValue(api, value, fieldMeta);

        this.basic[sectionKey][api] = normalized;

        if (shouldApplyTitleCase) {
            this._rebuildSections([sectionKey]);
        }
        
        //for others record picker
        this.basic[sectionKey].Display ||= {};
        this.basic[sectionKey].Display[api] = displayValue;

        if (api === "Date_of_Birth_As_Per_10th_Marksheet__c") {

            let refDate =
                this.basic.personalDetails.Application__r?.Batch__r?.CalculateAgeAsOf__c;

            if (!refDate) {
                const today = new Date();
                refDate = today.toISOString().slice(0, 10);
            }

            this.basic.personalDetails.Age_as_on_Customisable_Date__c =
                this._computeAge(refDate, normalized);
        }

        if(api === "HavePassport__c") {
            if(this.basic[sectionKey][api] === 'Yes') {
                this.basic.personalDetails.PassportApplicationNumber__c = null;
            } else if(this.basic[sectionKey][api] === 'No') {
                this.basic.personalDetails.PassportNumber__c = null;
            }
        }

        if(api === "Nationality__c") {
            if(this.basic[sectionKey][api] !== 'Indian') {
                this.basic.personalDetails.HavePassport__c = null;
                this.basic.personalDetails.PassportApplicationNumber__c = null;
                this.basic.personalDetails.AadhaarCardNumber__c = null;                
            }
        }

        // Clear opposite section when ParentOrGuardian changes
        if (api === "ParentOrGuardianDetails__c") {
            if (normalized === "Parents") {
                // Clear guardian fields
                ["GuardianName__c", "GuardianEmail__c", "GuardianMobile__c", "GuardianOccupation__c", "OtherGuardianOccupation__c", "GuardianRelationship__c"]
                    .forEach(f => this.basic.guardianDetails[f] = null);
            }

            if (normalized === "Guardian") {
                // Clear parent fields
                [
                    "FatherTitle__c", "Father_s_Name__c", "Father_E_Mail_ID__c",
                    "FatherIncome__c", "Parent_s_Mobile_Number__c", "FatherOccupation__c",
                    "OtherFatherOccupation__c",
                    "MotherTitle__c", "Mother_s_Name__c", "Mother_E_Mail_ID__c",
                    "MotherIncome__c", "Mother_s_Mobile_Number__c", "MotherOccupation__c",
                    "OtherMotherOccupation__c",
                    "FatherMotherSelection__c",
                ].forEach(f => this.basic.parentDetails[f] = null);
            }
        }

        // --- Correspondence hierarchy ---
        if (api === 'Corr_Country__c') {
            this.basic.correspondenceAddress.Corr_State__c = null;
            this.basic.correspondenceAddress.Corr_City__c = null;
            this.basic.correspondenceAddress.Other_Corr_City__c = null;
            this.basic.correspondenceAddress.Display ||= {};
            this.basic.correspondenceAddress.Display.Corr_City__c = null;
            this.basic.correspondenceAddress.Corr_Ind_Pincode__c = null;
            if (this.basic.correspondenceAddress.Display) {
                this.basic.correspondenceAddress.Display.Corr_Ind_Pincode__c = null;
            }
            this.basic.correspondenceAddress.Corr_Pincode__c = null;
        }

        if (api === 'Corr_State__c') {
            this.basic.correspondenceAddress.Corr_City__c = null;
            this.basic.correspondenceAddress.Other_Corr_City__c = null;
            this.basic.correspondenceAddress.Display ||= {};
            this.basic.correspondenceAddress.Display.Corr_City__c = null;
            this.basic.correspondenceAddress.Corr_Ind_Pincode__c = null;
            if (this.basic.correspondenceAddress.Display) {
                this.basic.correspondenceAddress.Display.Corr_Ind_Pincode__c = null;
            }
            this.basic.correspondenceAddress.Corr_Pincode__c = null;
        }

        if (api === "Corr_City__c") {
            this.basic.correspondenceAddress.Other_Corr_City__c = null;
            this.basic.correspondenceAddress.Display ||= {};
            this.basic.correspondenceAddress.Corr_Ind_Pincode__c = null;
            if (this.basic.correspondenceAddress.Display) {
                this.basic.correspondenceAddress.Display.Corr_Ind_Pincode__c = null;
            }
            this.basic.correspondenceAddress.Corr_Pincode__c = null;
        }

        // --- Permanent hierarchy ---
        if (api === 'Perm_Country__c') {
            this.basic.permanentAddress.Perm_State__c = null;
            this.basic.permanentAddress.Perm_City__c = null;
            this.basic.permanentAddress.Other_Perm_City__c = null;
            this.basic.permanentAddress.Display ||= {};
            this.basic.permanentAddress.Display.Perm_City__c = null;
            this.basic.permanentAddress.Perm_Ind_Pincode__c = null;
            if (this.basic.permanentAddress.Display) {
                this.basic.permanentAddress.Display.Perm_Ind_Pincode__c = null;
            }
            this.basic.permanentAddress.Perm_Pincode__c = null;
        }

        if (api === 'Perm_State__c') {
            this.basic.permanentAddress.Perm_City__c = null;
            this.basic.permanentAddress.Other_Perm_City__c = null;
            this.basic.permanentAddress.Display ||= {};
            this.basic.permanentAddress.Display.Perm_City__c = null;
            this.basic.permanentAddress.Perm_Ind_Pincode__c = null;
            if (this.basic.permanentAddress.Display) {
                this.basic.permanentAddress.Display.Perm_Ind_Pincode__c = null;
            }
            this.basic.permanentAddress.Perm_Pincode__c = null;
        }

        if (api === "Perm_City__c") {
            this.basic.permanentAddress.Other_Perm_City__c = null;
            this.basic.permanentAddress.Display ||= {};
            this.basic.permanentAddress.Perm_Ind_Pincode__c = null;
            if (this.basic.permanentAddress.Display) {
                this.basic.permanentAddress.Display.Perm_Ind_Pincode__c = null;
            }
            this.basic.permanentAddress.Perm_Pincode__c = null;
        }

        // copy address
        if (api === "Is_Permanent_Same__c") {

            if (normalized === "Yes") {
                // copy correspondence → permanent
                ["Country", "State", "City", "Address1", "Address2", "Pincode", "Ind_Pincode"]
                    .forEach(k => {
                        this.basic.permanentAddress[`Perm_${k}__c`] =
                            this.basic.correspondenceAddress[`Corr_${k}__c`];
                    });
                // 🔥 Copy "Other City" text field explicitly
                this.basic.permanentAddress.Other_Perm_City__c = 
                    this.basic.correspondenceAddress.Other_Corr_City__c ?? null;                
            }

            if (normalized === "No") {
                // reset permanent address
                ["Country", "State", "City", "Address1", "Address2", "Pincode", "Ind_Pincode"]
                    .forEach(k => {
                        this.basic.permanentAddress[`Perm_${k}__c`] = null;
                    });

                // 🔥 Copy "Other City" text field explicitly
                this.basic.permanentAddress.Other_Perm_City__c = null;
            }
        }
        
        // Define fields that trigger visibility changes and require full rebuild
        const rebuildTriggerFields = [
            'Nationality__c',
            'HavePassport__c',
            'ParentOrGuardianDetails__c',
            'FatherMotherSelection__c',
            'FatherOccupation__c',
            'MotherOccupation__c',
            'GuardianOccupation__c',
            'Is_Permanent_Same__c',
            'Corr_Country__c',
            'Corr_State__c',
            'Corr_City__c',
            'Corr_Ind_Pincode__c',
            'Perm_Country__c',
            'Perm_State__c',
            'Perm_City__c',
            'Perm_Ind_Pincode__c',
            "Date_of_Birth_As_Per_10th_Marksheet__c"
        ];

        this.reviseFieldConfigs();
        
        // Only rebuild if this field affects visibility or dependent fields
        if (rebuildTriggerFields.includes(api)) {
            
            this._buildRenderModelAll();
        }
    }

    _computeAge(refDateStr, dobStr) {
        try {
            if (!dobStr) return null;
            const ref = new Date(refDateStr);
            const dob = new Date(dobStr);
            if (isNaN(ref) || isNaN(dob)) return null;

            let age = ref.getFullYear() - dob.getFullYear();
            const m = ref.getMonth() - dob.getMonth();
            if (m < 0 || (m === 0 && ref.getDate() < dob.getDate())) {
                age--;
            }
            return age;
        } catch {
            return null;
        }
    }

    /* ------------------------------------------------------------
       VALIDATION
    ------------------------------------------------------------ */
    async validateAll() {

        const errors = {};

        const validatePattern = (text, pattern) => {
            if (!text) {
                return { isValid: true };
            }
            pattern instanceof RegExp || (pattern = new RegExp(pattern));
            const isValid = pattern.test(text);
            return { isValid };
        }

        const renderedSections = this.sectionModel.map(s => s.key);

        renderedSections.forEach(sectionKey => {
            const meta = this.metadata[sectionKey];
            if (!meta) return;

            meta.fields.forEach(f => {
                if (!this._isFieldVisible(f)) return;

                if (f.required) {
                    const val = this.basic[sectionKey]?.[f.api];
                    const empty = val === "" || val === null || val === undefined;

                    if (empty) {
                        errors[sectionKey] ||= {};
                        errors[sectionKey][f.api] = `${f.label || f.api} is required`;
                    }
                }

                if (f.pattern) {
                    const { isValid } = validatePattern(this.basic[sectionKey]?.[f.api], f.pattern);
                    if (!isValid) {
                        errors[sectionKey] ||= {};
                        errors[sectionKey][f.api] = ``;
                    }
                }

                if (f.type === "email") {
                    const { isValid } = validatePattern(this.basic[sectionKey]?.[f.api], /^(?!.*\.\.)(?!\.)(?!.*\.$)[a-zA-Z0-9._%+-]{1,64}@[a-zA-Z0-9-]{1,63}(?:\.[a-zA-Z]{2,})+$/);
                    if (!isValid) {
                        errors[sectionKey] ||= {};
                        errors[sectionKey][f.api] = ``;
                    }
                }

                if (f.type == 'date' && (f.min || f.max)) {
                    const secData = this.basic[sectionKey] || {};
                    const res = validateMinMaxDate(f, secData[f.api]);
                    if (res) {
                        errors[sectionKey] ||= {};
                        errors[sectionKey][f.api] = ``;
                    }
                }

            });
        });

        const actualAge = Number(this.basic.personalDetails.Age_as_on_Customisable_Date__c);
        const maxAge = Number(this.basic.personalDetails.Application__r?.Batch__r?.UpperAgeBound__c);
        const minAge = Number(this.basic.personalDetails.Application__r?.Batch__r?.LowerAgeBound__c);

        if (!isNaN(actualAge)) {

            if (!isNaN(minAge) && !isNaN(maxAge) &&
                (actualAge < minAge || actualAge > maxAge)) {

                errors.personalDetails ||= {};
                errors.personalDetails.Age_as_on_Customisable_Date__c =
                    `Age must be between ${minAge} and ${maxAge}`;
            }

            else if (!isNaN(minAge) && actualAge < minAge) {
                errors.personalDetails ||= {};
                errors.personalDetails.Age_as_on_Customisable_Date__c =
                    `Age should be greater than or equal to ${minAge}`;
            }

            else if (!isNaN(maxAge) && actualAge > maxAge) {
                errors.personalDetails ||= {};
                errors.personalDetails.Age_as_on_Customisable_Date__c =
                    `Age should be less than or equal to ${maxAge}`;
            }
        }



        // Gather phone validation errors from rendered child only
        const wrapper = this.template.querySelector('c-af-basic-details');
        if (wrapper && typeof wrapper.validatePhoneField === 'function') {
            const phoneErrors = await wrapper.validatePhoneField(); // ARRAY
            phoneErrors.forEach(err => {
                errors[err.section] ||= {};
                errors[err.section][err.api] = err.message;
            });
        }

        // APPLY ERRORS to the single visible wrapper
        if (wrapper && typeof wrapper.applyErrors === 'function') {
            Object.keys(errors).forEach(sectionKey => {
                const errorsForSection = errors[sectionKey] || {};
                wrapper.applyErrors(errorsForSection, sectionKey);
            });
        }

        const hasErrors = Object.values(errors)
            .some(sec => sec && Object.keys(sec).length > 0);

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

        return Object.keys(errors).length === 0;
    }

    _isFieldVisible(fMeta) {
        if (!fMeta.visibleWhen) return true;

        const conds = Array.isArray(fMeta.visibleWhen)
            ? fMeta.visibleWhen
            : [fMeta.visibleWhen];

        const root = this.contextBlock || this.basic; // ⭐ only change

        return conds.every(cond => {
            const key = Object.keys(cond)[0];
            const expected = cond[key];

            const parts = key.split('.');
            let cur = root; // ⭐ start from root

            for (let p of parts) {
                if (cur == null) return false;
                cur = cur[p];
            }

            if (expected === '__notNull' || expected === '__notEmpty') {
                return cur !== null && cur !== undefined && cur !== '';
            }

            return String(cur) === String(expected);
        });
    }

    _buildFluidRows(meta, sectionData) {
        const cs = meta.columnSystem || 12;
        const rows = [];

        sectionData.Display ||= {};

        let row = { columns: [], used: 0 };

        meta.fields.forEach(f => {
            if (f.type === 'note') return;
            if (!this._isFieldVisible(f)) return;

            const span = f.span || 3;

            if (row.used + span > cs) {
                rows.push(row);
                row = { columns: [], used: 0 };
            }

            // ✅ CLONE METADATA
            const metaForRender = { ...f, sectionKey: meta.key };

            // ✅ INJECT DYNAMIC FILTER
            if (metaForRender.dynamicFilter && this[metaForRender.dynamicFilter] !== undefined) {
                const dyn = this[metaForRender.dynamicFilter];
                metaForRender.filter =
                    typeof dyn === "function" ? dyn.call(this) : dyn;
            }

            row.columns.push({
                key: `${meta.key}-${f.api}`,
                widthStyle: `grid-column: span ${span};`,
                fields: [{
                    key: `${meta.key}-${f.api}`,
                    meta: metaForRender,
                    value: sectionData?.[f.api] ?? null
                }]
            });

            row.used += span;
        });

        if (row.columns.length) {
            rows.push(row);
        }

        return rows.map((r, i) => ({
            key: `${meta.key}-fluid-row-${i}`,
            style: `display:grid;grid-template-columns:repeat(${cs},1fr);gap:8px;margin-bottom:12px;`,
            columns: r.columns
        }));
    }

    _buildFluidRowFromFieldList(meta, fieldApis, sectionData, rowIndex) {
        const cs = meta.columnSystem || 12;
        const rows = [];

        sectionData.Display ||= {};

        let row = { columns: [], used: 0 };

        fieldApis.forEach(api => {
            const f = meta.fields.find(x => x.api === api);
            if (!f || !this._isFieldVisible(f)) return;

            const span = f.span || 3;

            if (row.used + span > cs) {
                rows.push(row);
                row = { columns: [], used: 0 };
            }

            const metaForRender = { ...f, sectionKey: meta.key };

            if (metaForRender.dynamicFilter && this[metaForRender.dynamicFilter] !== undefined) {
                const dyn = this[metaForRender.dynamicFilter];
                metaForRender.filter =
                    typeof dyn === "function" ? dyn.call(this) : dyn;
            }

            row.columns.push({
                key: `${meta.key}-${api}`,
                widthStyle: `grid-column: span ${span};`,
                fields: [{
                    key: `${meta.key}-${api}`,
                    meta: metaForRender,
                    value: sectionData?.[api] ?? null
                }]
            });

            row.used += span;
        });

        if (row.columns.length) rows.push(row);

        return rows.map((r, i) => ({
            key: `${meta.key}-fluid-${rowIndex}-${i}`,
            style: `display:grid;grid-template-columns:repeat(${cs},1fr);gap:8px;margin-bottom:12px;`,
            columns: r.columns
        }));
    }



    clearInvisibleFields() {
        Object.entries(this.metadata).forEach(([sectionKey, sectionMeta]) => {
            const sectionData = this.basic[sectionKey];
            if (!sectionData) return;

            const isMultiRow = !!sectionMeta.useSequenceKey;

            sectionMeta.fields.forEach(fMeta => {
                if (fMeta.type === 'note') return;

                if (this._isFieldVisible(fMeta)) return;

                // ----------------------------
                // SINGLE OBJECT SECTION
                // ----------------------------
                if (!isMultiRow) {
                    delete sectionData[fMeta.api];
                    return;
                }

                // ----------------------------
                // MULTI-ROW SECTION
                // ----------------------------
                Object.values(sectionData).forEach(row => {
                    if (row && typeof row === 'object') {
                        delete row[fMeta.api];
                    }
                });
            });
        });
    }


    /* ------------------------------------------------------------
       SAVE
    ------------------------------------------------------------ */
    buildSavePayload() {
        const out = {};

        context.parents.forEach(p => {
            const sectionKey = p.logicalName;         // e.g., "personalDetails"
            const model = this.basic.hasOwnProperty(sectionKey) ? this.basic[sectionKey] : false;
            if(!model) {
                return;
            };

            const block = {
                sobject: p.sobject,
                recordName: p.recordName,
                fields: {}
            };

            p.fieldsToQuery.forEach(api => {
                if(p.sobject === "Application__c" && api === "Application_Status__c") return;
                if (api === "Id") {
                    if (model.Id) block.fields.Id = model.Id;
                } else {               
                    block.fields[api] = model[api] ?? null;
                }
            });

            block.fields[context.parentLookupField] = this.application.Id;

            out[p.logicalName] = block;
        });

        return out;
    }

    async syncApplicantAccount() {
        const applicantId = this.application?.Applicant__c;
        if (!applicantId) {
            return;
        }

        const fields = {
            Id: applicantId,
            FirstName: this.basic?.personalDetails?.First_Name__c ?? null,
            MiddleName: this.basic?.personalDetails?.Middle_Name__c ?? null,
            LastName: this.basic?.personalDetails?.Last_Name__c ?? null,
            Phone: this.basic?.contactDetails?.Mobile_Number__c ?? null
        };

        await updateRecord({ fields });
    }

    @api async saveForm() {
        if(this.isReadOnly) return true;
        this.isLoading = true;
        this.clearInvisibleFields();

        // --- Enforce clearing on SAVE also ---
        const mode = this.basic.parentOrGuardian.ParentOrGuardianDetails__c;

        // Clear Guardian if Parents is selected
        if (mode === "Parents") {
            [
                "GuardianName__c",
                "GuardianEmail__c",
                "GuardianMobile__c",
                "GuardianOccupation__c",
                "OtherGuardianOccupation__c",
                "GuardianRelationship__c"
            ].forEach(f => this.basic.guardianDetails[f] = null);
        }

        // Clear Parents if Guardian is selected
        if (mode === "Guardian") {
            [
                "FatherTitle__c", "Father_s_Name__c", "Father_E_Mail_ID__c",
                "FatherIncome__c", "Parent_s_Mobile_Number__c", "FatherOccupation__c",
                "OtherFatherOccupation__c",
                "MotherTitle__c", "Mother_s_Name__c", "Mother_E_Mail_ID__c",
                "MotherIncome__c", "Mother_s_Mobile_Number__c", "MotherOccupation__c",
                "OtherMotherOccupation__c",
                "FatherMotherSelection__c"
            ].forEach(f => this.basic.parentDetails[f] = null);
        }

        //copy address
        if (this.basic.correspondenceAddress.Is_Permanent_Same__c === "Yes") {
            ["Country", "State", "City", "Address1", "Address2", "Pincode", "Ind_Pincode"]
                .forEach(k => {
                    this.basic.permanentAddress[`Perm_${k}__c`] =
                                this.basic.correspondenceAddress[`Corr_${k}__c`];

                });

            // 🔥 Copy "Other City" text field explicitly
            this.basic.permanentAddress.Other_Perm_City__c = 
                this.basic.correspondenceAddress.Other_Corr_City__c ?? null;
        }

        const valid = await this.validateAll();
        if (!valid) {
            this.isLoading = false;
            return false;
        }

        const payload = this.buildSavePayload();

        try {
            await saveParents({
                applicationId: this.application.Id,
                payloadJson: JSON.stringify(payload)
            });

            try {
                await this.syncApplicantAccount();
            } catch (accountError) {
                console.error("account sync error", accountError);
                console.error("account sync error body", accountError?.body);
                console.error("account sync output errors", accountError?.body?.output?.errors);
                console.error("account sync field errors", accountError?.body?.output?.fieldErrors);
                this.dispatchEvent(new ShowToastEvent({
                    title: "Partial save",
                    message: "Personal Details saved, but Person Account sync failed",
                    variant: "error",
                    mode: "sticky"
                }));
                await this.fetchForm(this.application.Id);
                return false;
            }
            
            await updateStage({ 
                applicationId: this.application.Id, 
                newStage: 'Basic Details' 
            });
            
            this.dispatchEvent(new ShowToastEvent({
                title: 'Success',
                message: "Saved successfully",
                variant: 'success'
            }));

            await this.fetchForm(this.application.Id);
            return true

        } catch (e) {
            console.error("save error", e);
            this.dispatchEvent(new ShowToastEvent({
                title: "Save failed",
                message: "Please try again",
                variant: "error"
            }));
            return false;
        } finally {
            this.isLoading = false;
        }       

    }
}