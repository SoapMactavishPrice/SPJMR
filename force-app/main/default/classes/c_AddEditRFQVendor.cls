public class c_AddEditRFQVendor {
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
    
    public Boolean showList{get;set;}
    public Boolean showForm{get;set;}
    public String SearchText{get;set;}
    public list<wrapProduct> wrapList{get;set;}
    public map<id,id> selectedproduct {get;set;}
    public List<RFQ_Vendor__c> bLineList{get;set;}
    public list<Vendor__c> pList{get;set;}
    public RFQ__c oppty{get;set;}
    public list<wrapOpptyLine> opList{get;set;}
    set<String> acctben = new set<String>();
    public String v_Vendor_Id {get;set;}
    public boolean hidebutton {get;set;}
    
    //List<RFQ_Vendor__c> plist_rfq_vendor {get;set;}
        
    public c_AddEditRFQVendor()
    {
        pageNo = 1;
        offset = noOfRec * (pageNo-1);
        isFirst = true;
        
        pageNo_2 = 1;
        offset_2 = noOfRec * (pageNo_2-1);
        isFirst_2 = true;
        
        SearchText = null;
        selectedproduct=new Map<id,id>();
        wrapList=new list<wrapProduct>();
        bLineList=new list<RFQ_Vendor__c>();
        opList=new List<wrapOpptyLine>();
        //plist_rfq_vendor = new List<RFQ_Vendor__c>();
        rid=ApexPages.currentPage().getParameters().get('id'); 
        oppty = [select id,name from RFQ__c where id=:rid];
        
        //v_Vendor_Name = new RFQ_Vendor__c();
        
        showList = false;
        showForm = true;
        
        f_load_form();
    }
    
    public void f_load_list() {
        
        
        for(RFQ_Vendor__c ab: [SELECT Id, Name,Vendor_Name__c 
                             FROM RFQ_Vendor__c Where  RFQ__c=:oppty.id]){
            system.debug('ab------'+ab);
            acctben.add(ab.Vendor_Name__c );
            system.debug('acctben------'+acctben);
        }        
      
        plist=[select id,name,Vendor_Code__c, GST_Number__c, Vendor_Status__c,State__c, Address_1__c
               From Vendor__c
               where Vendor_Status__c = 'Active' 
               AND id NOT IN :acctben 
               ORDER BY Name
               limit:noOfRec offset:offset];
        
        totalPages=[Select id, name from Vendor__c where Vendor_Status__c = 'Active' AND id NOT IN :acctben ].size()/noOfRec+1;
        
        System.debug('plist'+plist);
        
        wrapList.clear();
        
        for(Vendor__c p:plist)
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
    }
    
    public void f_load_form() {
        
        opList.clear();
        
        totalPages_2=[Select id, name from RFQ_Vendor__c where RFQ__c=:oppty.id ].size()/noOfRec+1;
        
        List<RFQ_Vendor__c> plist_rfq_vendor = new List<RFQ_Vendor__c>();
        
        plist_rfq_vendor = [SELECT Id, Name,Vendor_Name__c, RFQ__c, Vendor_Name__r.name,
                            Vendor_Name__r.Vendor_Code__c, Vendor_Name__r.GST_Number__c, 
                            Vendor_Name__r.State__c, Vendor_Name__r.Vendor_Status__c
                            FROM RFQ_Vendor__c 
                            Where RFQ__c=:oppty.id
                            limit:noOfRec offset:offset_2];
        
        for(RFQ_Vendor__c p: plist_rfq_vendor){
            p.Vendor_Code__c        = p.Vendor_Name__r.Vendor_Code__c;
            p.Vendor_GST__c         = p.Vendor_Name__r.GST_Number__c;
            p.Vendor_Location__c    = p.Vendor_Name__r.State__c;
            p.Vendor_Status__c      = p.Vendor_Name__r.Vendor_Status__c;
                                 
            opList.add(new wrapOpptyLine(p,null,p.Vendor_Name__r.name));
        }

        if(pageNo_2==totalPages_2)
        {
            islast_2=true;
        }
        if(pageNo_2==1)
        {
            isFirst_2=true;
        }else
        {
            isFirst_2=false;
        }
    }
    
    public pageReference nextPage_2()
    {
        pageNo_2 = pageNo_2 + 1;
        offset_2 = noOfRec * (pageNo_2-1);
        
        opList.clear();
        
        totalPages_2=[Select id, name from RFQ_Vendor__c where RFQ__c=:oppty.id ].size()/noOfRec+1;

        List<RFQ_Vendor__c> plist_rfq_vendor = new List<RFQ_Vendor__c>();
        
        plist_rfq_vendor = [SELECT Id, Name,Vendor_Name__c, RFQ__c, Vendor_Name__r.name,
                            Vendor_Name__r.Vendor_Code__c, Vendor_Name__r.GST_Number__c, 
                            Vendor_Name__r.State__c, Vendor_Name__r.Vendor_Status__c
                            FROM RFQ_Vendor__c 
                            Where RFQ__c=:oppty.id
                            limit:noOfRec offset:offset_2];
        
        for(RFQ_Vendor__c p: plist_rfq_vendor){
            p.Vendor_Code__c        = p.Vendor_Name__r.Vendor_Code__c;
            p.Vendor_GST__c         = p.Vendor_Name__r.GST_Number__c;
            p.Vendor_Location__c    = p.Vendor_Name__r.State__c;
            p.Vendor_Status__c      = p.Vendor_Name__r.Vendor_Status__c;
                                 
            opList.add(new wrapOpptyLine(p,null,p.Vendor_Name__r.name));
        }
        
        if(pageNo_2==totalPages_2)
        {
            islast_2=true;
        }
        else
        {
            islast_2=false; 
        }
        if(pageNo_2==1)
        {
            isFirst_2=true;
        }
        else
        {
            isFirst_2=false;
        }
        return null;
    }
    
    public pageReference prePage_2()
    {
        pageNo_2 = pageNo_2 - 1;
        offset_2 = noOfRec * (pageNo_2 - 1);
        
        opList.clear();

        List<RFQ_Vendor__c> plist_rfq_vendor = new List<RFQ_Vendor__c>();
        
        plist_rfq_vendor = [SELECT Id, Name,Vendor_Name__c, RFQ__c, Vendor_Name__r.name,
                            Vendor_Name__r.Vendor_Code__c, Vendor_Name__r.GST_Number__c, 
                            Vendor_Name__r.State__c, Vendor_Name__r.Vendor_Status__c
                            FROM RFQ_Vendor__c 
                            Where RFQ__c=:oppty.id
                            limit:noOfRec offset:offset_2];
        
        for(RFQ_Vendor__c p: plist_rfq_vendor){
            p.Vendor_Code__c        = p.Vendor_Name__r.Vendor_Code__c;
            p.Vendor_GST__c         = p.Vendor_Name__r.GST_Number__c;
            p.Vendor_Location__c    = p.Vendor_Name__r.State__c;
            p.Vendor_Status__c      = p.Vendor_Name__r.Vendor_Status__c;
                                 
            opList.add(new wrapOpptyLine(p,null,p.Vendor_Name__r.name));
        }
        
        if(pageNo_2 == totalPages_2) {
            islast_2 = true;
        }
        else {
            islast_2 = false; 
        }
        
        if(pageNo_2==1) {
            isFirst_2 = true;
        }
        else {
            isFirst_2 = false;
        }
        return null;
    }
    
    public void Search() 
    {
        for(wrapProduct w : wrapList){
            System.debug('www'+w.isChecked);
            if(w.isChecked==true && !selectedproduct.containsKey(w.pro.id))
            {
                Map<String,String> values=new Map<string,string>();
                Vendor__c p = w.pro;
                RFQ_Vendor__c op = new RFQ_Vendor__c();
                op.RFQ__c               = oppty.Id;
                op.Vendor_Name__c       = p.id;
                op.Vendor_Code__c       = p.Vendor_Code__c;
                op.Vendor_GST__c        = p.GST_Number__c;
                op.Vendor_Location__c   = p.State__c;
                op.Vendor_Status__c     = p.Vendor_Status__c;
                bLineList.add(op);
                if(!test.isRunningTest()){
                     selectedproduct.put(p.Id,p.Id);
                }

                opList.add(new wrapOpptyLine(op,null,''));
            }
        }
        
        pageNo=1;
        offset=noOfRec*(pageNo-1);
        if(!test.isRunningTest()){
            wrapList.clear();
        }
        pList.clear();
        
        if(SearchText == null || SearchText == '')
        {
            system.debug('SearchText'+SearchText);
            pList=[select id,name,Vendor_Code__c, GST_Number__c, Vendor_Status__c,State__c, Address_1__c
                   From Vendor__c
                   where Vendor_Status__c = 'Active'
                   AND id NOT IN :acctben 
                   ORDER BY Name
                   limit:noOfRec offset:offset];
        }  
        else
        {
            String FinalText='%'+SearchText+'%';
            System.debug('search text'+SearchText);
            
            pList=[SELECT id,name,Vendor_Code__c, GST_Number__c, Vendor_Status__c,State__c, Address_1__c
                   FROM Vendor__c
                   WHERE Vendor_Status__c = 'Active'
                   AND id NOT IN :acctben
                   AND name Like:FinalText
                   ORDER BY Name
                   limit:noOfRec offset:offset];
        }
        
        /*if(Related.equals('All'))
        {
            pList=[select id,name,Item_Group__r.name, Description, CurrencyIsoCode,Item_No__c, HSN_Code__c,Item_Group__c, UOM_Master__c
                   From Vendor__c
                   where IsActive = true
                   AND id NOT IN :acctben
                   AND name Like:FinalText
                   limit:noOfRec offset:offset];
        }
        else
        {
            pList=[SELECT id,name,Item_Group__r.name, Description, CurrencyIsoCode,Item_No__c, HSN_Code__c,Item_Group__c, UOM_Master__c
                   FROM Vendor__c
                   WHERE IsActive = true
                   AND id NOT IN :acctben
                   AND name Like:FinalText
                   AND Item_Group__r.id=:Related
                   limit:noOfRec offset:offset];
        }*/
        for(Vendor__c p:plist)
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
                Map<String,String> values=new Map<string,string>();
                Vendor__c p = w.pro;
                RFQ_Vendor__c op = new RFQ_Vendor__c();
                op.RFQ__c               = oppty.Id;
                op.Vendor_Name__c       = p.id;
                op.Vendor_Code__c       = p.Vendor_Code__c;
                op.Vendor_GST__c        = p.GST_Number__c;
                op.Vendor_Location__c   = p.State__c;
                op.Vendor_Status__c     = p.Vendor_Status__c;
                bLineList.add(op);
                
                if(!test.isRunningTest()){
                     selectedproduct.put(p.Id,p.Id);
                }

                opList.add(new wrapOpptyLine(op,null,''));
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
            pList=[select id,name,Vendor_Code__c, GST_Number__c, Vendor_Status__c,State__c, Address_1__c
                   From Vendor__c
                   where Vendor_Status__c = 'Active'
                   AND id NOT IN :acctben 
                   ORDER BY Name
                   limit:noOfRec offset:offset];
        }  
        else
        {
            String FinalText='%'+SearchText+'%';
            System.debug('search text'+SearchText);
            
            pList=[SELECT id,name,Vendor_Code__c, GST_Number__c, Vendor_Status__c,State__c, Address_1__c
                   FROM Vendor__c
                   WHERE Vendor_Status__c = 'Active'
                   AND id NOT IN :acctben
                   AND name Like:FinalText
                   ORDER BY Name
                   limit:noOfRec offset:offset];
        }
        for(Vendor__c p:plist)
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
                Map<String,String> values=new Map<string,string>();
                Vendor__c p = w.pro;
                RFQ_Vendor__c op = new RFQ_Vendor__c();
                op.RFQ__c               = oppty.Id;
                op.Vendor_Name__c       = p.id;
                op.Vendor_Code__c       = p.Vendor_Code__c;
                op.Vendor_GST__c        = p.GST_Number__c;
                op.Vendor_Location__c   = p.State__c;
                op.Vendor_Status__c     = p.Vendor_Status__c;
                bLineList.add(op);
                if(!test.isRunningTest()){
                     selectedproduct.put(p.Id,p.Id);
                }
                
                opList.add(new wrapOpptyLine(op,null,''));
            }
        }
        if(!test.isRunningTest()){
            wrapList.clear();
        }
        pageNo=pageNo-1;
        offset=noOfRec*(pageNo-1);
        
        if(SearchText==null)
        {
            pList=[select id,name,Vendor_Code__c, GST_Number__c, Vendor_Status__c,State__c, Address_1__c
                   From Vendor__c
                   where Vendor_Status__c = 'Active'
                   AND id NOT IN :acctben 
                   ORDER BY Name
                   limit:noOfRec offset:offset];
        }  
        else
        {
            String FinalText='%'+SearchText+'%';
            System.debug('search text'+SearchText);
            
            pList=[SELECT id,name,Vendor_Code__c, GST_Number__c, Vendor_Status__c,State__c, Address_1__c
                   FROM Vendor__c
                   WHERE Vendor_Status__c = 'Active'
                   AND id NOT IN :acctben
                   AND name Like:FinalText
                   ORDER BY Name
                   limit:noOfRec offset:offset];
        }
        for(Vendor__c p:plist)
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
        /*for(wrapProduct w : wrapList){
            System.debug('www'+w.isChecked);
            System.debug('www ******************'+selectedproduct.containsKey(w.pro.id));
            if(w.isChecked==true && !selectedproduct.containsKey(w.pro.id))
            {
                Map<String,String> values=new Map<string,string>();
                System.debug('www'+w.isChecked);
                Vendor__c p = w.pro;
                RFQ_Vendor__c op = new RFQ_Vendor__c();
                
                op.RFQ__c               = oppty.Id;
                op.Item_Name__c         = p.id;
                op.CurrencyIsoCode      = p.CurrencyIsoCode;
                op.HSN_Code__c          = p.HSN_Code__c;
                op.Item_Description__c  = p.Description;
                op.Item_Group__c        = p.Item_Group__c;
                op.UOM__c               = p.UOM_Master__c;
                op.Item_Name_Temp__c    = p.name;
                
                bLineList.add(op);
                opList.add(new wrapOpptyLine(op,null)); 
            }
        }
        
        showList = false;
        showForm = true;*/
    }
    
    public pageReference saveRec()
    {
        List<RFQ_Vendor__c> lineList = new list<RFQ_Vendor__c>();
        for(wrapProduct w : wrapList)
        {
            if(w.isChecked==true && !selectedproduct.containsKey(w.pro.id)) { 
                RFQ_Vendor__c op = new RFQ_Vendor__c();
                op.RFQ__c               = oppty.id;
                op.Vendor_Name__c       = w.pro.id;
                op.Vendor_Code__c       = w.pro.Vendor_Code__c;
                op.Vendor_GST__c        = w.pro.GST_Number__c;
                op.Vendor_Location__c   = w.pro.State__c;
                op.Vendor_Status__c     = w.pro.Vendor_Status__c;
                lineList.add(op);
            }
        }
        insert lineList;
        
        //PageReference pageRef = new PageReference('/'+rid); 
        //pageRef.setRedirect(true);
        //return pageRef;
        
        showList = false;
        showForm = true;
        
        f_load_form();
        
        return null;
    }
    
    public void f_AddVendorPage()
    {
        showList = true;
        showForm = false;
        
        f_load_list();
    }

    public pageReference cancel()
    {
        PageReference pageRef = new PageReference('/'+rid);
        pageRef.setRedirect(true);
        return pageRef;
    }
    
    public pageReference f_VendorProductMap()
    {
        PageReference pageRef = new PageReference('/apex/RFQVendorProductMap?id=' + rid);
        pageRef.setRedirect(true);
        return pageRef;
    }
    
    public void f_Remove_Vendor()
    {
        //System.debug('v_Vendor_Id : ' + v_Vendor_Id);
        
        List<RFQ_Vendor_Item_Map__c> vimList = [SELECT Id
                                                FROM RFQ_Vendor_Item_Map__c
                                                WHERE RFQ__c = :rid
                                                AND RFQ_Vendor__c = :v_Vendor_Id
                                                //AND Vendor_Name__c = :v_Vendor_Id
                                                //AND Is_Awarded__c = true
                                                //AND Is_PO_Created__c != true	//NJNI
                                                //ORDER BY Item_Name__r.Name
                                                limit 1
                                               ];

        if (vimList.size() == 0) {
            try{
                RFQ_Vendor__c v_DeleteRecord = new RFQ_Vendor__c();
                v_DeleteRecord.Id = v_Vendor_Id;
                delete v_DeleteRecord;      
            }
            catch(exception e) {
            }
            
            f_load_form();
        }
        else {
            ApexPages.Message msg = new ApexPages.Message(ApexPages.Severity.ERROR,'Product Map for this Vendor');
            ApexPages.addMessage(msg);
        }
    }
    
    public class wrapProduct{ 
        public Vendor__c pro{get;set;}
        public boolean isChecked{get;set;}
        public Map<String,String> vMap{get;set;}
        public wrapProduct(Vendor__c i,map<id,id> selectedproduct){
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
        public RFQ_Vendor__c op{get;set;}
        public boolean isChecked{get;set;}
        public String Vendor_Name{get;set;}
        public Map<String,String> vMap{get;set;}
        public wrapOpptyLine(RFQ_Vendor__c opl,Map<String,String> values,String p_Vendor_Name )
        {
            op = opl;
            vMap = values;
            Vendor_Name = p_Vendor_Name;
        }
    }
}