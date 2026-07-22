public class Shortage_Rejection_Advice_Class {
    public id pid {get;set;}
    public Boolean showlist{get;set;}
    public Boolean ShowPage{get;set;}
    public List<GRN_Line_Item__c> plList;
    public List<wrapProduct> wList{get;set;}
    public List<Shortage_Rejection_Advice__c> packList{get;set;}
    public List<Shortage_Rejection_Advice__c> shortrejectList{get;set;}
    public GRN__c pi1;
    public GRN__c pi;
    set<String> acctben = new set<String>();
    public Shortage_Rejection_Advice_Class() 
    {
        showlist=true;
        ShowPage=false;
        wList=new List<wrapProduct>();
        pid=ApexPages.currentPage().getParameters().get('id');
        pi=[select id,name From GRN__c where id=:pid];
        for(Shortage_Rejection_Advice__c ab: [SELECT Id, Name,GRN_Line_Item_Code__c FROM Shortage_Rejection_Advice__c Where  GRN_Number__c=:pid ]) {
            system.debug('ab------'+ab);
            acctben.add(ab.GRN_Line_Item_Code__c);
            system.debug('acctben------'+acctben);
        }
        System.debug('acctben : ' + acctben);
        plList = [Select Id,Name,GRN__c,ASN_Quantity__c,Backend_Remaining_Qty__c,Balanced_Quantity__c,HSN_Code__c,Item_Code__c,Item_Description__c,
                  Item_Group__c,Item_Name__c,Item_Name__r.name,Quantity__c,Received_Quantity__c,Rejected_Quantity__c,Tax_Code__c,Total_Amount__c,UOM__c,CurrencyIsoCode,
                  Unit_Price__c,UOM_Master__c,Inventory__c From GRN_Line_Item__c Where GRN__c=:pi.id AND Name NOT IN :acctben];
        system.debug('plList===>'+plList);
        system.debug('plList===>'+plList.size());
        if(plList.size()==0){
            showlist=false;
            ApexPages.addmessage(new ApexPages.message(ApexPages.severity.Error, 'No Pending GRN Line Items ...!!!!!!'));
            system.debug('inside=== if');
        }else{
            showlist=true;
        }
        for(GRN_Line_Item__c p:plList)
        {
            wList.add(new wrapProduct(p));  
        }  
    }
    public pagereference save()
    {
        showlist=false;
        ShowPage=true;   
        packList=new List<Shortage_Rejection_Advice__c>();
        
        for(wrapProduct o:wList)
        {
            if(o.isChecked){ 
                system.debug('o.pro.Received_Quantity__c'+ o.pro.Received_Quantity__c);
                system.debug('o.pro.Rejected_Quantity__c'+o.pro.Rejected_Quantity__c);
                
                //Update in UpdateGRNLine.cls File also
                Shortage_Rejection_Advice__c p=new Shortage_Rejection_Advice__c();
                p.GRN_Number__c=pid;
                p.HSN_Code__c=o.pro.HSN_Code__c;
                p.Item_Name__c= o.pro.Item_Name__c;
                p.Quantity__c= o.pro.Rejected_Quantity__c;
                p.GRN_Line_Item_Code__c = o.pro.Name;
                p.UOM__c=o.pro.UOM__c;
                p.CurrencyIsoCode=o.pro.CurrencyIsoCode;
                p.Inventory__c=o.pro.Inventory__c;
                p.Rejection_Created__c=true;
                if( o.pro.Received_Quantity__c < p.Quantity__c){
                    ApexPages.addmessage(new ApexPages.message(ApexPages.severity.Error,'You cannot enter more than Received Quantity.!!!!!!'));
                    return null;
                }
                else{
                    packList.add(p);
                }
            } 
        }
        insert packList;
        system.debug('packList--'+packList);
        
        PageReference pageRef=new PageReference('/' +pid);
        pageRef.setRedirect(true);
        return pageRef;
    }
    
    public pagereference Cancel()
    {
        
        PageReference pageRef=new PageReference('/' +pid);
        pageRef.setRedirect(true);
        return pageRef;
    }
    
    
    public class wrapProduct{ 
        public GRN_Line_Item__c pro{get;set;}
        public boolean isChecked{get;set;}
        public wrapProduct(GRN_Line_Item__c i){
            pro=i;
            isChecked=false;
        }
    }
}