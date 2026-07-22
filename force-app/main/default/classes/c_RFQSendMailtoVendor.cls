public class c_RFQSendMailtoVendor {
    
    public id rid{get;set;}
   
    public list<wrap_Vendor> w_VendorList{		get;set;}
    public List<RFQ_Vendor__c> vList{get;set;}
    public List<RFQ_Item__c> pList{get;set;}
    public List<RFQ_Vendor_Item_Map__c> vim_list{get;set;}
    public RFQ__c o_rfq{get;set;}
    public Map<String,String> v_vendor_list{get;set;}
    
    public list<wrap_Vendor> w_VendorList_Selected{get;set;}
    public list<wrap_Product> w_ProductList{get;set;}
    
    Map < id, id > map_check_record = new Map < id, id > ();
    
    public c_RFQSendMailtoVendor()
    {
        v_vendor_list = new Map<String,String>();
        
        w_VendorList = new List<wrap_Vendor>();
        w_VendorList_Selected = new List<wrap_Vendor>();
        vList = new list<RFQ_Vendor__c>();
        vim_list = new list<RFQ_Vendor_Item_Map__c>();
        
        w_ProductList = new List<wrap_Product>();
        pList = new list<RFQ_Item__c>();
        
        rid = ApexPages.currentPage().getParameters().get('id'); 
        o_rfq = [select id,name, RFQ_Date__c, RFQ_Valid_Till__c from RFQ__c where id=:rid];
        
        //f_load_vendor();
        
        f_load_vendor_list();
        //f_load_product_list();
        //f_load_vendor_product_list();
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
        
        vList=[select id,Vendor_Code__c, Vendor_Name__c, Vendor_Name__r.Name
               From RFQ_Vendor__c
               WHERE RFQ__c = :rid
               ORDER BY Vendor_Name__r.Name];     
        
        for(RFQ_Vendor__c p:vList)
        {
            if (v_vendor_list.containsKey(p.Vendor_Name__c)) {
                w_VendorList.add(new wrap_Vendor(p,p.Vendor_Name__r.Name));
            }
        }
    }
    

    
    public void f_GenerateCSVFile(){
        
        for(wrap_Vendor v : w_VendorList) {
            if (v.isChecked) {
                
                vim_list = [select id,Name, Vendor_Name__c, Vendor_Name__r.Name, Vendor_Name__r.Vendor_Code__c,
                            Item_Name__c, Item_Name__r.ProductCode, Item_Name__r.Name
                            From RFQ_Vendor_Item_Map__c
                            WHERE RFQ__c = :rid
                            AND Vendor_Name__c = :v.op.Vendor_Name__c
                            //AND Is_PO_Created__c = true
                            ORDER BY Item_Name__r.Name];
                
                Set<Id> t_itemlist = new Set<Id>();
                for(RFQ_Vendor_Item_Map__c t_vim : vim_list)
                {
                    t_itemlist.add(t_vim.Item_Name__c);
                }
                
                pList = [SELECT Id, Name, Item_Name__c, Item_Name_Temp__c, Item_Description__c, Quantity__c, GST__c, GST_Type__c, Unit_Price_Chk__c,
                         Delivery_Cost__c , Packing_Cost__c, Expiry_Date__c, Discount_Chk__c, Total_Cost__c, Credit_Period__c, Payment_Terms__c,
                         Delivery_Terms__c, HSN_Code_Chk__c, Vendor_Supply_Qty__c, HSN_Code__c, Item_Group__c, Tax_Code__c
                         FROM RFQ_Item__c 
                         WHERE RFQ__c = :rid
                         AND Item_Name__c IN :t_itemlist];
                
                wrap_Hide_Column t_wHide_Column = new wrap_Hide_Column();
                Map<id,double> pMap = new Map<id,double>();
                
                for (RFQ_Item__c i: pList) {
                    
                    pMap.put(i.Item_Name__c, i.Quantity__c);
                    
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
                //wHide_Column.add(t_wHide_Column);
                
                
                string s_file_name = o_rfq.name + '_' + v.op.Vendor_Name__r.Name + '.csv';
                string S_file_body = '';
                //string s_file_header = 'Item No,Item Name,RFQ Quantity,GST %,UNIT PRICE,DELIVERY COST,PACKING COST,EXPIRY DATE,DISCOUNT,TOTAL COST,CREDIT PERIOD,PAYMENT TERMS,DELIVERY TERMS,VENDOR SUPPLY QTY \n';
                string s_file_header = 'Item No,Item Name,RFQ Quantity,';
                
                if (t_wHide_Column.flag_GST              ) {s_file_header+='GST,';}
                if (t_wHide_Column.flag_UNIT_PRICE       ) {s_file_header+='UNIT PRICE,';}
                if (t_wHide_Column.flag_DELIVERY_COST    ) {s_file_header+='DELIVERY COST,';}
                if (t_wHide_Column.flag_PACKING_COST     ) {s_file_header+='PACKING COST,';}
                if (t_wHide_Column.flag_EXPIRY_DATE      ) {s_file_header+='EXPIRY DATE,';}
                if (t_wHide_Column.flag_DISCOUNT         ) {s_file_header+='DISCOUNT,';}
                if (t_wHide_Column.flag_TOTAL_COST       ) {s_file_header+='TOTAL COST,';}
                if (t_wHide_Column.flag_CREDIT_PERIOD    ) {s_file_header+='CREDIT PERIOD,';}
                if (t_wHide_Column.flag_PAYMENT_TERMS    ) {s_file_header+='PAYMENT TERMS,';}
                if (t_wHide_Column.flag_DELIVERY_TERMS   ) {s_file_header+='DELIVERY TERMS,';}
                if (t_wHide_Column.flag_VENDOR_SUPPLY_QTY) {s_file_header+='VENDOR SUPPLY QTY';}
                
                s_file_header+='\n';
                
                for(RFQ_Vendor_Item_Map__c t_vim : vim_list)
                {
                    S_file_body+= t_vim.Item_Name__r.ProductCode + ',' + t_vim.Item_Name__r.Name + ',' + pMap.get(t_vim.Item_Name__c) + '\n';
                }
                
                //system.debug('vim_list : ' + vim_list);
                //system.debug('S_file_body : ' + S_file_body);
                
                // Check File Exists	START //
                ContentDocumentLink[] cdl_exists = [select id, ContentDocumentId 
                                                    from ContentDocumentLink
                                                    where LinkedEntityId = :v.op.Id];
                Set<Id> t_file_id = new Set<Id>();
                for(ContentDocumentLink t_id : cdl_exists)
                {
                    t_file_id.add(t_id.ContentDocumentId);
                }
                
                ContentVersion[] contentVersion_exists = [select id 
                                                          from ContentVersion 
                                                          where ContentDocumentId in :t_file_id 
                                                          AND Title = :s_file_name
                                                          limit 1];

                ContentVersion contentVersion = new ContentVersion();
                contentVersion.ContentLocation = 'S'; // S = Stored in Salesforce
                contentVersion.PathOnClient = s_file_name;
                contentVersion.Title = s_file_name;
                contentVersion.isMajorVersion = false;
                //contentVersion.VersionData = EncodingUtil.base64Decode(base64BlobValue);
                contentVersion.VersionData = Blob.valueOf(s_file_header + S_file_body);
                
                if (contentVersion_exists.size() > 0) {
                    contentVersion.id = contentVersion_exists[0].id;
                }
                
                upsert contentVersion;
                
                if (contentVersion_exists.size() == 0) {
                    contentVersion = [SELECT Id, ContentDocumentId FROM ContentVersion WHERE Id = :contentVersion.Id];
                    
                    ContentDocumentLink contentDocumentLink = new ContentDocumentLink();
                    contentDocumentLink.ContentDocumentId = contentVersion.ContentDocumentId;
                    contentDocumentLink.LinkedEntityId = v.op.Id;
                    contentDocumentLink.ShareType = 'V';
                    insert contentDocumentLink;
                }
                
            }
        }
        
        ApexPages.Message msg = new ApexPages.Message(ApexPages.Severity.INFO,'CSV File Generated Successfuly');
        ApexPages.addMessage(msg);
    }
    
    public void f_GeneratePDFFile(){
        
        for(wrap_Vendor v : w_VendorList) {
            if (v.isChecked) {
                
                PageReference pdf;
                pdf = Page.RFQPage_PDFMail;
                pdf.getParameters().put('id', rid);
                pdf.getParameters().put('vid', v.op.Id);
                
                Blob pdfbody;
                if (!test.isRunningTest()) {
                    pdfBody = pdf.getContentAsPDF();
                } else {
                    pdfBody = blob.valueOf('test');
                }
                
                string s_file_name = o_rfq.name + '_' + v.op.Vendor_Name__r.Name + '.pdf';
                
                List <Attachment> at = [Select id, name, body from Attachment where ParentId = :v.op.Id and name = :s_file_name limit 1];
                /*String name;
                if (at.size() != 0) {
                	name = 'RFQ PDF' + at.size() + '.pdf';
                } else {
                	name = 'RFQ PDF.pdf';
                }*/
                Attachment attach = new Attachment();
                attach.ParentId = v.op.Id;
                attach.Name = s_file_name;
                attach.Body = pdfBody;
                if (at.size() > 0) {
                    attach.id = at[0].id;
                }
                upsert attach;
                //insert attach;
                
            }
        }
        
        ApexPages.Message msg = new ApexPages.Message(ApexPages.Severity.INFO,'PDF File Generated Successfuly');
        ApexPages.addMessage(msg);
    }
    
    /*
    public void f_load_vendor_product_list() {
        
        vim_list = [select id,Name, Vendor_Name__c, Vendor_Name__r.Name, Vendor_Name__r.Vendor_Code__c,
               Item_Name__c, Item_Name__r.ProductCode, Item_Name__r.Name
               From RFQ_Vendor_Item_Map__c
               WHERE RFQ__c = :rid
               ORDER BY Vendor_Name__r.Name];
    }
    
    public void f_load_product_list() {
        
        pList = [SELECT Id, Name, Item_Name__c, Item_Name__r.ProductCode, Item_Name__r.Name //, Item_Name_Temp__c, Item_Description__c, Quantity__c, GST__c, GST_Type__c, Unit_Price_Chk__c,
                  //Delivery_Cost__c , Packing_Cost__c, Expiry_Date__c, Discount_Chk__c, Total_Cost__c, Credit_Period__c, Payment_Terms__c,
                  //Delivery_Terms__c, HSN_Code_Chk__c, Vendor_Supply_Qty__c
                  FROM RFQ_Item__c 
                  WHERE RFQ__c = :rid];
        
        for(RFQ_Item__c p:pList)
        {
            w_ProductList.add(new wrap_Product(p,''));
        }
    }
    
    public pageReference f_AddMapProduct()
    {
        ID t_id;
        List<RFQ_Vendor_Item_Map__c> t_vi_list = new List<RFQ_Vendor_Item_Map__c>();
        
        List<RFQ_Vendor_Item_Map__c> lineList = new list<RFQ_Vendor_Item_Map__c>();
        for(wrap_Vendor v : w_VendorList_Selected)
        {
            map_check_record.clear();
            t_id = v.op.Vendor_Name__r.Id;
            t_vi_list = [Select Id, Name, Item_Name__c 
                         from RFQ_Vendor_Item_Map__c 
                         WHERE RFQ__c = :rid 
                         AND Vendor_Name__c = :t_id];
            
            for (RFQ_Vendor_Item_Map__c i: t_vi_list) {
                map_check_record.put(i.Item_Name__c, i.Item_Name__c);
            }
            
            for(wrap_Product p : w_ProductList)
            {
                if(p.isChecked == true  &&  !map_check_record.containsKey(p.op.Item_Name__c)) {
                    RFQ_Vendor_Item_Map__c vim = new RFQ_Vendor_Item_Map__c();
                    vim.RFQ__c			= rid;
                    vim.Vendor_Name__c	= v.op.Vendor_Name__c;
                    vim.Item_Name__c	= p.op.Item_Name__c;
                    vim.RFQ_Vendor__c	= v.op.Id;
                    lineList.add(vim);
                }
            }
        }
        insert lineList;
        
        f_load_vendor_product_list();
        
        return null;
    }
    */
    
    

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
    
    public class wrap_Product
    {
        public RFQ_Item__c op{get;set;}
        public boolean isChecked{get;set;}
        public String Product_Name{get;set;}
        public wrap_Product(RFQ_Item__c v, String p_Product_Name )
        {
            op = v;
            Product_Name = p_Product_Name;
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