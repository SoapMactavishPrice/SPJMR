import { LightningElement, track } from 'lwc';
import verifyToken from '@salesforce/apex/LeadWebFormHelper.verifyToken';


export default class LeadFormTest extends LightningElement {

    @track userInputs = {};
    priorityOptions = [
        { label: "High", value: "High"},
        { label: "Medium", value: "Medium"},
        { label: "Low", value: "Low"}
    ];
    @track isTokenUnsuccessful = false;
    @track isErrorVerifyToken = false;
    @track isErrorGeneratingToken = false;
    @track tokenError = '';
    @track isSussessfulCreate = false;
    @track successMessage = '';
    siteKey = '6LdIKZcsAAAAAG5gjqUp-WmC7FHhpI6S-OC65bIO';


    handleClick(){
        console.log('Clicked Button')
        this.isTokenUnsuccessful = false;
        this.isErrorVerifyToken = false;
        this.isErrorGeneratingToken = false;
        this.tokenError = '';
        //Reset seccuss flag
        this.isSussessfulCreate = false;
        this.successMessage = '';
        
        /* google recaptcha logic start */
        grecaptcha.execute('6LeF5JcsAAAAAPnCmAG2tIOourv2V3etCcFiq_rP', { action: 'submit' })//Replace your SITE_KEY
        .then(token => {
//If you want to see the token, uncomment below line 
            console.log('Token->>>>', token); 
            // Send the token to your Apex controller for verification
            verifyToken({ 
                token: token
            })
            .then(result => {
                // Handle the result from Apex
                if (result.success) {
                    // Verification successful, implement your business logic here
                    console.log('Captcha Success')
                } else {
                    // Token verification unsucessful, display an error message
                    this.isTokenUnsuccessful = true;
                    this.isErrorVerifyToken = false;
                    this.isErrorGeneratingToken = false;
                    this.tokenError = 'Token verification unsuccessful->>>>' + result.message;
                }
            })
            .catch(error => {
                // Handle any error verify token from Apex
                this.isTokenUnsuccessful = false;
                this.isErrorVerifyToken = true;
                this.isErrorGeneratingToken = false;
                this.tokenError = 'Error verify token->>>>' + error.body.message;
            });
        })
        .catch(error => {
            //Handle error generating token
            this.isTokenUnsuccessful = false;
            this.isErrorVerifyToken = false;
            this.isErrorGeneratingToken = true;
            this.tokenError = 'reCAPTCHA token generation error->>>>' + error;
        });
        /* google recaptcha logic end */
        
    
    }
    

    
}