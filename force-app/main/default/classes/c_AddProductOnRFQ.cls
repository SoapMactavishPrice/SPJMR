public class c_AddProductOnRFQ {
    public id rid{get;set;}
    public integer pageNo{get;set;}
    public integer noOfRec=15;
    public integer totalRec{get;set;}
    public integer offset{get;set;}
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
    public List<RFQ_Item__c> bLineList{get;set;}
    public list<Product2> pList{get;set;}
    public RFQ__c oppty{get;set;}
    public list<wrapOpptyLine> opList{get;set;}
    // required for getDiscount
    public String pid {get;set;}
    public String uom {get;set;}
    public String qty {get;set;}
    set<String> acctben = new set<String>();
    public List<SelectOption> options { get; set; }
    public id v_Item_Id {get;set;}
    
    public c_AddProductOnRFQ()
    {
        SearchText=null;
        pageNo=1;
        offset=noOfRec*(pageNo-1);
        showList=true;
        showForm=false;
        isFirst=true;
        selectedproduct=new Map<id,id>();
        wrapList=new list<wrapProduct>();
        valueMap=new Map<String,String>();
        bLineList=new list<RFQ_Item__c>();
        opList=new List<wrapOpptyLine>();
        options = new List<SelectOption>();
        rid=ApexPages.currentPage().getParameters().get('id'); 
        //oppty=[select id,name,accountId,pricebook2id,CurrencyIsoCode,Tax_Code__c from opportunity where id=:rid];
        oppty=[select id,name from RFQ__c where id=:rid];
        //totalPages=[select id,name from pricebookentry where pricebook2id=:oppty.Pricebook2Id].size()/noOfRec+1;
        
        for(RFQ_Item__c ab: [SELECT Id, Name,Item_Name__c 
                             FROM RFQ_Item__c Where  RFQ__c=:oppty.id]){
            system.debug('ab------'+ab);
            acctben.add(ab.Item_Name__c );
            system.debug('acctben------'+acctben);
        }        
      
        plist=[select id,name,Item_Group__r.name, Description, CurrencyIsoCode,Item_No__c, HSN_Code__c,Item_Group__c, Tax_Code__c, Pricing_UOM__c//UOM_Master__c
               From Product2
               where IsActive = true 
               //AND Product2Id NOT IN :acctben 
               AND id NOT IN :acctben 
               ORDER BY name
               limit:noOfRec offset:offset];
        
        totalPages=[Select id from Product2 where isActive = true AND id NOT IN :acctben ].size()/noOfRec+1;
        
        System.debug('plist'+plist);
        
        for(Item_Group_Master__c a:[select id,name from Item_Group_Master__c order by name])
        {
            valueMap.put(a.name,a.id);
            //options.add(new SelectOption(a.name, a.id));
        }
        
        for(Product2 p:plist)
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
                //TaxDeterminationCls td=new TaxDeterminationCls();
                Map<String,String> values=new Map<string,string>();
                Product2 p = w.pro;
                RFQ_Item__c op = new RFQ_Item__c();
                
                op.RFQ__c               = oppty.Id;
                op.Item_Name__c         = p.id;
                op.CurrencyIsoCode      = p.CurrencyIsoCode;
                op.HSN_Code__c          = p.HSN_Code__c;
                op.Item_Description__c  = p.Description;
                op.Item_Group__c        = p.Item_Group__c;
                //op.UOM_Master__c        = p.Pricing_UOM__c;
                op.UOM__c               = p.Pricing_UOM__c;
                op.Tax_Code__c          = p.Tax_Code__c;
                op.Item_Name_Temp__c    = p.name;

                bLineList.add(op);
                if(!test.isRunningTest()){
                     selectedproduct.put(p.Id,p.Id);
                }
                
                /*for(UOM_Group__c uom: [select id,name,Alt_UOM__c,Alt_UOM__r.name from UOM_Group__c where Product__c=:p.product2Id])
                {
                  values.put(uom.Alt_UOM__r.name,uom.Alt_UOM__c);  
                }*/
                opList.add(new wrapOpptyLine(op,null));
            }
        }
        
        pageNo=1;
        offset=noOfRec*(pageNo-1);
        if(!test.isRunningTest()){
            wrapList.clear();
        }
        pList.clear();
        
        String FinalText='%'+SearchText+'%';
        System.debug('search text'+SearchText);
        
        if(Related.equals('All'))
        {
            pList=[select id,name,Item_Group__r.name, Description, CurrencyIsoCode,Item_No__c, HSN_Code__c,Item_Group__c, Tax_Code__c,Pricing_UOM__c// UOM_Master__c
                   From Product2
                   where IsActive = true
                   AND id NOT IN :acctben
                   AND name Like:FinalText
                   ORDER BY name
                   limit:noOfRec offset:offset];
            totalPages=[Select id from Product2 where isActive = true AND id NOT IN :acctben  AND name Like:FinalText ].size()/noOfRec+1;
            
        }
        else
        {
            pList=[SELECT id,name,Item_Group__r.name, Description, CurrencyIsoCode,Item_No__c, HSN_Code__c,Item_Group__c, Tax_Code__c,Pricing_UOM__c// UOM_Master__c
                   FROM Product2
                   WHERE IsActive = true
                   AND id NOT IN :acctben
                   AND name Like:FinalText
                   AND Item_Group__r.id=:Related
                   ORDER BY name
                   limit:noOfRec offset:offset];
             totalPages=[Select id from Product2 where isActive = true AND id NOT IN :acctben AND name Like:FinalText
                   AND Item_Group__r.id=:Related ].size()/noOfRec+1;
        }
        for(Product2 p:plist)
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
                //TaxDeterminationCls td=new TaxDeterminationCls();
                Map<String,String> values=new Map<string,string>();
                Product2 p = w.pro;
                RFQ_Item__c op = new RFQ_Item__c();
                
                op.RFQ__c               = oppty.Id;
                op.Item_Name__c         = p.id;
                op.CurrencyIsoCode      = p.CurrencyIsoCode;
                op.HSN_Code__c          = p.HSN_Code__c;
                op.Item_Description__c  = p.Description;
                op.Item_Group__c        = p.Item_Group__c;
                //op.UOM_Master__c        = p.Pricing_UOM__c;
                op.UOM__c               = p.Pricing_UOM__c;
                op.Tax_Code__c          = p.Tax_Code__c;
                op.Item_Name_Temp__c    = p.name;
                
                /*op.PricebookEntryId=p.id;
                op.Item_Name_Temp__c=p.Product2.name;
                op.Item_Code_Temp__c=p.Product2.Item_No__c;
                op.Item_Group_Temp__c=p.Product2.Item_Group__r.name;
                op.Quantity=1;
                op.UnitPrice=p.UnitPrice;
                op.Sales_UOM__c=p.Pricing_UOM__c;
                op.OpportunityId=oppty.Id;
                op.Product_Temp__c=p.Product2id;
                op.Total_Quantity__c=1;
                op.HSN_Master__c=p.Product2.HSN_Code__c;
                op.Tax_Code__c=td.getTaxCode(oppty.AccountId,p.Product2Id);
                //op.CurrencyIsoCode=oppty.CurrencyIsoCode;
                */
                bLineList.add(op);
                
                if(!test.isRunningTest()){
                     selectedproduct.put(p.Id,p.Id);
                }
                
                /*for(UOM_Group__c uom: [select id,name,Alt_UOM__c,Alt_UOM__r.name from UOM_Group__c where Product__c=:p.product2Id])
                {
                  values.put(uom.Alt_UOM__r.name,uom.Alt_UOM__c);  
                }
                */
                opList.add(new wrapOpptyLine(op,null));
            }
        }
        if(!test.isRunningTest()){
            wrapList.clear();
        }
        pageNo=pageNo+1;
        offset=noOfRec*(pageNo-1);
        system.debug('SearchText'+SearchText);
        
        if(SearchText == null)
        {
            system.debug('SearchText'+SearchText);
            pList=[select id,name,Item_Group__r.name, Description, CurrencyIsoCode,Item_No__c, HSN_Code__c,Item_Group__c, Tax_Code__c,Pricing_UOM__c// UOM_Master__c
                   From Product2
                   where IsActive = true
                   AND id NOT IN :acctben 
                   ORDER BY name
                   limit:noOfRec offset:offset];
        }  
        else
        {
            String FinalText='%'+SearchText+'%';
            System.debug('search text'+SearchText);
            
            if(Related.equals('All'))
            {
                pList=[SELECT id,name,Item_Group__r.name, Description, CurrencyIsoCode,Item_No__c, HSN_Code__c,Item_Group__c, Tax_Code__c,Pricing_UOM__c// UOM_Master__c
                       FROM Product2
                       WHERE IsActive = true
                       AND id NOT IN :acctben
                       AND name Like:FinalText
                       ORDER BY name
                   limit:noOfRec offset:offset];
            }
            else
            {
                 pList=[SELECT id,name,Item_Group__r.name, Description, CurrencyIsoCode,Item_No__c, HSN_Code__c,Item_Group__c, Tax_Code__c,Pricing_UOM__c// UOM_Master__c
                        FROM Product2
                        WHERE IsActive = true
                        AND id NOT IN :acctben
                        AND name Like:FinalText
                        and Product2.Item_Group__r.id=:Related
                        ORDER BY name
                        limit:noOfRec offset:offset];
            } 
        }
        for(Product2 p:plist)
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
                //TaxDeterminationCls td=new TaxDeterminationCls();
                Map<String,String> values=new Map<string,string>();
                Product2 p = w.pro;
                RFQ_Item__c op = new RFQ_Item__c();
                
                op.RFQ__c               = oppty.Id;
                op.Item_Name__c         = p.id;
                op.CurrencyIsoCode      = p.CurrencyIsoCode;
                op.HSN_Code__c          = p.HSN_Code__c;
                op.Item_Description__c  = p.Description;
                op.Item_Group__c        = p.Item_Group__c;
                //op.UOM_Master__c        = p.Pricing_UOM__c;
                op.UOM__c               = p.Pricing_UOM__c;
                op.Tax_Code__c          = p.Tax_Code__c;
                op.Item_Name_Temp__c    = p.name;
                
                /*op.PricebookEntryId=p.id;
                op.Item_Name_Temp__c=p.Product2.name;
                op.Item_Code_Temp__c=p.Product2.Item_No__c;
                op.Item_Group_Temp__c=p.Product2.Item_Group__r.name;
                op.Quantity=1;
                op.UnitPrice=p.UnitPrice;
                op.Sales_UOM__c=p.Pricing_UOM__c;
                op.OpportunityId=oppty.Id;
                op.Product_Temp__c=p.Product2id;
                op.Total_Quantity__c=1;
                op.HSN_Master__c=p.Product2.HSN_Code__c;
                op.Tax_Code__c=td.getTaxCode(oppty.AccountId,p.Product2Id);
                //op.CurrencyIsoCode=oppty.CurrencyIsoCode;
                */
                bLineList.add(op);
                if(!test.isRunningTest()){
                     selectedproduct.put(p.Id,p.Id);
                }
                /*for(UOM_Group__c uom: [select id,name,Alt_UOM__c,Alt_UOM__r.name from UOM_Group__c where Product__c=:p.product2Id])
                {
                  values.put(uom.Alt_UOM__r.name,uom.Alt_UOM__c);  
                }*/
                opList.add(new wrapOpptyLine(op,null));
            }
        }
        if(!test.isRunningTest()){
            wrapList.clear();
        }
        pageNo=pageNo-1;
        offset=noOfRec*(pageNo-1);
        
        if(SearchText==null)
        {
            pList=[select id,name,Item_Group__r.name, Description, CurrencyIsoCode,Item_No__c, HSN_Code__c,Item_Group__c, Tax_Code__c, Pricing_UOM__c//UOM_Master__c
                   From Product2
                   where IsActive = true
                   AND id NOT IN :acctben 
                   ORDER BY name
                   limit:noOfRec offset:offset];
        }  
        else
        {
            String FinalText='%'+SearchText+'%';
            System.debug('search text'+SearchText);
            
            if(Related.equals('All'))
            {
                pList=[SELECT id,name,Item_Group__r.name, Description, CurrencyIsoCode,Item_No__c, HSN_Code__c,Item_Group__c, Tax_Code__c,Pricing_UOM__c// UOM_Master__c
                       FROM Product2
                       WHERE IsActive = true
                       AND id NOT IN :acctben
                       AND name Like:FinalText
                       ORDER BY name
                   limit:noOfRec offset:offset];
            }
            else
            {
                 pList=[SELECT id,name,Item_Group__r.name, Description, CurrencyIsoCode,Item_No__c, HSN_Code__c,Item_Group__c, Tax_Code__c,Pricing_UOM__c// UOM_Master__c
                        FROM Product2
                        WHERE IsActive = true
                        AND id NOT IN :acctben
                        AND name Like:FinalText
                        and Product2.Item_Group__r.id=:Related
                        ORDER BY name
                        limit:noOfRec offset:offset];
            }
        }
        for(Product2 p:plist)
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
        for(wrapProduct w : wrapList){
            System.debug('www'+w.isChecked);
            System.debug('www ******************'+selectedproduct.containsKey(w.pro.id));
            if(w.isChecked==true && !selectedproduct.containsKey(w.pro.id))
            {
                Map<String,String> values=new Map<string,string>();
                //TaxDeterminationCls td=new TaxDeterminationCls();
                System.debug('www'+w.isChecked);
                Product2 p = w.pro;
                RFQ_Item__c op = new RFQ_Item__c();
                
                op.RFQ__c               = oppty.Id;
                op.Item_Name__c         = p.id;
                op.CurrencyIsoCode      = p.CurrencyIsoCode;
                op.HSN_Code__c          = p.HSN_Code__c;
                op.Item_Description__c  = p.Description;
                op.Item_Group__c        = p.Item_Group__c;
                //op.UOM_Master__c        = p.Pricing_UOM__c;
                op.UOM__c               = p.Pricing_UOM__c;
                op.Tax_Code__c          = p.Tax_Code__c;
                op.Item_Name_Temp__c    = p.name;

                op.GST__c               = true;
                op.Unit_Price_Chk__c    = true;
                op.Delivery_Cost__c     = true;
                op.Packing_Cost__c      = true;
                op.Expiry_Date__c       = true;
                op.Discount_Chk__c      = true;
                op.Total_Cost__c        = true;
                op.Credit_Period__c     = true;
                op.Payment_Terms__c     = true;
                op.Delivery_Terms__c    = true;
                op.Vendor_Supply_Qty__c = true;

                bLineList.add(op);
                
                //values.put('Item_Name_Temp__c',p.name);
                
                opList.add(new wrapOpptyLine(op,null)); 
            }
        }
        
        showList = false;
        showForm = true;
    }
    
    public pageReference saveRec()
    {
        //insert bLineList;
        Integer v_flag = 0;
        for(wrapOpptyLine o:opList)
        {
            if ((o.op.Quantity__c > 0) == false) {
                v_flag = 1;
            }
        }
        
        if (v_flag == 1) {
            //alert('Please enter Qty in all Item');
            ApexPages.Message msg = new ApexPages.Message(ApexPages.Severity.ERROR,'Please enter the quantity in all the items');
            ApexPages.addMessage(msg);
            return null;
        }
        else {
            List<RFQ_Item__c> lineList=new list<RFQ_Item__c>();
            for(wrapOpptyLine o:opList)
            {
                lineList.add(o.op);  
            }
            insert lineList;
            
            PageReference pageRef = new PageReference('/'+rid); 
            pageRef.setRedirect(true);
            return pageRef;
        }
    }
    // to get discount as applicable
    
    public void getdisc()
    {
        /*Account acc=[select id,name,Effective_Price__c,Do_not_Apply_Discount_Group__c,Effective_price_Consider_all_price__c,Account_Group__c,Price_Book__c,Effective_Discount_Group__c from Account where id=:oppty.Accountid];
        Product2 p=[select id,name,Item_Group__c,Manufactures__c from product2 where id=:pid];
        discountCalculate dc=new discountCalculate();
        System.debug('uom==>'+uom);
        if(uom=='')
            uom=null;
        Integer discount =dc.calculate(acc,p,Integer.valueOf(Qty),uom); 
        System.debug('discount'+discount);
        for(wrapOpptyLine l:opList)
        {
            if(l.op.Product_Temp__c==pid)
            {
                l.op.Discount=discount;
                l.op.UnitPrice=getUnitPrice(oppty.pricebook2id,pid,uom);
            }
        }
        */
    }
    
    public double getUnitPrice(String plId,String pid,String uom)
    {
        double price;
        System.debug('Uom'+uom);
        List<UOM_Master__c> uplist=[Select id,name,Price__c from UOM_Master__c  where Price_List__c=:plId and Item_Master__c=:pid and UOM_Name__c=:uom];
        if(uplist.size()==0)
        {
         List<PricebookEntry> peList=[Select id,name,UnitPrice from PricebookEntry where pricebook2id=:plid and product2id=:pid];   
          if(peList.size()!=0)
          {
              price=peList[0].UnitPrice;
          }
        }
        else
            price=uplist[0].Price__c;
        
        System.debug('price+'+price); 
        return price;
    }

    public pageReference cancel()
    {
        PageReference pageRef = new PageReference('/'+rid);
        pageRef.setRedirect(true);
        return pageRef;
    }
    
    public void f_Remove_Item()
    {
		for ( Integer i = opList.size() - 1; i >= 0; --i )
       	{
            if (opList[i].op.Item_Name__c == v_Item_Id){
                 opList.remove(i);
			}
         }
    }
    
    
    
    
    
    public class wrapProduct{ 
        public Product2 pro{get;set;}
        public boolean isChecked{get;set;}
           public Map<String,String> vMap{get;set;}
        public wrapProduct(Product2 i,map<id,id> selectedproduct){
            pro = i;
            //  vMap=values;
            if(selectedproduct.containsKey(pro.id))
                isChecked = true;
            else
                isChecked = false;  
        }
    } 
    
    public class wrapOpptyLine
    {
        public RFQ_Item__c op{get;set;}
        public Map<String,String> vMap{get;set;}
        public wrapOpptyLine(RFQ_Item__c opl,Map<String,String> values)
        {
          op=opl;
          vMap=values;
        }
    }
}