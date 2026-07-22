public class CreateRFQ {
    
    public Id opid {get;set;}        
    public Purchase_Requisition__c purch {get;set;}
    public List<Purchase_Requistion_Line_Item__c> prline {get;set;}
    public  RFQ__c rfq{get;set;}
   
    public CreateRFQ() {
        
        opid = ApexPages.currentPage().getParameters().get('id');
        
        purch = [ SELECT Id, Name, Vendor_Name__c,Warehouse__c,CurrencyIsoCode,Account_Name__c,Price_Book__c,
                Company_Master__c,Opportunity__c,Sales_Order__c,Maker__c, Checker__c 
                FROM Purchase_Requisition__c where id=: opid]; 

        prline= [Select Id, Name,CurrencyIsoCode, Inventory__c, Purchase_Requisition__c,Item_Group__c,
                Item_Name__c,Tax_Code__c,Quantity__c,UnitPrice__c,Sales_UOM__c,UOM__c,HSN_Code__c,Discount__c
                From Purchase_Requistion_Line_Item__c Where Purchase_Requisition__c=:purch.id];
    }
    
    public PageReference save() {
        
        RFQ__c r = new RFQ__c();
		r.CurrencyIsoCode        	= purch.CurrencyIsoCode;
		r.Purchase_Requisition__c   = purch.id;
		r.Warehouse__c           	= purch.Warehouse__c;
		r.RFQ_Date__c            	= System.today();
		r.Maker__c               	= purch.Maker__c;
		r.Checker__c             	= purch.Checker__c;
		r.Price_Book__c          	= purch.Price_Book__c;
		r.Company_Master__c      	= purch.Company_Master__c;
        
        //r.RFQ_Stage__c='Draft';
		//r.Account_Name__c=purch.Account_Name__c;    
        //r.Opportunity__c=purch.Opportunity__c;
        //r.Sales_Order__c=purch.Sales_Order__c;

        insert r; 

        List<RFQ_Item__c> rfqinsert = new List<RFQ_Item__c>();
        
        for(Purchase_Requistion_Line_Item__c prl:prline) { 
            RFQ_Item__c inlt = new RFQ_Item__c();
			inlt.RFQ__c         	= r.Id;
			inlt.CurrencyIsoCode	= prl.CurrencyIsoCode;
			inlt.Item_Name__c   	= prl.Item_Name__c;
			inlt.Quantity__c    	= prl.Quantity__c;
			inlt.UOM__c         	= prl.Sales_UOM__c;
            inlt.UOM_Master__c      = prl.UOM__c;
			inlt.Unit_Price__c  	= prl.UnitPrice__c;
			inlt.HSN_Code__c    	= prl.HSN_Code__c;
			inlt.Discount__c    	= prl.Discount__c;
			inlt.Item_Group__c  	= prl.Item_Group__c;
			inlt.Tax_Code__c    	= prl.Tax_Code__c;
            //inl.Inventory__c=wt.Inventory__c;
            //inl.Purchase_Order__c=po.id;
                        
            rfqinsert.add(inlt);
            //system.debug('rfqinsert'+rfqinsert);
            
        }
        insert rfqinsert;
        //system.debug('rfqinsert'+rfqinsert);
        
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