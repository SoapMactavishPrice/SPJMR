public class c_RFQVendorProductMapEdit {
    
    public id rid{get;set;}
    public integer noOfRec = 10;
    
    public integer offset{get;set;}
    public boolean islast{get;set;}
    public boolean isFirst{get;set;}
    public integer pageNo{get;set;}
    public integer totalPages{get;set;}
    
    public integer offset_2{get;set;}
    public boolean islast_2{get;set;}
    public boolean isFirst_2{get;set;}
    public integer pageNo_2{get;set;}
    public integer totalPages_2{get;set;}
    
    public list<wrap_Vendor> w_VendorList{get;set;}
    //public list<wrap_Vendor> w_VendorList_Selected{get;set;}
    public list<wrap_Product> w_ProductList{get;set;}
    public list<wrap_Product_Vendor> w_Product_VendorList{get;set;}
    public List<RFQ_Vendor__c> vList{get;set;}
    public List<RFQ_Item__c> pList{get;set;}
    public List<RFQ_Vendor_Item_Map__c> vimList{get;set;}
    public RFQ__c o_rfq{get;set;}
    
    
    set<String> selected_product = new set<String>();
    public id selected_vendor {get;set;}
    
    public c_RFQVendorProductMapEdit()
    {
        w_VendorList = new List<wrap_Vendor>();
        //w_VendorList_Selected = new List<wrap_Vendor>();
        vList = new list<RFQ_Vendor__c>();
        
        w_ProductList = new List<wrap_Product>();
        pList = new list<RFQ_Item__c>();
        
        w_Product_VendorList = new List<wrap_Product_Vendor>();
        
        vimList = new list<RFQ_Vendor_Item_Map__c>();
        
        rid = ApexPages.currentPage().getParameters().get('id'); 
        o_rfq = [select id,name from RFQ__c where id=:rid];
        
        //f_load_vendor();
        
        f_load_vendor_list();
        //f_load_product_list();
    }
    
    public void f_load_vendor_list() {
        
        vList=[select id,Vendor_Code__c, Vendor_Name__c, Vendor_Name__r.Name
               From RFQ_Vendor__c
               WHERE RFQ__c = :rid
               ORDER BY Vendor_Name__r.Name
              ];     
        
        for(RFQ_Vendor__c p:vList)
        {
            w_VendorList.add(new wrap_Vendor(p,p.Vendor_Name__r.Name));
        }
    }
    
    public void  f_select_vendor()
    {
        selected_vendor = Apexpages.currentPage().getParameters().get('p_id');
        //System.debug('selected_vendor : ' + selected_vendor);
        f_load_product_list();
    }

    
    public void f_load_product_list() {
        
        w_Product_VendorList.clear();
        w_ProductList.clear();
        selected_product.clear();
        
        vimList = [SELECT Id, Name, Vendor_Name__c, Item_Name__c, Item_Name__r.ProductCode, Item_Name__r.Name
                   , Is_Awarded__c, Is_PO_Created__c
                   FROM RFQ_Vendor_Item_Map__c  
                   WHERE RFQ__c = :rid
                   AND Vendor_Name__c = :selected_vendor
                   ORDER BY Item_Name__r.Name
                  ];
        
        //System.debug('vimList : ' + vimList);
        
        for(RFQ_Vendor_Item_Map__c vim:vimList)
        {
            w_Product_VendorList.add(new wrap_Product_Vendor(vim,'',true));
            selected_product.add(vim.Item_Name__c);
        }
        
        /*-------------------------------------------*/
        
        pList = [SELECT Id, Name, Item_Name__c, Item_Name__r.ProductCode, Item_Name__r.Name
                 FROM RFQ_Item__c  
                 WHERE RFQ__c = :rid
                 AND Item_Name__c NOT IN :selected_product 
                 ORDER BY Item_Name__r.Name
                ];
        
        for(RFQ_Item__c p:pList)
        {
            w_ProductList.add(new wrap_Product(p,'', false));
        }
    }
    
    public pageReference f_AddMapProduct()
    {
        List<RFQ_Vendor_Item_Map__c> lineAddList = new list<RFQ_Vendor_Item_Map__c>();
        List<RFQ_Vendor_Item_Map__c> lineDeleteList = new list<RFQ_Vendor_Item_Map__c>();
        
        //Delete
        for(wrap_Product_Vendor p : w_Product_VendorList)
        {
            if(p.isChecked == false && p.op.Is_Awarded__c != true) {
                lineDeleteList.add(p.op);
            }
        }
        
        List<RFQ_Vendor__c> t_rfq_ven = [select id , name from RFQ_Vendor__c where Vendor_Name__c = :selected_vendor];
        
        //Insert 
        for(wrap_Product p : w_ProductList)
        {
            if(p.isChecked == true) {
                RFQ_Vendor_Item_Map__c vim = new RFQ_Vendor_Item_Map__c();
                vim.RFQ__c              = rid;
                vim.Vendor_Name__c      = selected_vendor; //v.op.Vendor_Name__c;
                vim.Item_Name__c        = p.op.Item_Name__c;
                vim.RFQ_Vendor__c		= t_rfq_ven[0].Id;
                lineAddList.add(vim);
            }
        }

        insert lineAddList;
        delete lineDeleteList;
        
        f_load_product_list();

        ApexPages.Message msg = new ApexPages.Message(ApexPages.Severity.INFO,'Updated Successfuly');
        ApexPages.addMessage(msg);

        return null;
    }
    
    
    public pageReference cancel()
    {
        PageReference pageRef = new PageReference('/'+rid);
        pageRef.setRedirect(true);
        return pageRef;
    }
    
    public class wrap_Vendor
    {
        public RFQ_Vendor__c op{get;set;}
        public boolean isChecked{get;set;}
        public String Vendor_Name{get;set;}
        public wrap_Vendor(RFQ_Vendor__c v, String p_Vendor_Name )
        {
            op = v;
            Vendor_Name = p_Vendor_Name;
        }
    }
    
    public class wrap_Product
    {
        public RFQ_Item__c op{get;set;}
        public boolean isChecked{get;set;}
        public String Product_Name{get;set;}
        public wrap_Product(RFQ_Item__c v, String p_Product_Name, boolean p_isChecked )
        {
            op = v;
            Product_Name = p_Product_Name;
            isChecked = p_isChecked;
        }
    }
    
    public class wrap_Product_Vendor
    {
        public RFQ_Vendor_Item_Map__c op{get;set;}
        public boolean isChecked{get;set;}
        public String Product_Name{get;set;}
        public wrap_Product_Vendor(RFQ_Vendor_Item_Map__c v, String p_Product_Name, boolean p_isChecked )
        {
            op = v;
            Product_Name = p_Product_Name;
            isChecked = p_isChecked;
        }
    }
}