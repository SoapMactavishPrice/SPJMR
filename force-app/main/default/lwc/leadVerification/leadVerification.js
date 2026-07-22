import { LightningElement,track,wire } from 'lwc';
import { CurrentPageReference } from 'lightning/navigation';
import verifyLead from '@salesforce/apex/LeadVerification.verifyLead' 
import convertB2CLead from '@salesforce/apex/ConvertB2CLeadController.convertB2CLead'
import spjimrLogo from '@salesforce/resourceUrl/SPJIMR_RGB';
export default class LeadVerification extends LightningElement {

    @track boolean_Success = false;
    @track bool_isLoading = true;
    @track boolean_Error = false;
    @track boolean_LoggedIn = false;
    @track leadId =''
    @track bool_CalloutFlag = true
    logoUrl = spjimrLogo;
    @wire(CurrentPageReference)
    getPageReference(pageRef) {
        if (pageRef && this.bool_CalloutFlag) {
           
            
            const urlParams = pageRef.state;
            this.leadId = urlParams.leadId;
            this.email = urlParams.email;
            if(this.leadId && this.bool_CalloutFlag){
                this.bool_CalloutFlag = false
                console.log('Verifying Lead '+this.leadId);
                convertB2CLead({leadId:this.leadId, email:this.email})
                .then((result)=>{

                    console.log('Results are '+JSON.stringify(result));
                    let isSuccess = result.isSuccess
                    if(isSuccess){
                        this.boolean_Success = true;
                        this.boolean_Error = false;
                        this.boolean_LoggedIn = false;
                        this.bool_isLoading = false;
                    }
                    else if(!isSuccess && result.message ==='Lead is already converted.'){
                            this.boolean_Success = false;
                            this.boolean_Error = false;
                            this.loggedInPrompt = result[key]
                            this.boolean_LoggedIn = true
                            this.bool_isLoading = false;
                    }
                    else{
                         this.boolean_Error = true;
                         this.boolean_Success = false;
                         this.boolean_LoggedIn = false
                         this.bool_isLoading = false;
                    }
                    // Object.keys(result).find((key)=>{
                    //     console.log('Results are '+result[key])
                    //     switch(key){
                    //         case 'ERROR':
                    //             console.log('Error occured ',result[key]  );
                    //             this.boolean_Error = true;
                    //             this.boolean_Success = false;
                    //             this.boolean_LoggedIn = false
                    //             this.bool_isLoading = false;
                    //             break
                    //         case 'REGISTERED_OR_LOGGEDIN':
                    //             console.log('Lead already present/logged In ',result[key]  );
                    //             this.boolean_Success = false;
                    //             this.boolean_Error = false;
                    //             this.loggedInPrompt = result[key]
                    //             this.boolean_LoggedIn = true
                    //             this.bool_isLoading = false;
                    //             break
                    //         case 'SUCCESS':
                    //             console.log('Lead verified ',result[key]  );
                    //             this.boolean_Success = true;
                    //              this.boolean_Error = false;
                    //              this.boolean_LoggedIn = false
                    //             this.bool_isLoading = false;
                    //             break
                    //     }
                       
                    // })
                })
                .catch((error)=>{
                    console.log('Error occured ',JSON.stringify(error));
                    this.boolean_Success = false;
                    this.bool_isLoading = false;
                }
                )
            }
        }
    
    }
    
    


}