public class POPdf {
    public id inid {get;set;}
    public Purchase_Order__c quo {get;set;}
    public Purchase_Order_Item__c quoitem {get;set;}
    // public List<Invoice_Line_Item_Tax__c> ActualQuoteLine{get;set;}
    // public List<Invoice_Line_Item_Tax__c> quoteitemwithtax{get;set;}
    public List<Purchase_Order_Item__c> qlList{get;set;}
    public Opportunity opp{get;set;}
    public Product2 prod {get;set;}
    public List<wrapclass> listwrap{get; set;}
    public String emailId{get;set;}
    public String subject{get;set;}
    public String body{get;set;}
    public String amountInWords{get;set;}
    List<Wrapper> wrapperList = new List<Wrapper>();
    public string accountName;
    public string PONo;
    public string approval{get;set;}
    public Vendor__c vendor{get;set;}
    public String vendorAddress{get;set;}
    
    public string accountImageURL{
        get{
            String imageURL='';
            List<Purchase_Order__c> quo = new List<Purchase_Order__c>();
            
            quo = [SELECT id, Vendor_Name__r.Name, Vendor_Name__r.Address_1__c, PO_Date__c,Account_Name__r.Name,
                   Purchase_Requisition__r.Name, Approval_Status__c, Kind_Attention__r.Email, Document_Number__c, PO_Bill_To__r.Account__r.Name,
                   PO_Bill_To__r.Address__c, PO_Ship_To__r.Account__r.Name, PO_Ship_To__r.Address__c, Purchase_Requisition__r.Account_Name__r.Name,
                   PO_Bill_To__r.Country__c,PO_Bill_To__r.State__c,PO_Bill_To__r.City__c,PO_Bill_To__r.Zip_Code__c,
                   PO_Bill_To__r.Line_1_Block__c,PO_Bill_To__r.Line_2_Building_Floor_Room__c,PO_Bill_To__r.Line_3_Street_PO_Box__c,
                   PO_Ship_To__r.Country__c,PO_Ship_To__r.State__c,PO_Ship_To__r.City__c,PO_Ship_To__r.Zip_Code__c,
                   PO_Ship_To__r.Line_1_Block__c,PO_Ship_To__r.Line_2_Building_Floor_Room__c,PO_Ship_To__r.Line_3_Street_PO_Box__c,
                   PO_Ship_To__r.Country_Name__c,Company_Master__r.Logo__c,
                   PO_Bill_To__r.Country_Name__c,
                   Payment_Terms__c,Tax_Code__r.name,
                   Freight_Cost__c, Freight_Currency__c,
                   Remarks__c,Drum_Length_Tolerance__c,Quantity_Tolerance__c,Inspection_By__c,Embossing_Printing__c,Delivery_Schedule__c,Inspection_By__r.Name,
                   Kind_Attention__r.Name,
                   Kind_Attention__r.Phone, Kind_Attention__r.MobilePhone,
                   Kind_Attention__r.Business_Email__c,
                   
                   Purchase_Requisition__r.Vendor_GST__c,
                   Account_Name__r.GST_Number__c, Account_Name__r.GSTIN__c,
                   Company_Master__r.GSTIN_UIN_Number__c,
                   Vendor_Name__r.GST_Number__c
                   
                   FROM Purchase_Order__c where id=:inid];
            if(quo.size() > 0){
                if (quo[0].Company_Master__r.Logo__c != null){
                    Matcher imgMatcher = Pattern.compile( '<img(.+?)>' ).matcher(quo[0].Company_Master__r.Logo__c);           
                    while (imgMatcher.find()) {                
                        String imageTag = imgMatcher.group();
                        System.debug('imageTag^^'+imageTag );              
                        
                        imageURL= imageTag.substringBetween(' src="', '"' );
                        System.debug('imageURL^^' + imageURL );
                    }
                }
                return imageURL.unescapeHtml4();    
            }else{
                return '{!URLFOR($Resource.ARElectroLogo)}';
            }
            
        }
        set{}
    }
    
