public with sharing class DeleteBenefits {
    
   public Id opid {get;set;}
    Static Id sId;
    public List<wrTra> wrlist{get; set;}        
    public String wrlist1 {get;set;} 
    public Account acc {get;set;}
    public List<Account_Program_Batch_Selection__c> programlist{get;set;}
    public List<Program_Batch_Wise_Payment__c> FeePlanlist{get;set;}
    
    public DeleteBenefits() {
        
        opid = ApexPages.currentPage().getParameters().get('id');     
        
        acc=[SELECT  Id,  Name from Account where id=:opid Order By Name];        
        
        programlist=[ SELECT  Id,  Name FROM Account_Program_Batch_Selection__c where Student_Name__c=:acc.Id order by name ]; 
        
        Set<id> plset= new Set<id>();       
        for(Account_Program_Batch_Selection__c p:programlist){
            plset.add(p.id);
        }
        
        FeePlanlist=[ SELECT  Id, Name FROM Program_Batch_Wise_Payment__c where Program_Batch_Selection__c IN: plset  order by name]; 
        
        Set<id> plset1= new Set<id>();       
        for(Program_Batch_Wise_Payment__c p:FeePlanlist){
            plset1.add(p.id);
        }
         
        sId = opid;
        wrlist = new List<wrTra>(); 
        
        for(Account_Benefit__c tc:[SELECT  Id,  Name , Benefit__c , Benefit__r.Name, Benefit_Percentage__c, Benefit_Value__c, 
                                   Program_Batch_Wise_Fee_Plan__r.Program_Name__c,Program_Batch_Wise_Fee_Plan__r.Batch_Name__r.Name,
                                   Program_Batch_Wise_Fee_Plan__r.Batch_Name__c,Program_Batch_Wise_Fee_Plan__r.Program_Name__r.Name,
                                   Program_Batch_Wise_Fee_Plan__r.Fee_Plan_Category_Master__c,
                                   Program_Batch_Wise_Fee_Plan__r.Fee_Plan_Category_Master__r.Name
                                   FROM Account_Benefit__c  where Program_Batch_Wise_Fee_Plan__c IN:plset1 order by name]){
                                       
                                       System.debug('====> data: ' + JSON.serialize(tc));    
                                       wrlist.add(new wrTra(tc));
                                   }
        wrlist1 = JSON.serialize(wrlist);
        
    }
    
    @RemoteAction
    public static void save(String json, String id) {
        
        List<wrTra> wrlist = parsewTra(json);
        
        List<Account_Benefit__c> selist=new List<Account_Benefit__c>();
        
        for(wrTra wt:wrlist){ 
            if(wt.chk){
                Account_Benefit__c pbw=new Account_Benefit__c();
                pbw=wt.tra;
                selist.add(pbw);
            }          
        }
        
        for(Account_Benefit__c pbis: selist){
            delete pbis;
        }
        
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
        
        public Account_Benefit__c tra {get;set;}
        public Boolean chk{get;set;}
        
        public wrTra(Account_Benefit__c ben){
            this.tra=ben;
            this.chk=false;
            
        }
    } 
}