public class c_RFQSendMailPDFtoVendor {
    
    public String send_data_o_selected_vendor {get;set;}
    
    public id rid{get;set;}
    
    public list<wrap_Vendor> w_VendorList{get;set;}
    public List<RFQ_Vendor__c> vList{get;set;}
    public List<RFQ_Item__c> pList{get;set;}
    public List<RFQ_Vendor_Item_Map__c> vim_list{get;set;}
    public RFQ__c o_rfq{get;set;}
    public wrap_Vendor o_selected_vendor {get;set;}
    public Map<String,String> v_vendor_list{get;set;}
    public Map<ID,String> v_Map_Template_list{get;set;}
    
    public List<wrap_Hide_Column> wHide_Column{get;set;}
    public List<wrapVendorItemLine> wviList{get;set;}
    
    public string subject {get;set;}
    public string body {get;set;}
    public string emailId {get;set;}
    
    public string selectedValue{get;set;}
    
    public string selected_template{get;set;}
    public integer select_vendor_index{get;set;}
    
    public string lbl_SendAndNext{get;set;}
    
    public List<InternalWrapperClass> InternalWrapperClassLIst {get;set;}
    
    //List<Messaging.Emailfileattachment> efalist ;
    
    public c_RFQSendMailPDFtoVendor()
    {
        InternalWrapperClassLIst = new List<InternalWrapperClass>();
        v_vendor_list = new Map<String,String>();
        v_Map_Template_list = new Map<ID,String>();
        w_VendorList = new List<wrap_Vendor>();
        vList = new list<RFQ_Vendor__c>();
        vim_list = new list<RFQ_Vendor_Item_Map__c>();
        o_selected_vendor = new wrap_Vendor(null,'');
        
        wviList = new List<wrapVendorItemLine>();
        pList = new List<RFQ_Item__c>();
        wHide_Column = new List<wrap_Hide_Column>();
        
        //efalist = new List<Messaging.Emailfileattachment>();
        
        rid = ApexPages.currentPage().getParameters().get('id'); 
        o_rfq = [select id,name, RFQ_Date__c, RFQ_Valid_Till__c from RFQ__c where id=:rid];
        subject = 'Request For Quotation : ' + o_rfq.Name ;
        
        select_vendor_index = 0;
        
         lbl_SendAndNext = 'Send And Next';
        
        f_load_vendor_list();
        
        //f_load_template();
    }
    
    public void f_load_vendor_list() {
        
        AggregateResult[] group_vendor = [SELECT Vendor_Name__c, Vendor_Name__r.Name Name
                                          FROM RFQ_Vendor_Item_Map__c
                                          WHERE RFQ__c = :rid
                                          //AND Is_PO_Created__c = true
                                          GROUP BY Vendor_Name__c, Vendor_Name__r.Name
                                          ORDER BY Vendor_Name__r.Name];
        
        for (AggregateResult ar : group_vendor)  {
            //v_vendor_list.put((String)ar.get('Name'),(String)ar.get('Vendor_Name__c'));
            v_vendor_list.put((String)ar.get('Vendor_Name__c'),(String)ar.get('Name'));
        }    
        
        vList = [select id, Vendor_Code__c, Vendor_Name__c, Vendor_Name__r.Id, Vendor_Name__r.Name
                 , Vendor_Name__r.Finance_Email__c, Vendor_Name__r.PC_E_Mail__c, Vendor_Name__r.PC_Mobile_number__c
                 , Vendor_Name__r.Address_1__c, Vendor_Name__r.Address_2__c, Vendor_Name__r.Address_3__c, Vendor_Name__r.Address_4__c
                 , Vendor_Name__r.Vendor_Website__c, Vendor_Name__r.GST_Number__c
                 From RFQ_Vendor__c
                 WHERE RFQ__c = :rid
                 ORDER BY Vendor_Name__r.Name];     
        
        for(RFQ_Vendor__c p:vList)
        {
            if (v_vendor_list.containsKey(p.Vendor_Name__c)) {
                w_VendorList.add(new wrap_Vendor(p,p.Vendor_Name__r.Name));
            }
        }
        
        f_Show_Vendor();
        
        //send_data_o_selected_vendor = JSON.serialize(o_selected_vendor);
    }
    
