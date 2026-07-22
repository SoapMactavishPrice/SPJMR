public class UpdateGRNLine {
    public id pid {get;set;}
    public Boolean showlist{get;set;}
    public Boolean ShowPage{get;set;}
    public Boolean Showback{get;set;}
    public List<ASN_Line_Item__c> plList;
    public List<wrapProduct> wList{get;set;}
    public List<GRN_Line_Item__c> packList{get;set;}
    public List<Shortage_Rejection_Advice__c> shortrejectList{get;set;}
    public List<Pending_Sales_Order__c> pendSOList{get;set;}
    public GRN__c pi;
    list < id > pList = new List < id > ();
    Map < id, id > iMap = new Map < id, id > ();
    Public Decimal RemQty {get;set;}
    public String OrderId {get;set;}
    
    public UpdateGRNLine(){
        showlist=true;
        ShowPage=false;
        Showback=false;
        wList=new List<wrapProduct>();
        pid=ApexPages.currentPage().getParameters().get('id');
        pi=[select id,name,CurrencyIsoCode,ASN_Number__c, ASN_Number__r.Total_Remaining_Quantity__c,Sales_Order__c From GRN__c where id=:pid];
        
        OrderId=pi.Sales_Order__c;
        
        plList = [Select Id, Name, Item_Name__c,Item_Name__r.name,Pending_PO_Order__c, Quantity__c,ASN__c,Inventory__c, 
                  Tax_Code__c,HSN_Code__c,Unit_Price__c,UOM_Master__c,UOM__c,Item_Name__r.Item_No__c,Total_Remaining_Quantity__c
                  From ASN_Line_Item__c 
                  Where ASN__c=:pi.ASN_Number__c AND Total_Remaining_Quantity__c!=0];
        RemQty=PI.ASN_Number__r.Total_Remaining_Quantity__c;
        for(ASN_Line_Item__c p:plList)
        {
            wList.add(new wrapProduct(p));  
        }  
        
        if(RemQty == 0){
            system.debug('RemQty---'+RemQty);
            ApexPages.Message msg = new ApexPages.Message(ApexPages.Severity.ERROR,'No more Quantity to create GRN item.!!!!!!');
            ApexPages.addMessage(msg);
        }
    }
    public pagereference AddProduct(){
        showlist=false;
        ShowPage=true;  
        Showback=false;
        packList=new List<GRN_Line_Item__c>();
        
        for(wrapProduct o:wList)
        {
            if(o.isChecked) { 
                
                GRN_Line_Item__c p = new GRN_Line_Item__c();
                p.GRN__c               = pid;
                p.ASN_Line_Item__c     = o.pro.id;
                p.Tax_Code__c          = o.pro.Tax_Code__c;
                p.HSN_Code__c          = o.pro.HSN_Code__c;
                p.Unit_Price__c        = o.pro.Unit_Price__c;
                p.Item_Name__c         = o.pro.Item_Name__c; 
                p.Quantity__c          = o.pro.Quantity__c;
                p.UOM_Master__c        = o.pro.UOM_Master__c;
                p.UOM__c			   = o.pro.UOM__c;
                p.CurrencyIsoCode      = pi.CurrencyIsoCode;
                p.ASN_Quantity__c      = o.pro.Quantity__c;
                //p.Received_Quantity__c = o.pro.Received_Quantity__c;
                p.Inventory__c         = o.pro.Inventory__c;
                p.Pending_PO_Order__c  = o.pro.Pending_PO_Order__c;
                
                packList.add(p);
                pList.add(o.pro.Item_Name__c);
                
            }
            system.debug('packList--' + packList.size());
        }
        
        
        if(packList.size()==0) {
            ShowPage=false;
            Showback=true;
            ApexPages.addmessage(new ApexPages.message(ApexPages.severity.Error, 'Please select atleast one Product.!!!!!!'));
            //ApexPages.Message msg = new ApexPages.Message(ApexPages.Severity.ERROR,'Please select atleast one Product.!!!!!!');
            return null;
        }
        
        
        return null;
    }
    public pagereference save(){
        shortrejectList = new List<Shortage_Rejection_Advice__c>();
        for(GRN_Line_Item__c bw : packList){ 
            
            if(bw.Received_Quantity__c > bw.ASN_Quantity__c){
                System.debug('in if----->');
                ApexPages.addmessage(new ApexPages.message(ApexPages.severity.WARNING,'Accepted Quantity Should not be more than Challan Quantity:'));
                return null;
            }
            if((bw.Received_Quantity__c!=null && bw.Rejected_Quantity__c!=null && bw.ASN_Quantity__c!=null)){
                if((bw.Received_Quantity__c + bw.Rejected_Quantity__c) != bw.ASN_Quantity__c){
                    ApexPages.addmessage(new ApexPages.message(ApexPages.severity.WARNING,'Accepted Quantity + Rejected Quantity Should be equal to Challan Quantity:'));
                    return null; 
                }
            }
            //Update in Shortage_Rejection_Advice_Class.cls File also
            Shortage_Rejection_Advice__c sr=new Shortage_Rejection_Advice__c();
            sr.GRN_Number__c=pid;
            sr.HSN_Code__c=bw.HSN_Code__c;
            sr.Item_Name__c=bw.Item_Name__c; 
            sr.Quantity__c=bw.Rejected_Quantity__c;
            sr.GRN_Line_Item_Code__c = bw.Name;
            sr.UOM__c=bw.UOM__c;
            sr.CurrencyIsoCode=bw.CurrencyIsoCode;
            sr.Inventory__c=bw.Inventory__c;
            sr.Rejection_Created__c=true;
            //sr.UOM_Master__c=bw.UOM_Master__c;
            // p.ASN_Line_Item__c=o.pro.id;
            //sr.Tax_Code__c=o.pro.Tax_Code__c;
            // sr.Unit_Price__c=o.pro.Unit_Price__c;
            //system.debug('p.Rejected_Quantity__c--'+bw.Rejected_Quantity__c);
            if(bw.Rejected_Quantity__c!=null){
                shortrejectList.add(sr);
            }
            
            system.debug('shortrejectList--'+shortrejectList);
            
        } 
        insert packList;
        system.debug('packList--'+packList);
        insert shortrejectList;
        system.debug('shortrejectList--'+shortrejectList);
        list < Product_Inventory__c > invlist = new list < Product_Inventory__c > ();
        
        set<id> wid= new set<id>();
        set<id> gid= new set<id>();
        for(GRN_Line_Item__c bw : packList){ 
            gid.add(bw.id);
        }
        system.debug('wid--'+wid);
        List<GRN_Line_Item__c> grnlinelist = [Select Id, Name, GRN__c,Warehouse__c,Item_Name__c,Received_Quantity__c,GRN__r.Opportunity__c,GRN__r.Sales_Order__c,GRN__r.Account_Name__c,GRN__r.Warehouse__c From GRN_Line_Item__c Where Id=:gid];
        system.debug('grnlinelist--'+grnlinelist);
        for(GRN_Line_Item__c bw : grnlinelist){ 
            wid.add(bw.GRN__r.Warehouse__c);
        }
        list < Product_Inventory__c > inv = [select id, name, Item_Master__c, Warehouse__c From Product_Inventory__c where Item_Master__c IN: pList And Warehouse__c IN:wid];
        system.debug('inv--'+inv.size());
        for (Product_Inventory__c i: inv) {
            system.debug('i--'+i.Name);
        }
        for(GRN_Line_Item__c bw : grnlinelist){ 
            for (Product_Inventory__c i: inv) {
                iMap.put(i.Item_Master__c, i.id);
            }
            system.debug('iMap'+iMap);
            for (id i: pList) {
                if (!iMap.containsKey(i)) {
                    system.debug('inside if');
                    Product_Inventory__c inv1 = new Product_Inventory__c();
                    inv1.Item_Master__c = i;
                    system.debug('bw.GRN__r.Warehouse__c'+bw.GRN__r.Warehouse__c);
                    inv1.Warehouse__c = bw.GRN__r.Warehouse__c;
                    invlist.add(inv1);
                }
            }
        }
        insert invlist;
        system.debug('invlist'+invlist);
        for (Product_Inventory__c i: invlist) {
            iMap.put(i.Item_Master__c, i.Id);           
        }
        system.debug('iMap'+iMap);
        
        pendSOList = [Select Id, Name,Sales_Order__c,Item_Name__c From Pending_Sales_Order__c Where Sales_Order__c =: OrderId];
        system.debug('pendSOList--'+pendSOList.size());  
        
        Map<id,id> pendingMap=new Map<id,id>();
        for(Pending_Sales_Order__c pen:pendSOList){
            pendingMap.put(pen.Item_Name__c,pen.id);
        }
        
        list < Inventory_Receipt__c > IRList = new list < Inventory_Receipt__c > ();
        list < Blocked_Inventory__c > BIList = new List < Blocked_Inventory__c > ();
        for (GRN_Line_Item__c gr: grnlinelist) {
            Inventory_Receipt__c  IR = new Inventory_Receipt__c();
            IR.GRN__c = gr.GRN__c;
            IR.GRN_Line_Item__c = gr.id;
            system.debug('iMap.get(gr.Item_Name__c)'+iMap.get(gr.Item_Name__c));
            IR.Warehouse_Inventory__c = iMap.get(gr.Item_Name__c);
            IR.Quantity__c = gr.Received_Quantity__c;
            IR.Product2__c=gr.Item_Name__c;
            IRList.add(IR);
            
            Blocked_Inventory__c BI = new Blocked_Inventory__c();
            BI.GRN_Line_Item__c = gr.id;
            BI.Account__c=gr.GRN__r.Account_Name__c;
            BI.AccountId__c=gr.GRN__r.Account_Name__c;
            BI.Opportunity__c=gr.GRN__r.Opportunity__c;
            BI.Sales_Order__c=gr.GRN__r.Sales_Order__c;
            BI.Product_Name__c=gr.Item_Name__c;
            BI.Pending_Sales_Order__c=pendingMap.get(gr.Item_Name__c);
            BI.Warehouse_Inventory__c = iMap.get(gr.Item_Name__c);
            //BI.Material_Planning_Line_Item__c = gr.MLineID__c;
            BI.Quantity__c = gr.Received_Quantity__c;
            if(gr.GRN__r.Account_Name__c!=null){
                BI.Blocked_Inventory_Status__c='Blocked';
            }
            if(gr.GRN__r.Account_Name__c==null){
                BI.Blocked_Inventory_Status__c='Available';
            }
            
            BI.Inventory_Status_Sub_Type__c='GRN';
            BIList.add(BI);
        }
        insert IRList;
        insert BIList;
        
        PageReference pageRef=new PageReference('/' +pid);
        pageRef.setRedirect(true);
        return pageRef;
    }
    
    public void Back() {
        for(GRN_Line_Item__c asnItem: packList) {
            delete asnItem;
        }
        showlist=true;
        Showback=false;
        /* PageReference pageRef = new PageReference('/' + pid);
        pageRef.setRedirect(true);
        return pageRef;*/
    }
    
    public pagereference Cancel(){
        
        PageReference pageRef=new PageReference('/' +pid);
        pageRef.setRedirect(true);
        return pageRef;
    }
    
    public class wrapProduct{ 
        public ASN_Line_Item__c pro{get;set;}
        public boolean isChecked{get;set;}
        public wrapProduct(ASN_Line_Item__c i){
            pro = i;
            isChecked = false;
        }
    }
}