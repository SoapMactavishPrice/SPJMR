import { LightningElement, track } from 'lwc';
import exportApplicationsBatch from '@salesforce/apex/ExportApplicationsController.exportApplicationsBatch'
import getExportStatus from '@salesforce/apex/ExportApplicationsController.getExportStatus'

import { ShowToastEvent } from 'lightning/platformShowToastEvent';
export default class BulkCsvExporter extends LightningElement {

    downloadUrl='';

    showToast(title,message,mode) {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: title,
                    message: message,
                    variant: mode
                })
            );
        }
    

        showToastWithLink(title,message,mode,link) {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: title,
                    message: '{1}',
                    messageData:['Salesforce',
                        {url:link,
                        label:message}
                    ],
                    variant: mode,
                    mode:'sticky'
                })
            );
        }
       

    startPolling(jobId) {
    this.pollInterval = setInterval(() => {
        getExportStatus({ jobId: jobId })
        .then(result => {

            if (result.status === 'Completed') {

                clearInterval(this.pollInterval);

                this.downloadUrl = result.downloadUrl;
                console.log('URL is ',this.downloadUrl)
                this.showToastWithLink('Export Ready', 'Click to download file', 'success',this.downloadUrl);

            } else if (result.status === 'Failed') {

                clearInterval(this.pollInterval);
                this.showToast('Export Failed', 'Please check logs', 'error');
            }

        });
    }, 3000);
}


    async startExport(){
       await exportApplicationsBatch({programCode:'GMP'})
        .then((result)=>{
            this.showToast('Export Started','Please wait for the job to complete','info');
            this.startPolling(result)
        })
        .catch((error)=>{
            console.log('Error '+JSON.stringify(error))
           // this.showToast('Error'error.body ? JSON.stringify(error.body.message) : JSON.stringify(error.message))
        })
    }

}