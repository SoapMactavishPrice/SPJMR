public with sharing  class AddSchoolWiseCorporateClass {
    
    public List < School_Wise_Corporate__c > selist {get;set;}
    public Id opid {get;set;}
    Static Id sId;
    public List<wrTra> wrlist{get; set;}        
    //public List<wrTra> wrlist3{get; set;}        
    public String wrlist1 {
        get;
        set;
    }
        set<String> acctben = new set<String>();
    
    public AddSchoolWiseCorporateClass() {
        
        opid = ApexPages.currentPage().getParameters().get('id');
        sId = opid;
        System.debug('SID'+sId);
        wrlist = new List<wrTra>(); 
        
         for(School_Wise_Corporate__c ab: [SELECT Id, Name, School__c, Corporate__c   FROM School_Wise_Corporate__c 
                                        Where  School__c=:opid ]){
                                            
                                            system.debug('ab------'+ab);
                                            acctben.add(ab.Corporate__c);
                                            system.debug('acctben------'+acctben);
                                        }
        
        for(Corporate__c tc:[ SELECT  Id,  Name,  Corporate_Contact__c,  Corporate_Code__c,Corporate_Email__c,Corporate_Agreement_End_Date__c,
                             Corporate_Agreement_Reminder_Date__c,  Corporate_Status__c,  Corporate_Band__c,  Corporate_Fee_Model__c,  
                             Corporate_Fee_Breakup__c,  Paid_by_Corporate__c,  Invoicing_Frequency__c,  Paid_by_Parent__c,  
                             Corporate_Agreement_Start_Date__c,  Paid_By_Parent_Formula__c,  Parent_Corporate__c,  Corporate_No__c 
                             FROM Corporate__c where Corporate_Status__c='Active'  and id NOT IN :acctben]){
                                 
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
        
        List<School_Wise_Corporate__c> selist=new List<School_Wise_Corporate__c>();
        
        for(wrTra wt:wrlist){ 
            if(wt.chk){
                
                School_Wise_Corporate__c oppt = new School_Wise_Corporate__c();
                oppt.School__c= id;
                oppt.Corporate__c=wt.tra.id;
                
                selist.add(oppt);
                system.debug('selist------------'+selist);
            }           
        }
        insert selist;
        
        PageReference pageRef = new PageReference('/' + id);
        pageRef.setRedirect(true);
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
        
        public Corporate__c tra {get;set;}
        public Boolean chk{get;set;}
        
        public wrTra(Corporate__c ben){
            this.tra=ben;
            this.chk=false;
            
        }
    }   
}