    public boolean f_Show_Vendor()
    {
        InternalWrapperClassLIst.clear();
        
        o_selected_vendor = w_VendorList[select_vendor_index];

        InternalWrapperClass iwc = new InternalWrapperClass();
        iwc.Name = o_selected_vendor.op.Vendor_Name__r.Name;
        iwc.Id = o_selected_vendor.op.Vendor_Name__r.Id;
        iwc.Email = o_selected_vendor.op.Vendor_Name__r.Finance_Email__c;
        InternalWrapperClassLIst.add(iwc);

        if (o_selected_vendor.op.Vendor_Name__r.Finance_Email__c == '' || o_selected_vendor.op.Vendor_Name__r.Finance_Email__c == null) {
            f_apex_msg('Vendor Email ID are blank');
            return false;
        }
        
        f_Show_Products();
        //f_Show_Attachments();
        return true;
    }
    
    public void f_Show_Products()
    {
        pList.clear();
        wviList.clear();
        wHide_Column.clear();
        
        List<RFQ_Vendor_Item_Map__c> vimList = [SELECT Id, Name, Vendor_Name__c, Item_Name__c, Item_Name__r.ProductCode, Item_Name__r.Name
                                                , CGST__c, SGST__c, IGST__c, Unit_Price__c, Delivery_Cost__c, Packing_Cost__c, Total_Cost__c
                                                , Discount__c, Credit_Period__c, Delivery_Terms__c, Payment_Terms__c, Vendor_Supply_Qty__c
                                                , Expiry_Date__c
                                                FROM RFQ_Vendor_Item_Map__c
                                                WHERE RFQ__c = :rid
                                                AND Vendor_Name__c = :o_selected_vendor.op.Vendor_Name__r.id
                                                ORDER BY Item_Name__r.Name
                                               ];
        
        Set<Id> t_itemlist = new Set<Id>();
        for(RFQ_Vendor_Item_Map__c t_vim : vimList)
        {
            t_itemlist.add(t_vim.Item_Name__c);
        }

        pList = [SELECT Id, Name, Item_Name__c, Item_Name_Temp__c, Item_Description__c, Quantity__c, GST__c, GST_Type__c, Unit_Price_Chk__c,
                 Delivery_Cost__c , Packing_Cost__c, Expiry_Date__c, Discount_Chk__c, Total_Cost__c, Credit_Period__c, Payment_Terms__c,
                 Delivery_Terms__c, HSN_Code_Chk__c, Vendor_Supply_Qty__c
                 FROM RFQ_Item__c 
                 WHERE RFQ__c = :rid
                AND Item_Name__c IN :t_itemlist];
       
        wrap_Hide_Column t_wHide_Column = new wrap_Hide_Column();
        Map<id,RFQ_Item__c> pMap = new Map<id,RFQ_Item__c>();
        
        for (RFQ_Item__c i: pList) {
            pMap.put(i.Item_Name__c, i);
            
            if(i.GST__c == true)                {   t_wHide_Column.flag_GST               = true;   }
            if(i.Unit_Price_Chk__c == true)     {   t_wHide_Column.flag_UNIT_PRICE        = true;   }
            if(i.Delivery_Cost__c == true)      {   t_wHide_Column.flag_DELIVERY_COST     = true;   }
            if(i.Packing_Cost__c == true)       {   t_wHide_Column.flag_PACKING_COST      = true;   }
            if(i.Expiry_Date__c == true)        {   t_wHide_Column.flag_EXPIRY_DATE       = true;   }
            if(i.Discount_Chk__c == true)       {   t_wHide_Column.flag_DISCOUNT          = true;   }
            if(i.Total_Cost__c == true)         {   t_wHide_Column.flag_TOTAL_COST        = true;   }
            if(i.Credit_Period__c == true)      {   t_wHide_Column.flag_CREDIT_PERIOD     = true;   }
            if(i.Payment_Terms__c == true)      {   t_wHide_Column.flag_PAYMENT_TERMS     = true;   }
            if(i.Delivery_Terms__c == true)     {   t_wHide_Column.flag_DELIVERY_TERMS    = true;   }
            if(i.Vendor_Supply_Qty__c == true)  {   t_wHide_Column.flag_VENDOR_SUPPLY_QTY = true;   }
        }
        
        wHide_Column.add(t_wHide_Column);
        
        for(RFQ_Vendor_Item_Map__c t :vimList)
        {
            if (pMap.containsKey(t.Item_Name__r.id)) {
                wviList.add(new wrapVendorItemLine(t, pMap.get(t.Item_Name__r.id)));
            }
        }
    }
    
    
    public void f_load_template() {
        
        /*List<SelectOption> options = new List<SelectOption>();
        options.add(new SelectOption('--Select Email Template--','--Select Email Template--'));
        
        emailTemplates=[SELECT Id, Name, TemplateType, Description from EmailTemplate];   
        for(EmailTemplate et:emailTemplates){
            options.add(new SelectOption(et.Id,et.Name));
        }
        return options;*/
        
        List<EmailTemplate> v_EmailTemplateList = new List<EmailTemplate>();
        v_EmailTemplateList = [SELECT Id, Name, TemplateType, Description from EmailTemplate];   
        
        v_Map_Template_list.put(null,'Select Email Template');
        
        for (EmailTemplate ar : v_EmailTemplateList)  {
            v_Map_Template_list.put((ID)ar.get('Id'),(String)ar.get('Name'));
        }
    }
    
