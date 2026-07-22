public class CreatePO {
    
    // public List<Delivery_Order__c> selist {get;set;}
    public Id opid {get;set;}        
    public Purchase_Requisition__c pack {get;set;}
    // public List<Delivery_Order__c> dolist{get;set;}
    // public Id AccId {get;set;}
    public List<Purchase_Requistion_Line_Item__c> doline {get;set;}
    public Purchase_Order__c po{get;set;}
   
    public CreatePO() {
        
        opid = ApexPages.currentPage().getParameters().get('id');
        
        pack = [ SELECT Id, Name, Vendor_Name__c,Warehouse__c,Account_Name__c,Price_Book__c,Company_Master__c,Opportunity__c,Sales_Order__c, Purchase_Requisition__c.CurrencyIsoCode
                FROM Purchase_Requisition__c where id=: opid]; 
        doline= [Select Id, Name,CurrencyIsoCode, Inventory__c, Purchase_Requisition__c,Item_Group__c,Item_Name__c,Tax_Code__c,Quantity__c,Sales_UOM__c,UOM__c,UnitPrice__c,HSN_Code__c,Discount__c
                 From Purchase_Requistion_Line_Item__c Where Purchase_Requisition__c=:pack.id];
    }
    
    public PageReference save() {
        System.debug(pack.Vendor_Name__c);
        if(String.valueOf(pack.Vendor_Name__c) == '' || String.valueOf(pack.Vendor_Name__c) == null) {
            ApexPages.addmessage(new ApexPages.message(ApexPages.severity.WARNING, 'Please select the Vendor'));
            return null;
        }

        Purchase_Order__c i =new Purchase_Order__c();
        i.CurrencyIsoCode=pack.CurrencyIsoCode;
        i.Purchase_Requisition__c=pack.id;
        i.Vendor_Name__c=pack.Vendor_Name__c;
        i.Warehouse__c=pack.Warehouse__c;
        i.PO_Stage__c='Draft';
        i.PO_Date__c=Date.today();
		i.Account_Name__c=pack.Account_Name__c;    
        i.Price_Book__c=pack.Price_Book__c;
        i.Company_Master__c=pack.Company_Master__c;
        i.Opportunity__c=pack.Opportunity__c;
        i.Sales_Order__c=pack.Sales_Order__c;
        insert i; 
        system.debug('i---'+i);
        po=[Select Id, Name From Purchase_Order__c Where id=:i.id];
        system.debug('po---'+po);
        List<Purchase_Order_Item__c> POinsert = new List<Purchase_Order_Item__c>();
        
        for(Purchase_Requistion_Line_Item__c wt:doline){ 
            
            Purchase_Order_Item__c inl = new Purchase_Order_Item__c();
            inl.Purchase_Order__c=po.id;
            inl.CurrencyIsoCode=wt.CurrencyIsoCode;
            inl.Item_Name__c=wt.Item_Name__c;
            inl.Qty__c=wt.Quantity__c;
            inl.UOM_Master__c=wt.UOM__c;
            inl.Unit_Price__c=wt.UnitPrice__c;
            inl.HSN_Master__c=wt.HSN_Code__c;
            inl.Discount_In_Percentage__c=wt.Discount__c;
            inl.Item_Group__c=wt.Item_Group__c;
            inl.Tax_Code__c=wt.Tax_Code__c;
            inl.Inventory__c=wt.Inventory__c;
            inl.Sales_UOM__c=wt.Sales_UOM__c;
            POinsert.add(inl);
            
        }
        system.debug('POinsert---'+POinsert);
        insert POinsert;
        
        PageReference pageRef = new PageReference('/' + opid);
        pageRef.setRedirect(true);
        return pageRef;       
    }
    
    
    public PageReference cancel() {
        
        PageReference pageRef = new PageReference('/' + opid);
        pageRef.setRedirect(true);
        return pageRef;      
    }    
}