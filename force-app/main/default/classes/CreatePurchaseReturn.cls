public class CreatePurchaseReturn {
    public id pid {get;set;}
    public Boolean showlist{get;set;}
    public Boolean ShowPage{get;set;}
    public Boolean Showback{get;set;}
    public List<Shortage_Rejection_Advice__c> plList;
    public List<wrapProduct> wList{get;set;}
    public List<Purchase_Return_Line_Item__c> packList{get;set;}
    public Purchase_Return__c pi;
    public GRN__c od {get;set;} 
    Public Decimal RemQty {get;set;}
    public List<Purchase_Return__c> pRList{get;set;}
    
    public CreatePurchaseReturn(){
        
        ShowPage=false;
        Showback=false;
        wList=new List<wrapProduct>();
        pid=ApexPages.currentPage().getParameters().get('id');
        system.debug('pid---'+pid); 
        
        od= [SELECT Id, Name,CurrencyIsoCode,ASN_Number__c,ASN_Number__r.Purchase_Order__c,Vendor__c,Warehouse__c,ASN_Number__r.LR_Nos__c,ASN_Number__r.LR_Date__c,
             ASN_Number__r.Challan_Date__c,Total_Purchase_Return_Quantity__c, ASN_Number__r.Driver_Name__c,ASN_Number__r.Driver_Contact__c,ASN_Number__r.Driver_license_Number__c
             FROM GRN__c where id=:pid]; 
        system.debug('od---'+od);
        RemQty=od.Total_Purchase_Return_Quantity__c;
        
        plList = [Select Id, Quantity__c,Item_Name__r.name,Item_Name__r.Item_No__c,Inventory__c,UOM__c,GRN_Number__c,Remaining_Quantity__c,UOM_Master__c,HSN_Code__c
                  FROM Shortage_Rejection_Advice__c  Where GRN_Number__c=:od.Id AND Remaining_Quantity__c!=0];
        system.debug('plList---'+plList);
        for(Shortage_Rejection_Advice__c p:plList)
        {
            wList.add(new wrapProduct(p));  
        }  
        system.debug('wList---'+wList);
        showlist=true;
        if(RemQty == 0 || RemQty==null){
            showlist=false;
            ApexPages.addmessage(new ApexPages.message(ApexPages.severity.Error, 'No Shortage/Rejection Quantity To Make Purchase Return.!!!!!!'));
        }else{
            showlist=true;
        }
        
        // if(od.Status !='Activated' || od.Status !='Short Closed'){
        /* if(od.PO_Stage__c =='Draft' || od.PO_Stage__c =='Cancelled' || od.PO_Stage__c =='Fulfilled'){
ApexPages.Message msg = new ApexPages.Message(ApexPages.Severity.ERROR,'Please make sure Purchase Order Status is Active to Create ASN');
ApexPages.addMessage(msg);
system.debug('if------');
}*/
        
    }
    public pagereference AddProduct(){
        showlist=false;
        ShowPage=true;  
        Showback=false;
        packList=new List<Purchase_Return_Line_Item__c>();
        
        
        if(RemQty > 0){
            system.debug('inside=== if >>>>');
            Purchase_Return__c di=new Purchase_Return__c();
            di.GRN_Number__c=pid;
            di.CurrencyIsoCode=od.CurrencyIsoCode;
            di.Purchase_Return_Date__c=Date.today();
            di.ASN_Number__c=od.ASN_Number__c;     
            di.PO_Number__c=od.ASN_Number__r.Purchase_Order__c;
            di.Vendor_Name__c=od.Vendor__c;
            di.Pickup_Warehouse__c=od.Warehouse__c;
            di.LR_Nos__c=od.ASN_Number__r.LR_Nos__c;
            di.LR_Date__c=od.ASN_Number__r.LR_Date__c;
            di.Challan_Date__c=od.ASN_Number__r.Challan_Date__c;
            di.Driver_Name__c=od.ASN_Number__r.Driver_Name__c;
            di.Driver_Contact__c=od.ASN_Number__r.Driver_Contact__c;
            di.Driver_license_Number__c=od.ASN_Number__r.Driver_license_Number__c;
            insert di;
            
            
            pi=[select id,name,CurrencyIsoCode,GRN_Number__c From Purchase_Return__c where Id=:di.id AND GRN_Number__c=:od.Id];
            pRList=[select id,name,CurrencyIsoCode,GRN_Number__c From Purchase_Return__c where Id=:di.id AND GRN_Number__c=:od.Id];
            for(wrapProduct o:wList){
                if(o.isChecked){ 
                    Purchase_Return_Line_Item__c p=new Purchase_Return_Line_Item__c();
                    p.Purchase_Return__c=pi.Id;
                    p.Shortage_Rejection_Advice__c=o.pro.id;
                    p.Item_Name__c=o.pro.Item_Name__c;
                    p.Backend_Remaining_Quantity__c=o.pro.Remaining_Quantity__c;
                    p.Return_Quantity__c=o.pro.Remaining_Quantity__c;
                    p.HSN_Code__c=o.pro.HSN_Code__c;
                    p.UOM_Master__c=o.pro.UOM_Master__c;
                    p.UOM__c= o.pro.UOM__c;
                    p.CurrencyIsoCode=pi.CurrencyIsoCode;
                    
                    packList.add(p);
                }
            }
            if(packList.size()==0){
                ShowPage=false;
                Showback=true;
                ApexPages.addmessage(new ApexPages.message(ApexPages.severity.Error, 'Please select atleast one Product.!!!!!!'));
                //ApexPages.Message msg = new ApexPages.Message(ApexPages.Severity.ERROR,'Please select atleast one Product.!!!!!!');
                return null;
            }
        }
         return null;
    }
    public pagereference save(){
        
        for(Purchase_Return_Line_Item__c bw : packList){ 
            system.debug('bw.Return_Quantity__c'+ bw.Return_Quantity__c);
            system.debug('o.pro.Backend_Remaining_Qty__c'+bw.Backend_Remaining_Quantity__c);
            if( bw.Return_Quantity__c>bw.Backend_Remaining_Quantity__c){
                ApexPages.addmessage(new ApexPages.message(ApexPages.severity.Error,'You cannot enter more Quantity.!!!!!!'));
                return null;
            }
            
        } 
        insert packList;
        
        PageReference pageRef=new PageReference('/' +pid);
        pageRef.setRedirect(true);
        return pageRef;
    }
    
    public void Back() {
        for(Purchase_Return_Line_Item__c asnItem: packList) {
            delete asnItem;
        }
        showlist=true;
        Showback=false;
      
    }
    public pagereference Cancel()
    {
        
        PageReference pageRef=new PageReference('/' +pid);
        pageRef.setRedirect(true);
        return pageRef;
    }
    
    public pagereference del() {
        for(Purchase_Return__c pur:pRList){
            delete pur;
        }
        PageReference pageRef=new PageReference('/' +pid);
        pageRef.setRedirect(true);
        return pageRef;
    }
    
    public class wrapProduct{ 
        public Shortage_Rejection_Advice__c pro{get;set;}
        public boolean isChecked{get;set;}
        public wrapProduct(Shortage_Rejection_Advice__c i){
            pro=i;
            isChecked=false;
        }
    } 
}