    public List<SelectOption> getItems()
    {
        List<SelectOption> options = new List<SelectOption>();
        options.add(new SelectOption('-- Select Email Template --','-- Select Email Template --'));
        
        List<EmailTemplate> v_EmailTemplateList = new List<EmailTemplate>();
        v_EmailTemplateList = [SELECT Id, Name, TemplateType, Description from EmailTemplate ORDER BY Name];   
        for(EmailTemplate et : v_EmailTemplateList){
            options.add(new SelectOption(et.Id,et.Name));
        }
        return options;
    }
    
    public void f_GetTemplateBody() {
        
        EmailTemplate emptemp = [SELECT Id FROM EmailTemplate WHERE Id = :selected_template];
        
        Messaging.SingleEmailMessage[] previewEmails = new Messaging.SingleEmailMessage[]{};
        Messaging.SingleEmailMessage firstPreviewEmail = new Messaging.SingleEmailMessage();
        firstPreviewEmail.setUseSignature(false);
        firstPreviewEmail.setSaveAsActivity(false);
        firstPreviewEmail.setTemplateId(selected_template);
        firstPreviewEmail.setTargetObjectId(UserInfo.getUserId());
        //firstPreviewEmail.setWhatId(dealId);
        previewEmails.add(firstPreviewEmail);
        Messaging.SingleEmailMessage secondPreviewEmail = new Messaging.SingleEmailMessage();
        previewEmails.add(secondPreviewEmail);
        
        try 
        {
            List<Messaging.SendEmailResult> previewResult = Messaging.sendEmail(previewEmails);
        }
        catch (Exception e) 
        {
            String generatedEmailBody = firstPreviewEmail.getPlainTextBody();  // Email body generated
            //System.debug('generatedEmailBody == >'+generatedEmailBody);
            generatedEmailBody = generatedEmailBody.replaceAll('\r', '\n');
            generatedEmailBody = generatedEmailBody.replace('\n', '');
            body = generatedEmailBody;
            
            System.debug('body : ' + body);
        }
    }
    
