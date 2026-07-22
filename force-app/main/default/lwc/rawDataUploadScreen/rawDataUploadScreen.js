import { LightningElement, api,wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getImportSummary from '@salesforce/apex/RawDataController.getImportSummary';
import insertImportRows from '@salesforce/apex/RawDataController.insertImportRows';
import startImport from '@salesforce/apex/RawDataController.startImport';
import getImports from '@salesforce/apex/RawDataController.getImports';
import startProcessing from '@salesforce/apex/RawDataController.startProcessing';
import startBatch from '@salesforce/apex/LeadImportProcessBatchStarter.startBatch'
const CHUNK_SIZE = 1 * 1024 * 1024; // 1 MB
const ROW_BATCH_SIZE = 500;

export default class RawDataUploadScreen extends LightningElement {
    importColumns = [
    {
        type: 'button',
        typeAttributes: {
            label: 'View',
            name: 'view',
            variant: 'base'
        }
    },
    { label: 'File Name', fieldName: 'Title__c' },
    { label: 'Status', fieldName: 'Status__c' },
    { label: 'Imported On', fieldName: 'CreatedDate', type: 'date' }
];
    failedColumns = [
    {
        label: 'Row',
        fieldName: 'Row_Number__c'
    },
    {
        label: 'Name',
        fieldName: 'Name__c'
    },
    {
        label: 'Email',
        fieldName: 'Email__c'
    },
    {
        label: 'Error',
        fieldName: 'Error_Message__c'
    }
];
    totalRows = 0;
    @api recordId;
    processedRows = 0
    showError = false;
    errorMessage = '';
    imports = []
    fileName = '';
    description = '';
    summary = null
    selectedFile;
    importId;
    rowOffset=0
    remainder = '';
    isFirstChunk = true;
    currentRowNumber = 1;

    isLoading = false;

    @wire(getImports)
    wiredImports({error,data}){
        if(error){
            console.log('Error Fetching Imports ',JSON.stringify(error))

        }
        else if(data){
            this.imports = data
        }
    }

    get isDisabledUpload(){
        if(this.fileName){
            return false
        }
        return true
    }

    get isDisabledBatch() {
    return !(this.selectedFile && this.fileName);
}

get selectedFileName() {
    return this.selectedFile ? this.selectedFile.name : '';
}
    get progressValue() {
    if (!this.totalRows) {
        return 0;
    }

    return Math.round(
        (this.processedRows / this.totalRows) * 100
    );
}

get progressLabel() {
    return `${this.processedRows} / ${this.totalRows} rows uploaded`;
}

    handleFileNameChange(event) {
        this.fileName = event.target.value;
    }

    handleDescriptionChange(event) {
        this.description = event.target.value;
    }

    handleFileSelection(event) {

        const file = event.target.files[0];

        if (!file) {
            return;
        }

        this.selectedFile = file;

        console.log(
            'Selected File:',
            file.name,
            file.size
        );
        
    }
async calculateTotalRows() {

    let start = 0;
    let total = 0;
    let remainder = '';

    while (start < this.selectedFile.size) {

        const chunk =
            this.selectedFile.slice(
                start,
                start + CHUNK_SIZE
            );

        let text =
            await this.readChunk(chunk);

        text = remainder + text;

        const lines =
            text.split(/\r?\n/);

        remainder = lines.pop();

        total += lines.length;

        start += CHUNK_SIZE;
    }

    if (remainder) {
        total++;
    }

    this.totalRows = Math.max(total - 1, 0); // remove header
}

    async sendRowsInBatches(rows) {

    if (!rows || rows.length === 0) {
        return;
    }

    for (
        let i = 0;
        i < rows.length;
        i += ROW_BATCH_SIZE
    ) {

        const batch =
            rows.slice(
                i,
                i + ROW_BATCH_SIZE
            );

        console.log(
            'Sending batch size:',
            batch.length
        );

        console.log(
            'Payload size:',
            JSON.stringify(batch).length
        );

        await insertImportRows({
            importId: this.importId,
            rows: batch
        });
        this.processedRows += batch.length;
    }
}

    async handleBatchStart() {
       this.remainder = '';
    this.isFirstChunk = true;
    this.currentRowNumber = 1;

    this.processedRows = 0;
    this.totalRows = 0;

        try {

            this.showError = false;
            this.errorMessage = '';

            if (!this.fileName || !this.selectedFile) {

                this.showError = true;
                this.errorMessage =
                    'Please provide a Title and select a CSV file.';

                return;
            }

            this.isLoading = true;

            this.importId = await startImport({
                fileName: this.fileName,
                description: this.description
            });

            console.log('Import Id => ', this.importId);
            await this.calculateTotalRows();
            await this.processFile();

            await startProcessing({
                importId: this.importId
            });
            console.log(
    'Import Completed. Total Rows:',
    this.processedRows
);
         
        } catch (error) {

            console.error(
                'Import Error:',
                JSON.stringify(error)
            );

            this.showError = true;

            this.errorMessage =
                error?.body?.message ||
                error?.message ||
                'Unexpected error occurred';

        } finally {

            this.isLoading = false;
            startBatch({parentImportId:this.importId})
            .then(()=>{
                console.log('Batch started succesfully');
            })
        }
    }

    async processFile() {
        

        let start = 0;

        while (start < this.selectedFile.size) {

            const chunk = this.selectedFile.slice(
                start,
                start + CHUNK_SIZE
            );

            let text = await this.readChunk(chunk);

            text = this.remainder + text;

            const lines = text.split(/\r?\n/);

            this.remainder = lines.pop();

           const rows = this.parseChunk(lines);

           console.log(
    'Rows Parsed:',
    rows.length
);

if (rows.length > 0) {

    await this.sendRowsInBatches(rows);

    console.log(
        'Uploaded Rows:',
        rows.length
    );
}

            start += CHUNK_SIZE;
        }

        if (this.remainder) {

    const rows =
        this.parseChunk(
            [this.remainder]
        );

    await this.sendRowsInBatches(rows);
}
    }


    handleRowSelection(event){
     const id = event.detail.row.Id;

    getImportSummary({ parentId: id })
        .then(result=>{
            this.summary = result;
        });
}
    async sendChunkToApex(rows) {

        if (!rows || rows.length === 0) {
            return;
        }

        await insertImportRows({
            importId: this.importId,
            rows: rows
        });
    }

    parseChunk(lines) {

        const rows = [];

        let startIndex = 0;

        if (this.isFirstChunk) {

            const headerRow = lines[0];

            this.validateHeaders(headerRow);

            startIndex = 1;
            this.isFirstChunk = false;
        }

        for (
            let i = startIndex;
            i < lines.length;
            i++
        ) {

            if (!lines[i]?.trim()) {
                continue;
            }
            
            const cols = lines[i].split(',');
            if (cols.length < 18) {

    console.warn(
        'Skipping invalid row:',
        lines[i]
    );

    continue;
}


            rows.push({

                rowNumber: this.currentRowNumber++,

                name: cols[0]?.trim() || '',
                email: cols[1]?.trim() || '',
                phone: cols[2]?.trim() || '',
                programme: cols[3]?.trim() || '',
                leadSource: cols[4]?.trim() || '',
                country: cols[5]?.trim() || '',
                state: cols[6]?.trim() || '',
                city: cols[7]?.trim() || '',
                yearsOfWorkExperience:
                    cols[8]?.trim() || '',
                entranceExamScore:
                    cols[9]?.trim() || '',
                entranceExamName:
                    cols[10]?.trim() || '',
                partnerCompany:
                    cols[11]?.trim() || '',
                organization:
                    cols[12]?.trim() || '',
                referralSource:
                    cols[13]?.trim() || '',
                designation:
                    cols[14]?.trim() || '',
                age:
                    cols[15]?.trim() || '',
                college:
                    cols[16]?.trim() || '',
                graduationYear:
                    cols[17]?.trim() || ''

            });
        }

        return rows;
    }

    validateHeaders(headerLine) {

        const expectedHeaders = [
            'Name',
            'Email',
            'Phone',
            'Programme',
            'Lead Source',
            'Country',
            'State',
            'City',
            'Years of Work Experience',
            'Do you have Entrance Exam Scores?',
            'Entrance Exam Name',
            'SPJIMR Partner Company',
            'Organization',
            'How did you find out about us?',
            'Current Designation',
            'Age',
            'College',
            'Graduation Year',
            'Send Welcome and Verification Email?'
        ];

        const uploadedHeaders =
            headerLine
                .split(',')
                .map(header => header.trim());

        if (
            uploadedHeaders.length !==
            expectedHeaders.length
        ) {
            throw new Error(
                `Invalid header count. Expected ${expectedHeaders.length} columns but found ${uploadedHeaders.length}.`
            );
        }

        for (
            let i = 0;
            i < expectedHeaders.length;
            i++
        ) {

            if (
                uploadedHeaders[i] !==
                expectedHeaders[i]
            ) {

                throw new Error(
                    `Invalid header at column ${i + 1}. Expected "${expectedHeaders[i]}" but found "${uploadedHeaders[i]}".`
                );
            }
        }
    }

    readChunk(blob) {

        return new Promise(
            (resolve, reject) => {

                const reader =
                    new FileReader();

                reader.onload = () => {
                    resolve(reader.result);
                };

                reader.onerror = reject;

                reader.readAsText(blob);
            }
        );
    }

    showToast(
        title,
        message,
        variant
    ) {

        this.dispatchEvent(
            new ShowToastEvent({
                title,
                message,
                variant
            })
        );
    }
}