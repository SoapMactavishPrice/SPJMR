public class c_RFQPage_PDFMail {
    
    // public String send_data_o_selected_vendor {get;set;}
    
    public id rid{get;set;}
    public id vid{get;set;}
    
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
    
    // public string selectedValue{get;set;}
    
    // public string selected_template{get;set;}
    public integer select_vendor_index{get;set;}
    
    
    public c_RFQPage_PDFMail()
    {
        v_vendor_list = new Map<String,String>();
        v_Map_Template_list = new Map<ID,String>();
        w_VendorList = new List<wrap_Vendor>();
        vList = new list<RFQ_Vendor__c>();
        vim_list = new list<RFQ_Vendor_Item_Map__c>();
        o_selected_vendor = new wrap_Vendor(null,'');
        
        wviList = new List<wrapVendorItemLine>();
        pList = new List<RFQ_Item__c>();
        wHide_Column = new List<wrap_Hide_Column>();
        
        rid = ApexPages.currentPage().getParameters().get('id'); 
        vid = ApexPages.currentPage().getParameters().get('vid'); 
        o_rfq = [select id,name, RFQ_Date__c, RFQ_Valid_Till__c from RFQ__c where id=:rid];
        
        select_vendor_index = 0;
        
        f_load_vendor_list();
    }
    
    public void f_load_vendor_list() {
        
        AggregateResult[] group_vendor = [SELECT Vendor_Name__c, Vendor_Name__r.Name Name
                                          FROM RFQ_Vendor_Item_Map__c
                                          WHERE RFQ__c = :rid
                                          //AND Is_PO_Created__c = true
                                          AND RFQ_Vendor__r.Id = :vid
                                          GROUP BY Vendor_Name__c, Vendor_Name__r.Name
                                          ORDER BY Vendor_Name__r.Name];
        
        for (AggregateResult ar : group_vendor)  {
            //v_vendor_list.put((String)ar.get('Name'),(String)ar.get('Vendor_Name__c'));
            v_vendor_list.put((String)ar.get('Vendor_Name__c'),(String)ar.get('Name'));
        }    
        for(String str: v_vendor_list.keySet()) {
            System.debug(str + ' : ' + v_vendor_list.get(str));
        }
        vList = [select id, Vendor_Code__c, Vendor_Name__c, Vendor_Name__r.Id, Vendor_Name__r.Name
                 , Vendor_Name__r.Finance_Email__c, Vendor_Name__r.PC_E_Mail__c, Vendor_Name__r.PC_Mobile_number__c
                 , Vendor_Name__r.Address_1__c, Vendor_Name__r.Address_2__c, Vendor_Name__r.Address_3__c, Vendor_Name__r.Address_4__c
                 , Vendor_Name__r.Vendor_Website__c, Vendor_Name__r.GST_Number__c
                 From RFQ_Vendor__c
                 WHERE RFQ__c = :rid 
                 AND Id = :vid
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
    
    public void f_Show_Vendor()
    {
        o_selected_vendor = w_VendorList[select_vendor_index];
        
         f_Show_Products();
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