import { LightningElement,wire } from 'lwc';
import { CurrentPageReference } from 'lightning/navigation';
import getApplicationUrl from '@salesforce/apex/InterviewController.getApplicationUrl'
import { NavigationMixin } from 'lightning/navigation';
export default class ViewApplicationPDF extends LightningElement {

    recordId='';
    applicationId='';
    @wire(CurrentPageReference)
        getPageReference(pageRef) {
            if (pageRef) {
                
                console.log('PageRef is ',pageRef)
                this.recordId = pageRef.attributes.recordId;
                console.log('Record Id is ',this.recordId);
            }
        }


     
    async handleViewApplication(){
       
        if(this.recordId){
            await getApplicationUrl({slotId:this.recordId})
            .then((result)=>{console.log('Res is ',JSON.stringify(result))
                this[NavigationMixin.GenerateUrl]({
                    type: 'standard__webPage',
                    attributes: {
                url: result 
            }
        }).then(generatedUrl => {
            window.open(generatedUrl);
        });
               })
            .catch((error)=>{
                console.log('Error here ',JSON.stringify(error));})
        }
    }
}