    public void f_Show_Attachments() {
        string s_file_name_pdf = o_rfq.name + '_' + o_selected_vendor.op.Vendor_Name__r.Name + '.pdf';
        string s_file_name_csv = o_rfq.name + '_' + o_selected_vendor.op.Vendor_Name__r.Name + '.csv';
        List <Attachment> at = [Select id, name, body from Attachment where ParentId = :o_selected_vendor.op.Id and name = :s_file_name_pdf limit 1];
        
        // Attachment
        List<Messaging.Emailfileattachment> efalist = new List<Messaging.Emailfileattachment>();
        //efalist = new List<Messaging.Emailfileattachment>();
        
        // PDF Attachment
        if (at.Size() > 0) {
            Messaging.Emailfileattachment efa = new Messaging.Emailfileattachment();
            efa.setFileName(at[0].Name);
            efa.setBody(at[0].Body);
            efalist.add(efa);
        }
        
        // CSV Attachment
        ContentDocumentLink[] cdl_exists = [select id, ContentDocumentId 
                                            from ContentDocumentLink
                                            where LinkedEntityId = :o_selected_vendor.op.Id];
        Set<Id> t_file_id = new Set<Id>();
        for(ContentDocumentLink t_id : cdl_exists)
        {
            t_file_id.add(t_id.ContentDocumentId);
        }
        
        for (ContentVersion cversion :  [select Id, title, versiondata from ContentVersion 
                                         where ContentDocumentId in :t_file_id 
                                         AND Title = :s_file_name_csv
                                         limit 1]) 
        {
            Messaging.Emailfileattachment efa = new Messaging.Emailfileattachment();
            efa.setFileName(cversion.title);
            efa.setBody(cversion.versiondata);
            efalist.add(efa); 
        }
    }
    
    public pageReference saveTemp() {
        
        // --------- 	Save PDF File START	--------- //
        PageReference pdf;
        pdf = Page.RFQPage_PDF;
        //pdf = Page.RFQSendMailPDFtoVendor;
        pdf.getParameters().put('id', o_selected_vendor.op.Id);
        
        Blob pdfbody;
        if (!test.isRunningTest()) {
            pdfBody = pdf.getContentAsPDF();
        } else {
            pdfBody = blob.valueOf('test');
        }
        
        string s_file_name = o_rfq.name + '_' + o_selected_vendor.op.Vendor_Name__r.Name + '.pdf';
        
        List <Attachment> at = [Select id, name, body from Attachment where ParentId = :o_selected_vendor.op.Id and name = :s_file_name limit 1];
        /*String name;
        if (at.size() != 0) {
            name = 'RFQ PDF' + at.size() + '.pdf';
        } else {
            name = 'RFQ PDF.pdf';
        }*/
        Attachment attach = new Attachment();
        attach.ParentId = o_selected_vendor.op.Id;
        attach.Name = s_file_name;
        if (at.size() > 0) {
            attach.id = at[0].id;
        }
        upsert attach;
        //insert attach;
        // --------- 	Save PDF File END	--------- //
        
        PageReference pageRef = new PageReference('/' + o_selected_vendor.op.Id);
        PageRef.setRedirect(true);
        return PageRef;
    }
    
    public pageReference SendAndNext() {
        
        if (o_selected_vendor.op.Vendor_Name__r.Finance_Email__c == '' || o_selected_vendor.op.Vendor_Name__r.Finance_Email__c == null) {
            return f_apex_msg('Vendor Email ID are blank');
        }

        if (subject == '') {
            return f_apex_msg('Please fill the subject');
        }
        
        if (body == '') {
            return f_apex_msg('Please fill the email body');
        }
        
        f_save_send_mail();

        
        // --------- 	Next Vendor START	--------- //

        select_vendor_index = select_vendor_index + 1 ;
        
        if (w_VendorList.size() > select_vendor_index) {
            f_Show_Vendor();
        }
        if (w_VendorList.size() == select_vendor_index + 1) {
            lbl_SendAndNext = 'Send';
        }
        
        // --------- 	Next Vendor END	--------- //
        
        return null;
    }
    
