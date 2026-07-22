public class AddProductOnPurchaseOrder {
 public map<id,id> selectedproduct {get;set;}
    public list<pricebookentry> pList{get;set;}
    public String SearchText{get;set;}
    public Boolean SelectAll{get;set;}
    public List<Purchase_Order_Item__c> bLineList{get;set;}
    public list<wrapProduct> wrapList{get;set;}
    public Boolean showList{get;set;}
    public Boolean  showForm{get;set;}
    public id bId{get;set;}
    public Purchase_Order__c purchOrd{get;set;}
    public integer pageNo{get;set;}
    public integer noOfRec=10;
    public integer totalRec{get;set;}
    public integer offset{get;set;}
    public boolean islast{get;set;}
    public boolean isFirst{get;set;}
    public integer totalPages{get;set;}
    public List<String> pickListValuesList{get;set;}
    public Map<String,String> valueMap{get;set;}
    Public String Related{get;set;}
    public Map<String,String> values{get;set;}
    public list<wrapOpptyLine> opList{get;set;}
    set<String> acctben = new set<String>();
    
      public AddProductOnPurchaseOrder(){
        
       selectedproduct=new Map<id,id>();
        SearchText=null;
        pageNo=1;
        offset=noOfRec*(pageNo-1);
        bId=ApexPages.CurrentPage().getparameters().get('id');
        showList=true;
        showForm=false;
        isFirst=true;
        wrapList=new list<wrapProduct>();
        SelectAll=false;
        bLineList=new list<Purchase_Order_Item__c>();
        opList=new List<wrapOpptyLine>();
        valueMap=new Map<String,String>();
        purchOrd=[select id,name,Price_Book__c, Purchase_Order__c.CurrencyIsoCode from Purchase_Order__c where id=:bId];
        totalPages=[select id,name,Pricebook2Id,ProductCode from pricebookentry where Pricebook2Id=:purchOrd.Price_Book__c].size()/noOfRec+1;
        System.debug('totalPages'+totalPages);
        for(Purchase_Order_Item__c ab: [SELECT Id,Name,Item_Name__c,Purchase_Order__c,Item_Name__r.Available__c FROM Purchase_Order_Item__c 
                                       Where  Purchase_Order__c=:purchOrd.id ]){
                                           
                                           system.debug('ab------'+ab);
                                           acctben.add(ab.Item_Name__c );
                                           system.debug('acctben------'+acctben);
                                       }
        
         pList=[select id,name,UnitPrice,ProductCode,Pricing_UOM__c,Product2.Pricing_UOM__c,product2.Description,Product2.In_Stock__c,Product2.UOM_Master__r.Name,Product2.HSN_Code__c,CurrencyIsoCode, Product2Id, Product2.name,product2.Item_No__c,Product2.Item_Group__r.name,product2.Sales_UOM__r.name, 
               Product2.Tax_Code__c,Product2.Available__c From pricebookentry where pricebook2id=:purchOrd.Price_Book__c AND Product2.IsActive=true AND Product2Id NOT IN :acctben AND CurrencyIsoCode=:purchOrd.CurrencyIsoCode limit:noOfRec offset:offset];
       //AND Product2Id NOT IN :acctben
         System.debug('plist'+plist);
        for(Item_Group_Master__c a:[select id,name from Item_Group_Master__c])
        {
            valueMap.put(a.name,a.id);
        }
        for(pricebookentry pr:pList)
        {
            wrapList.add(new wrapProduct(pr,selectedproduct,values)); 
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

    public void Search() 
    {
        for(wrapProduct w : wrapList){
            System.debug('www'+w.isChecked);
            if(w.isChecked==true && !selectedproduct.containsKey(w.pro.id))
            {
                Map<String,String> values=new Map<string,string>();
                System.debug('www'+w.isChecked);
                pricebookentry p=w.pro;
                Purchase_Order_Item__c bl=new Purchase_Order_Item__c();
                bl.Purchase_Order__c=purchOrd.id;
                bl.Item_Name__c=p.Product2Id;
                bl.UOM_Master__c=p.Product2.UOM_Master__c;
                bl.Sales_UOM__c=p.Product2.Pricing_UOM__c;
                bl.Qty__c=1;
                bl.Unit_Price__c=p.UnitPrice;
                bl.Tax_Code__c=p.Product2.Tax_Code__c;
                bl.Available__c=p.Product2.Available__c;
                System.debug('Available__c'+p.Product2.Available__c);
              //  bl.Sales_UOM__c=p.Pricing_UOM__c;
                /*bl.Make__c=p.Make__c;
                bl.Image_Url__c=p.Image_Url__c;
                bl.Technical_Specification__c=p.Technical_Specification__c;
                bl.Item_Type__c=p.Item_Type__c;
                bl.IS_IEC_standard__c=p.IS_IEC_standard__c;
                bl.Item_Particular__c=p.Item_Particular__c;
                bl.Current_Stock__c=p.Current_Stock__c;
                bl.Product_Code__c=p.ProductCode;*/
                bLineList.add(bl);
                selectedproduct.put(p.Id,p.Id);
                
                for(UOM_Group__c uom: [select id,name,Alt_UOM__c,Alt_UOM__r.name from UOM_Group__c where Product__c=:p.Id])
                {
                  values.put(uom.Alt_UOM__r.name,uom.Alt_UOM__c);  
                }
                opList.add(new wrapOpptyLine(bl,values));
            }
        }
        //String relatedText=selectedValues(Related);
        pageNo=1;
        offset=noOfRec*(pageNo-1);
        wrapList.clear();
        pList.clear();
        //String RelatedText='%'+Related+'%';
        String FinalText='%'+SearchText+'%';
        System.debug('search text'+SearchText);
        
        if(Related.equals('All'))
        {
            
            pList=[select id,name,UnitPrice,ProductCode,Product2Id,Product2.In_Stock__c,Pricing_UOM__c,Product2.UOM_Master__r.Name,Product2.HSN_Code__c,product2.Description,Product2.name,product2.Item_No__c,Product2.Item_Group__r.name,product2.Sales_UOM__r.name, Product2.Pricing_UOM__c,
                   Product2.Available__c,Product2.Tax_Code__c from pricebookentry where pricebook2id=:purchOrd.Price_book__c and Product2.IsActive=true AND Product2Id NOT IN :acctben AND (product2.name Like:FinalText OR product2.Description Like:FinalText OR product2.Item_No__c Like:FinalText OR product2.ProductCode Like:FinalText)  limit:noOfRec offset:offset];
        }
        else
        {
            pList=[select id,name,UnitPrice,ProductCode,Product2Id,Product2.In_Stock__c,Pricing_UOM__c,Product2.UOM_Master__r.Name,Product2.HSN_Code__c,Product2.name,product2.Item_No__c,Product2.Item_Group__r.name,Product2.Item_Group__r.id,product2.Sales_UOM__r.name,product2.Description, Product2.Pricing_UOM__c,
                   Product2.Available__c, Product2.Tax_Code__c from pricebookentry where pricebook2id=:purchOrd.Price_book__c and Product2.IsActive=true AND Product2Id NOT IN :acctben AND (product2.name Like:FinalText OR product2.Name Like:FinalText OR product2.Item_No__c Like:FinalText OR product2.ProductCode=:FinalText) and Product2.Item_Group__r.id=:Related limit:noOfRec offset:offset];
        }
        for(pricebookentry p:plist)
        {
            wrapList.add(new wrapProduct(p,selectedproduct,values));    
        }
        System.debug('totalPages'+totalPages);
        System.debug('pageNo'+pageNo); 
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
        //return null;
    }
    public void AddRec() 
    {
        showList=false;
        showForm=true;
        system.debug('Select All'+SelectAll);
        for(wrapProduct w : wrapList){
            System.debug('www : '+w.isChecked + ' : ' + !selectedproduct.containsKey(w.pro.id));
            if(w.isChecked==true && !selectedproduct.containsKey(w.pro.id))
            {
                Map<String,String> values=new Map<string,string>();
                System.debug('www'+w.isChecked);
                pricebookentry p=w.pro;
                Purchase_Order_Item__c bl=new Purchase_Order_Item__c();
                bl.Purchase_Order__c=purchOrd.id;
                bl.Item_Name__c=p.Product2Id;
                bl.UOM_Master__c=p.Product2.UOM_Master__c;
                bl.Sales_UOM__c=p.Product2.Pricing_UOM__c;
                bl.Qty__c=1;
                bl.Unit_Price__c=p.UnitPrice;
                bl.Tax_Code__c=p.Product2.Tax_Code__c;
                bl.Available__c=p.Product2.Available__c;
                System.debug('Available__c'+p.Product2.Available__c);
                /*bl.Make__c=p.Make__c;
                bl.Image_Url__c=p.Image_Url__c;
                bl.Technical_Specification__c=p.Technical_Specification__c;
                bl.Item_Type__c=p.Item_Type__c;
                bl.IS_IEC_standard__c=p.IS_IEC_standard__c;
                bl.Item_Particular__c=p.Item_Particular__c;
                bl.Current_Stock__c=p.Current_Stock__c;
                bl.Product_Code__c=p.ProductCode;*/
                bLineList.add(bl);
                //System.debug('www'+values);
                for(UOM_Group__c uom: [select id,name,Alt_UOM__c,Alt_UOM__r.name from UOM_Group__c where Product__c=:p.Id])
                {
                    System.debug('uom'+uom);
                  values.put(uom.Alt_UOM__r.name,uom.Alt_UOM__c);  
                }

                System.debug('www'+values);
                opList.add(new wrapOpptyLine(bl,values));
                
            }
            
        }
        
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
    
  /*  public pageReference saveRec()
    {
        insert bLineList;
        list<BOM__c> baList=new List<BOM__c>();
        for(BOM_Item__c b:bLineList){
            //if(b.Child_BOM_Attached__c){
                BOM__c ba=new BOM__c();
                ba.Parent_BOM__c=b.BOM__c;
                //ba.BOM_Line_Item__c=b.id;
                //ba.Project__c=bom.project__c;
                //ba.Active__c=true;
                baList.add(ba);
            //}
            
        }
        insert baList;
        
        PageReference pageRef = new PageReference('/'+bId);
        pageRef.setRedirect(true);
        return pageRef;
    }*/



    public pageReference saveRec()
    {
        //insert bLineList;
        List<Purchase_Order_Item__c> lineList=new list<Purchase_Order_Item__c>();
        for(wrapOpptyLine o:opList)
        {
          lineList.add(o.op);  
        }
        insert lineList;
        PageReference pageRef = new PageReference('/'+bId); 
        pageRef.setRedirect(true);
        return pageRef;
    }


    
    public pageReference cancel()
    {
        PageReference pageRef = new PageReference('/'+bId);
        pageRef.setRedirect(true);
        return pageRef;
    }
    
    public pageReference nextPage()
    {
        
        for(wrapProduct w : wrapList){
            System.debug('www'+w.isChecked);
            if(w.isChecked==true && !selectedproduct.containsKey(w.pro.id))
            {
                 Map<String,String> values=new Map<string,string>();
                System.debug('www'+w.isChecked);
                pricebookentry p=w.pro;
                Purchase_Order_Item__c bl=new Purchase_Order_Item__c();
                bl.Purchase_Order__c=purchOrd.id;
                bl.Item_Name__c=p.Product2Id;
                bl.UOM_Master__c=p.Product2.UOM_Master__c;
                bl.Sales_UOM__c=p.Product2.Pricing_UOM__c;
                bl.Qty__c=1;
                bl.Unit_Price__c=p.UnitPrice;
                bl.Available__c=p.Product2.Available__c;
                System.debug('p.Product2.Available__c'+p.Product2.Available__c);
                /*bl.Make__c=p.Make__c;
                bl.Image_Url__c=p.Image_Url__c;
                bl.Technical_Specification__c=p.Technical_Specification__c;
                bl.Item_Type__c=p.Item_Type__c;
                bl.IS_IEC_standard__c=p.IS_IEC_standard__c;
                bl.Item_Particular__c=p.Item_Particular__c;
                bl.Current_Stock__c=p.Current_Stock__c;
                bl.Product_Code__c=p.ProductCode;*/
                bLineList.add(bl);
                selectedproduct.put(p.Id,p.Id);
                
                 for(UOM_Group__c uom: [select id,name,Alt_UOM__c,Alt_UOM__r.name from UOM_Group__c where Product__c=:p.Id])
                {
                  values.put(uom.Alt_UOM__r.name,uom.Alt_UOM__c);  
                }
               // opList.add(new wrapOpptyLine(op,values));
                  opList.add(new wrapOpptyLine(bl,values));
                
                
            }
        }
        wrapList.clear();
        pageNo=pageNo+1;
        offset=noOfRec*(pageNo-1);
        
        if(SearchText==null)
        {
            pList=[select id,name,UnitPrice,Pricing_UOM__c,ProductCode,Product2.In_Stock__c,Product2Id,Product2.UOM_Master__r.Name,Product2.HSN_Code__c,Product2.name,product2.Item_No__c,Product2.Item_Group__r.name,product2.Sales_UOM__r.name, 
                   Product2.Tax_Code__c,Product2.Available__c,Product2.Pricing_UOM__c from pricebookentry where Product2.IsActive=true AND pricebook2id=:purchOrd.Price_book__c  limit:noOfRec offset:offset];
            
        }
        else
        {
            String FinalText='%'+SearchText+'%';
            
            if(Related.equals('All'))
            {
                pList=[select id,name,UnitPrice,Pricing_UOM__c,ProductCode,Product2.In_Stock__c,Product2Id,Product2.UOM_Master__r.Name,Product2.HSN_Code__c,Product2.name,product2.Item_No__c,Product2.Item_Group__r.name,product2.Sales_UOM__r.name, 
                       Product2.Tax_Code__c,Product2.Available__c,Product2.Pricing_UOM__c,Product2.Description from pricebookentry where Product2.IsActive=true AND pricebook2id=:purchOrd.Price_book__c and Product2.IsActive=true AND Product2Id NOT IN :acctben AND product2.name Like:FinalText  limit:noOfRec offset:offset];
            }
            else
            {
                pList=[select id,name,UnitPrice,Pricing_UOM__c,ProductCode,Product2.In_Stock__c,Product2Id,Product2.UOM_Master__r.Name,Product2.HSN_Code__c,Product2.name,product2.Item_No__c,Product2.Item_Group__r.name,Product2.Item_Group__r.id,product2.Sales_UOM__r.name, 
                       Product2.Tax_Code__c,Product2.Available__c,Product2.Pricing_UOM__c,Product2.Description from pricebookentry where pricebook2id=:purchOrd.Price_book__c and Product2.IsActive=true AND Product2Id NOT IN :acctben AND product2.name Like:FinalText and Product2.Item_Group__r.id=:Related limit:noOfRec offset:offset];
            } 
            
        }
        
        for(pricebookentry pr:pList)
        {
            wrapList.add(new wrapProduct(pr,selectedproduct,values)); 
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
                System.debug('www'+w.isChecked);
                pricebookentry p=w.pro;
                Purchase_Order_Item__c bl=new Purchase_Order_Item__c();
                bl.Purchase_Order__c=purchOrd.id;
                bl.Item_Name__c=p.Product2Id;
                bl.UOM_Master__c=p.Product2.UOM_Master__c;
                bl.Sales_UOM__c=p.Product2.Pricing_UOM__c;
                bl.Qty__c=1;
                bl.Unit_Price__c=p.UnitPrice;
                bLineList.add(bl);
                selectedproduct.put(p.Id,p.Id);
            }
        }
        wrapList.clear();
        pageNo=pageNo-1;
        offset=noOfRec*(pageNo-1);
        
        if(SearchText==null) 
        {
            pList=[select id,name,UnitPrice,Pricing_UOM__c,ProductCode,Product2.In_Stock__c,Product2Id,Product2.UOM_Master__r.Name,Product2.HSN_Code__c,Product2.name,product2.Item_No__c,Product2.Item_Group__r.name,product2.Sales_UOM__r.name,
                   Product2.Tax_Code__c,Product2.Pricing_UOM__c,Product2.Description from pricebookentry where pricebook2id=:purchOrd.Price_book__c  limit:noOfRec offset:offset];
            
            
        }
        else
        {
            String FinalText='%'+SearchText+'%';
            
            if(Related.equals('All'))
            {
                pList=[select id,name,UnitPrice,Pricing_UOM__c,ProductCode,Product2.In_Stock__c,Product2Id,Product2.UOM_Master__r.Name,Product2.HSN_Code__c,Product2.name,product2.Item_No__c,Product2.Item_Group__r.name,product2.Sales_UOM__r.name, 
                       Product2.Tax_Code__c,Product2.Pricing_UOM__c,Product2.Description from pricebookentry where pricebook2id=:purchOrd.Price_book__c and Product2.IsActive=true AND Product2Id NOT IN :acctben AND product2.name Like:FinalText  limit:noOfRec offset:offset];
            }
            else
            {
                pList=[select id,name,UnitPrice,Pricing_UOM__c,ProductCode,Product2.In_Stock__c,Product2Id,Product2.UOM_Master__r.Name,Product2.HSN_Code__c,Product2.name,product2.Item_No__c,Product2.Item_Group__r.name,Product2.Item_Group__r.id,product2.Sales_UOM__r.name,
                       Product2.Tax_Code__c,Product2.Pricing_UOM__c,Product2.Description from pricebookentry where Product2.IsActive=true AND pricebook2id=:purchOrd.Price_book__c and Product2Id NOT IN :acctben AND product2.name Like:FinalText and Product2.Item_Group__r.id=:Related limit:noOfRec offset:offset];
            }
           
        }
        
        for(pricebookentry pr:pList)
        {
            wrapList.add(new wrapProduct(pr,selectedproduct,values)); 
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
    public class wrapProduct{ 
        public pricebookentry pro{get;set;}
        public boolean isChecked{get;set;}
        public wrapProduct(pricebookentry i,map<id,id> selectedproduct,Map<String,String> values){
            pro = i;
            if(selectedproduct.containsKey(pro.id))
                isChecked = true;
            else
                isChecked = false;  
        }
    }  

    public class wrapOpptyLine
    {
        public Purchase_Order_Item__c op{get;set;}
        public Map<String,String> vMap{get;set;}
        public wrapOpptyLine(Purchase_Order_Item__c opl,Map<String,String> values)
        {
          op=opl;
          vMap=values;
            
        }
        
    }

    //public List<BOM_Item__c> bLineList{get;set;}
}