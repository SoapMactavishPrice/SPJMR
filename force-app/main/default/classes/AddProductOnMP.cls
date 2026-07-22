public class AddProductOnMP {
    public map<id,id> selectedproduct {get;set;}
    public list<pricebookentry> pList{get;set;}
    public String SearchText{get;set;}
    public Boolean SelectAll{get;set;}
    public List<Material_Planning_Item__c> bLineList{get;set;}
    public list<wrapProduct> wrapList{get;set;}
    public Boolean showList{get;set;}
    public Boolean  showForm{get;set;}
    public id bId{get;set;}
    public Material_Planning__c bom{get;set;}
    public integer pageNo{get;set;}
    public integer noOfRec=10;
    public integer totalRec{get;set;}
    public integer offset{get;set;}
    public boolean islast{get;set;}
    public boolean isFirst{get;set;}
    public integer totalPages{get;set;}
    //public List<String> pickListValuesList{get;set;}
    public Map<String,String> valueMap{get;set;}
    Public String Related{get;set;}
    public Map<String,String> values{get;set;}
    public list<wrapOpptyLine> opList{get;set;}
    public List<SelectOption> options { get; set; }
    
    public AddProductOnMP(){
        
       selectedproduct=new Map<id,id>();
        /* List<String> pickListValuesList= new List<String>();
        Schema.DescribeFieldResult fieldResult = BOM_Item__c.Group__c.getDescribe();
        List<Schema.PicklistEntry> ple = fieldResult.getPicklistValues();
        for( Schema.PicklistEntry pickListVal : ple){
            pickListValuesList.add(pickListVal.getLabel());
        } 
        valueMap=new Map<String,String>();
        for(String a:pickListValuesList)
        {
            valueMap.put(a,a);
        }
        */
        SearchText=null;
        pageNo=1;
        offset=noOfRec*(pageNo-1);
        bId=ApexPages.CurrentPage().getparameters().get('id');
        showList=true;
        showForm=false;
        isFirst=true;
        wrapList=new list<wrapProduct>();
        SelectAll=false;
        bLineList=new list<Material_Planning_Item__c>();
        opList=new List<wrapOpptyLine>();
        options = new List<SelectOption>();
        valueMap=new Map<String,String>();
        bom=[select id,Name,CurrencyIsoCode,Price_Book__c From Material_Planning__c where id=:bId];
        //totalPages=[Select id,name, UOM_Master__r.Name from Product2 where isActive=true].size()/noOfRec+1;
        totalPages=[select id,name,Pricebook2Id,ProductCode from pricebookentry where Pricebook2Id=:bom.Price_Book__c].size()/noOfRec+1;
        System.debug('totalPages'+totalPages);
        plist=[select id,name,UnitPrice,ProductCode,Pricing_UOM__c,Product2.In_Stock__c,product2.Description,Product2.UOM_Master__r.Name,Product2.HSN_Code__c,CurrencyIsoCode, Product2Id, Product2.name,product2.Item_No__c,Product2.Item_Group__r.name,product2.Sales_UOM__r.name 
               From pricebookentry where pricebook2id=:bom.Price_Book__c AND Product2.IsActive=true AND CurrencyIsoCode=:bom.CurrencyIsoCode limit:noOfRec offset:offset];

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
                Material_Planning_Item__c bl=new Material_Planning_Item__c();
                bl.Material_Planning__c=bom.id;
                bl.Item_Name__c=p.Product2Id;
                bl.UOM__c=p.Product2.UOM_Master__c;
                bl.BOM_Quantity__c=1;
                bl.In_Stock__c=p.Product2.In_Stock__c;
                bl.Sales_UOM__c=p.Pricing_UOM__c;
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
        
        if(!Test.isRunningTest())
            wrapList.clear();
        
        pList.clear();
        //String RelatedText='%'+Related+'%';
        String FinalText='%'+SearchText+'%';
        System.debug('search text'+SearchText);
        
        if(Related.equals('All'))
        {  
           // totalPages=[Select id,name from Product2 where (name LIKE :FinalText OR ProductCode LIKE:FinalText) AND isActive=true ].size()/noOfRec+1;
            
            pList=[select id,name,UnitPrice,ProductCode,Product2Id,Product2.In_Stock__c,product2.Description,Pricing_UOM__c,Product2.UOM_Master__r.Name,Product2.HSN_Code__c,Product2.name,product2.Item_No__c,Product2.Item_Group__r.name,product2.Sales_UOM__r.name
                   from pricebookentry where pricebook2id=:bom.Price_book__c and Product2.IsActive=true AND (product2.name Like:FinalText OR product2.Item_No__c Like:FinalText OR product2.Description Like:FinalText OR product2.ProductCode Like:FinalText)  limit:noOfRec offset:offset];

        }
        else
        {
            pList=[select id,name,UnitPrice,ProductCode,Product2Id,Product2.In_Stock__c,product2.Description,Pricing_UOM__c,Product2.UOM_Master__r.Name,Product2.HSN_Code__c,Product2.name,product2.Item_No__c,Product2.Item_Group__r.name,Product2.Item_Group__r.id,product2.Sales_UOM__r.name 
                   from pricebookentry where pricebook2id=:bom.Price_book__c and Product2.IsActive=true AND (product2.name Like:FinalText OR product2.Item_No__c Like:FinalText OR product2.Description Like:FinalText OR product2.ProductCode=:FinalText ) and Product2.Item_Group__r.id=:Related limit:noOfRec offset:offset];
            
        }
        System.debug('pList'+pList);
        System.debug('pListvalues'+values);
        for(pricebookentry pr2:pList)
        {
            wrapList.add(new wrapProduct(pr2,selectedproduct,values)); 
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
    
    public pageReference nextPage(){
        
        for(wrapProduct w : wrapList){
            System.debug('www'+w.isChecked);
            if(w.isChecked==true && !selectedproduct.containsKey(w.pro.id))
            {
                 Map<String,String> values=new Map<string,string>();
                System.debug('www'+w.isChecked);
                pricebookentry p=w.pro;
                Material_Planning_Item__c bl=new Material_Planning_Item__c();
                bl.Material_Planning__c=bom.id;
                bl.Item_Name__c=p.Product2Id;
                bl.UOM__c=p.Product2.UOM_Master__c;
                bl.BOM_Quantity__c=1;
                bl.In_Stock__c=p.Product2.In_Stock__c;
                bl.Sales_UOM__c=p.Pricing_UOM__c;
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
        if(!Test.isRunningTest())
            wrapList.clear();
        
        pageNo=pageNo+1;
        offset=noOfRec*(pageNo-1);
        
        if(SearchText==null)
        {
            pList=[select id,name,UnitPrice,Pricing_UOM__c,ProductCode,product2.Description,Product2.In_Stock__c,Product2Id,Product2.UOM_Master__r.Name,Product2.HSN_Code__c,Product2.name,product2.Item_No__c,Product2.Item_Group__r.name,product2.Sales_UOM__r.name 
                   from pricebookentry where Product2.IsActive=true AND pricebook2id=:bom.Price_book__c  limit:noOfRec offset:offset];
            
        }
        else
        {
            String FinalText='%'+SearchText+'%';
            
            if(Related.equals('All'))
            {
                pList=[select id,name,UnitPrice,Pricing_UOM__c,ProductCode,product2.Description,Product2.In_Stock__c,Product2Id,Product2.UOM_Master__r.Name,Product2.HSN_Code__c,Product2.name,product2.Item_No__c,Product2.Item_Group__r.name,product2.Sales_UOM__r.name 
                       from pricebookentry where Product2.IsActive=true AND pricebook2id=:bom.Price_book__c and Product2.IsActive=true AND product2.name Like:FinalText  limit:noOfRec offset:offset];
            }
            else
            {
                pList=[select id,name,UnitPrice,Pricing_UOM__c,product2.Description,ProductCode,Product2.In_Stock__c,Product2Id,Product2.UOM_Master__r.Name,Product2.HSN_Code__c,Product2.name,product2.Item_No__c,Product2.Item_Group__r.name,Product2.Item_Group__r.id,product2.Sales_UOM__r.name
                       from pricebookentry where pricebook2id=:bom.Price_book__c and Product2.IsActive=true AND product2.name Like:FinalText and Product2.Item_Group__r.id=:Related limit:noOfRec offset:offset];
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
    public pageReference prePage(){
        for(wrapProduct w : wrapList){
            System.debug('www'+w.isChecked);
            if(w.isChecked==true && !selectedproduct.containsKey(w.pro.id))
            {
                System.debug('www'+w.isChecked);
                pricebookentry p=w.pro;
                Material_Planning_Item__c bl=new Material_Planning_Item__c();
                bl.Material_Planning__c=bom.id;
                bl.Item_Name__c=p.Product2Id;
                bl.UOM__c=p.Product2.UOM_Master__c;
                bl.BOM_Quantity__c=1;
                bl.In_Stock__c=p.Product2.In_Stock__c;
                bl.Sales_UOM__c=p.Pricing_UOM__c;
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
            }
        }
        if(!Test.isRunningTest())
            wrapList.clear();
        
        pageNo=pageNo-1;
        offset=noOfRec*(pageNo-1);
        
        if(SearchText==null)
        {
            pList=[select id,name,UnitPrice,Pricing_UOM__c,ProductCode,product2.Description,Product2.In_Stock__c,Product2Id,Product2.UOM_Master__r.Name,Product2.HSN_Code__c,Product2.name,product2.Item_No__c,Product2.Item_Group__r.name,product2.Sales_UOM__r.name 
                   from pricebookentry where pricebook2id=:bom.Price_book__c  limit:noOfRec offset:offset];
        }
        else
        {
            String FinalText='%'+SearchText+'%';
            
            
            if(Related.equals('All'))
            {
                pList=[select id,name,UnitPrice,Pricing_UOM__c,ProductCode,Product2.In_Stock__c,product2.Description,Product2Id,Product2.UOM_Master__r.Name,Product2.HSN_Code__c,Product2.name,product2.Item_No__c,Product2.Item_Group__r.name,product2.Sales_UOM__r.name 
                       from pricebookentry where pricebook2id=:bom.Price_book__c and Product2.IsActive=true AND product2.name Like:FinalText  limit:noOfRec offset:offset];
            }
            else
            {
                pList=[select id,name,UnitPrice,Pricing_UOM__c,ProductCode,Product2.In_Stock__c,Product2Id,product2.Description,Product2.UOM_Master__r.Name,Product2.HSN_Code__c,Product2.name,product2.Item_No__c,Product2.Item_Group__r.name,Product2.Item_Group__r.id,product2.Sales_UOM__r.name 
                       from pricebookentry where Product2.IsActive=true AND pricebook2id=:bom.Price_book__c AND product2.name Like:FinalText and Product2.Item_Group__r.id=:Related limit:noOfRec offset:offset];
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
    public void AddRec(){
        showList=false;
        showForm=true;
        system.debug('Select All'+SelectAll);
        for(wrapProduct w : wrapList){
            System.debug('www'+w.isChecked);
            if(w.isChecked==true && !selectedproduct.containsKey(w.pro.id))
            {
                Map<String,String> values=new Map<string,string>();
                System.debug('www'+w.isChecked);
                pricebookentry p=w.pro;
                Material_Planning_Item__c bl=new Material_Planning_Item__c();
                bl.Material_Planning__c=bom.id;
                bl.Item_Name__c=p.Product2Id;
                bl.UOM__c=p.Product2.UOM_Master__c;
                bl.BOM_Quantity__c=1;
                bl.In_Stock__c=p.Product2.In_Stock__c;
                bl.Sales_UOM__c=p.Pricing_UOM__c;
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
                    if(uom.Alt_UOM__r.name!=null)
                  values.put(uom.Alt_UOM__r.name,uom.Alt_UOM__c);  
                }
                System.debug('www'+values);
                opList.add(new wrapOpptyLine(bl,values));
                }
        }
    }
    public void selectAll(){
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

    public pageReference saveRec(){
        //insert bLineList;
        List<Material_Planning_Item__c> lineList=new list<Material_Planning_Item__c>();
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
    
   /* public class wrapProduct{ 
        public Product2 pro{get;set;}
        public boolean isChecked{get;set;}
        public Map<String,String> vMap{get;set;}
        public wrapProduct(Product2 i,map<id,id> selectedproduct,Map<String,String> values){
            pro = i;
            vMap=values;
            if(selectedproduct.containsKey(pro.id))
                isChecked = true;
            else
                isChecked = false;  
        }
    } */

    public class wrapOpptyLine
    {
        public Material_Planning_Item__c op{get;set;}
        public Map<String,String> vMap{get;set;}
        public wrapOpptyLine(Material_Planning_Item__c opl,Map<String,String> values)
        {
          op=opl;
          vMap=values;
        }
        
    }
}