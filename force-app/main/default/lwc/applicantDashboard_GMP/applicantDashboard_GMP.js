import { LightningElement,api } from 'lwc';

export default class ApplicantDashboard_GMP extends LightningElement {
    @api prgmData;

    connectedCallback(){
        console.log('This is data ',JSON.stringify(this.prgmData))
    }
}