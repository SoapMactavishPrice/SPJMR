public class AccountButtons {
    
    public string currentRecID{get;set;}
    public Account acc {get;set;}
  //  public Invoice__c inv {get;set;}
    
    public AccountButtons(){
        
        currentRecID=ApexPages.CurrentPage().getparameters().get('id');        
    }
    
    public pageReference withdraw() {
        PageReference pageRef = new PageReference('/lightning/cmp/c__StudentWithdrawCaller?c__refRecordId='+currentRecID+'&c__refsObjectName=Account');
        pageRef.setRedirect(false);
        return pageRef;
    }
    
    public pageReference studentTransfer() {
        
        PageReference pageRef = new PageReference('/lightning/cmp/c__StudentTransferCaller?c__refRecordId='+currentRecID+'&c__refsObjectName=Account');
        pageRef.setRedirect(false);
        return pageRef;
    }
    
    public pageReference AddLevel() {
        
        PageReference pageRef = new PageReference('/lightning/cmp/c__addProgramBatchOnAccountManagerCaller?c__refRecordId='+currentRecID+'&c__refsObjectName=Account');
        pageRef.setRedirect(false);
        return pageRef;
    }
    
    public pageReference Withdrawal() {
        
        PageReference pageRef = new PageReference('/apex/WithdrawalProcessPage?id='+currentRecID);  
        pageRef.setRedirect(true);
        return pageRef;
    }
    
    public pageReference BatchTransfer() {
        
        PageReference pageRef = new PageReference('/apex/BatchTransfer?id='+currentRecID);  
        pageRef.setRedirect(true);
        return pageRef;
    }
    
    public pageReference GenerateInvoice() {
        
        PageReference pageRef = new PageReference('/apex/GenerateInvoice?id='+currentRecID);  
        pageRef.setRedirect(true);
        return pageRef;
    }
    public pageReference ViewInvoice() {
        
        PageReference pageRef = new PageReference('/apex/ViewInvoice?id='+currentRecID);  
        pageRef.setRedirect(true);
        return pageRef;
    }
    public pageReference ViewReceipt() {
        
        PageReference pageRef = new PageReference('/apex/ViewReceipts?id='+currentRecID);  
        pageRef.setRedirect(true);
        return pageRef;
    }
    
    public pageReference GenerateReceipt() { 
        
        PageReference pageRef = new PageReference('/apex/MakeReceiptPayment?id='+currentRecID);  
        pageRef.setRedirect(true);
        return pageRef;
    }
    
    public pageReference AddBenefits() {
        
        PageReference pageRef = new PageReference('/apex/AddBenefitsOnAccount?id='+currentRecID);  
        pageRef.setRedirect(true);
        return pageRef;
    }
    public pageReference AddBenefits2() {
        
        PageReference pageRef = new PageReference('/lightning/cmp/c__AddBenefitsOnAccountCaller?c__refRecordId='+currentRecID+'&c__refsObjectName=Account');
        pageRef.setRedirect(false);
        return pageRef;
    }
    
    public pageReference Instalment() {
        
        PageReference pageRef = new PageReference('/apex/MakeInstalment?id='+currentRecID);  
        pageRef.setRedirect(true);
        return pageRef;
    }
    
    public pageReference Lumpsum() {
        
        PageReference pageRef = new PageReference('/apex/MakeLumpsumPayment?id='+currentRecID);  
        pageRef.setRedirect(true);
        return pageRef;
    }
    
    public pageReference OptInOptOut() {
        
        PageReference pageRef = new PageReference('/apex/opt_in_opt_out?id='+currentRecID);  
        pageRef.setRedirect(true);
        return pageRef;
    }
    
    public pageReference ViewOutstanding() {
        
        PageReference pageRef = new PageReference('/apex/ViewOutstandingOnFeeplan?id='+currentRecID);  
        pageRef.setRedirect(true);
        return pageRef;
    }
    
    public pageReference AddProgramBatch() {
        
        PageReference pageRef = new PageReference('/apex/AddProgramBatchOnAccountPage?id='+currentRecID);  
        pageRef.setRedirect(true);
        return pageRef;
    }
    
    public pageReference AddFeePlan() {
        
        PageReference pageRef = new PageReference('/apex/AddFeePlan?id='+currentRecID);  
        pageRef.setRedirect(true);
        return pageRef;
    }
    
    public pageReference EditAllPrograms() {
        
        PageReference pageRef = new PageReference('/apex/EditAllProgramBatch?id='+currentRecID);  
        pageRef.setRedirect(true);
        return pageRef;
    }
    
    public pageReference ViewAllFeePlans() {
        
        PageReference pageRef = new PageReference('/apex/EditAllBatchWisePaymentPage?id='+currentRecID);  
        pageRef.setRedirect(true);
        return pageRef;
    }
    
    public pageReference EditAllDocumentsPage() {
        
        PageReference pageRef = new PageReference('/apex/EditAllDocumentsPage?id='+currentRecID);  
        pageRef.setRedirect(true);
        return pageRef;
    }
    
    public pageReference MakePayTest() { 
        
        PageReference pageRef = new PageReference('/apex/Test_MakePayment?id='+currentRecID);  
        pageRef.setRedirect(true);
        return pageRef;
    }
    
     public pageReference AddStationaryMaster() { 
        
        PageReference pageRef = new PageReference('/apex/AddStationaryMaster?id='+currentRecID);  
        pageRef.setRedirect(true);
        return pageRef;
    }
    
    public pageReference DeleteBenefit() { 
        
        PageReference pageRef = new PageReference('/apex/DeleteBenefits?id='+currentRecID);  
        pageRef.setRedirect(true);
        return pageRef;
    }

    public pageReference GenerateInvoiceLWC() {
        
        // PageReference pageRef = new PageReference('/apex/GenerateInvoiceOnAccount?id='+currentRecID);  
        PageReference pageRef = new PageReference('/lightning/cmp/c__generateInvoiceCaller?c__refRecordId='+currentRecID+'&c__refsObjectName=Account');
        pageRef.setRedirect(true);
        return pageRef;
    }
}