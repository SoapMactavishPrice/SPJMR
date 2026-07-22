public class c_CreatePO {
    
    public string rid{get;set;}
    public List<RFQ_Vendor__c> plist_rfq_vendor {get;set;}
    
    public ID selected_vendor {get;set;}
    
    public List<RFQ_Vendor_Item_Map__c> vimList{get;set;}
    public List<RFQ_Item__c> pList{get;set;}
    
    public Map<String,String> v_vendor_list{get;set;}
    public Map<id,RFQ_Item__c> pMap = new Map<id,RFQ_Item__c>();
    //public Map<String,Boolean> t_Map_Hide_Column = new Map<String,Boolean>();
    //public List <Map<String, Boolean>> Map_Hide_Column {get;set;} //new List <Map<String, Boolean>>();

    public Map<Id,Integer> v_item_po_list{get;set;}
    
    public List<wrap_Hide_Column> wHide_Column{get;set;}
    public List<wrapVendorItemLine> wviList{get;set;}
    
    public RFQ__c o_rfq{get;set;}
    
    public Purchase_Order__c po {get;set;}
    
    public c_CreatePO(){
        
        rid = ApexPages.CurrentPage().getparameters().get('id');
        o_rfq = [select id,name, Warehouse__c, Taxes__c, Checker__c, Checker_Remarks__c, 
                 Approver__c, Approver_Remarks__c, Freight_Cost__c, Freight_Currency__c, Freight__c, Freight_Extra__c, 
                 Maker__c, Maker_Remarks__c, Discount__c, Payment_Terms__c, Company_Master__c, Price_Book__c
                 from RFQ__c 
                 where id = :rid];
        
        plist_rfq_vendor = new List<RFQ_Vendor__c>();
        v_vendor_list = new Map<String,String>();
        v_item_po_list = new Map<Id,Integer>();
        wviList = new List<wrapVendorItemLine>();
        vimList = new list<RFQ_Vendor_Item_Map__c>();
        pList = new List<RFQ_Item__c>();
        wHide_Column = new List<wrap_Hide_Column>();
        po = new Purchase_Order__c();
        //Map_Hide_Column = new List <Map<String, Boolean>>();
        
        f_load_vendor();
    }
    
    public void f_load_vendor() {
        
        plist_rfq_vendor = [SELECT Id, Name,Vendor_Name__c, RFQ__c, Vendor_Name__r.name
                            FROM RFQ_Vendor__c 
                            Where RFQ__c = :rid
                            ORDER BY Vendor_Name__r.Name];
		/*for(RFQ_Vendor__c a : plist_rfq_vendor)
        {
            v_vendor_list.put(a.Vendor_Name__r.name,a.Vendor_Name__r.id);
        }*/
        
        
        AggregateResult[] group_vendor = [SELECT Vendor_Name__c, Vendor_Name__r.Name Name
                                          FROM RFQ_Vendor_Item_Map__c
                                          WHERE RFQ__c = :rid
                                          AND Is_Awarded__c = true
                                          //AND Is_Approve_Reject__c = true
                                          //AND Is_PO_Created__c != true	//NJNI
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
        v_item_po_list.clear();
        
        vimList = [SELECT Id, Name, Vendor_Name__c, Item_Name__c, Item_Name__r.ProductCode, Item_Name__r.Name
                   , CGST__c, SGST__c, IGST__c, Unit_Price__c, Delivery_Cost__c, Packing_Cost__c, Total_Cost__c
                   , Discount__c, Credit_Period__c, Delivery_Terms__c, Payment_Terms__c, Vendor_Supply_Qty__c
                   , Expiry_Date__c, RFQ_Vendor__c
                   FROM RFQ_Vendor_Item_Map__c
                   WHERE RFQ__c = :rid
                   AND Vendor_Name__c = :selected_vendor
                   AND Is_Awarded__c = true
                   //AND Is_Approve_Reject__c = true
                   //AND Is_PO_Created__c != true	//NJNI
                   ORDER BY Item_Name__r.Name
                  ];

        pList = [SELECT Id, Name, Item_Name__c, Item_Name_Temp__c, Item_Description__c, Quantity__c, GST__c, GST_Type__c, Unit_Price_Chk__c,
                 Delivery_Cost__c , Packing_Cost__c, Expiry_Date__c, Discount_Chk__c, Total_Cost__c, Credit_Period__c, Payment_Terms__c,
                 Delivery_Terms__c, HSN_Code_Chk__c, Vendor_Supply_Qty__c, UOM__c,UOM_Master__c,HSN_Code__c, Item_Group__c, Tax_Code__c,
                 Item_Name__r.Pricing_UOM__c
                 FROM RFQ_Item__c 
                 WHERE RFQ__c = :rid];
       
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

        AggregateResult[] group_item_po = [SELECT Item_Name__c, Item_Name__r.Name Name, Item_Name__r.Id Id, SUM(PO_Qty__c) Total_PO
                                           FROM RFQ_PO__c
                                           WHERE RFQ__c = :rid
                                           AND Vendor_Name__c = :selected_vendor
                                           AND Purchase_Order__r.PO_Stage__c <> 'Cancelled'
                                           GROUP BY Item_Name__c, Item_Name__r.Name, Item_Name__r.Id
                                           ORDER BY Item_Name__r.Name];
        
        for (AggregateResult ar : group_item_po)  {
            v_item_po_list.put((Id)ar.get('Id'),Integer.valueOf((Decimal)ar.get('Total_PO')));
        }
        
        for(RFQ_Vendor_Item_Map__c t :vimList)
        {
            if (pMap.containsKey(t.Item_Name__r.id)) {
                RFQ_Item__c p_i = pMap.get(t.Item_Name__r.id);
                Integer p_po_qty = v_item_po_list.get(t.Item_Name__r.id);
                if (p_po_qty == null) {
                    p_po_qty = 0;
                }
                if (p_i.Quantity__c > p_po_qty) {
                    //wviList.add(new wrapVendorItemLine(t, pMap.get(t.Item_Name__r.id), v_item_po_list.get(t.Item_Name__r.id)));    
                    wviList.add(new wrapVendorItemLine(t, p_i, p_po_qty));    
                }
            }
        }
    }
    
    /* public boolean f_validate() {
        boolean v_flag = true;
        boolean v_flag1 = false;
        for(wrapVendorItemLine wt : wviList){
            if (wt.isChecked == true)
                v_flag1 = true;
                if (wt.Pending_Qty > 0 && wt.Pending_Qty > wt.Pending_Qty_1) {
                    v_flag = false;
                }
            }
        }
        
        if (v_flag1 == false) {
            ApexPages.Message msg = new ApexPages.Message(ApexPages.Severity.ERROR,'Please select atleast one product');
            ApexPages.addMessage(msg);
        }

        if (v_flag == false) {
            ApexPages.Message msg = new ApexPages.Message(ApexPages.Severity.ERROR,'Pending Quantity Exceed');
            ApexPages.addMessage(msg);
        } 

        return v_flag;
    } */
    
    public boolean f_save() {
        
        //Purchase_Order__c po = new Purchase_Order__c();
        po = new Purchase_Order__c();
		po.RFQ_Number__c        = o_rfq.id;
		po.Vendor_Name__c       = selected_vendor;
		po.PO_Date__c           = system.today();
		po.PO_Stage__c          = 'Draft';
		po.Warehouse__c         = o_rfq.Warehouse__c;
		po.Taxes__c             = o_rfq.Taxes__c;
		po.Checker__c           = o_rfq.Checker__c;
		po.Checker_Remarks__c   = o_rfq.Checker_Remarks__c;
		po.Approver__c          = o_rfq.Approver__c;
		po.Approver_Remarks__c  = o_rfq.Approver_Remarks__c;        
		po.Freight_Cost__c      = o_rfq.Freight_Cost__c;
		po.Freight_Currency__c  = o_rfq.Freight_Currency__c;
		po.Freight__c           = o_rfq.Freight__c;
		po.Freight_Extra__c     = o_rfq.Freight_Extra__c;
		po.Maker__c             = o_rfq.Maker__c;
		po.Maker_Remarks__c     = o_rfq.Maker_Remarks__c;
		po.Discount__c          = o_rfq.Discount__c;
		po.Payment_Terms__c     = o_rfq.Payment_Terms__c;
		po.Company_Master__c    = o_rfq.Company_Master__c;
		po.Price_Book__c        = o_rfq.Price_Book__c;
        insert po;
        
        List<Purchase_Order_Item__c> poi_insert = new List<Purchase_Order_Item__c>();
        List<RFQ_Vendor_Item_Map__c> t_vimlist = new List<RFQ_Vendor_Item_Map__c>();
        List<RFQ_PO__c> t_po_rfq_list = new List<RFQ_PO__c>();
        
        for(wrapVendorItemLine wt : wviList){
            
            //if (wt.isChecked == true && wt.vi.Vendor_Supply_Qty__c > 0 && wt.Pending_Qty > 0) {
            if (wt.isChecked == true && wt.Pending_Qty > 0) {

                Purchase_Order_Item__c poi = new Purchase_Order_Item__c();
                poi.Purchase_Order__c         = po.id;
                //poi.CurrencyIsoCode           = wt.CurrencyIsoCode;
                poi.Item_Name__c              = wt.i.Item_Name__c;
                poi.UOM_Master__c             = wt.i.UOM_Master__c;
                //poi.Sales_UOM__c       		  = wt.i.UOM__c;
                poi.Sales_UOM__c       		  = wt.i.Item_Name__r.Pricing_UOM__c;
                poi.Unit_Price__c             = wt.vi.Unit_Price__c;
                poi.HSN_Master__c             = wt.i.HSN_Code__c;
                poi.Discount_In_Percentage__c = wt.vi.Discount__c;
                poi.Item_Group__c             = wt.i.Item_Group__c;
                poi.Tax_Code__c               = wt.i.Tax_Code__c;
                //poi.Inventory__c              = wt.Inventory__c;
				//poi.Qty__c                    = wt.vi.Vendor_Supply_Qty__c;
                poi.Qty__c                    = wt.Pending_Qty;
                poi_insert.add(poi);
                
                //Insert Record in RFQ_PO__c Object for Log
                RFQ_PO__c t_rfq_po = new RFQ_PO__c();
                t_rfq_po.RFQ__c = rid;
                t_rfq_po.RFQ_Vendor__c = wt.vi.RFQ_Vendor__c;
                t_rfq_po.Vendor_Name__c = wt.vi.Vendor_Name__c;
                t_rfq_po.Item_Name__c = wt.i.Item_Name__c;
                t_rfq_po.PO_Qty__c = wt.Pending_Qty;
                t_rfq_po.Purchase_Order__c = po.id;
                t_po_rfq_list.add(t_rfq_po);
                
                // Update Is_PO_Created__c flag in RFQ_Vendor_Item_Map__c Object
                RFQ_Vendor_Item_Map__c t_vim = new RFQ_Vendor_Item_Map__c();
                t_vim.Id = wt.vi.Id;
                t_vim.Is_PO_Created__c = true;
                t_vimlist.add(t_vim);
            }
        }
        
        system.debug('poi_insert : ' + poi_insert);
        
        if(poi_insert.size() > 0) {
            insert poi_insert;
            insert t_po_rfq_list;
            update t_vimlist;
            return true;
        }
        else {
            return false;
        }
    }
    
    Public pageReference saveRec() 
    {
        /* if (f_validate() == false) {
            ApexPages.Message msg = new ApexPages.Message(ApexPages.Severity.ERROR,'Pending Quantity Exceed');
            ApexPages.addMessage(msg);
        }
        else {
            if (f_save() == true) {
                //return false;
                f_Show_Products();

                ApexPages.Message msg = new ApexPages.Message(ApexPages.Severity.INFO,'Updated Successfuly');
                ApexPages.addMessage(msg);
            }
            else {
                ApexPages.Message msg = new ApexPages.Message(ApexPages.Severity.ERROR,'Error occured');
                ApexPages.addMessage(msg);
            }
        } */

        boolean v_flag = true;
        boolean v_flag1 = false;
        for(wrapVendorItemLine wt : wviList){
            if (wt.isChecked == true) {
                v_flag1 = true;
                if (wt.Pending_Qty > 0 && wt.Pending_Qty > wt.Pending_Qty_1) {
                    v_flag = false;
                }
            }
        }
        
        if (v_flag1 == false) {
            ApexPages.Message msg = new ApexPages.Message(ApexPages.Severity.ERROR,'Please select atleast one product');
            ApexPages.addMessage(msg);
            return null;
        }

        if (v_flag == false) {
            ApexPages.Message msg = new ApexPages.Message(ApexPages.Severity.ERROR,'Pending Quantity Exceed');
            ApexPages.addMessage(msg);
            return null;
        } 

        if (f_save() == true) {
            f_Show_Products();

            ApexPages.Message msg = new ApexPages.Message(ApexPages.Severity.INFO,'Updated Successfuly');
            ApexPages.addMessage(msg);
        }
        else {
            ApexPages.Message msg = new ApexPages.Message(ApexPages.Severity.ERROR,'Error occured');
            ApexPages.addMessage(msg);
        }

        return null;

        /*pagereference pg= new pagereference('/'+rid);
        pg.setRedirect(true);
        return pg; */
    }
    
    Public Pagereference f_goto_lastpo(){
        if (po.Id != null) {
            pagereference pg=new pagereference('/'+po.Id);
            pg.setRedirect(true);
            return pg;
        }
        else {
            return null;
        }
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
        public boolean isChecked{get;set;}
        public integer PO_Qty{get;set;}
        public integer Pending_Qty{get;set;} 
        public integer Pending_Qty_1{get;set;} 
        
        public wrapVendorItemLine(RFQ_Vendor_Item_Map__c p_vi, RFQ_Item__c p_i, Integer p_po_qty)
        {
            if (p_po_qty == null) {
                p_po_qty = 0;
            }
            
            vi = p_vi;
            i = p_i;
            PO_Qty = p_po_qty;
            Pending_Qty = Integer.valueOf(i.Quantity__c - p_po_qty);
            Pending_Qty_1 = Pending_Qty;
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