    public void f_save_send_mail() {

        string s_file_name_pdf = o_rfq.name + '_' + o_selected_vendor.op.Vendor_Name__r.Name + '.pdf';
        string s_file_name_csv = o_rfq.name + '_' + o_selected_vendor.op.Vendor_Name__r.Name + '.csv';
        List <Attachment> at = [Select id, name, body from Attachment where ParentId = :o_selected_vendor.op.Id and name = :s_file_name_pdf limit 1];
        
        // --------- 	Save PDF File START	--------- //
        
        /*
        PageReference pdf;
        pdf = Page.RFQPage_PDF;
        //pdf = Page.RFQSendMailPDFtoVendor;
        pdf.getParameters().put('id', o_selected_vendor.op.Id);
        
        Blob pdfbody;
        if (!test.isRunningTest()) {
            pdfBody = pdf.getContentAsPDF();
        } else {
            pdfBody = blob.valueOf('test');
        }
		*/
        
        /*String name;
        if (at.size() != 0) {
            name = 'RFQ PDF' + at.size() + '.pdf';
        } else {
            name = 'RFQ PDF.pdf';
        }*/
        /*
        Attachment attach = new Attachment();
        attach.ParentId = o_selected_vendor.op.Id;
        attach.Name = s_file_name_pdf;
        attach.Body = pdfBody;
        if (at.size() > 0) {
            attach.id = at[0].id;
        }
        upsert attach;
        //insert attach;
		*/
        
        // --------- 	Save PDF File END	--------- //
        
        
        // --------- 	Send Mail START	--------- //
        
        List<String> s_address = new List<String>();
        //s_address.add(o_selected_vendor.op.Vendor_Name__r.Finance_Email__c);
        for(InternalWrapperClass t:InternalWrapperClassLIst)
        {
            s_address.add(t.Email);
            //s_address.add('g.anjani9@gmail.com');
        }
        if (emailId != ''){
            s_address.add(emailId);
        }
        
        Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
        email.setSubject(subject);
        email.setToAddresses(s_address);
        body = body.replaceAll('<[^>]+>',' ');
        body = body.replaceAll('&amp;','&');
        email.setPlainTextBody(body);
        
        
        // Attachment
        List<Messaging.Emailfileattachment> efalist = new List<Messaging.Emailfileattachment>();
        
        // PDF Attachment
        if (at.Size() > 0) {
            Messaging.Emailfileattachment efa = new Messaging.Emailfileattachment();
            efa.setFileName(at[0].Name);
            efa.setBody(at[0].Body);
            efalist.add(efa);
            
        }
        
        // CSV Attachment
        ContentDocumentLink[] cdl_exists = [select id, ContentDocumentId 
                                            from ContentDocumentLink
                                            where LinkedEntityId = :o_selected_vendor.op.Id];
        Set<Id> t_file_id = new Set<Id>();
        for(ContentDocumentLink t_id : cdl_exists)
        {
            t_file_id.add(t_id.ContentDocumentId);
        }
        
        for (ContentVersion cversion :  [select Id, title, versiondata from ContentVersion 
                                         where ContentDocumentId in :t_file_id 
                                         AND Title = :s_file_name_csv
                                         limit 1]) 
        {
            Messaging.Emailfileattachment efa = new Messaging.Emailfileattachment();
            efa.setFileName(cversion.title);
            efa.setBody(cversion.versiondata);
            efalist.add(efa); 
        }        
        
        email.setFileAttachments(efalist);
                
        /*
            //fetch Email Attachment
            Set<Id> emailAttchIds = new Set<Id>();
            List<Email_Attachment__c> emailAttachmentList = [SELECT Id, MOM__c FROM Email_Attachment__c WHERE MOM__c =:oid];
            for(Email_Attachment__c e:emailAttachmentList){
            emailAttchIds.add(e.Id);
            }
            
            List<Id> ContentDocumentids = new List<Id>();
            
            if(emailAttchIds.size() > 0) {
            List<ContentDocumentLink> contentDocumentLinklIst= [SELECT LinkedEntityid, ContentDocumentid 
            FROM ContentDocumentLink 
            WHERE LinkedEntityid IN :emailAttchIds];
            for(ContentDocumentLink cd :contentDocumentLinklIst)
            {
            ContentDocumentids.add(cd.ContentDocumentid);  
            }
            for (ContentVersion cversion : [SELECT title, PathOnClient, FileType,versiondata 
            FROM contentversion 
            WHERE ContentDocumentId IN :ContentDocumentids])
            {
            // system.debug('body : '+WOCFbody+'-----------'+cversion.title);
            Messaging.Emailfileattachment efa1 = new Messaging.Emailfileattachment();
            efa1.setFileName(cversion.title);
            efa1.setBody(cversion.versiondata);
            efalist.add(efa1); 
            }
            }*/
        
        
        
        Messaging.SendEmailResult[] r = Messaging.SendEmail(new Messaging.SingleEmailMessage[] {email});
        
        /*EmailMessage em = new EmailMessage();
            em.Subject = subject;
            em.RelatedToId = o_selected_vendor.op.Id;
            if(emailId != '') {
            em.ToAddress = emailId;
            }
            em.MessageDate = Datetime.now();
            em.TextBody = body;
            em.Incoming = false;
            insert em;*/
        
        // --------- 	Send Mail END	--------- //
    }
    
    
    public void SendToAll() {
        for(integer i = 0; i < w_VendorList.size(); i++){
            select_vendor_index = i;
            boolean b = f_Show_Vendor();
            if (b){
                f_save_send_mail();
            }
        }
    }
    
