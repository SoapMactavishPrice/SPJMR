import { LightningElement, track, wire } from 'lwc';
import validateFile from '@salesforce/apex/B2CImportController.validateFile';
import sheetJs from '@salesforce/resourceUrl/sheetJs';
import { loadScript } from 'lightning/platformResourceLoader';
import { CloseActionScreenEvent } from 'lightning/actions';
import { getRecord, getFieldValue } from "lightning/uiRecordApi"
import START_DATE from "@salesforce/schema/Campaign.StartDate";
import END_DATE from "@salesforce/schema/Campaign.EndDate";
import Name from "@salesforce/schema/Campaign.Name";
import isActive from "@salesforce/schema/Campaign.IsActive"
import TYPE_FIELD from "@salesforce/schema/Campaign.Type";
import LightningConfirm from 'lightning/confirm';

const FIELDS = ["Campaign.IsActive", "Campaign.Name",
    "Campaign.EndDate", "Campaign.StartDate", "Campaign.Type",
    "Campaign.Source__r.Name"];

export default class B2cLeadImportExcel extends LightningElement {

    file;
    fileName;
    csvData;
    campaignId = '';
    @track errors = [];
    @track success = false;
    @track isLoading = false;
    campaignFound = false;
    campaignSource = '';
    sheetJsInitialized = false;
    campaignData = '';



    get campaignType() {
        return getFieldValue(this.campaignData, TYPE_FIELD);
    }

    get campaignSource() {
        return getFieldValue(this.campaignData, SOURCE)
    }

    get campaignStartDate() {
        return getFieldValue(this.campaignData, START_DATE)
    }

    get campaignEndDate() {
        return getFieldValue(this.campaignData, END_DATE)
    }

    get campaignName() {
        return getFieldValue(this.campaignData, Name)
    }

    get isActive() {
        return getFieldValue(this.campaignData, isActive)
    }


    @wire(getRecord, { recordId: "$campaignId", fields: FIELDS })
    getCampaignRecord({ error, data }) {
        if (data) {
            this.campaignFound = true
            this.campaignData = data
        } else if (error) {
            this.errors = 'Error fetching Campaigns: ' + JSON.stringify(error)
        }
    }

    handleCampaignChange(event) {
        this.campaignId = event.detail.recordId
        console.log('Campaing Id:' + this.campaignId)
    }

    connectedCallback() {
        loadScript(this, sheetJs)
            .then(() => {
                this.sheetJsInitialized = true;
            })
            .catch(error => {
                console.error('SheetJS load error', error);
            });
    }

    get isValidateDisabled() {
        return !this.contentDocuId || !this.campaignId || this.isLoading;
    }

    get hasErrors() {
        return this.errors && this.errors.length > 0;
    }

    handleFileUpload(event) {
        const uploadedFiles = event.detail.files;

        if (!uploadedFiles || uploadedFiles.length === 0) {
            console.error('No file returned from upload');
            return;
        }

        const file = uploadedFiles[0];

        this.fileName = file.name;
        this.contentDocuId = file.documentId;

        console.log('File Name:', this.fileName);
        console.log('ContentDocumentId:', this.contentDocuId);

        this.errors = [];
        this.success = false;
    }

    processCSV() {
        return new Promise((resolve, reject) => {
            const reader = new FileReader();

            reader.onload = () => {
                this.csvData = reader.result;
                resolve();
            };

            reader.onerror = reject;
            reader.readAsText(this.file);
        });
    }

    processXLSX() {
        return new Promise((resolve, reject) => {

            const reader = new FileReader();

            reader.onload = (e) => {
                const data = new Uint8Array(e.target.result);

                const workbook = XLSX.read(data, { type: 'array' });

                const firstSheet = workbook.Sheets[workbook.SheetNames[0]];

                this.csvData = XLSX.utils.sheet_to_csv(firstSheet);

                resolve();
            };

            reader.onerror = reject;
            reader.readAsArrayBuffer(this.file);
        });
    }

    handleClose() {
        this.dispatchEvent(new CloseActionScreenEvent());
    }

    downloadTemplate() {

        let doc = '';


        const headers = [
            "Name",
            "Email",
            "Phone",
            "Programme",
            "Country",
            "State",
            "City",
            "Years of Work Experience",
            "Do you have Entrance Exam Scores?",
            "Entrance Exam Name",
            "SPJIMR Partner Company",
            "Organization",
            "How did you find out about us?",
            "Current Designation",
            "Age",
            "College",
            "Graduation Year"
        ];

        doc += headers.join(',') + '\n';

        const row = [
            `"John Doe"`,
            `"john@test.com"`,
            `"9876543210"`,
            `"GMP"`,
            `"India"`,
            `"Maharashtra"`,
            `"Mumbai"`,
            `"5"`,
            `"Yes"`,
            `"CAT"`,
            `"ABC Corp"`,
            `"XYZ Ltd"`,
            `"Google"`,
            `"Manager"`,
            `"30"`,
            `"IIT"`,
            `"2015"`
        ];

        doc += row.join(',') + '\n';

        var element = 'data:application/vnd.ms-excel,' + encodeURIComponent(doc);

        let downloadElement = document.createElement('a');
        downloadElement.href = element;
        downloadElement.target = '_self';
        downloadElement.download = 'Lead_Import_Template.csv';

        document.body.appendChild(downloadElement);
        downloadElement.click();
    }

    async handleValidate() {
        if (this.campaignId && this.contentDocuId) {
            await validateFile({ campaignId: this.campaignId, contentDocumentId: this.contentDocuId })
    .then((result) => {
        console.log('Result ' + JSON.stringify(result));

        if (result.ERROR) {
            this.errors = [{ message: result.ERROR }];

            this.hasErrors = true;
            this.success = false;
        } else if (result.SUCCESS) {
            this.success = true;
            this.hasErrors = false;
        }
    })
    .catch((error) => {
        console.log('Actual exception ' + JSON.stringify(error));
    });

                console.log('ERRORs object'+JSON.stringify(this.errors))
        }
    }

}