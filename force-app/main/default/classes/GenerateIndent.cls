public class GenerateIndent {
    public id mpId{get;set;}
    public list<Material_Planning_item__c> listmpLine{get;set;}
    public list<wrapProduct> wpList{get;set;}
    public list<Material_Planning_item__c> spList{get;set;}
    public boolean showform{get;set;}
    public boolean showList{get;set;} 
    public Material_Planning__c mp{get;set;} 
    public List<Pending_Sales_Order__c> plList{get;set;}
    public list<id>ids;
    public GenerateIndent(){
        ids=new List<id>();
        showList=true;
        showform=false;
        spList=new list<Material_Planning_item__c>();
        mpId=ApexPages.CurrentPage().getparameters().get('id');
        System.debug('mpId'+mpId);
        mp=[select id,name,BOM__c,Project_Name__c,Opportunity__c,Sales_Order__c,Account_Name__c,Approver__c,Approver_Remarks__c,Checker__c,
            Checker_Remark__c,Maker_Remarks__c,Warehouse_Site__c,Price_Book__c,Company_Master__c
            From Material_Planning__c where id=:mpId];
        System.debug('mp'+mp);
        listmpLine = [Select id,Image__c,Item_Type__c,IS_IEC_standard__c,Material_Planning__r.Sales_Order__c,Sales_UOM__c,Material_Planning__r.Account_Name__c,UOM__c,IQ__c,
                      Pending_Quantity__c,Technical_Specification__c,Name,Material_Planning__c,HSN_SAC_Code__c, UnitPrice__c,Material_Planning__r.Opportunity__c,
                      Available_Stock__c,Indent_Quantity__c,Quantity_To_Block__c,BOM_Quantity__c,Item_Name__c,Inventory__c,Item_Group__c,Tax_Code__c
                      From Material_Planning_item__c where Material_Planning__c =: mpId AND Added_To_Indent__c=false];//AND Added_To_Material_Planning__c=false ,
        wpList=new list<wrapProduct>();
        for(Material_Planning_item__c i:listmpLine)
        {
            System.debug('test : ' + i.Pending_Quantity__c + ' : ' + i.Quantity_To_Block__c);
            wpList.add(new wrapProduct(i));  
        }
    }
    public pageReference cancel(){
        PageReference pageRef = new PageReference('/'+mpId);
        pageRef.setRedirect(true);
        return pageRef;
    }
    public void AddRec(){ 
        showList=false;
        showform=true;
        System.debug('wpList' + wpList);
        for(wrapProduct w:wpList)
        {
            if(w.isChecked)
            {
                spList.add(w.pro);
            }
        }
    }
    public PageReference saveRec(){
        list<Purchase_Requistion_Line_Item__c> irList=new list<Purchase_Requistion_Line_Item__c>();
        list<Blocked_Inventory__c> bList=new list<Blocked_Inventory__c>();
        map<id,id> iMap=new Map<id,id>();
        list<Material_Planning_item__c> line=new list<Material_Planning_item__c>();
        system.debug('line 51 ......'+spList);
        Set<id> orderId = new Set<id>();
        for(Material_Planning_item__c ind:spList){
            orderId.add(ind.Material_Planning__r.Sales_Order__c);
            system.debug('ind.BOM_Quantity__c ......'+ind.BOM_Quantity__c);
            system.debug('ind.IQ__c ......'+ind.IQ__c);
            system.debug('ind.Pending_Quantity__c ......'+ind.Pending_Quantity__c);
            system.debug('ind.Quantity_To_Block__c......'+ind.Quantity_To_Block__c);
            //system.debug(ind);
            if(((Integer)ind.Pending_Quantity__c - (Integer)ind.Quantity_To_Block__c) >0) {
                line.add(ind);
                system.debug('line......'+line);
            }
            system.debug('line ......'+line);
        }
        system.debug('orderId--'+orderId);  
       plList = [Select Id, Name,Sales_Order__c,Item_Name__c From Pending_Sales_Order__c Where Sales_Order__c IN:orderId];
        system.debug('plList--'+plList.size());  
        
        Purchase_Requisition__c  ir=new Purchase_Requisition__c ();
        //ir.Project_Name__c=mp.Project_Name__c;
        ir.Material_Planning__c=mp.id;
        ir.BOM__c=mp.BOM__c;
        ir.Purchase_Requisition_Date__c=Date.today();
        ir.Purchase_Requisition_Status__c='Active';
        ir.Opportunity__c=mp.Opportunity__c;
        ir.Sales_Order__c=mp.Sales_Order__c;
        ir.Account_Name__c=mp.Account_Name__c;
        ir.Approver__c=mp.Approver__c;
        ir.Approver_Remarks__c=mp.Approver_Remarks__c;
        ir.Checker__c=mp.Checker__c;
        ir.Checker_Remark__c=mp.Checker_Remark__c;
        ir.Maker_Remarks__c=mp.Maker_Remarks__c;
        ir.Warehouse__c=mp.Warehouse_Site__c;
        ir.Price_Book__c= mp.Price_Book__c;
        ir.Company_Master__c=mp.Company_Master__c;
        // ids.add(ir.id);
        System.debug('spList : ' + spList);
        for(Material_Planning_item__c ind:spList){
            if(validate((Integer)ind.Pending_Quantity__c,(Integer)ind.Available_Stock__c,(Integer)ind.Quantity_To_Block__c)){
                ApexPages.addmessage(new ApexPages.message(ApexPages.severity.Error,'Quantity To Block Should not be more than Available stock OR Pending Quantity'));
                return null;
            }
        }
        system.debug('line.size() ......'+line.size());
        if(line.size()>0)
            insert ir;  
        system.debug('ir ......'+ir);
        System.debug('spList : ' + spList);
        Set<id> invtid= new Set<id>();
        for(Material_Planning_item__c ind:spList){
            invtid.add(ind.Inventory__c);
            ind.IQ__c=ind.Pending_Quantity__c-ind.Quantity_To_Block__c;
            
            if(validate((Integer)ind.Pending_Quantity__c, (Integer)ind.Available_Stock__c, (Integer)ind.Quantity_To_Block__c)){
                //ApexPages.addmessage(new ApexPages.message(ApexPages.severity.Error,'Quantity To Block Should not be more than Available stock OR BOM Quantity'));
                //return null;
                system.debug('inside if...');
            }
            else
            {
                system.debug('inside else......');
                
                
                Purchase_Requistion_Line_Item__c irl=new Purchase_Requistion_Line_Item__c();
                irl.Purchase_Requisition__c=ir.Id;
                irl.Material_Planning_Item__c=ind.id;
                irl.Item_Group__c=ind.Item_Group__c;
                irl.Item_Name__c=ind.Item_Name__c;
                //irl.Quantity__c=ind.BOM_Quantity__c-ind.Quantity_To_Block__c;
                irl.Quantity__c=ind.Pending_Quantity__c - ind.Quantity_To_Block__c;
                irl.Tax_Code__c=ind.Tax_Code__c;
                //irl.Make__c=ind.Make__c;
                //irl.Design_Attached__c=ind.Design_Attached__c;
                irl.Technical_Specification__c=ind.Technical_Specification__c;
                irl.UOM__c=ind.UOM__c;
                irl.IS_IEC_standard__c=ind.IS_IEC_standard__c;
                irl.HSN_Code__c=ind.HSN_SAC_Code__c;
                irl.Inventory__c=ind.Inventory__c;
                irl.Sales_UOM__c=ind.Sales_UOM__c;
                irl.Tax_Code__c=ind.Tax_Code__c;
                //irl.Image_Url__c=ind.Image_Url__c;
                //irl.BOM_Quantity__c=ind.BOM_Quantity__c;
                
                irl.UnitPrice__c = ind.UnitPrice__c;
                
                iMap.put(ind.id,ind.Inventory__c);
                irl.MLineID__c=ind.id;
                if(ind.Pending_Quantity__c-ind.Quantity_To_Block__c>0)
                    irList.add(irl);
                if(ind.Pending_Quantity__c-ind.Quantity_To_Block__c==0)
                    ind.Added_To_Indent__c=true;
            }
        }
        system.debug('spList......'+spList);
        system.debug('irList......'+irList);
        update spList;
        insert irList;
        Map<id,id> irMap=new Map<id,id>();
        for(Purchase_Requistion_Line_Item__c ir1:irList){
            irMap.put(ir1.Item_Name__c,ir1.id);
        }
        
        Map<id,id> pendingMap=new Map<id,id>();
        for(Pending_Sales_Order__c pen:plList){
            pendingMap.put(pen.Item_Name__c,pen.id);
        }
		system.debug('pendingMap--'+pendingMap);        
        for(Material_Planning_item__c ind:spList){
            if(ind.Quantity_To_Block__c!=0){
                Blocked_Inventory__c b=new Blocked_Inventory__c();
                
                b.Product_Name__c=ind.Item_Name__c;
                b.Warehouse_Inventory__c=iMap.get(ind.Id);
                b.Material_Planning_item__c=ind.id;
                b.Purchase_Requistion_Item__c=irMap.get(ind.Item_Name__c);
                b.Project__c=mp.Project_Name__c;
                b.Quantity__c=ind.Quantity_To_Block__c;
                b.Opportunity__c=ind.Material_Planning__r.Opportunity__c;
                b.Sales_Order__c=ind.Material_Planning__r.Sales_Order__c;
                b.Pending_Sales_Order__c=pendingMap.get(ind.Item_Name__c);
                system.debug(' b.Pending_Sales_Order__c--'+ b.Pending_Sales_Order__c);   
                //b.Blocked_Inventory_Status__c='Blocked';
                b.Account__c=ind.Material_Planning__r.Account_Name__c;
                b.AccountId__c=ind.Material_Planning__r.Account_Name__c;
                if(ind.Material_Planning__r.Account_Name__c!=null){
                    b.Blocked_Inventory_Status__c='Blocked';
                }
                if(ind.Material_Planning__r.Account_Name__c==null){
                    b.Blocked_Inventory_Status__c='Available';
                }
                b.Inventory_Status_Sub_Type__c='Indent';
                bList.add(b); 
            }
        }
        system.debug('bList......'+bList);
        insert bList;
        
        Set<id> newblid= new Set<id>();
        Set<id> inventory= new Set<id>();
        for(Blocked_Inventory__c bi :bList){
            newblid.add(bi.Id);
            inventory.add(bi.Warehouse_Inventory__c);
        }
        system.debug('newblid......'+newblid);
        system.debug('inventory......'+inventory);
        List<Blocked_Inventory__c> blockinvlist = [Select Id, Name,Quantity__c,Product_Name__c,Blocked_Inventory_Status__c,Inventory_Status_Sub_Type__c
                                                   From Blocked_Inventory__c Where Id IN:newblid AND 
                                                   (Blocked_Inventory_Status__c='Blocked' OR Inventory_Status_Sub_Type__c='Indent') AND
                                                   (Blocked_Inventory_Status__c='Available' OR Inventory_Status_Sub_Type__c='Indent') ];
        system.debug('blockinvlist......'+blockinvlist.size());
        
        List<Blocked_Inventory__c> blockInv= [Select Id, Name,Quantity__c,Product_Name__c,Blocked_Inventory_Status__c,Inventory_Status_Sub_Type__c,Warehouse_Inventory__c
                                              From Blocked_Inventory__c Where Warehouse_Inventory__c IN:inventory AND
                                              (Blocked_Inventory_Status__c='Available' AND Inventory_Status_Sub_Type__c='Opening Stock')];
        system.debug('blockInv......'+blockInv.size());
        if(blockInv.size()>0){
            Map<Id,Id> bMap = new Map<Id,Id>();
            for(Blocked_Inventory__c bi :blockInv){
                bMap.put(bi.Product_Name__c,bi.Id);
            }
            system.debug('bMap......'+bMap);
            List<Indent_Generator__c> indgenInsert = new List<Indent_Generator__c>();
            for(Blocked_Inventory__c bi :blockinvlist){
                Indent_Generator__c ig = new Indent_Generator__c();
                // ig.Blocked_Inventory__c=blockInv[0].id; //added on 26/10/2021
                ig.Blocked_Inventory__c=bMap.get(bi.Product_Name__c); //blockInv.Id; commented on 26/10/2021
                ig.Quantity__c=bi.Quantity__c;
                ig.Product__c=bi.Product_Name__c;
                indgenInsert.add(ig);
            }
            insert indgenInsert;
            system.debug('indgenInsert......'+indgenInsert);
        }
        PageReference pageRef = new PageReference('/'+mpId);
        pageRef.setRedirect(true);
        return pageRef; 
        
    }
    public boolean validate(Integer bom,Integer avl,Integer blk){
        boolean flag=false;
        if(bom>avl && blk>avl)
        {
            flag=true;            
        }
        if(bom<avl&& blk>bom){
            flag =true;
        }
        return flag;    
    }
    public class wrapProduct{
        public Material_Planning_item__c pro{get;set;}
        public boolean isChecked{get;set;}
        public wrapProduct(Material_Planning_item__c i){
            pro = i;
            isChecked = false;
        }
    } 
}