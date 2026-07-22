public with sharing class RegistrationPDF {
    
    public string currentRecID{get;set;}
    public Account acc {get;set;}
    public list <Account_Parent__c> father {get;set;} 
    public list <Account_Parent__c> mother {get;set;}
    public list <Account_Parent__c> Guardian {get;set;}
    public List <Account_Sibling__c> sibling{get;set;}
    
    public String emailId{get;set;}
    List<Wrapper> wrapperList = new List<Wrapper>();
    public String subject{get;set;}
    public String body{get;set;}
    
    public List <Document_Details__c>  child {get;set;}
    public List <Document_Details__c>  mom {get;set;}
    public List <Document_Details__c>  dad {get;set;}
    
    public RegistrationPDF(){
        
        currentRecID=ApexPages.CurrentPage().getparameters().get('id');
        
        acc=[ SELECT  Id,Name, Date_Of_Birth__c, Gender__c ,Place_of_Birth__c ,Blood_Group__c ,Nationality__c ,Address_for_correspondence__c,
             Admission_In__c , Telephone_No__c ,Address__c,Previous_School_If_Any__c ,PersonEmail , Emergency_Contact_Name__c,
             Emergency_Contact_Relationship__c , Emergency_Contact_No_Other_than_Parents__c , What_Language_your_child_speaks_at_home__c ,
             Does_child_speakunderstand_English__c ,Speaking_language_at_appropriate_level__c ,Difficulty_in_understanding_child_speech__c ,
             Is_your_child_toilet_trained__c ,Developmental_milestones_at_correct_time__c ,Has_the_child_suffered_any_major_illness__c ,
             Has_child_undergone_any_major_surgery__c,Child_have_any_specific_fears__c , Does_your_child_have_any_allergies__c ,
             Does_child_have_any_specific_difficulty__c ,General_comments_about_your_child__c ,Make_your_contact_details_available__c ,
             Like_to_participate_in_school_activities__c ,Pediatrician_Family_Doctors_Name__c ,Clinics_Tel_No__c ,Mobile_No__c,Comment_8__c,
             BillingStreet, BillingState, BillingCity, BillingCountry, BillingPostalCode, ShippingStreet, ShippingState, ShippingCity,
             ShippingCountry,ShippingPostalCode,Comment_5__c,Comment_4__c,Comment_6__c,Comment_3__c,Comment_2__c,Comment_1__c,Comment_7__c,
             Terms_and_Conditions__c 
             FROM Account  where id=:currentRecID];
        
        emailId=acc.PersonEmail;
        subject='Registration Pdf';
        
        system.debug('acc.............'+acc);
        
        father=[ SELECT  Id,Name, Student_Name__c  , Parent_Name__c ,Parent_Address_Info__c ,Office_Address__c , Qualification__c ,
                Telephone_No_Home__c ,Designation__c ,Email_Id__c ,Mobile__c , Parent_Relation__c 
                FROM Account_Parent__c  where Student_Name__c=:currentRecID and Parent_Relation__c='Father'];
        
        system.debug('father.............'+father);
        
        mother=[ SELECT  Id,Name, Student_Name__c  , Parent_Name__c ,Parent_Address_Info__c ,Office_Address__c , Qualification__c ,
                Telephone_No_Home__c ,Designation__c ,Email_Id__c ,Mobile__c , Parent_Relation__c 
                FROM Account_Parent__c  where Student_Name__c=:currentRecID and Parent_Relation__c='Mother'];
        
        system.debug('mother.............'+mother);
        
        Guardian=[ SELECT  Id,Name, Student_Name__c  , Parent_Name__c ,Parent_Address_Info__c ,Office_Address__c , Qualification__c ,
                  Telephone_No_Home__c ,Designation__c ,Email_Id__c ,Mobile__c , Parent_Relation__c 
                  FROM Account_Parent__c  where Student_Name__c=:currentRecID and Parent_Relation__c='Guardian'];
        
        system.debug('Guardian.............'+Guardian);
        
        sibling=[ SELECT  Id,  Name,  Salutation__c,  Student_Account__c,Middle_Name__c,Last_Name__c,Student_Status__c,Student_Name__c ,
                 Date_of_Birth__c,  Other_School_Name__c, Gender__c 
                 FROM Account_Sibling__c  where Student_Name__c=:acc.Id order by name];  
        
        system.debug('sibling.............'+sibling);
        
    }
    
    public String getchildimage() {  
        
        child=[ SELECT Id, Name, Student_Name__c, Document_Name__c,Document_Name__r.Name  FROM Document_Details__c  
               WHERE Student_Name__c=:acc.Id and Document_Name__r.Name ='Passport Picture Child' order by name]; 
        
        Set<id> plset= new Set<id>();             
        for(Document_Details__c p:child){
            plset.add(p.id);
        }
        
        String fileId = '';
        List<Attachment> attachedFiles = [select Id from Attachment where parentId IN : plset order By LastModifiedDate DESC limit 1];
        if( attachedFiles != null && attachedFiles.size() > 0 ) {
            fileId = attachedFiles[0].Id;
        }
        return fileId;    
    }
    
    public String getfatherimage() {  
        
        dad=[ SELECT Id, Name, Student_Name__c, Document_Name__c,Document_Name__r.Name  FROM Document_Details__c  
             WHERE Student_Name__c=:acc.Id and Document_Name__r.Name ='Passport Picture Father' order by name]; 
        
        Set<id> plset1= new Set<id>();             
        for(Document_Details__c p:dad){
            plset1.add(p.id);
        }
        
        String fileId = '';
        List<Attachment> attachedFiles1 = [select Id from Attachment where parentId IN : plset1 order By LastModifiedDate DESC limit 1];
        if( attachedFiles1 != null && attachedFiles1.size() > 0 ) {
            fileId = attachedFiles1[0].Id;
        }
        return fileId;    
    }
    
    public String getmotherimage() {  
        
        mom=[ SELECT Id, Name, Student_Name__c, Document_Name__c,Document_Name__r.Name  FROM Document_Details__c  
             WHERE Student_Name__c=:acc.Id and Document_Name__r.Name ='Passport Picture Mother' order by name]; 
        
        Set<id> plset2= new Set<id>();             
        for(Document_Details__c p:mom){
            plset2.add(p.id);
        }
        
        String fileId = '';
        List<Attachment> attachedFiles2 = [select Id from Attachment where parentId IN : plset2 order By LastModifiedDate DESC limit 1];
        if( attachedFiles2 != null && attachedFiles2.size() > 0 ) {
            fileId = attachedFiles2[0].Id;
        }
        return fileId;    
    }
    
    public pageReference saveTemp()
    { 
        
            //this is for Security Source Scanner
        String [] attachFields = new String [] {'ParentId','Name','Body'};
                
        // Obtaining the field name/token map for the Attachment object
        Map<String,Schema.SObjectField> credrecp = Schema.SObjectType.Attachment.fields.getMap();
        for (String fieldToCheck : attachFields) {
            // Check if the user has create access on the each field
            if (!credrecp.get(fieldToCheck).getDescribe().isCreateable()) {
                ApexPages.addMessage(new ApexPages.Message(ApexPages.Severity.FATAL,
                                                           'Insufficient access'));
                return null; 
            }
        }
        
        PageReference pdf; 
        pdf = Page.RegistrationPDF; 
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
            
            name='Registration Pdf'+'_'+at.size()+'.pdf';
        }
        else
        {
            name='Registration Pdf.pdf';
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
        String [] attachFields = new String [] {'ParentId','Name','Body'};
                
        // Obtaining the field name/token map for the Attachment object
        Map<String,Schema.SObjectField> credrecp = Schema.SObjectType.Attachment.fields.getMap();
        for (String fieldToCheck : attachFields) {
            // Check if the user has create access on the each field
            if (!credrecp.get(fieldToCheck).getDescribe().isCreateable()) {
                ApexPages.addMessage(new ApexPages.Message(ApexPages.Severity.FATAL,
                                                           'Insufficient access'));
                return null; 
            }
        }
        
        //this is for Security Source Scanner
        String [] emailFields = new String [] {'Subject','RelatedToId','ToAddress','MessageDate','Incoming','Status','TextBody'};
                
        // Obtaining the field name/token map for the Attachment object
        Map<String,Schema.SObjectField> emessag = Schema.SObjectType.EmailMessage.fields.getMap();
        for (String fieldToCheck : emailFields) {
            // Check if the user has create access on the each field
            if (!emessag.get(fieldToCheck).getDescribe().isCreateable()) {
                ApexPages.addMessage(new ApexPages.Message(ApexPages.Severity.FATAL,
                                                           'Insufficient access'));
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
        pdf = Page.RegistrationPDF;
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
            name='Registration Pdf_'+at.size()+'.pdf';
        }
        else {
            name='Registration Pdf.pdf';
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
        
        //attach.id=null;
        //attach.ParentId=em.id;
        // insert attach;
        
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