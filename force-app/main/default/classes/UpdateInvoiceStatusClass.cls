public with sharing class UpdateInvoiceStatusClass {
 /*   
    public string currentRecID{get;set;}
    public Account acc {get;set;}    
    public List<Invoice__c> invlist{get;set;}
    public List<Program_Batch_Wise_Instalment__c> paymentlist {get;set;}
    public List<Invoice_Line_Item__c> inLineList {get;set;}
    public List<Invoice_Line_Item__c> InvoiceLineList {get;set;}
    public List<Stationary_Item_Account__c> statItemList {get;set;}
    public Decimal ProgCount {get; set;}
    
    public UpdateInvoiceStatusClass(){
        
        currentRecID=ApexPages.CurrentPage().getparameters().get('id');
        
        acc=[ SELECT  Id, Name FROM Account  where id=:currentRecID];
        
        invlist=[ SELECT Id,Name,Invoice_Status__c,Student_Name__c,Remaining_Amount__c,Grand_Total__c, Amount_Received__c , Invoice_Date__c 
                 FROM Invoice__c  where Student_Name__c=:acc.Id and Remaining_Amount__c !=0 order by Name];  
        
        ProgCount=invlist.size();
        if(ProgCount == 0){
            ApexPages.Message msg = new ApexPages.Message(ApexPages.Severity.ERROR,'No Invoice to Cancel.!!!!!!');
            ApexPages.addMessage(msg);
        }
        
        paymentlist = [SELECT Id, Name, Student_Name__c, No_of_Invoice_Line_Item__c FROM Program_Batch_Wise_Instalment__c 
                       Where Student_Name__c=:acc.id];
        system.debug('paymentlist---' + paymentlist);
        
        statItemList = [SELECT Id, Name, Item_Name__c, Student__c, Price__c, Quantity__c, Total__c, Item_Name__r.Name, Remaining_Amount__c,
                        Amount_Received__c, Amount_Received_Date__c,Cheque_Deposit_Date__c, Transaction_Reference_Number__c, 
                        Date_of_Transaction__c, Cheque_Number__c, Cheque_Issue_Date__c
                        FROM Stationary_Item_Account__c where Student__c =: acc.Id ];
    }
    
    Public Pagereference Save(){
        
        set<id> invid = new set<id>();
        for(Invoice__c i: invlist){
            invid.add(i.id);
        }
        
        if(invlist.size()>0){
            system.debug('invlist======'+invlist);   
            update invlist; 
        }
        
        set<id> CancInvId = new set<id>();
        for(Invoice__c inv: invlist){
            if(inv.Invoice_Status__c =='Cancel'){
                CancInvId.add(inv.id);
            }            
        }
        
        Map<id, Invoice_Line_Item__c> lineitemMap = new Map<id, Invoice_Line_Item__c>();
        
        InvoiceLineList = [SELECT Id, Name, Invoice__c  FROM Invoice_Line_Item__c Where Invoice__c =:CancInvId]; 
        
        for (Invoice_Line_Item__c invi: InvoiceLineList) {
            
            system.debug('inside if ======'+invi);  
            
            Invoice_Line_Item__c ili = new Invoice_Line_Item__c();
            ili.Id = invi.Id;
            ili.Invoice_Status__c='Cancel';
            lineitemMap.put(ili.id, ili);
        }
        
        update lineitemMap.values();
        
        inLineList = [SELECT Id, Name,Program__r.Name,Session__r.Name, Fee_Plan_Name__c,Instalment_Name__c,Instalment_Name__r.name,
                      Cheque_Number__c, Cheque_Issue_Date__c, Fee_Plan_Name__r.Name, Instalment_Name__r.Instalment_Fees__c, School__c,
                      Program__c, Session__c,Cheque_Deposit_Date__c, Date_of_Transaction__c, Payment_Source__c,Invoice__c,
                      Amount_Received_Date__c,Remaining_Amount__c,stationary_Item__c,Transaction_Reference_Number__c,
                      Amount_Received__c, Payment_Milestone__c, Instalment_Fees__c, Instalment_Due_Date__c, Payment_Milestone__r.id,
                      Item_Name__r.name, Price__c, Remaining_Amount_Stat__c, Total_Amount__c,Quantity__c,HSN_SAC_Code__c,
                      Total_Tax_Amount__c,Grand_Total__c,
                      Invoice__r.Invoice_Status__c
                      FROM Invoice_Line_Item__c Where Invoice__c=:invid];        
        
        Map<id, Program_Batch_Wise_Instalment__c> paymentMap = new Map<id, Program_Batch_Wise_Instalment__c>();
        Map<id, Stationary_Item_Account__c> stationaryMap = new Map<id, Stationary_Item_Account__c>();
        
        for (Invoice_Line_Item__c inv: inLineList) {
            system.debug('inside if ======'+inv);   
            system.debug('status ======'+inv.Invoice__r.Invoice_Status__c);  
            
            // For Payment milestone //
            if(inv.Invoice__r.Invoice_Status__c=='Cancel' && inv.Payment_Milestone__c!= null){
                Program_Batch_Wise_Instalment__c pbi = new Program_Batch_Wise_Instalment__c();
                pbi.Id = inv.Payment_Milestone__c;
                pbi.No_of_Invoice_Line_Item__c = 0;
                paymentMap.put(pbi.id, pbi);
            }
            // For Stationary Items //
            if(inv.Invoice__r.Invoice_Status__c=='Cancel' && inv.stationary_Item__c!= null){
                Stationary_Item_Account__c pbi = new Stationary_Item_Account__c();
                pbi.Id = inv.stationary_Item__c;
                pbi.No_of_Invoice_Line_Item__c = 0;
                stationaryMap.put(pbi.id, pbi);
            }
        }
        
        update paymentMap.values();
        update stationaryMap.values();
        
        pagereference pg= new pagereference('/'+currentRecID);
        pg.setRedirect(true);
        return pg;  
    }
    
    Public Pagereference Cancel(){
        
        pagereference pg=new pagereference('/'+currentRecID);
        pg.setRedirect(true);
        return pg;        
    } */
}