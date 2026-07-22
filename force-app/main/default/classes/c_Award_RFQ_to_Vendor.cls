public class c_Award_RFQ_to_Vendor {
    
    public string rid {get;set;}
    public RFQ__c o_rfq {get;set;}
    public List<RFQ_Vendor_Item_Map__c> plist_rfq_vendor_item_map {get;set;}
    public List<RFQ_Item__c> pList_item{get;set;}
    public List<RFQ_PO__c> pList_po_item{get;set;}
    
    public String send_data_rfq {get;set;}
    public String send_data_vendor_item_map {get;set;}
    public String send_data_item {get;set;}
    public String send_data_po_item {get;set;}

    public c_Award_RFQ_to_Vendor() {
        
        rid = ApexPages.CurrentPage().getparameters().get('id');
        
        o_rfq = new RFQ__c();
        plist_rfq_vendor_item_map = new List<RFQ_Vendor_Item_Map__c>();
        pList_item = new List<RFQ_Item__c>();
        pList_po_item = new List<RFQ_PO__c>();

        f_load_vendor_item_map();
    }
    
    public void f_load_vendor_item_map() {
        
        o_rfq = [ SELECT id, name, CreatedDate, Award_Date__c FROM RFQ__c where id = :rid];
        
        plist_rfq_vendor_item_map = [SELECT Id, Name,Vendor_Name__c, RFQ__c, Item_Name__c, Vendor_Name__r.Name, Item_Name__r.Name
                                     , Credit_Period__c, Delivery_Cost__c, Delivery_Terms__c, Discount__c, Expiry_Date__c, IGST__c
                                     , Packing_Cost__c, Payment_Terms__c, Total_Cost__c, Unit_Price__c, Vendor_Supply_Qty__c
                                     , Is_Awarded__c
                                     FROM RFQ_Vendor_Item_Map__c 
                                     Where RFQ__c = :rid
                                     ORDER BY  Vendor_Name__r.Name, Item_Name__r.Name];
        
        pList_item = [SELECT Id, Name, Item_Name__c, Item_Name_Temp__c, Item_Description__c, Quantity__c, GST__c, GST_Type__c, Unit_Price_Chk__c,
                 Delivery_Cost__c , Packing_Cost__c, Expiry_Date__c, Discount_Chk__c, Total_Cost__c, Credit_Period__c, Payment_Terms__c,
                 Delivery_Terms__c, HSN_Code_Chk__c, Vendor_Supply_Qty__c
                 FROM RFQ_Item__c 
                 WHERE RFQ__c = :rid];
        
        /*pList_po_item = [SELECT Item_Name__c, Item_Name__r.Name, Item_Name__r.Id, Vendor_Name__c, Vendor_Name__r.Name, Vendor_Name__r.Id, 
                         Purchase_Order__c, Purchase_Order__r.PO_Stage__c
                         FROM RFQ_PO__c
                         WHERE RFQ__c = :rid
                         AND Purchase_Order__r.PO_Stage__c <> 'Cancelled'
                         ORDER BY Item_Name__r.Name, Vendor_Name__r.Name];*/
        
        AggregateResult[] group_po_item = [SELECT Item_Name__c, Item_Name__r.Name, Item_Name__r.Id, SUM(PO_Qty__c) Total_PO
                                          FROM RFQ_PO__c
                                          WHERE RFQ__c = :rid
                                          AND Purchase_Order__r.PO_Stage__c <> 'Cancelled'
                                          GROUP BY Item_Name__c, Item_Name__r.Name, Item_Name__r.Id
                                          ORDER BY Item_Name__r.Name];
        
        send_data_rfq 				= JSON.serialize(o_rfq);
        send_data_vendor_item_map 	= JSON.serialize(plist_rfq_vendor_item_map);
        send_data_item 				= JSON.serialize(pList_item);
        send_data_po_item 			= JSON.serialize(group_po_item);
    }
    
    public PageReference f_load_vendor_item_map1() {
        PageReference pageRef = new PageReference(ApexPages.currentPage().getUrl());
        pageRef.setRedirect(true);
        
        f_load_vendor_item_map();
        
        return pageRef;
    }
    
    
    @RemoteAction
    public static boolean f_Save(List<RFQ_Vendor_Item_Map__c> p_data, RFQ__c p_RFQ ){
        system.debug('p_data : ' + p_data);
        system.debug('p_RFQ : ' + p_RFQ);
        
        List<RFQ_Vendor_Item_Map__c> t_vim_list = new List<RFQ_Vendor_Item_Map__c>(); 
        
        for (Integer i = 0; i < p_data.size(); i++) 
        {
            RFQ_Vendor_Item_Map__c t_vim = new RFQ_Vendor_Item_Map__c(); 
            t_vim.RFQ__c 			= p_RFQ.Id;
            t_vim.Id 				= p_data[i].Id;
            t_vim.Is_Awarded__c 	= p_data[i].Is_Awarded__c;
            t_vim_list.add(t_vim);
        }
        
        //system.debug('t_vim_list : ' + t_vim_list);
        
        update t_vim_list;
        
        RFQ__c t_rfq = [SELECT id, Award_Date__c FROM RFQ__c where id = :p_RFQ.Id];
        if (t_rfq.Award_Date__c == null) {
            t_rfq.Award_Date__c = System.today();
            update t_rfq;
        }

        return true;
    }

    public void f_Send_Notification()
    {
        RFQ__c o_rfq = [select id,name, OwnerId from RFQ__c where id = :rid];

        Id typeId = [SELECT Id FROM CUstomNotificationType WHERE DeveloperName = 'Notify_Employee_about_WO_creation'].Id;
        //system.debug('typeId=='+typeId);

        Messaging.CustomNotification notification = new Messaging.CustomNotification();
        notification.setBody('This is notify that the RFQ Award to Vendor are Updated For RFQ : ' + o_rfq.name + ' .');
        notification.setTitle('RFQ Award to Vendor are Updated');
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
    
}