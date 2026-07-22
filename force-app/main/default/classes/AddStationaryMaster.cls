public with sharing class AddStationaryMaster {
    
    public List < Stationary_Item_Account__c > selist {get;set;}
    public Id opid {get;set;}
    Static Id sId;
    public List<wrTra> wrlist{get; set;}        
    //public List<wrTra> wrlist3{get; set;}        
    public String wrlist1 {
        get;
        set;
    }
    
    public AddStationaryMaster() {
        
        opid = ApexPages.currentPage().getParameters().get('id');
        sId = opid;
        System.debug('SID'+sId);
        wrlist = new List<wrTra>(); 
        
        for(Stationary_Master__c tc:[ SELECT  Id,  Name,Price__c,Quantity__c, Tax_Code__c, Tax_Applicable__c   
                                     FROM Stationary_Master__c where Name!=null]){
            
            System.debug('====> data: ' + JSON.serialize(tc));    
            wrlist.add(new wrTra(tc));
        }
        wrlist1 = JSON.serialize(wrlist);
        
    }
    
    @RemoteAction
    public static void save(String json, String id) {
        
        System.debug('--wrlist1------>'+id);       
        System.debug('--wrlist2------>');
        
        List<wrTra> wrlist = parsewTra(json);
        
        System.debug('--wrlist------> '+wrlist);
        
        List<Stationary_Item_Account__c> selist=new List<Stationary_Item_Account__c>();
        
        for(wrTra wt:wrlist){ 
            if(wt.chk){
                
                Stationary_Item_Account__c oppt = new Stationary_Item_Account__c();
                oppt.Student__c= id;
                oppt.Item_Name__c=wt.tra.id;
                oppt.Price__c=wt.tra.Price__c;
                oppt.Quantity__c=wt.tra.Quantity__c;
                oppt.Tax_Code__c=wt.tra.Tax_Code__c;
                oppt.Tax_Applicable__c=wt.tra.Tax_Applicable__c;
                
                selist.add(oppt);
                system.debug('selist------------'+selist);
            }           
        }
        insert selist;
        
        //PageReference pageRef = new PageReference('/' + id);
        //pageRef.setRedirect(true);
    }
    
    public static List<wrTra> parsewTra(String json) {
        return (List<wrTra>) System.JSON.deserialize(json, List<wrTra>.class);
    }
    
    public PageReference cancel() {
        
        PageReference pageRef = new PageReference('/' + opid);
        pageRef.setRedirect(true);
        return pageRef;      
    }
    
    public class wrTra{
        
        public Stationary_Master__c tra {get;set;}
        public Boolean chk{get;set;}
        
        public wrTra(Stationary_Master__c ben){
            this.tra=ben;
            this.chk=false;
            
        }
    }   
}