    public void removeSelected() {
        
        
    }
    
    public pageReference f_apex_msg(string p_msg) {
        ApexPages.Message msg = new ApexPages.Message(ApexPages.Severity.ERROR, p_msg);
        ApexPages.addMessage(msg);
        //PageReference pageRef = new PageReference('/' + rid);
        //pageRef.setRedirect(true);
        return null;
    }
    
    public pageReference cancel()
    {
        PageReference pageRef = new PageReference('/'+rid);
        pageRef.setRedirect(true);
        return pageRef;
    }
    
    public class wrap_Vendor
    {
        public RFQ_Vendor__c op{get;set;}
        public boolean isChecked{get;set;}
        public String Vendor_Name{get;set;}
        public wrap_Vendor(RFQ_Vendor__c v, String p_Vendor_Name )
        {
            op = v;
            Vendor_Name = p_Vendor_Name;
            isChecked = true;
        }
    }
    
    public class InternalWrapperClass {
        public String Name {get;set;}
        public String Id {get;set;}
        public String Email {get;set;}
    }
    
    public class wrapVendorItemLine
    {
        public RFQ_Vendor_Item_Map__c vi{get;set;}
        public RFQ_Item__c i{get;set;}
        
        public wrapVendorItemLine(RFQ_Vendor_Item_Map__c p_vi, RFQ_Item__c p_i)
        {
            vi = p_vi;
            i = p_i;
        }
    }
    
    public class wrap_Hide_Column
    {
        public boolean flag_GST               {get;set;}
        public boolean flag_UNIT_PRICE        {get;set;}
        public boolean flag_DELIVERY_COST     {get;set;}
        public boolean flag_PACKING_COST      {get;set;}
        public boolean flag_EXPIRY_DATE       {get;set;}
        public boolean flag_DISCOUNT          {get;set;}
        public boolean flag_TOTAL_COST        {get;set;}
        public boolean flag_CREDIT_PERIOD     {get;set;}
        public boolean flag_PAYMENT_TERMS     {get;set;}
        public boolean flag_DELIVERY_TERMS    {get;set;}
        public boolean flag_VENDOR_SUPPLY_QTY {get;set;}
        
        public wrap_Hide_Column(){
            flag_GST               = false;
            flag_UNIT_PRICE        = false;
            flag_DELIVERY_COST     = false;
            flag_PACKING_COST      = false;
            flag_EXPIRY_DATE       = false;
            flag_DISCOUNT          = false;
            flag_TOTAL_COST        = false;
            flag_CREDIT_PERIOD     = false;
            flag_PAYMENT_TERMS     = false;
            flag_DELIVERY_TERMS    = false;
            flag_VENDOR_SUPPLY_QTY = false;
        }
    }
}