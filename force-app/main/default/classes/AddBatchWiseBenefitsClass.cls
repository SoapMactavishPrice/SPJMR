public  with sharing class AddBatchWiseBenefitsClass {
    
    public List < Batch_Wise_Benefit__c > selist {get;set;}
    public Batch_Wise_Fee_Plan__c feeplan {get;set;} 
    public Id opid {get;set;}
    Static Id sId; 
    //public List<wrTra> wrlist3{get; set;}        
    // public List<wrTra> wrlist1{get; set;}    
    public String wrlist1 {
        get;
        set;
    }
    
    set<String> acctben = new set<String>();
    
    
    public AddBatchWiseBenefitsClass() {
        
        opid = ApexPages.currentPage().getParameters().get('id');     
        feeplan=[ SELECT  Id, Name, Fee_Plan_Category_Master__c,Fee_Plan_Category_Master__r.Name 
                 FROM Batch_Wise_Fee_Plan__c  where id=:opid];
        
        sId = opid;
        System.debug('SID'+sId);
        List<wrTra> wrlist = new List<wrTra>(); 
        // wrlist1 = new List<wrTra>(); 
        
        for(Batch_Wise_Benefit__c ab: [SELECT Id, Name, Batch_Wise_Fee_Plan__c, Benefit_Name__c   FROM Batch_Wise_Benefit__c 
                                       Where  Batch_Wise_Fee_Plan__c=:opid ]){
                                           
                                           system.debug('ab------'+ab);
                                           acctben.add(ab.Benefit_Name__c);
                                           system.debug('acctben------'+acctben);
                                       }
        
        
        for(Benefit__c tc:[ SELECT  Id,Name,Benefit_Code__c,Benefit_Percentage__c,  Benefit_Value__c,Corporate__c,Benefit_Start_Date__c,
                           Benefit_End_Date__c,Grace_Period_In_Days__c,Corporate__r.Name,Status__c,Is_Benefit_in_Percentage__c,
                           Benefit_Type_Master__c,Benefit_Type_Master__r.Name
                           FROM Benefit__c where Corporate__c=null and Status__c='Active' and
                           (Benefit_Type_Master__r.Name ='Generic' or Benefit_Type_Master__r.Name =:feeplan.Fee_Plan_Category_Master__r.Name) and 
                           id NOT IN :acctben order by name]){
                               
                               System.debug('====> data: ' + JSON.serialize(tc));    
                               wrlist.add(new wrTra(tc));
                           }
        wrlist1 = JSON.serialize(wrlist);
        
    }
    
    @RemoteAction
    public static void save(String json, String id) {
        
        System.debug('--wrlist1------>'+id);
        
        // sId = ApexPages.currentPage().getParameters().get('id');
        // AddProgramsOnSchoolsClass apos = new AddProgramsOnSchoolsClass();
        
        System.debug('--wrlist2------>'+json);
        
        List<wrTra> wrlist = parsewTra(json);
        
        System.debug('--wrlist------> '+wrlist);
        // System.debug('--sId------> '+sId);
        
        List<Batch_Wise_Benefit__c> selist=new List<Batch_Wise_Benefit__c>();
        
        for(wrTra wt:wrlist){ 
            if(wt.chk == true){
                
                Batch_Wise_Benefit__c oppt = new Batch_Wise_Benefit__c();
                oppt.Batch_Wise_Fee_Plan__c= id;
                oppt.Benefit_Name__c=wt.tra.id;
                oppt.Benefit_Percentage__c=wt.tra.Benefit_Percentage__c;
                oppt.Benefit_Value__c=wt.tra.Benefit_Value__c;
                
                
                selist.add(oppt);
                system.debug('selist------------'+selist);
            }           
        }
        insert selist;
        
        PageReference pageRef = new PageReference('/' + id);
        // System.debug('pageRef--> '+pageRef);
        pageRef.setRedirect(true);
        //return pageRef;       
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
        
        public Benefit__c tra {get;set;}
        public Boolean chk{get;set;}
        
        public wrTra(Benefit__c ben){
            this.tra=ben;
            this.chk=false;
            
        }
    }   
}