    public POPdf(){
        
        inid=ApexPages.currentPage().getParameters().get('id');
        quo = new Purchase_Order__c(); 
        quoitem = new Purchase_Order_Item__c();
        NumbersToWordsClass ntc = new NumbersToWordsClass(); 
        qlList = new List<Purchase_Order_Item__c>();
        listwrap  = new List<wrapclass>();
        // quo= [SELECT Id, Name, Approval_Status__c, Purchase_Requisition__c,Document_Number__c,Kind_Attention__r.Email,Purchase_Requisition__r.Account_Name__r.Name FROM Purchase_Order__c Where id=: inid];
        quo = [
            SELECT id, Vendor_Name__r.Name, Vendor_Name__c, Vendor_Name__r.Address_1__c, PO_Date__c,Account_Name__r.Name,
            Purchase_Requisition__r.Name, Approval_Status__c, Kind_Attention__r.Email, Document_Number__c, PO_Bill_To__r.Account__r.Name,
            Company_Master__r.Name,Company_Master__r.Company_Address__c,Company_Master__r.Company_City__c,Company_Master__r.Company_State__c,Tax_Code__c,
            Company_Master__r.Company_Country__c,Company_Master__r.Phone_1__c,Company_Master__r.Phone_2__c,Company_Master__r.Phone_3__c,
            Company_Master__r.Email__c,Company_Master__r.Website__c,Company_Master__r.Fax__c,Company_Master__r.Quote_Body__c,
            PO_Bill_To__r.Address__c, PO_Ship_To__r.Account__r.Name, PO_Ship_To__r.Address__c, Purchase_Requisition__r.Account_Name__r.Name,
            PO_Bill_To__r.Country__c,PO_Bill_To__r.State__c,PO_Bill_To__r.City__c,PO_Bill_To__r.Zip_Code__c,
            PO_Bill_To__r.Line_1_Block__c,PO_Bill_To__r.Line_2_Building_Floor_Room__c,PO_Bill_To__r.Line_3_Street_PO_Box__c,
            PO_Ship_To__r.Country__c,PO_Ship_To__r.State__c,PO_Ship_To__r.City__c,PO_Ship_To__r.Zip_Code__c,
            PO_Ship_To__r.Line_1_Block__c,PO_Ship_To__r.Line_2_Building_Floor_Room__c,PO_Ship_To__r.Line_3_Street_PO_Box__c,
            PO_Ship_To__r.Country_Name__c,
            PO_Bill_To__r.Country_Name__c,
            Payment_Terms__c,Tax_Code__r.name,
            Freight_Cost__c, Freight_Currency__c,
            Remarks__c,Drum_Length_Tolerance__c,Quantity_Tolerance__c,Inspection_By__c,Embossing_Printing__c,Delivery_Schedule__c,Inspection_By__r.Name,
            Kind_Attention__r.Name,
            Kind_Attention__r.Phone, Kind_Attention__r.MobilePhone,
            Kind_Attention__r.Business_Email__c,
            
            Purchase_Requisition__r.Vendor_GST__c,
            Account_Name__r.GST_Number__c, Account_Name__r.GSTIN__c,
            Company_Master__r.GSTIN_UIN_Number__c,
            Vendor_Name__r.GST_Number__c
            
            FROM Purchase_Order__c where id=:inid
        ];
        emailId=quo.Kind_Attention__r.Email;
        PONo= quo.Document_Number__c;
        accountName=quo.Purchase_Requisition__r.Account_Name__r.Name;
        approval=quo.Approval_Status__c;
        
        if(quo.Vendor_Name__c != null) {
            vendor = [select id,
                      (Select id, Name, Default__c, Vendor__c, Address_Type__c, Line_1_Block__c, Line_2_Building_Floor_Room__c,
                       Line_3_Street_PO_Box__c, Line_4__c, GST_Type__c, City__c, Pin_Code__c, State__c, Country__c, GSTIN__c
                       from Vendor_Address__r where Default__c=:true)
                      from Vendor__c where id=:quo.Vendor_Name__c];
            
            if(vendor.Vendor_Address__r.size() > 0) {
                Vendor_Address__c va = vendor.Vendor_Address__r[0];
                
                if(va.Line_1_Block__c != null)
                    vendorAddress = va.Line_1_Block__c;
                
                if(va.Line_2_Building_Floor_Room__c != null)
                    vendorAddress += ', ' + va.Line_2_Building_Floor_Room__c;
                
                if(va.Line_3_Street_PO_Box__c != null)
                    vendorAddress += ', ' + va.Line_3_Street_PO_Box__c;
                
                if(va.Line_4__c != null)
                    vendorAddress += ', ' + va.Line_4__c;
                
                if(va.City__c != null)
                    vendorAddress += ', ' + va.City__c;
                
                if(va.State__c != null)
                    vendorAddress += ', ' + va.State__c;
                
                if(va.Country__c != null)
                    vendorAddress += ', ' + va.Country__c;
                
                if(va.Pin_Code__c != null)
                    vendorAddress += ', ' + va.Pin_Code__c;
            }
        }
        
        /*
        vendorAddress = [Select id, Name, Default__c, Vendor__c, Address_Type__c, Line_1_Block__c, Line_2_Building_Floor_Room__c,
                                   Line_3_Street_PO_Box__c, Line_4__c, GST_Type__c, City__c, Pin_Code__c, State__c, Country__c, GSTIN__c
                                   from Vendor_Address__c where Vendor__c=:quo.Vendor_Name__c limit 1];
        */
        
        //amountInWords = ntc.convert(quo.Grand_Total__c.longValue());
        
        // quoitem = [SELECT Id, Name, Tax_Code__r.Tax_Name_Label__c, CurrencyIsoCode,HSN_Master__r.Name,HSN_Master__c,Purchase_Order__c,Item_Code__c,Item_Description__c,Item_Name__c,
        //           Qty__c,Tax_Code__c,Unit_Price__c,UOM_Master__c
        //          FROM Purchase_Order_Item__c Where Purchase_Order__c =: quo.id  Limit 1];
        
        //quoteitemwithtax = [Select id ,Invoice_Line_Item__r.id,Rate__c,Tax_Amount__c,Tax_Combination__r.Name,Invoice_Line_Item__c
        //              from Invoice_Line_Item_Tax__c Where Invoice_Line_Item__r.id =: quoitem.id];
        
        // system.debug('quoteitemwithtax-------'+quoteitemwithtax);
        
        qlList = [
            SELECT id, Item_Code__c, Item_Name__r.Name, Sales_UOM__r.Name, UOM_Master__r.Name, Qty__c, Unit_Price__c,
            Discount_In_Percentage__c,Color__c, Net_per_unit__c, Price_After_Discount__c,MRP_Price__c,Total_Price_After_Tax__c,
            Tax_Code__r.Name
            FROM Purchase_Order_Item__c WHERE Purchase_Order__c=: quo.id
        ];
        
        // qlList = [SELECT Id, Name, Tax_Code__r.Tax_Name_Label__c, CurrencyIsoCode,HSN_Master__r.Name,HSN_Master__c,Purchase_Order__c,Item_Code__c,Item_Description__c,Item_Name__c,
        //         Qty__c,Tax_Code__c,Unit_Price__c,UOM_Master__c
        //          FROM Purchase_Order_Item__c Where Purchase_Order__c =: quo.id];
        system.debug('approval--'+approval);
        if( approval != 'Approved'){
            system.debug('approval--'+approval);
            ApexPages.Message msg = new ApexPages.Message(ApexPages.Severity.ERROR,'Get the Approval to generate PO !!!!!!');
            ApexPages.addMessage(msg);
        }
        
        /*  Set<Id> quoteids = new Set<Id>();
for(Invoice_Line_Item__c test1 : qlList){

quoteids.add(test1.id);
ActualQuoteLine = [Select id,Name,Invoice_Line_Item__r.id,Rate__c,Tax_Amount__c,Tax_Combination__r.Name,Invoice_Line_Item__c
from  Invoice_Line_Item_Tax__c  WHERE Invoice_Line_Item__r.id=: test1.id];

listwrap.add(new wrapclass(test1,ActualQuoteLine));
}*/
    }
    
