public with sharing  class GenerateFeePlanOnAccount {
    
    public string currentRecID{get;set;}
    public Account acc {get;set;}
    public List<Program_Batch_Wise_Payment__c> feelist{get;set;}
    public List<Account_Program_Batch_Selection__c> programlist{get;set;}
    public String emailId{get;set;}
    List<Wrapper> wrapperList = new List<Wrapper>();
    public String subject{get;set;}
    public String body{get;set;}
    public Map<string, List<Program_Batch_Wise_Payment__c>> sMap {get;set;}
    public list<Account_Program_Batch_Selection__c> proglist{get;set;}
    public Id Rtid{get;set;}
    public boolean show {get;set;}
    Set<id> plset= new Set<id>();             
    
    public GenerateFeePlanOnAccount(){
        
        currentRecID=ApexPages.CurrentPage().getparameters().get('id');
        show=false;
        acc=[ SELECT  Id,  Name,Parent_Name__c, PersonEmail,School_Lookup__r.Name FROM Account  where id=:currentRecID];
        
        programlist=[  SELECT  Id,  Name,  Student_Name__c,School_Name__c,  Program_Name__c,  Batch_Name__c,
                     Benefit__r.Name,Corporate__r.Name,Batch_Name__r.Name,Program_Name__r.Name,School_Name__r.Name
                     FROM Account_Program_Batch_Selection__c where Student_Name__c=:acc.Id and Program_Status__c ='Active' order by name ]; 
        
        System.debug('programlist '+programlist); 
        
        
        for(Account_Program_Batch_Selection__c p:programlist){
            plset.add(p.id);
        }  
        
        System.debug('acc '+acc);
        
        emailId=acc.PersonEmail;
        subject='Fee Details';
        
        system.debug('sMap====='+JSON.serialize(sMap));  
    }
    
    // Get Program / Batch Selection
    public List<SelectOption> getprogramlist1(){
        List < SelectOption > options = new List < SelectOption > ();
        proglist=[select id,Name,Program_Name__c,School_Name__c,Batch_Name__c,Program_Name__r.Name,Batch_Name__r.Name
                  from Account_Program_Batch_Selection__c where Student_Name__c=:acc.id ORDER by Name];
        //proglist2=proglist;
        system.debug('School>>>>>>>'+proglist);
        options.add(new SelectOption('None', 'None'));
        for(Account_Program_Batch_Selection__c sc:proglist){
            options.add(new SelectOption(sc.Batch_Name__c, sc.Program_Name__r.Name+ ' / ' +sc.Batch_Name__r.Name));
        }
        return options;
    } 
    
    
    public void render(){
        		System.debug('********INSIDE RENDER*******');
                sMap = new Map<string, List<Program_Batch_Wise_Payment__c>>();
                
        feelist=[SELECT  Id,  Name,  Program_Name__c,  Batch_Name__c,Payment_Type__c,Fees__c,Payment_Source__c, 
                 Payment_Status__c,Program_Batch_Selection__c,Fee_Plan_Name__c,Benefit_Applicable__c,Batch_Name__r.Name,
                 Total_Amount_Received__c,  Remaining_Amount__c,  Total_Fee_Amount__c,  Fee_Plan_Category_Master__r.Name,
                 Student_Name__c,  School_Name__c,  Total_Amount__c ,Actual_Fees__c,Fee_Plan_Category_Master__c,
                 Program_Name__r.Name,Fee_Plan_Name__r.Name, Refund_Applicable__c ,Pro_Rata_Fees_Applicable__c,Grand_Total__c,
                 Total_Benefit_Amount__c,Remaining_Amt__c,Program_Batch_Selection__r.Total_Fee_Amount__c
                 FROM Program_Batch_Wise_Payment__c  where Program_Batch_Selection__c IN: plset and Batch_Name__c =:Rtid order by name];
        
        System.debug('feelist '+feelist);
        
        for(Program_Batch_Wise_Payment__c p: feelist){
            String unq = p.Program_Name__r.Name  + ' / '+ p.Batch_Name__r.Name + ' / Total Amount : Rs. ' + p.Program_Batch_Selection__r.Total_Fee_Amount__c ;
            if(sMap.get(unq)==Null){
                List<Program_Batch_Wise_Payment__c> plist = new List<Program_Batch_Wise_Payment__c>();
                plist.add(p);
                sMap.put(unq, plist);
            }else{
                List<Program_Batch_Wise_Payment__c> plist = sMap.get(unq);
                plist.add(p);
                sMap.put(unq, plist);
            }
        }
    }
    
    
    public pageReference saveTemp() { 
        
        //this is for Security Source Scanner
        String [] attachFields = new String [] {'ParentId','name','body'};
            
            // Obtaining the field name/token map for the Attachment object
            Map<String,Schema.SObjectField> credrecp = Schema.SObjectType.Attachment.fields.getMap();
        for (String fieldToCheck : attachFields) {
            // Check if the user has create access on the each field
            if (!credrecp.get(fieldToCheck).getDescribe().isCreateable()) {
                ApexPages.addMessage(new ApexPages.Message(ApexPages.Severity.FATAL,'Insufficient access'));
                return null; 
            }
        }
        
        PageReference pdf; 
        pdf = Page.GenerateFeePlanOnAccountPDF; 
        pdf.getParameters().put('id',currentRecID);
        Blob pdfBody;
        if(!test.isRunningTest()){
            pdfBody = pdf.getContentAsPDF();
        }
        else
        {
            pdfBody = blob.valueof('TEST');
        }
        list<Attachment> at=[select id,name,body from Attachment where ParentId=:currentRecID];
        String name;
        if(at.size()!=0){ 
            
            name='Fee Plan'+'_'+at.size()+'.pdf';
        }
        else
        {
            name='Fee Plan.pdf';
        }
        Attachment attach = new Attachment();
        attach.ParentId =currentRecID;
        attach.name = name;
        attach.body = pdfBody ;
        System.debug('tId '+currentRecID);
        INSERT attach;
        PageReference pageRef = new PageReference('/'+currentRecID);
        pageRef.setRedirect(true);
        return pageRef;
    }
    
    public pageReference saveAndSend()   {
       
        //this is for Security Source Scanner
        String [] attachFields = new String [] {'ParentId','name','body'};
            
            // Obtaining the field name/token map for the Attachment object
            Map<String,Schema.SObjectField> credrecp = Schema.SObjectType.Attachment.fields.getMap();
        for (String fieldToCheck : attachFields) {
            // Check if the user has create access on the each field
            if (!credrecp.get(fieldToCheck).getDescribe().isCreateable()) {
                ApexPages.addMessage(new ApexPages.Message(ApexPages.Severity.FATAL,  'Insufficient access'));
                return null; 
            }
        }
        
        //this is for Security Source Scanner
        String [] emailFields = new String [] {'Subject','RelatedToId','ToAddress','MessageDate','Incoming','Status','textbody'};
            
            // Obtaining the field name/token map for the Attachment object
            Map<String,Schema.SObjectField> emessag = Schema.SObjectType.EmailMessage.fields.getMap();
        for (String fieldToCheck : emailFields) {
            // Check if the user has create access on the each field
            if (!emessag.get(fieldToCheck).getDescribe().isCreateable()) {
                ApexPages.addMessage(new ApexPages.Message(ApexPages.Severity.FATAL,'Insufficient access'));
                return null; 
            }
        }
        
        Attachment a; 
        for(String key : emailId.split(',')) {
            wrapperList.add(new Wrapper(key));
        }
        
        String[] addresses = new string [wrapperList.size()];
        String[] ccAddresses = new string [wrapperList.size()];
        PageReference pdf;
        pdf = Page.GenerateFeePlanOnAccountPDF;
        pdf.getParameters().put('id',currentRecID);
        Blob pdfBody;
        if(!test.isRunningTest()){
            pdfBody = pdf.getContentAsPDF();
        }
        else {
            pdfBody = blob.valueof('TEST');
        }
        list<Attachment> at=[select id,name,body from Attachment where ParentId=:currentRecID];
        String name;
        if(at.size()!=0) {
            name='Fee Plan_'+at.size()+'.pdf';
        }
        else {
            name='Fee Plan.pdf';
        }
        Attachment attach = new Attachment();
        attach.ParentId =currentRecID;
        attach.name = name;
        attach.body = pdfBody ;
        System.debug('tId '+currentRecID);
        INSERT attach;
        
        Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
        for (Integer i = 0; i < wrapperList.size(); i++) {
            addresses[i] = wrapperList[i].email;
        }
        
        email.setSubject(Subject);
        email.setToAddresses(ccAddresses);
        email.setToAddresses(addresses); //Used SOQL to retrieve addresses in the address
        // email.setToAddresses(customerEmail);
        email.setPlainTextBody(body);
        
        Messaging.Emailfileattachment efa = new Messaging.Emailfileattachment();
        efa.setFileName(attach.Name);
        efa.setBody(attach.Body);
        email.setFileAttachments(new Messaging.EmailFileAttachment[] {efa});
        
        Messaging.SendEmailResult [] r = Messaging.SendEmail(new Messaging.SingleEmailMessage[] {email}); 
        
        EmailMessage em=new EmailMessage();
        em.Subject=subject;
        em.RelatedToId=currentRecID;  
        em.ToAddress=emailId;
        em.MessageDate=system.today();
        em.TextBody=body;
        em.Incoming=false;
        em.Status='3';
        insert em;
        
       /* attach.id=null;
        attach.ParentId=em.id;
        insert attach;
        */
        PageReference pageRef = new PageReference('/'+currentRecID);
        pageRef.setRedirect(true);
        return pageRef;
    }
    
    Public Pagereference Cancel(){
        
        pagereference pg=new pagereference('/'+currentRecID);
        pg.setRedirect(true);
        return pg;        
    }  
    
    public class Wrapper{
        public String email{get;set;}
        public Wrapper(String i){
            email = i;
        }
    }
}