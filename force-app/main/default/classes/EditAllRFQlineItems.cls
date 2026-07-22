public class EditAllRFQlineItems {
    
    public string currentRecID{get;set;}
    public List<RFQ_Item__c> opList {get;set;}
    //public string v_FieldName{get;set;}
    //public Boolean v_FieldValue = false;
    //public Boolean v_tbl_GST{get;set;}
    
    public integer noOfRec = 10;
    
    public integer offset{get;set;}
    public boolean islast{get;set;}
    public boolean isFirst{get;set;}
    public integer pageNo{get;set;}
    public integer totalPages{get;set;}
    
    List<selectOption> options = new List<selectOption>();
    public string str_selected_field {get;set;}
    
    public EditAllRFQlineItems(){
        
        currentRecID = ApexPages.CurrentPage().getparameters().get('id');
        
        f_load_productlist();
    }
    
    public void f_load_productlist(){

        pageNo = 1;
        offset = noOfRec * (pageNo-1);
        isFirst = true;
        
        totalPages=[Select id, name from RFQ_Item__c WHERE RFQ__c=:currentRecID ].size()/noOfRec+1;
        
        opList = [SELECT Id, Name, Item_Name__c, Item_Name_Temp__c, Item_Description__c, Quantity__c, GST__c, GST_Type__c, Unit_Price_Chk__c,
                  Delivery_Cost__c , Packing_Cost__c, Expiry_Date__c, Discount_Chk__c, Total_Cost__c, Credit_Period__c, Payment_Terms__c,
                  Delivery_Terms__c, HSN_Code_Chk__c, Vendor_Supply_Qty__c
                  FROM RFQ_Item__c 
                  WHERE RFQ__c=:currentRecID
                  limit:noOfRec offset:offset]; 
        
        //system.debug('opList>>>>>>>'+opList);  
        
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
    
    public List<selectOption> getAccNames() {
        options.clear();
        
        options.add(new selectOption('GST','GST'));
        options.add(new selectOption('UNIT PRICE','UNIT PRICE'));
        options.add(new selectOption('DELIVERY COST','DELIVERY COST'));
        options.add(new selectOption('PACKING COST','PACKING COST'));
        options.add(new selectOption('EXPIRY DATE','EXPIRY DATE'));
        options.add(new selectOption('DISCOUNT','DISCOUNT'));
        options.add(new selectOption('TOTAL COST','TOTAL COST'));
        options.add(new selectOption('CREDIT PERIOD','CREDIT PERIOD'));
        options.add(new selectOption('PAYMENT TERMS','PAYMENT TERMS'));
        options.add(new selectOption('DELIVERY TERMS','DELIVERY TERMS'));
        options.add(new selectOption('VENDOR SUPPLY QTY','VENDOR SUPPLY QTY'));

        return options;
    }
    
    public void f_Select_All() 
    {
        System.debug('str_selected_field : ' + str_selected_field);
        
        List<RFQ_Item__c> updateList = new List<RFQ_Item__c>();

        updateList = [SELECT Id, Name, Item_Name__c, Item_Name_Temp__c, Item_Description__c, Quantity__c, GST__c, GST_Type__c, Unit_Price_Chk__c,
                      Delivery_Cost__c , Packing_Cost__c, Expiry_Date__c, Discount_Chk__c, Total_Cost__c, Credit_Period__c, Payment_Terms__c,
                      Delivery_Terms__c, HSN_Code_Chk__c, Vendor_Supply_Qty__c
                      FROM RFQ_Item__c 
                      WHERE RFQ__c=:currentRecID
                     ]; 
        
        for(RFQ_Item__c o:updateList)
        {
            if (str_selected_field == 'GST') {
                o.GST__c = true;
            }
            if (str_selected_field == 'UNIT PRICE') {
                o.Unit_Price_Chk__c = true;
            }
            if (str_selected_field == 'DELIVERY COST') {
                o.Delivery_Cost__c = true;
            }
            if (str_selected_field == 'PACKING COST') {
                o.Packing_Cost__c = true;
            }
            if (str_selected_field == 'EXPIRY DATE') {
                o.Expiry_Date__c = true;
            }
            if (str_selected_field == 'DISCOUNT') {
                o.Discount_Chk__c = true;
            }
            if (str_selected_field == 'TOTAL COST') {
                o.Total_Cost__c = true;
            }
            if (str_selected_field == 'CREDIT PERIOD') {
                o.Credit_Period__c = true;
            }
            if (str_selected_field == 'PAYMENT TERMS') {
                o.Payment_Terms__c = true;
            }
            if (str_selected_field == 'DELIVERY TERMS') {
                o.Delivery_Terms__c = true;
            }
            if (str_selected_field == 'VENDOR SUPPLY QTY') {
                o.Vendor_Supply_Qty__c = true;
            }
        }
        
        update updateList;
        
        f_load_productlist();
    }
    
    public void f_Unselect_All() 
    {
        System.debug('str_selected_field : ' + str_selected_field);
        
        List<RFQ_Item__c> updateList = new List<RFQ_Item__c>();

        updateList = [SELECT Id, Name, Item_Name__c, Item_Name_Temp__c, Item_Description__c, Quantity__c, GST__c, GST_Type__c, Unit_Price_Chk__c,
                      Delivery_Cost__c , Packing_Cost__c, Expiry_Date__c, Discount_Chk__c, Total_Cost__c, Credit_Period__c, Payment_Terms__c,
                      Delivery_Terms__c, HSN_Code_Chk__c, Vendor_Supply_Qty__c
                      FROM RFQ_Item__c 
                      WHERE RFQ__c=:currentRecID
                     ]; 
        
        for(RFQ_Item__c o:updateList)
        {
            if (str_selected_field == 'GST') {
                o.GST__c = false;
            }
            if (str_selected_field == 'UNIT PRICE') {
                o.Unit_Price_Chk__c = false;
            }
            if (str_selected_field == 'DELIVERY COST') {
                o.Delivery_Cost__c = false;
            }
            if (str_selected_field == 'PACKING COST') {
                o.Packing_Cost__c = false;
            }
            if (str_selected_field == 'EXPIRY DATE') {
                o.Expiry_Date__c = false;
            }
            if (str_selected_field == 'DISCOUNT') {
                o.Discount_Chk__c = false;
            }
            if (str_selected_field == 'TOTAL COST') {
                o.Total_Cost__c = false;
            }
            if (str_selected_field == 'CREDIT PERIOD') {
                o.Credit_Period__c = false;
            }
            if (str_selected_field == 'PAYMENT TERMS') {
                o.Payment_Terms__c = false;
            }
            if (str_selected_field == 'DELIVERY TERMS') {
                o.Delivery_Terms__c = false;
            }
            if (str_selected_field == 'VENDOR SUPPLY QTY') {
                o.Vendor_Supply_Qty__c = false;
            }
        }
        
        update updateList;
        
        f_load_productlist();
    }
    
    public pageReference nextPage()
    {
        if (f_save() == false) {
            return null;
        }
        
        pageNo = pageNo + 1;
        offset = noOfRec * (pageNo-1);
        
        opList.clear();
        
        //totalPages=[Select id, name from RFQ_Vendor__c where RFQ__c=:oppty.id ].size()/noOfRec+1;

        opList = [SELECT Id, Name, Item_Name__c, Item_Name_Temp__c, Item_Description__c, Quantity__c, GST__c, GST_Type__c, Unit_Price_Chk__c,
                  Delivery_Cost__c , Packing_Cost__c, Expiry_Date__c, Discount_Chk__c, Total_Cost__c, Credit_Period__c, Payment_Terms__c,
                  Delivery_Terms__c, HSN_Code_Chk__c, Vendor_Supply_Qty__c
                  FROM RFQ_Item__c 
                  WHERE RFQ__c=:currentRecID
                  limit:noOfRec offset:offset]; 
        
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
        if (f_save() == false) {
            return null;
        }
        
        pageNo = pageNo - 1;
        offset = noOfRec * (pageNo - 1);
        
        opList.clear();

        opList = [SELECT Id, Name, Item_Name__c, Item_Name_Temp__c, Item_Description__c, Quantity__c, GST__c, GST_Type__c, Unit_Price_Chk__c,
                  Delivery_Cost__c , Packing_Cost__c, Expiry_Date__c, Discount_Chk__c, Total_Cost__c, Credit_Period__c, Payment_Terms__c,
                  Delivery_Terms__c, HSN_Code_Chk__c, Vendor_Supply_Qty__c
                  FROM RFQ_Item__c 
                  WHERE RFQ__c=:currentRecID
                  limit:noOfRec offset:offset]; 
        
        if(pageNo == totalPages) {
            islast = true;
        }
        else {
            islast = false; 
        }
        
        if(pageNo==1) {
            isFirst = true;
        }
        else {
            isFirst = false;
        }
        return null;
    }
    
    public boolean f_save() {
        
        Integer v_flag = 0;
        for(RFQ_Item__c o:opList)
        {
            if ((o.Quantity__c > 0) == false) {
                v_flag = 1;
            }
        }
        
        if (v_flag == 1) {
            ApexPages.addmessage(new ApexPages.message(ApexPages.severity.Error, 'Please enter Qty in all Item'));
            return false;
        }
        else {
            if(opList.size() > 0) {
                system.debug('opList======'+opList);   
                update opList; 
            }        
            return true; 
        }
    }
    
    Public Pagereference saveRec() 
    {
        if (f_save() == false) {
            return null;
        }
        
        pagereference pg= new pagereference('/'+currentRecID);
        pg.setRedirect(true);
        return pg; 
    }
    
    Public Pagereference cancel(){        
        pagereference pg=new pagereference('/'+currentRecID);
        pg.setRedirect(true);
        return pg;        
    } 
    
    /*public void selectAllCheckboxes(){    
        system.debug('v_FieldName : ' + v_FieldName);   system.debug('v_FieldValue : ' +  v_FieldValue);  
        for(RFQ_Item__c o:opList)
        {
            o.put(v_FieldName,v_FieldValue);
        }
    }*/
    
    /*public class wrapProduct{ 
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
    }*/
}