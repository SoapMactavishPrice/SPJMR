import { LightningElement } from 'lwc';
import resetPassword from '@salesforce/apex/PasswordResetController.resetPassword'

export default class PasswordResetConfirmation extends LightningElement {
    siteUrl;
    email;
    isSuccess = false;
    isError = false;

    connectedCallback() {
        this.siteUrl = window.location.origin;

        this.siteUrl = this.siteUrl + '/applicationportal/s'

        const params = new URLSearchParams(window.location.search);
        this.email = params.get('email');

        console.log('Site URL:', this.siteUrl);
        console.log('Email:', this.email);

        resetPassword({ email: this.email })
            .then(result => {
                console.log('Password reset successful:', result);
                this.isSuccess = true;
            })
            .catch(error => {
                console.error('Error resetting password:', error);
                this.isError = true;
            });
    }
}