import { LightningElement ,api,wire} from 'lwc';
import { notifyRecordUpdateAvailable,getRecord,
    getFieldValue } from 'lightning/uiRecordApi';
import FIRSTNAME_FIELD from '@salesforce/schema/Lead.FirstName';
import LASTNAME_FIELD from '@salesforce/schema/Lead.LastName';
import STATUS_FIELD from '@salesforce/schema/Lead.Status';

    const fields = [FIRSTNAME_FIELD, LASTNAME_FIELD,STATUS_FIELD];

export default class TestComp extends LightningElement {
    @api recordId
    previousData='';
    @wire(getRecord, { recordId: '$recordId', fields })
    leadData({error,data}){
        if(data){
            //console.log('Data Values are '+data.fields.Status +' '+ this.previousData.fields.Status)
            if(this.previousData && this.previousData.fields){
                console.log('Data Values are '+data.fields.Status +' '+ this.previousData.fields.Status)
                if(data.fields.Status.value !== this.previousData.fields.Status.value){
                    console.log('Refresh now since data changed.')
                }
            }
            else{
                console.log('Data Values are '+data.fields.Status +' ')
                console.log('First time loading data.')
            }
                
            
            this.previousData = this.data
            console.log('Data: '+JSON.stringify(data))
        }
        else if(error){
            console.log('Error in Wire: '+JSON.stringify(error))
        }
    }

    // connectedCallback() {
    //     console.log('Record Id '+this.recordId)
    //     // Small delay helps ensure DML + Flow completes
    //     setTimeout(() => {
    //         notifyRecordUpdateAvailable([{ recordId: this.recordId }])
    //         .then((result)=>{
    //             console.log('Result '+JSON.stringify(result))
    //         }).catch((error)=>{
    //             console.log('Error  '+error)
    //         })
    //         ;
    //     }, 2000);
    // }
}