import { LightningElement,track,api } from 'lwc';
import FIRST_PROGRAM from '@salesforce/schema/Program_Detail__c.X1st_Programme_Applying_For__c';
import SECOND_PROGRAM from '@salesforce/schema/Program_Detail__c.X2nd_Programme_Applying_For__c';
import SPECIALISATION_1 from '@salesforce/schema/Program_Detail__c.Specialization_1_for__c';
import SPECIALISATION_2 from '@salesforce/schema/Program_Detail__c.Specialization_2_for__c';
import Specialisation1Reason from '@salesforce/schema/Program_Detail__c.Reasons_I_have_Specialization_1__c';
import Specialisation2Reason from '@salesforce/schema/Program_Detail__c.Reasons_I_have_Specialization_2__c';
import PGEMPBatch from '@salesforce/schema/Program_Detail__c.Join_PGEMP_Batch__c';
import PartnerSchool from '@salesforce/schema/Program_Detail__c.Partner_School__c';
import PartnerSchoolProgram from '@salesforce/schema/Program_Detail__c.Partner_School_Program__c';
import PartnerSchoolSpecialisation from '@salesforce/schema/Program_Detail__c.Partner_School_Specilisation__c';

export default class ProgramDetails extends LightningElement {
   @track fields = [FIRST_PROGRAM,SECOND_PROGRAM,SPECIALISATION_1,SPECIALISATION_2,
    Specialisation1Reason,Specialisation2Reason,PGEMPBatch,PartnerSchool,
    PartnerSchoolProgram,PartnerSchoolSpecialisation]

    @api applicationId;
    recId;


    handleSubmit(event){
        event.preventDefault()
        const fields = event.detail.fields
        fields.Application__c = this.applicationId
        console.log(JSON.stringify(fields))
        const submitform = new CustomEvent('submitform', {
            detail:'1'
        })
        this.dispatchEvent(submitform)
        
        
    }
}