public class c_RFQVendorProductMap {
    
    public id rid{get;set;}
    public integer noOfRec = 10;
    
    public integer offset{get;set;}
    public boolean islast{get;set;}
    public boolean isFirst{get;set;}
    public integer pageNo{get;set;}
    public integer totalPages{get;set;}
    
    public integer offset_2{get;set;}
    public boolean islast_2{get;set;}
    public boolean isFirst_2{get;set;}
    public integer pageNo_2{get;set;}
    public integer totalPages_2{get;set;}
   
    public list<wrap_Vendor> w_VendorList{get;set;}
    public list<wrap_Vendor> w_VendorList_Selected{get;set;}
    public list<wrap_Product> w_ProductList{get;set;}
    public List<RFQ_Vendor__c> vList{get;set;}
    public List<RFQ_Item__c> pList{get;set;}
    public List<RFQ_Vendor_Item_Map__c> vim_list{get;set;}
    public RFQ__c o_rfq{get;set;}
    
    Map < id, id > map_check_record = new Map < id, id > ();
    
    String[] vendor = new String[]{};
    
    public c_RFQVendorProductMap()
    {
        w_VendorList = new List<wrap_Vendor>();
        w_VendorList_Selected = new List<wrap_Vendor>();
        vList = new list<RFQ_Vendor__c>();
        vim_list = new list<RFQ_Vendor_Item_Map__c>();
        
        w_ProductList = new List<wrap_Product>();
        pList = new list<RFQ_Item__c>();
        
        rid = ApexPages.currentPage().getParameters().get('id'); 
        o_rfq = [select id,name from RFQ__c where id=:rid];
        
        //f_load_vendor();
        
        f_load_vendor_list();
        f_load_product_list();
        f_load_vendor_product_list();
    }
    
    public void f_load_vendor_list() {
        
        vList=[select id,Vendor_Code__c, Vendor_Name__c, Vendor_Name__r.Name
               From RFQ_Vendor__c
               WHERE RFQ__c = :rid
               ORDER BY Vendor_Name__r.Name];     
        
        for(RFQ_Vendor__c p:vList)
        {
            w_VendorList.add(new wrap_Vendor(p,p.Vendor_Name__r.Name));
        }
    }
    
    public pageReference f_select_vendor()
    {
        /*for(wrap_Vendor w : w_VendorList){
            if(w.isChecked == true)
            {
                w_VendorList_Selected.add(w);
            }
        }*/
        
        //for (Integer i = 0; i < w_VendorList.size(); i++ )
        for (Integer i = w_VendorList.size() - 1; i >= 0; i-- )
        {
            if(w_VendorList.get(i).isChecked == true)
            {
                w_VendorList_Selected.add(w_VendorList.get(i));
                w_VendorList.remove(i);
            }
        }

        return null;         
    }
    
    public pageReference f_unselect_vendor()
    {
        /*for(wrap_Vendor w : w_VendorList){
            if(w.isChecked == true)
            {
                w_VendorList_Selected.add(w);
            }
        }*/
        
        for (Integer i = w_VendorList_Selected.size() - 1; i >= 0; i-- )
        {
            if(w_VendorList_Selected.get(i).isChecked == true)
            {
                w_VendorList.add(w_VendorList_Selected.get(i));
                w_VendorList_Selected.remove(i);
            }
        }

        return null;         
    }
    
    public void f_load_vendor_product_list() {
        
        vim_list = [select id,Name, Vendor_Name__c, Vendor_Name__r.Name, Vendor_Name__r.Vendor_Code__c,
               Item_Name__c, Item_Name__r.ProductCode, Item_Name__r.Name
               From RFQ_Vendor_Item_Map__c
               WHERE RFQ__c = :rid
               ORDER BY Vendor_Name__r.Name];
    }
    
