public with sharing class EditAllBatchWisePaymentClass {
    
    public string currentRecID{get;set;}
    public Account acc {get;set;}    
    public List<Program_Batch_Wise_Payment__c> feelist{get;set;}
    public List<Account_Program_Batch_Selection__c> programlist{get;set;}
    public String body{get;set;}
    public Map<string, List<Program_Batch_Wise_Payment__c>> sMap {get;set;}
    public Decimal ProgCount {get; set;}
    
    public EditAllBatchWisePaymentClass(){
        
        currentRecID=ApexPages.CurrentPage().getparameters().get('id');
        
        sMap = new Map<string, List<Program_Batch_Wise_Payment__c>>();
        
        acc=[ SELECT  Id,  Name FROM Account  where id=:currentRecID];
        
        programlist=[  SELECT  Id,  Name,  Student_Name__c,School_Name__c,  Program_Name__c,  Batch_Name__c,
                     Benefit__r.Name,Corporate__r.Name,Batch_Name__r.Name,Program_Name__r.Name,School_Name__r.Name
                     FROM Account_Program_Batch_Selection__c where Student_Name__c=:acc.Id  order by name ]; 
        //and Program_Status__c ='Active'
        
        ProgCount=programlist.size();
        if(ProgCount == 0){
            ApexPages.Message msg = new ApexPages.Message(ApexPages.Severity.ERROR,'No Active Programs..!!!!!!');
            ApexPages.addMessage(msg);
        }
        
        system.debug('programlist====='+programlist); 
        
        Set<id> plset= new Set<id>();             
        for(Account_Program_Batch_Selection__c p:programlist){
            plset.add(p.id);
        }             
        
        feelist=[SELECT  Id,  Name,  Program_Name__c,  Batch_Name__c,Payment_Type__c,Fees__c,Payment_Source__c, 
                 Payment_Status__c,Program_Batch_Selection__c,Fee_Plan_Name__c,Benefit_Applicable__c,Batch_Name__r.Name,
                 Total_Amount_Received__c,  Remaining_Amount__c,  Total_Fee_Amount__c, Tax_Amount__c , 
                 Student_Name__c,  School_Name__c,  Total_Amount__c ,Actual_Fees__c,Remaining_Amt__c,
                 Program_Name__r.Name,Fee_Plan_Name__r.Name, Refund_Applicable__c ,Pro_Rata_Fees_Applicable__c,Grand_Total__c,
                 Total_Benefit_Amount__c,Tax_Applicable__c
                 FROM Program_Batch_Wise_Payment__c where Program_Batch_Selection__c IN: plset order by name];
        
        system.debug('feelist====='+feelist); 
        
        
        for(Program_Batch_Wise_Payment__c p: feelist){
            
            String unq = p.Program_Name__r.Name + ' / '+ p.Batch_Name__r.Name;
            
            if(sMap.get(unq)==Null){
                
                List<Program_Batch_Wise_Payment__c> plist = new List<Program_Batch_Wise_Payment__c>();
                plist.add(p);
                sMap.put(unq, plist);
            }
            else{
                List<Program_Batch_Wise_Payment__c> plist = sMap.get(unq);
                plist.add(p);
                sMap.put(unq, plist);
            }
        }
        system.debug('sMap====='+JSON.serialize(sMap));  
    }
    
    Public Pagereference Cancel(){
        
        pagereference pg=new pagereference('/'+currentRecID);
        pg.setRedirect(true);
        return pg;        
    }   
}