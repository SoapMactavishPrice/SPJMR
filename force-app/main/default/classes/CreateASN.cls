public class CreateASN {
    public id pid {get;set;}
    public Boolean showlist{get;set;}
    public Boolean ShowPage{get;set;}
    public Boolean Showback{get;set;}
    public List<Pending_PO_Order__c> plList;
    public List<wrapProduct> wList{get;set;}
    public List<ASN_Line_Item__c> packList{get;set;}
    public List<ASN__c> asnList{get;set;}
    
    public ASN__c pi;
    public Purchase_Order__c od {get;set;} 
    Public Decimal RemQty {get;set;}
    
    public CreateASN() {
        
        ShowPage=false;
        Showback=false;
        wList=new List<wrapProduct>();
        pid=ApexPages.currentPage().getParameters().get('id');
        system.debug('pid---'+pid);
        
        od= [SELECT Id, Name, PO_Stage__c,Account_Name__c, Warehouse__c,Warehouse_Address__c, CurrencyIsoCode,Payment_Terms__c,Freight__c,Freight_Cost__c,Freight_Extra__c,Taxes__c,Discount__c,Opportunity__c,Sales_Order__c,
             PO_Bill_To__c,PO_Ship_To__c,Kind_Attention__c,Special_Notes__c,Instruction__c,Total_Remaining_Quantity__c,Company_Master__c,Vendor_Name__c,Vendor_Contact_Person_Name__c,Vendor_Contact_Person_Type__c
             FROM Purchase_Order__c where id=:pid]; 
        system.debug('od---'+od);
        RemQty=od.Total_Remaining_Quantity__c;
        
        plList = [Select Id, Name, Approver_Remarks__c,Approver__c,Checker_Remark__c,Checker__c,Sales_UOM__c,CurrencyIsoCode,Item_Group__c,Item_Name__c,Maker_Remarks__c,
                  Maker__c,Purchase_Order_Item__c,Purchase_Order__c,Quantity__c,Item_Name__r.name,Item_Name__r.Item_No__c,Inventory__c,Remaining_Quantity__c,
                  ASN_Remaining_Quantity__c,Purchase_Order_Item__r.Tax_Code__c,Purchase_Order_Item__r.Unit_Price__c,Purchase_Order_Item__r.HSN_Master__c,Purchase_Order_Item__r.Sales_UOM__c
                  FROM Pending_PO_Order__c Where Purchase_Order__c=:od.Id AND Remaining_Quantity__c!=0];// AND Remaining_Quantity__c!=0
        system.debug('plList---'+plList);
        for(Pending_PO_Order__c p:plList)
        {
            wList.add(new wrapProduct(p));  
        }  
        system.debug('wList---'+wList);
        showlist=true;
        if(RemQty == 0 || RemQty==null){
            showlist=false;
            //ApexPages.Message msg = new ApexPages.Message(ApexPages.Severity.ERROR,'No Pending Quantity To Make Delivery Order.!!!!!!');
            ApexPages.addmessage(new ApexPages.message(ApexPages.severity.Error, 'No Pending Quantity To Make ASN.!!!!!!'));
            system.debug('inside=== if');
            // return null;
        }else{
            showlist=true;
        }
        
        // if(od.Status !='Activated' || od.Status !='Short Closed'){
        if(od.PO_Stage__c =='Draft' || od.PO_Stage__c =='Cancelled' || od.PO_Stage__c =='Fulfilled'){
            ApexPages.Message msg = new ApexPages.Message(ApexPages.Severity.ERROR,'Please make sure Purchase Order Status is Active to Create ASN');
            ApexPages.addMessage(msg);
            system.debug('if------');
        }
        
    }
    public pagereference AddProduct(){
        showlist=false;
        ShowPage=true;   
        Showback=false;
        packList=new List<ASN_Line_Item__c>();
        asnList = new List<ASN__c>();
                
        if(RemQty > 0){
            system.debug('inside=== if >>>>');
            ASN__c di=new ASN__c();
            di.Purchase_Order__c=pid;
            di.ASN_Date__c=Date.today();
            di.Payment_Terms__c=od.Payment_Terms__c;
            di.Freight__c=od.Freight__c;
            di.Freight_Cost__c=od.Freight_Cost__c;
            di.Freight_Extra__c=od.Freight_Extra__c;
            di.Taxes__c=od.Taxes__c;
            di.Discount_Percentage__c=od.Discount__c;
            di.CurrencyIsoCode=od.CurrencyIsoCode;
            di.Bill_To__c=od.PO_Bill_To__c;
            di.Ship_To__c=od.PO_Ship_To__c;
            di.Kind_Attention__c=od.Kind_Attention__c;
            di.Status__c='Active';
            di.Account_Name__c=od.Account_Name__c;
            di.Opportunity__c=od.Opportunity__c;
        	di.Sales_Order__c=od.Sales_Order__c;
            di.Warehouse__c=od.Warehouse__c;
            di.Kind_Attention__c=od.Kind_Attention__c;
            di.Vendor__c=od.Vendor_Name__c;
            di.Vendor_Contact_Person_Name__c=od.Vendor_Contact_Person_Name__c;
            di.Vendor_Contact_Person_Type__c=od.Vendor_Contact_Person_Type__c;
            // di.Tax_Code__c=od.Tax_Code__c;
            di.Company_Master__c=od.Company_Master__c;
            di.Special_Notes__c=od.Special_Notes__c;
            di.Instruction__c=od.Instruction__c;
            
            insert di;
            
            
            pi=[select id,name,CurrencyIsoCode,Purchase_Order__c from ASN__c where Id=:di.id AND Purchase_Order__c=:od.Id];
            asnList=[select id,name,CurrencyIsoCode,Purchase_Order__c from ASN__c where Id=:di.id AND Purchase_Order__c=:od.Id];
            for(wrapProduct o:wList){
                if(o.isChecked){ 
                    ASN_Line_Item__c p=new ASN_Line_Item__c();
                    p.ASN__c=pi.Id;
                    p.Pending_PO_Order__c=o.pro.id;
                    p.Item_Name__c=o.pro.Item_Name__c;
                    p.Inventory__c=o.pro.Inventory__c;
                    p.Backend_Remaining_Qty__c=o.pro.Remaining_Quantity__c;
                    p.Quantity__c=o.pro.Remaining_Quantity__c;
                    p.Tax_Code__c=o.pro.Purchase_Order_Item__r.Tax_Code__c;
                    p.Unit_Price__c=o.pro.Purchase_Order_Item__r.Unit_Price__c;
                    p.HSN_Code__c=o.pro.Purchase_Order_Item__r.HSN_Master__c;
                    p.CurrencyIsoCode=pi.CurrencyIsoCode;
					p.UOM__c=o.pro.Purchase_Order_Item__r.Sales_UOM__c;                    
                    packList.add(p);
                    system.debug('packList--'+packList.size());
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
        
        for(ASN_Line_Item__c bw : packList){ 
            system.debug('bw.Quantity__c'+ bw.Quantity__c);
            system.debug('o.pro.Backend_Remaining_Qty__c'+bw.Backend_Remaining_Qty__c);
            if( bw.Quantity__c>bw.Backend_Remaining_Qty__c){
                ApexPages.addmessage(new ApexPages.message(ApexPages.severity.Error,'You cannot enter more Quantity.!!!!!!'));
                return null;
            }
            
        } 
        insert packList;
        
        PageReference pageRef=new PageReference('/' +pid);
        pageRef.setRedirect(true);
        return pageRef;
    }
    
    public pagereference Del() {
        for(ASN__c asnItem: asnList) {
            delete asnItem;
        }
        PageReference pageRef = new PageReference('/' + pid);
        pageRef.setRedirect(true);
        return pageRef;
    }
    
     public void Back() {
        for(ASN__c asnItem: asnList) {
            delete asnItem;
        }
        showlist=true;
        Showback=false;
       /* PageReference pageRef = new PageReference('/' + pid);
        pageRef.setRedirect(true);
        return pageRef;*/
    }
    
    
    public pagereference Cancel()
    {
        
        PageReference pageRef=new PageReference('/' +pid);
        pageRef.setRedirect(true);
        return pageRef;
    }
    
    public class wrapProduct{ 
        public Pending_PO_Order__c pro{get;set;}
        public boolean isChecked{get;set;}
        public wrapProduct(Pending_PO_Order__c i){
            pro=i;
            isChecked=false;
        }
    } 
}