    public void f_load_product_list() {
        
        pageNo = 1;
        offset = noOfRec * (pageNo-1);
        isFirst = true;
        
        totalPages=[Select id from RFQ_Item__c WHERE RFQ__c = :rid ].size()/noOfRec+1;
        
        pList = [SELECT Id, Name, Item_Name__c, Item_Name__r.ProductCode, Item_Name__r.Name //, Item_Name_Temp__c, Item_Description__c, Quantity__c, GST__c, GST_Type__c, Unit_Price_Chk__c,
                  //Delivery_Cost__c , Packing_Cost__c, Expiry_Date__c, Discount_Chk__c, Total_Cost__c, Credit_Period__c, Payment_Terms__c,
                  //Delivery_Terms__c, HSN_Code_Chk__c, Vendor_Supply_Qty__c
                  FROM RFQ_Item__c 
                  WHERE RFQ__c = :rid
                  limit:noOfRec offset:offset];
        
        for(RFQ_Item__c p:pList)
        {
            w_ProductList.add(new wrap_Product(p,''));
        }
        
        if(pageNo==totalPages)
        {
            islast=true;
        }
        if(pageNo==1)
        {
            isFirst=true;
        }else
        {
            isFirst=false;
        }
    }
    
    public pageReference nextPage()
    {
        f_AddMapProduct();
        
        w_ProductList.clear();
        
        pageNo = pageNo + 1;
        offset = noOfRec * (pageNo - 1);
        
        pList = [SELECT Id, Name, Item_Name__c, Item_Name__r.ProductCode, Item_Name__r.Name //, Item_Name_Temp__c, Item_Description__c, Quantity__c, GST__c, GST_Type__c, Unit_Price_Chk__c,
                 //Delivery_Cost__c , Packing_Cost__c, Expiry_Date__c, Discount_Chk__c, Total_Cost__c, Credit_Period__c, Payment_Terms__c,
                 //Delivery_Terms__c, HSN_Code_Chk__c, Vendor_Supply_Qty__c
                 FROM RFQ_Item__c 
                 WHERE RFQ__c = :rid
                 limit:noOfRec offset:offset];
        
        for(RFQ_Item__c p:pList)
        {
            w_ProductList.add(new wrap_Product(p,''));
        }
        
        if(pageNo==totalPages)
        {
            islast=true;
        }
        else
        {
            islast=false; 
        }
        if(pageNo==1)
        {
            isFirst=true;
        }
        else
        {
            isFirst=false;
        }
        return null;
    }
    
    public pageReference prePage()
    {
        f_AddMapProduct();
        
        w_ProductList.clear();
        
        pageNo = pageNo - 1;
        offset = noOfRec * (pageNo - 1);
            
        pList = [SELECT Id, Name, Item_Name__c, Item_Name__r.ProductCode, Item_Name__r.Name //, Item_Name_Temp__c, Item_Description__c, Quantity__c, GST__c, GST_Type__c, Unit_Price_Chk__c,
                 //Delivery_Cost__c , Packing_Cost__c, Expiry_Date__c, Discount_Chk__c, Total_Cost__c, Credit_Period__c, Payment_Terms__c,
                 //Delivery_Terms__c, HSN_Code_Chk__c, Vendor_Supply_Qty__c
                 FROM RFQ_Item__c 
                 WHERE RFQ__c = :rid
                 limit:noOfRec offset:offset];
        
        for(RFQ_Item__c p:pList)
        {
            w_ProductList.add(new wrap_Product(p,''));
        }

        if(pageNo==totalPages)
        {
            islast=true;
        }
        else
        {
            islast=false; 
        }
        if(pageNo==1)
        {
            isFirst=true;
        }
        else
        {
            isFirst=false;
        }
        return null;
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

        ApexPages.Message msg = new ApexPages.Message(ApexPages.Severity.INFO,'Updated Successfuly');
        ApexPages.addMessage(msg);
        
        return null;
    }
    
    /*public List<SelectOption> getItems() {
        
        pList=[select id,Vendor_Name__c, Vendor_Name__r.Name
               From RFQ_Vendor__c
               ORDER BY Vendor_Name__r.Name];
        
        List<SelectOption> options = new List<SelectOption>();
        
        for(RFQ_Vendor__c p:pList)
        {
            //w_VendorList.add(new wrap_Vendor(p,p.Vendor_Name__r.Name));    
            options.add(new SelectOption(p.id,p.Vendor_Name__r.Name));
        }
        //options.add(new SelectOption('US','US'));
        //options.add(new SelectOption('MEXICO','Mexico'));
        return options;
    }
    
    public String[] getVendor() {
        //If multiselect is false, countries must be of type String
        return vendor;
    }
    
    public void setVendor(String[] vendor) {
        //If multiselect is false, countries must be of type String
        this.vendor = vendor;
    }
    
    public PageReference test() {
        return null;
    }*/
    
    
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
}