    public pageReference SavePdf(){  
        
        try{
            Attachment a;
            PageReference pdf;
            pdf = Page.POPdfPage;
            pdf.getParameters().put('id',inid);
            Blob pdfBody;
            if(!test.isRunningTest()){
                pdfBody = pdf.getContentAsPDF();
            }
            else
            {
                pdfBody = blob.valueof('TEST');
            }
            list<Attachment> at=[select id,name,body from Attachment where ParentId=:inid];
            system.debug('atttt'+at);
            String name;
            
            if(at.size()!=0)
                name=accountName +'-'+ PONo + '_V'+at.size()+'.pdf';
            else
            {
                name=accountName +'-'+ PONo + '_V'+'.pdf'; // 'PO Pdf.pdf';
            }
            
            Attachment attach = new Attachment();
            attach.ParentId =inid;
            attach.name = name;
            attach.body = pdfBody ;
            System.debug('tId '+inid);
            INSERT attach;
            system.debug('attach'+attach);
            
        }
        catch(exception e){
            system.debug('SavePOPdf'+e);
        }
        
        PageReference pageRef = new PageReference('/'+inid);
        pageRef.setRedirect(true);
        return pageRef;
    }
    
    public pageReference saveAndSend() {
        
        Attachment a; 
        for(String key : emailId.split(','))
        {
            wrapperList.add(new Wrapper(key));
        }
        String[] addresses = new string [wrapperList.size()];
        String[] ccAddresses = new string [wrapperList.size()];
        PageReference pdf;
        pdf = Page.POPdfPage;
        pdf.getParameters().put('id',inid);
        Blob pdfBody;
        if(!test.isRunningTest()){
            pdfBody = pdf.getContentAsPDF();
        }
        else
        {
            pdfBody = blob.valueof('TEST');
        }
        list<Attachment> at=[select id,name,body from Attachment where ParentId=:inid];
        String name;
        
        if(at.size()!=0)
            name=accountName +'-'+ PONo + '_V'+at.size()+'.pdf';
        else
        {
            name=accountName +'-'+ PONo + '_V'+'.pdf'; // 'PO Pdf.pdf';
        }
        Attachment attach = new Attachment();
        attach.ParentId =inid;
        attach.name = name;
        attach.body = pdfBody ;
        System.debug('tId '+inid);
        INSERT attach;
        
        Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
        for (Integer i = 0; i < wrapperList.size(); i++) {
            
            addresses[i] = wrapperList[i].email;
        }
        
        
        email.setSubject(Subject);
        email.setToAddresses(ccAddresses);
        email.setToAddresses(addresses); //Used SOQL to retrieve addresses in the address
        // email.setToAddresses(customerEmail);
        email.setHtmlBody(body);
        
        Messaging.Emailfileattachment efa = new Messaging.Emailfileattachment();
        efa.setFileName(attach.Name);
        efa.setBody(attach.Body);
        email.setFileAttachments(new Messaging.EmailFileAttachment[] {efa});
        
        Messaging.SendEmailResult [] r = Messaging.SendEmail(new Messaging.SingleEmailMessage[] {email}); 
        
        PageReference pageRef = new PageReference('/'+inid);
        pageRef.setRedirect(true);
        return pageRef;
    }
    
    
    public class wrapclass{
        public Invoice_Line_Item__c quo {get;set;}
        public list<Invoice_Line_Item_Tax__c>tList{get;set;}
        public wrapclass(Invoice_Line_Item__c ben,list<Invoice_Line_Item_Tax__c>data){
            this.quo=ben;
            this.tList=data;
            
        }
    }
    
    public class Wrapper{
        public String email{get;set;}
        public Wrapper(String i){
            email = i;
        }
    }
    
    Public Pagereference Cancel(){
        
        pagereference pg=new pagereference('/'+inid);
        pg.setRedirect(true);
        return pg;        
    }  
}