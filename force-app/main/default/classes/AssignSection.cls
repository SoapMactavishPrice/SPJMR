public with sharing  class AssignSection {
    
    public List < Account_Program_Batch_Selection__c > selist {get;set;}
    public Account acc {get;set;} 
    public Id opid {get;set;}
    Static Id sId;
    public List<wrTra> wrlist{get; set;}        
    //public List<wrTra> wrlist3{get; set;}        
    public String wrlist1 {get; set;} 
    set<String> acctben = new set<String>();
    static Account_Program_Batch_Selection__c aclist {get;set;}
    public List<Account_Program_Batch_Selection__c> programlist{get;set;}
    
    public AssignSection() {
        
        opid = ApexPages.currentPage().getParameters().get('id');     
        
        //selist = new list<Account_Program_Batch_Selection__c>();
        
        acc = [SELECT Id, Name from Account where id =: opid Order By Name];
        
        programlist=[Select Id, Name,Student_Name__c,Batch_Name__c From Account_Program_Batch_Selection__c where Student_Name__c=:opid ];
        
         Set<id> plset= new Set<id>();
        
        for(Account_Program_Batch_Selection__c p:programlist){
            plset.add(p.Batch_Name__c);
        }
        
        sId = opid;
        System.debug('SID'+sId);
        wrlist = new List<wrTra>();   
        
        for(Account_Program_Batch_Selection__c ab: [SELECT Id, Name,Section__c FROM Account_Program_Batch_Selection__c 
                                                    Where  Student_Name__c=:opid ]){
                                                        
                                                        system.debug('ab------'+ab);
                                                        acctben.add(ab.Section__c);
                                                        system.debug('acctben------'+acctben);
                                                    }
        
        for(Section__c tc:[ SELECT  Id,Name, Max_Strength__c, Grade__c,Total_Admitted__c, Remaining__c 
                           FROM Section__c  where Grade__c in : plset and id NOT IN :acctben order by name]){
                               
                               System.debug('====> data: ' + JSON.serialize(tc));    
                               wrlist.add(new wrTra(tc));
                           }
        wrlist1 = JSON.serialize(wrlist);
        
    }
    
    @RemoteAction
    public static void save(String json, String id ) {
        
        //this is for Security Source Scanner
            String [] avFields4 = new String [] {'Id'};
                
                // Obtaining the field name/token map for the Assignd vehicle object
                Map<String,Schema.SObjectField> credrecp4 = Schema.SObjectType.Account_Program_Batch_Selection__c.fields.getMap();
            for (String fieldToCheck : avFields4) {
                // Check if the user has create access on the each field
                if (!credrecp4.get(fieldToCheck).getDescribe().isUpdateable()==false) {
                    ApexPages.addMessage(new ApexPages.Message(ApexPages.Severity.FATAL, 'Insufficient access'));
                    return; 
                }
            } 
        
        String [] contactUpdateFields = new String [] {'Section__c'};
            
            // Obtaining the field name/token map for the Contact object
            Map<String,Schema.SObjectField> m = Schema.SObjectType.Account_Program_Batch_Selection__c.fields.getMap();
        for (String fieldToCheck : contactUpdateFields) {
            // Check if the user has create access on the each field
            if (!m.get(fieldToCheck).getDescribe().isUpdateable()) {
               ApexPages.addMessage(new ApexPages.Message(ApexPages.Severity.FATAL, 'Insufficient access'));
                return;
            }
        }
        
        
        List<wrTra> wrlist = parsewTra(json);
        
        List<Account_Program_Batch_Selection__c> selist=new List<Account_Program_Batch_Selection__c>();
        
        Account_Program_Batch_Selection__c aclist=[Select Id, Name, Student_Name__c
                                                   From Account_Program_Batch_Selection__c where Student_Name__c=:id];
        for(wrTra wt:wrlist){ 
            if(wt.chk == true){
                
                Account_Program_Batch_Selection__c oppt = new Account_Program_Batch_Selection__c();
                
                oppt.id=aclist.id;
                oppt.Section__c=wt.tra.id;
                
                selist.add(oppt);
                system.debug('selist------------'+selist);
            }           
        }
        update selist;
        
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
        
        public Section__c tra {get;set;}
        public Boolean chk{get;set;}
        
        public wrTra(Section__c ben){
            this.tra=ben;
            this.chk=false;
            
        }
    }   
}