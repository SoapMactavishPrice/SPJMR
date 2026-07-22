public class Copy_AddProductOnPurchaseReq {
    public id rid{get;set;}
    public integer pageNo{get;set;}
    public integer noOfRec=10;
    public integer totalRec{get;set;}
    public integer offset{get;set;}
    public Boolean SelectAll{get;set;}
    public boolean islast{get;set;}
    public boolean isFirst{get;set;}
    public integer totalPages{get;set;}
    public Boolean showList{get;set;}
    public Boolean  showForm{get;set;}
    Public String Related{get;set;}
    public String SearchText{get;set;}
    public Map<String,String> valueMap{get;set;}
    public list<wrapProduct> wrapList{get;set;}
    public map<id,id> selectedproduct {get;set;}
    public List<Purchase_Requistion_Line_Item__c> bLineList{get;set;}
    public list<pricebookentry> pList{get;set;}
    public Purchase_Requisition__c oppty{get;set;}
    public list<wrapOpptyLine> opList{get;set;}
    public String pid {get;set;}
    public String uom {get;set;}
    public String qty {get;set;}
    set<String> acctben = new set<String>();
    public List<SelectOption> options { get; set; }
    public Copy_AddProductOnPurchaseReq()
    {
        SearchText=null;
        pageNo=1;
        offset=noOfRec*(pageNo-1);
        showList=true;
        showForm=false;
        isFirst=true;
        selectedproduct=new Map<id,id>();
        wrapList=new list<wrapProduct>();
         SelectAll=false;
        valueMap=new Map<String,String>();
        bLineList=new list<Purchase_Requistion_Line_Item__c>();
        opList=new List<wrapOpptyLine>();
        options = new List<SelectOption>();
        rid=ApexPages.currentPage().getParameters().get('id'); 
        oppty=[select id,name,Account_Name__c,Price_Book__c,CurrencyIsoCode from Purchase_Requisition__c where id=:rid];
        totalPages=[select id,name,Pricebook2Id,ProductCode from pricebookentry where Pricebook2Id=:oppty.Price_Book__c].size()/noOfRec+1;
        
        for(Purchase_Requistion_Line_Item__c ab: [SELECT Id, Name,Item_Name__c,Purchase_Requisition__c FROM Purchase_Requistion_Line_Item__c 
                                       Where  Purchase_Requisition__c=:oppty.id ]){
                                           
                                           system.debug('ab------'+ab);
                                           acctben.add(ab.Item_Name__c );
                                           system.debug('acctben------'+acctben);
                                       }
        
        plist=[select id,name,UnitPrice,ProductCode,Pricing_UOM__c,product2.Description,Product2.In_Stock__c,Product2.UOM_Master__r.Name,Product2.HSN_Code__c,CurrencyIsoCode, Product2Id, Product2.name,product2.Item_No__c,Product2.Item_Group__r.name,product2.Sales_UOM__r.name 
               From pricebookentry where pricebook2id=:oppty.Price_Book__c AND Product2.IsActive=true AND Product2Id NOT IN :acctben AND CurrencyIsoCode=:oppty.CurrencyIsoCode limit:noOfRec offset:offset];
       //AND Product2Id NOT IN :acctben
         System.debug('plist'+plist);
        for(Item_Group_Master__c a:[select id,name from Item_Group_Master__c order by name])
        {
            valueMap.put(a.name,a.id);
            options.add(new SelectOption(a.id, a.name));
        }
        
        for(pricebookentry p:plist)
        {
            wrapList.add(new wrapProduct(p,selectedproduct));    
        }
        System.debug('wrapList'+wrapList);
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
        
       /* if(oppty.Tax_Code__c==null){
            ApexPages.Message msg = new ApexPages.Message(ApexPages.Severity.ERROR,'Please add Tax Code before adding Products ');
            ApexPages.addMessage(msg);
        }*/
    }
    
    public void Search() 
    {
        for(wrapProduct w : wrapList){
            System.debug('www'+w.isChecked);
            if(w.isChecked==true && !selectedproduct.containsKey(w.pro.id))
            {
                TaxDeterminationCls td=new TaxDeterminationCls();
                Map<String,String> values=new Map<string,string>();
                pricebookentry p=w.pro;
                Purchase_Requistion_Line_Item__c op=new Purchase_Requistion_Line_Item__c();
               // op.PricebookEntryId=p.id;
                op.Item_Name__c=p.Product2Id;
                op.Quantity__c=1;
                op.UnitPrice__c=p.UnitPrice;
                op.Sales_UOM__c=p.Pricing_UOM__c;
                op.Purchase_Requisition__c=oppty.Id;
                op.Total_Quantity__c=1;
                op.In_Stock__c=p.Product2.In_Stock__c;
				bLineList.add(op);
                if(!test.isRunningTest()){
                     selectedproduct.put(p.Id,p.Id);
                }
                
                for(UOM_Group__c uom: [select id,name,Alt_UOM__c,Alt_UOM__r.name from UOM_Group__c where Product__c=:p.product2Id])
                {
                  values.put(uom.Alt_UOM__r.name,uom.Alt_UOM__c);  
                }
                opList.add(new wrapOpptyLine(op,values));
            }
        }
        
        pageNo=1;
        offset=noOfRec*(pageNo-1);
        if(!test.isRunningTest()){
            wrapList.clear();
        }
        pList.clear();
        //String RelatedText='%'+Related+'%';
        String FinalText='%'+SearchText+'%';
        System.debug('search text'+SearchText);
        System.debug('Related'+Related);
        if(Related.equals('All'))
        {
            
            pList=[select id,name,UnitPrice,ProductCode,Product2Id,product2.Description,Product2.In_Stock__c,Pricing_UOM__c,Product2.UOM_Master__r.Name,Product2.HSN_Code__c,Product2.name,product2.Item_No__c,Product2.Item_Group__r.name,product2.Sales_UOM__r.name from pricebookentry where pricebook2id=:oppty.Price_book__c and Product2.IsActive=true AND Product2Id NOT IN :acctben AND (product2.name Like:FinalText OR product2.Item_No__c Like:FinalText OR product2.Description Like:FinalText OR product2.ProductCode Like:FinalText)  limit:noOfRec offset:offset];
        }
        else
        {
            pList=[select id,name,UnitPrice,ProductCode,Product2Id,product2.Description,Product2.In_Stock__c,Pricing_UOM__c,Product2.UOM_Master__r.Name,Product2.HSN_Code__c,Product2.name,product2.Item_No__c,Product2.Item_Group__r.name,Product2.Item_Group__r.id,product2.Sales_UOM__r.name from pricebookentry where pricebook2id=:oppty.Price_book__c and Product2.IsActive=true AND Product2Id NOT IN :acctben AND (product2.name Like:FinalText OR product2.Item_No__c Like:FinalText OR product2.Description Like:FinalText OR product2.ProductCode=:FinalText) and Product2.Item_Group__r.id=:Related limit:noOfRec offset:offset];
        }
        for(pricebookentry p:plist)
        {
            wrapList.add(new wrapProduct(p,selectedproduct));    
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
        
    }
    public pageReference nextPage()
    {
        for(wrapProduct w : wrapList){
            System.debug('www'+w.isChecked);
            if(w.isChecked==true && !selectedproduct.containsKey(w.pro.id))
            {
                TaxDeterminationCls td=new TaxDeterminationCls();
                Map<String,String> values=new Map<string,string>();
                pricebookentry p=w.pro;
                Purchase_Requistion_Line_Item__c op=new Purchase_Requistion_Line_Item__c();
               // op.PricebookEntryId=p.id;
                op.Item_Name__c=p.Product2Id;
                op.Quantity__c=1;
                op.UnitPrice__c=p.UnitPrice;
                op.Sales_UOM__c=p.Pricing_UOM__c;
                op.Purchase_Requisition__c=oppty.Id;
                op.Total_Quantity__c=1;
                op.In_Stock__c=p.Product2.In_Stock__c;
				bLineList.add(op);
                if(!test.isRunningTest()){
                     selectedproduct.put(p.Id,p.Id);
                }
                
                for(UOM_Group__c uom: [select id,name,Alt_UOM__c,Alt_UOM__r.name from UOM_Group__c where Product__c=:p.product2Id])
                {
                  values.put(uom.Alt_UOM__r.name,uom.Alt_UOM__c);  
                }
                opList.add(new wrapOpptyLine(op,values));
            }
        }
        if(!test.isRunningTest()){
            wrapList.clear();
        }
        pageNo=pageNo+1;
        offset=noOfRec*(pageNo-1);
        system.debug('SearchText'+SearchText);
        if(SearchText==null)
        {
            system.debug('SearchText'+SearchText);
            pList=[select id,name,UnitPrice,Pricing_UOM__c,ProductCode,Product2.In_Stock__c,Product2Id,Product2.UOM_Master__r.Name,Product2.HSN_Code__c,Product2.name,product2.Item_No__c,Product2.Item_Group__r.name,product2.Sales_UOM__r.name from pricebookentry where Product2.IsActive=true AND pricebook2id=:oppty.Price_book__c  limit:noOfRec offset:offset];
        }  
        else
        {
            String FinalText='%'+SearchText+'%';
            System.debug('search text'+SearchText);
            
            if(Related.equals('All'))
            {
                pList=[select id,name,UnitPrice,Pricing_UOM__c,ProductCode,Product2.In_Stock__c,Product2Id,Product2.UOM_Master__r.Name,Product2.HSN_Code__c,Product2.name,product2.Item_No__c,Product2.Item_Group__r.name,product2.Sales_UOM__r.name from pricebookentry where Product2.IsActive=true AND pricebook2id=:oppty.Price_book__c and Product2.IsActive=true AND Product2Id NOT IN :acctben AND product2.name Like:FinalText  limit:noOfRec offset:offset];
            }
            else
            {
                pList=[select id,name,UnitPrice,Pricing_UOM__c,ProductCode,Product2.In_Stock__c,Product2Id,Product2.UOM_Master__r.Name,Product2.HSN_Code__c,Product2.name,product2.Item_No__c,Product2.Item_Group__r.name,Product2.Item_Group__r.id,product2.Sales_UOM__r.name from pricebookentry where pricebook2id=:oppty.Price_book__c and Product2.IsActive=true AND Product2Id NOT IN :acctben AND product2.name Like:FinalText and Product2.Item_Group__r.id=:Related limit:noOfRec offset:offset];
            } 
        }
        for(pricebookentry p:pList)
        {
            wrapList.add(new wrapProduct(p,selectedproduct));    
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
        
        for(wrapProduct w : wrapList){
            System.debug('www'+w.isChecked);
            if(w.isChecked==true && !selectedproduct.containsKey(w.pro.id))
            {
                TaxDeterminationCls td=new TaxDeterminationCls();
                Map<String,String> values=new Map<string,string>();
                pricebookentry p=w.pro;
                Purchase_Requistion_Line_Item__c op=new Purchase_Requistion_Line_Item__c();
               // op.PricebookEntryId=p.id;
                op.Item_Name__c=p.Product2Id;
                op.Quantity__c=1;
                op.UnitPrice__c=p.UnitPrice;
                op.Sales_UOM__c=p.Pricing_UOM__c;
                op.Purchase_Requisition__c=oppty.Id;
                op.Total_Quantity__c=1;
                op.In_Stock__c=p.Product2.In_Stock__c;
				bLineList.add(op);
                if(!test.isRunningTest()){
                     selectedproduct.put(p.Id,p.Id);
                }
                for(UOM_Group__c uom: [select id,name,Alt_UOM__c,Alt_UOM__r.name from UOM_Group__c where Product__c=:p.product2Id])
                {
                  values.put(uom.Alt_UOM__r.name,uom.Alt_UOM__c);  
                }
                opList.add(new wrapOpptyLine(op,values));
            }
        }
        if(!test.isRunningTest()){
            wrapList.clear();
        }
        pageNo=pageNo-1;
        offset=noOfRec*(pageNo-1);
        
        if(SearchText==null)
        {
            
            pList=[select id,name,UnitPrice,Pricing_UOM__c,ProductCode,Product2.In_Stock__c,Product2Id,Product2.UOM_Master__r.Name,Product2.HSN_Code__c,Product2.name,product2.Item_No__c,Product2.Item_Group__r.name,product2.Sales_UOM__r.name from pricebookentry where pricebook2id=:oppty.Price_book__c  limit:noOfRec offset:offset];
        }  
        else
        {
            String FinalText='%'+SearchText+'%';
            System.debug('search text'+SearchText);
            
            if(Related.equals('All'))
            {
                pList=[select id,name,UnitPrice,Pricing_UOM__c,ProductCode,Product2.In_Stock__c,Product2Id,Product2.UOM_Master__r.Name,Product2.HSN_Code__c,Product2.name,product2.Item_No__c,Product2.Item_Group__r.name,product2.Sales_UOM__r.name from pricebookentry where pricebook2id=:oppty.Price_book__c and Product2.IsActive=true AND Product2Id NOT IN :acctben AND product2.name Like:FinalText  limit:noOfRec offset:offset];
            }
            else
            {
                pList=[select id,name,UnitPrice,Pricing_UOM__c,ProductCode,Product2.In_Stock__c,Product2Id,Product2.UOM_Master__r.Name,Product2.HSN_Code__c,Product2.name,product2.Item_No__c,Product2.Item_Group__r.name,Product2.Item_Group__r.id,product2.Sales_UOM__r.name from pricebookentry where Product2.IsActive=true AND pricebook2id=:oppty.Price_book__c and Product2Id NOT IN :acctben AND product2.name Like:FinalText and Product2.Item_Group__r.id=:Related limit:noOfRec offset:offset];
            }
        }
        for(pricebookentry p:plist)
        {
            wrapList.add(new wrapProduct(p,selectedproduct));    
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
    public void AddRec() 
    {
        showList=false;
        showForm=true;
        
        for(wrapProduct w : wrapList){
            System.debug('www'+w.isChecked);
            System.debug('www ******************'+selectedproduct.containsKey(w.pro.id));
            if(w.isChecked==true && !selectedproduct.containsKey(w.pro.id))
            {
                TaxDeterminationCls td=new TaxDeterminationCls();
                Map<String,String> values=new Map<string,string>();
                pricebookentry p=w.pro;
                Purchase_Requistion_Line_Item__c op=new Purchase_Requistion_Line_Item__c();
               // op.PricebookEntryId=p.id;
                op.Item_Name__c=p.Product2Id;
                op.Quantity__c=1;
                op.UnitPrice__c=p.UnitPrice;
                op.Sales_UOM__c=p.Pricing_UOM__c;
                op.Purchase_Requisition__c=oppty.Id;
                op.Total_Quantity__c=1;
                op.In_Stock__c=p.Product2.In_Stock__c;
				bLineList.add(op);
                for(UOM_Group__c uom: [select id,name,Alt_UOM__c,Alt_UOM__r.name from UOM_Group__c where Product__c=:p.product2Id])
                {
                  if(uom.Alt_UOM__r.name!=null)
                  values.put(uom.Alt_UOM__r.name,uom.Alt_UOM__c);  
                }
                System.debug('Values'+values);
                opList.add(new wrapOpptyLine(op,values)); 
            }
        }
    }
     public pageReference saveRec()
    {
        //insert bLineList;
        List<Purchase_Requistion_Line_Item__c> lineList=new list<Purchase_Requistion_Line_Item__c>();
        for(wrapOpptyLine o:opList)
        {
          lineList.add(o.op);  
        }
        insert lineList;
        PageReference pageRef = new PageReference('/'+rid); 
        pageRef.setRedirect(true);
        return pageRef;
    }
    
    public void selectAll()
    {
        System.debug('in select all');
        for(wrapProduct w : wrapList){
            if(SelectAll)
                w.isChecked=true;
            else
                w.isChecked=false;
        }
        
    }
    public pageReference cancel()
    {
        PageReference pageRef = new PageReference('/'+rid);
        pageRef.setRedirect(true);
        return pageRef;
    }
    public class wrapProduct{ 
        public pricebookentry pro{get;set;}
        public boolean isChecked{get;set;}
        public wrapProduct(pricebookentry i,map<id,id> selectedproduct){
            pro = i;
            if(selectedproduct.containsKey(pro.id))
                isChecked = true;
            else
                isChecked = false;  
        }
    } 
	 public class wrapOpptyLine{
        public Purchase_Requistion_Line_Item__c op{get;set;}
        public Map<String,String> vMap{get;set;}
        public wrapOpptyLine(Purchase_Requistion_Line_Item__c opl,Map<String,String> values)
        {
          op=opl;
          vMap=values;
            
        }
        
    }
}