public class ShortClosePO {
    public id pid {get;set;}
    public Boolean showlist{get;set;}
    public Boolean ShowPage{get;set;}
    public Boolean Showback{get;set;}
    public List<Pending_PO_Order__c> plList;
    public List<wrapProduct> wList{get;set;}
    public List<Short_Close_PO__c> packList{get;set;}
    public Purchase_Order__c pi {get;set;}
    public String shortclose {get;set;}
    Public Decimal RemQty {get;set;}
    public ShortClosePO(){
        showlist=true;
        ShowPage=false;
        Showback=false;
        wList=new List<wrapProduct>();
        pid=ApexPages.currentPage().getParameters().get('id');
        pi=[SELECT Id, Name, PO_Stage__c,Warehouse_Address__c, Payment_Terms__c,Freight__c,Freight_Cost__c,Freight_Extra__c,Taxes__c,Discount__c,
            PO_Bill_To__c,PO_Ship_To__c,Kind_Attention__c,Special_Notes__c,Instruction__c,Total_Remaining_Quantity__c,Short_Close_Reason__c
            FROM Purchase_Order__c where id=:pid];
        shortclose=pi.Short_Close_Reason__c;
        if(shortclose == null){
            system.debug('RemQty---'+RemQty);
            ApexPages.Message msg = new ApexPages.Message(ApexPages.Severity.ERROR,'Provide Short Close Reason.!!!!!!');
            ApexPages.addMessage(msg);
        }
        //SC_Remaining_Quantity__c
        plList = [Select Id, Name, Item_Name__c, Short_Close_Quantity__c,SC_Remaining_Quantity__c, Item_Name__r.name, Item_Name__r.Item_No__c,Remaining_Quantity__c, 
                  Quantity__c,Purchase_Order__c From Pending_PO_Order__c Where Purchase_Order__c=:pi.Id AND Remaining_Quantity__c!=0];
        
        RemQty=PI.Total_Remaining_Quantity__c;
        system.debug('RemQty---'+RemQty);
        
        for(Pending_PO_Order__c p:plList)
        {
            wList.add(new wrapProduct(p));  
        }  
        
        if(RemQty == 0){
            system.debug('RemQty---'+RemQty);
            ApexPages.Message msg = new ApexPages.Message(ApexPages.Severity.ERROR,'No Pending Quantity To Make Short Close.!!!!!!');
            ApexPages.addMessage(msg);
        }
        
        
    }
    public pagereference AddProduct()
    {
        showlist=false;
        ShowPage=true;   
        Showback=false;
        packList=new List<Short_Close_PO__c>();
        
        for(wrapProduct o:wList)
        {
            if(o.isChecked)
            { 
                Short_Close_PO__c p=new Short_Close_PO__c();
                p.Purchase_Order__c=pid;
                p.Pending_PO_Order__c=o.pro.id;
                // p.Pricelist_Master__c=o.pro.Price_List__c;
                //p.Description__c=o.pro.Item_Description__c; 
                //p.Discount__c=o.pro.discount__c;
                p.Item_Name__c=o.pro.Item_Name__c;
                p.Backend_Remaining_Qty__c=o.pro.Remaining_Quantity__c;
                p.Short_Close_Qty__c=o.pro.Remaining_Quantity__c;
                
                p.CurrencyIsoCode=pi.CurrencyIsoCode;
                packList.add(p);
            } 
        }
        if(packList.size()==0){
            ShowPage=false;
            Showback=true;
            ApexPages.addmessage(new ApexPages.message(ApexPages.severity.Error, 'Please select atleast one Product.!!!!!!'));
            //ApexPages.Message msg = new ApexPages.Message(ApexPages.Severity.ERROR,'Please select atleast one Product.!!!!!!');
            return null;
        }
        return null;
    }
    public pagereference save()
    {
        for(Short_Close_PO__c bw : packList){ 
            system.debug('bw.Quantity__c'+ bw.Short_Close_Qty__c);
            system.debug('o.pro.Backend_Remaining_Qty__c'+bw.Backend_Remaining_Qty__c);
            if( bw.Short_Close_Qty__c>bw.Backend_Remaining_Qty__c){
                ApexPages.addmessage(new ApexPages.message(ApexPages.severity.Error,'You cannot enter more Quantity.!!!!!!'));
                return null;
            }
            
        } 
        
        pi=[SELECT Id, Name, PO_Stage__c,Warehouse_Address__c, Payment_Terms__c,Freight__c,Freight_Cost__c,Freight_Extra__c,Taxes__c,Discount__c,
            PO_Bill_To__c,PO_Ship_To__c,Kind_Attention__c,Special_Notes__c,Instruction__c,Total_Remaining_Quantity__c,Short_Close_Reason__c
            FROM Purchase_Order__c where id=:pid];
        pi.PO_Stage__c='Short Closed';
        update pi;
        insert packList;
        
        PageReference pageRef=new PageReference('/' +pid);
        pageRef.setRedirect(true);
        return pageRef;
    }
    public void Back() {
        for(Short_Close_PO__c asnItem: packList) {
            delete asnItem;
        }
        showlist=true;
        Showback=false;
      //  PageReference pageRef = new PageReference('/' + pid);
       // pageRef.setRedirect(true);
       // return pageRef;
    }
    public pagereference Cancel()
    {
        
        PageReference pageRef=new PageReference('/' +pid);
        pageRef.setRedirect(true);
        return pageRef;
    }
    
    
    public class wrapProduct{ 
        public Pending_PO_Order__c pro{get;set;}
        public boolean isChecked{get;set;}
        public wrapProduct(Pending_PO_Order__c i){
            pro=i;
            isChecked=false;
        }
    }
}