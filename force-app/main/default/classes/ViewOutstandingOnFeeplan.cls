public with sharing class ViewOutstandingOnFeeplan {
    
    public string currentRecID{get;set;}
    public Account acc {get;set;}    
    public List<Account_Program_Batch_Selection__c> programlist{get;set;} // Program/Batch
    public List<Program_Batch_Wise_Payment__c> FeePlanList{get;set;}  // Fee Plan
    public String FeePlanListString{get;set;}  // Fee Plan
    public List<Program_Batch_Wise_Instalment__c> Paymentlist{get;set;} // 
    public String PaymentlistString{get;set;}  // Payment Milestone
    
    public ViewOutstandingOnFeeplan(){
        
        currentRecID=ApexPages.CurrentPage().getparameters().get('id');
        
        acc=[ SELECT  Id, Name FROM Account  where id=:currentRecID];
        
        programlist=[SELECT  Id,  Name,  Program_Name__c,  Batch_Name__c,  Benefit__c,  Student_Name__c,  Corporate__c,  Program_Status__c, 
              Total_Fee_Amount__c,  School_Name__c,  Total_Amount_Received__c,  Remaining_Amount__c,  Email__c 
              FROM Account_Program_Batch_Selection__c where Student_Name__c=:acc.Id];   
        
        System.debug('programlist>>>>>>>>>>'+programlist);
        
        Set<id> plset= new Set<id>();        
        for(Account_Program_Batch_Selection__c p:programlist){
            plset.add(p.id);
        }
        
        // Fee Plan
        FeePlanList=[ SELECT  Id,  Name,  Program_Name__c,  Batch_Name__c,  Payment_Type__c,  Fees__c,  Payment_Source__c, 
                     Payment_Status__c,Program_Batch_Selection__c,Fee_Plan_Name__c,Benefit_Applicable__c,Fee_Plan_Name__r.Name,
                     Total_Amount_Received__c,  Remaining_Amount__c,  Total_Fee_Amount__c,  
                     Student_Name__c,  School_Name__c,  Total_Amount__c,
                     Program_Name__r.Name,Batch_Name__r.Name
                     FROM Program_Batch_Wise_Payment__c where Program_Batch_Selection__c IN: plset  Order By Name ]; 
        
        System.debug('FeePlanList>>>>>>>>>>'+FeePlanList);
        
        FeePlanListString = JSON.serialize(FeePlanList);
        
        System.debug('FeePlanListString   ------------->>'+FeePlanListString);
        
        Set<id> plset1= new Set<id>();       
        for(Program_Batch_Wise_Payment__c p:FeePlanList){
            plset1.add(p.id);
        }
        
        // Payment Milestone
        Paymentlist=[  SELECT  Id,  Name,  Instalment_Reminder_Date__c,  Instalment_Due_Date__c,  Instalment_Fees__c,  Instalment_Remarks__c, 
                     Instalment_Payment_Status__c,Payment_Source__c,Instalment_Name__c, Instalment_Name__r.Name, 
                     Amount_Received__c,  Remaining_Amount__c,  Payment_Collection_Type__c,  Amount_Received_Date__c,  
                     Total_Amount__c,Student_Name__c,Program_Name__c,Batch_Name__c,Batch_Name__r.Name, Cheque_Number__c,Cheque_Issue_Date__c,  
                     Cheque_Deposit_Date__c,  Transaction_Reference_Number__c,  Date_of_Transaction__c,  Payment_Realization_Date__c, 
                     School_Name__r.Name,Student_Name__r.Name,Program_Name__r.Name,School_Name__c,Program_Batch_Wise_Payment__c
                     FROM Program_Batch_Wise_Instalment__c 
                     where Program_Batch_Wise_Payment__c IN: plset1 order by Instalment_Due_Date__c ];
        
        System.debug('Paymentlist>>>>>>>>>>'+Paymentlist);
        
        PaymentlistString = JSON.serialize(Paymentlist);
        System.debug('Paymentlist>>>>>>>>>>'+PaymentlistString);
        
    }
    
    public pageReference Cancel() {
        
        PageReference pageRef = new PageReference('/'+currentRecID);
        pageRef.setRedirect(true);
        return pageRef ;
    }
}