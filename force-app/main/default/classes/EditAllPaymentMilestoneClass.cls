public with sharing class EditAllPaymentMilestoneClass {
    
    public string currentRecID{get;set;}
    public List<Batch_Wise_Instalment__c> oppList {get;set;}
    
    public EditAllPaymentMilestoneClass(){
        
        currentRecID=ApexPages.CurrentPage().getparameters().get('id');
        
        oppList=[ SELECT  Id,  Name,  Instalment_Remarks__c,  Instalment_Reminder_Date__c,  Instalment_Due_Date__c,  Instalment_Fees__c,  
                 Instalment_Sequence__c,  Batch_Wise_Fee_Plan__c,Exclude_Benefit__c,No_Impact__c,
                 Credit_Period__c,Invoice_Due_Date__c, Fee_Plan_Category__c 
                 FROM Batch_Wise_Instalment__c where Batch_Wise_Fee_Plan__c=:currentRecID]; 
        
        system.debug('oppList>>>>>>>'+oppList);  
        
    }
    
    Public Pagereference Save(){
        
      /*  for(Batch_Wise_Instalment__c bw : oppList){ 
            if(( bw.Fee_Plan_Category__c =='Admission Fee' || bw.Fee_Plan_Category__c =='Misc Fee' ||
                bw.Fee_Plan_Category__c =='Registration Fee' || bw.Fee_Plan_Category__c =='Annual Fee' ||
                bw.Fee_Plan_Category__c =='Student Kit') && bw.Instalment_Due_Date__c !=null){
                    ApexPages.addmessage(new ApexPages.message(ApexPages.severity.Error,'You cannot enter Invoice Process Date.!!!!!!'));
                    return null;
                }
            
        }  */
        
        if(oppList.size()>0){
            system.debug('Just To Insert');
            system.debug('oppList======'+oppList);   
            update oppList; 
        }        
        pagereference pg= new pagereference('/'+currentRecID);
        pg.setRedirect(true);
        return pg;  
    }
    
    Public Pagereference Cancel(){
        
        pagereference pg=new pagereference('/'+currentRecID);
        pg.setRedirect(true);
        return pg;        
    }   
}