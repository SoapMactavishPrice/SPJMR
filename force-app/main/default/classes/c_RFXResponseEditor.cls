public class c_RFXResponseEditor {
    
    public string rid{get;set;}
    public List<RFQ_Vendor__c> plist_rfq_vendor {get;set;}
    
    public ID selected_vendor {get;set;}
    
    public List<RFQ_Vendor_Item_Map__c> vimList{get;set;}
    public List<RFQ_Item__c> pList{get;set;}
    
    public Map<String,String> v_vendor_list{get;set;}
    public Map<id,RFQ_Item__c> pMap = new Map<id,RFQ_Item__c>();
    //public Map<String,Boolean> t_Map_Hide_Column = new Map<String,Boolean>();
    //public List <Map<String, Boolean>> Map_Hide_Column {get;set;} //new List <Map<String, Boolean>>();

    public List<wrap_Hide_Column> wHide_Column{get;set;}
    public List<wrapVendorItemLine> wviList{get;set;}
    
    public c_RFXResponseEditor(){
        
        rid = ApexPages.CurrentPage().getparameters().get('id');
        
        plist_rfq_vendor = new List<RFQ_Vendor__c>();
        v_vendor_list = new Map<String,String>();
        wviList = new List<wrapVendorItemLine>();
        vimList = new list<RFQ_Vendor_Item_Map__c>();
        pList = new List<RFQ_Item__c>();
        wHide_Column = new List<wrap_Hide_Column>();
        //Map_Hide_Column = new List <Map<String, Boolean>>();
        
        f_load_vendor();
    }
    
    public void f_load_vendor() {
        
        /*plist_rfq_vendor = [SELECT Id, Name,Vendor_Name__c, RFQ__c, Vendor_Name__r.name
                            FROM RFQ_Vendor__c 
                            Where RFQ__c = :rid
                            ORDER BY Vendor_Name__r.Name];
        
        for(RFQ_Vendor__c a : plist_rfq_vendor)
        {
            v_vendor_list.put(a.Vendor_Name__r.name,a.Vendor_Name__r.id);
        }*/
        
        AggregateResult[] group_vendor = [SELECT Vendor_Name__c, Vendor_Name__r.Name Name
                                          FROM RFQ_Vendor_Item_Map__c
                                          WHERE RFQ__c = :rid
                                          GROUP BY Vendor_Name__c, Vendor_Name__r.Name
                                          ORDER BY Vendor_Name__r.Name];
        
        for (AggregateResult ar : group_vendor)  {
            v_vendor_list.put((String)ar.get('Name'),(String)ar.get('Vendor_Name__c'));
        }
    }
    
    public void f_Show_Products()
    {
        vimList.clear();
        pList.clear();
        wviList.clear();
        pMap.clear();
        wHide_Column.clear();
        
        vimList = [SELECT Id, Name, Vendor_Name__c, Item_Name__c, Item_Name__r.ProductCode, Item_Name__r.Name
                   , CGST__c, SGST__c, IGST__c, Unit_Price__c, Delivery_Cost__c, Packing_Cost__c, Total_Cost__c
                   , Discount__c, Credit_Period__c, Delivery_Terms__c, Payment_Terms__c, Vendor_Supply_Qty__c
                   , Expiry_Date__c
                   FROM RFQ_Vendor_Item_Map__c
                   WHERE RFQ__c = :rid
                   AND Vendor_Name__c = :selected_vendor
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
        //System.debug('wHide_Column : ' + wHide_Column);
        //System.debug('pMap : ' + pMap);

        for(RFQ_Vendor_Item_Map__c t :vimList)
        {
            if (pMap.containsKey(t.Item_Name__r.id)) {
                wviList.add(new wrapVendorItemLine(t, pMap.get(t.Item_Name__r.id)));
            }
        }
    }
    
    public boolean f_save() {
        
        List<RFQ_Vendor_Item_Map__c> s_vi = new List<RFQ_Vendor_Item_Map__c>();
        
        for(wrapVendorItemLine w : wviList){
            Decimal v_Quantity = this.f_check_number(String.valueOf(w.i.Quantity__c));
            Decimal v_IGST = this.f_check_number(String.valueOf(w.vi.IGST__c));
            Decimal v_Unit_Price = this.f_check_number(String.valueOf(w.vi.Unit_Price__c));
            Decimal v_Delivery_Cost = this.f_check_number(String.valueOf(w.vi.Delivery_Cost__c));
            Decimal v_Packing_Cost = this.f_check_number(String.valueOf(w.vi.Packing_Cost__c));
            Decimal v_Discount = this.f_check_number(String.valueOf(w.vi.Discount__c));

            Decimal v_t_q_p = v_Quantity * v_Unit_Price;
            if (v_Discount != 0) {
                v_t_q_p = v_t_q_p - (v_t_q_p * (v_Discount/100));
            }
            if (v_IGST != 0) {
                v_t_q_p = v_t_q_p + (v_t_q_p * (v_IGST/100));
            }

            w.vi.Total_Cost__c = (v_t_q_p + v_Delivery_Cost + v_Packing_Cost).setScale(0);

            s_vi.add(w.vi);
        }

        if(s_vi.size() > 0) {
            update s_vi;
            return true;
        }
        else{
            return false;
        }
    }

    Public Decimal f_check_number(String p_data) {
        If( p_data == '' || p_data == null || p_data.trim() == '' || p_data.length() == 0) {
            return 0.00;
        } else {
            return decimal.valueOf(p_data);
        }
    }
    
    Public pagereference saveRec() 
    {
        if (f_save() == true) {
            //return false;
            f_Show_Products();

            ApexPages.Message msg = new ApexPages.Message(ApexPages.Severity.INFO,'Updated Successfuly');
            ApexPages.addMessage(msg);
        }

        return null;
        
        /*pagereference pg= new pagereference('/'+rid);
        pg.setRedirect(true);
        return pg; */
    }

    public void f_Send_Notification()
    {
        RFQ__c o_rfq = [select id,name, OwnerId from RFQ__c where id = :rid];

        Id typeId = [SELECT Id FROM CUstomNotificationType WHERE DeveloperName = 'Notify_Employee_about_WO_creation'].Id;
        //system.debug('typeId=='+typeId);

        Messaging.CustomNotification notification = new Messaging.CustomNotification();
        notification.setBody('This is notify that the RFX Vendor Response has been updated For RFQ : ' + o_rfq.name + ' .');
        notification.setTitle('RFX Vendor Response Updated');
        // notification.setSenderId(workord.WO_Assigned_To__c);//(Userinfo.getUserId());
        notification.setNotificationTypeId(typeId);
        notification.setTargetId(rid); // target object id

        Set<String> addressee = new Set<String>();
        addressee.add(o_rfq.OwnerId);

        notification.send(addressee); // target user id.

        ApexPages.Message msg = new ApexPages.Message(ApexPages.Severity.INFO,'Notification Send Successfully');
        ApexPages.addMessage(msg);
    }
    
    Public Pagereference cancel(){        
        pagereference pg=new pagereference('/'+rid);
        pg.setRedirect(true);
        return pg;
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