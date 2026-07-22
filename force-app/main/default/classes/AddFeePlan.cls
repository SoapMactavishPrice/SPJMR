public With Sharing class AddFeePlan {
    
    public List < Program_Batch_Wise_Payment__c > selist {get;set;}
    public Id opid {get;set;}
    public Set<Id> progId = new Set<Id>();
    public List<wrTra> wrlist{get; set;}        
    public list<Account_Program_Batch_Selection__c> proglist{get;set;}
    public List<Batch_Wise_Fee_Plan__c> programlist{get;set;}
    public list<Account_Program_Batch_Selection__c> proglist2 = new list<Account_Program_Batch_Selection__c>();
    public Account_Program_Batch_Selection__c apbs{get; set;}
    public list<Account_Program_Batch_Selection__c> acntlist {get;set;}
    public Id Rtid{get;set;}
    //public Id FeeId{get;set;} commented on 26th feb
    public Account acc{get;set;}
    public Map<string, List<Batch_Wise_Fee_Plan__c>> sMap {get;set;}
    set<String> acctben = new set<String>();

    
    public AddFeePlan() {
        
        opid = ApexPages.currentPage().getParameters().get('id'); 
        acc = [SELECT Id, Name, School_Lookup__c, School_Lookup__r.Name,Student_Category__c from Account where id =: opid Order By Name];
                
    }
    
       // Get Program / Batch Selection
    public List<SelectOption> getprogramlist1(){
        List < SelectOption > options = new List < SelectOption > ();
        proglist=[select id,Name,Program_Name__c,School_Name__c,Batch_Name__c,Program_Name__r.Name,Batch_Name__r.Name
                  from Account_Program_Batch_Selection__c where Student_Name__c=:opid ORDER by Name];
        proglist2=proglist;
        system.debug('School>>>>>>>'+proglist);
        options.add(new SelectOption('None', 'None'));
        for(Account_Program_Batch_Selection__c sc:proglist){
            options.add(new SelectOption(sc.Batch_Name__c, sc.Program_Name__r.Name+ ' / ' +sc.Batch_Name__r.Name));
        }
        return options;
    } 
    
    public void render(){
        
        sMap = new Map<string, List<Batch_Wise_Fee_Plan__c>>();
        
        system.debug('Rtid>>>>>>>'+Rtid);
        wrlist = new List<wrTra>();  
        
        Set<Id> setprogramId = new Set<Id>();
        
        for(Account_Program_Batch_Selection__c ap : [Select Id, Name, Batch_Name__c  From  Account_Program_Batch_Selection__c
                                                     where Batch_Name__c=:Rtid AND Student_Name__c=:opid]){ 
                                                         setprogramId.add(ap.id);
                                                         System.debug('**************************program'+setprogramId);
                                                     }
        
        for(Program_Batch_Wise_Payment__c  ab: [SELECT Id, Name, Fee_Plan_Name__c, Batch_Name__c FROM Program_Batch_Wise_Payment__c 
                                                Where  Program_Batch_Selection__c in : setprogramId ]){
                                                    acctben.add(ab.Fee_Plan_Name__c);
                                            		System.debug('acctben------'+acctben);
                                        }
        
        programlist = [SELECT Id,Name,Batch_Name__c,Batch_Code__c, 
                       Benefit_Applicable__c,Year__c,Tenure_Type__c,Payment_Type__c,
                       Total_Amount__c,Program_Name__c,Actual_Fees__c,
                       Refund_Applicable__c,Pro_Rata_Fees_Applicable__c,Amount_Per_Month__c,Type__c,No_of_Terms__c, 
                       No_of_Months__c,Fees_without_Benefit__c,Total_Benefit_Value__c,Total_Benefit_Percentage__c,
                       Total_Benefit_Amount__c,Number_of_Instalment__c,Fees_with_Benefit__c,No_Of_Instalment_Created__c,
                       Batch_Name__r.School_Name__c,Fee_Plan_Type__c, Fee_Plan_Category_Master__c,Select__c,
                       Fee_Plan_Category_Master__r.Name,Tax_Applicable__c, Total_Amount_with_Tax__c FROM Batch_Wise_Fee_Plan__c
                       where Batch_Name__c =:Rtid and Batch_Name__r.School_Name__c=:acc.School_Lookup__r.Name 
                       and Fee_Plan_Type__c =:acc.Student_Category__c 
                       order by Name]; //and id NOT IN :acctben
        
        Set<id> plset= new Set<id>();  
        System.debug('programlist---++++---'+programlist);
        System.debug('programlist size---++++---'+programlist.size());
        
        for(Batch_Wise_Fee_Plan__c p:programlist){
            plset.add(p.id);
        }
        
        for(Batch_Wise_Fee_Plan__c p: programlist){
            System.debug('programlist---++++---'+p.Fee_Plan_Category_Master__r.Name);
            String unq =p.Fee_Plan_Category_Master__r.Name;
            
            if(sMap.get(unq)==Null){
                
                List<Batch_Wise_Fee_Plan__c> plist = new List<Batch_Wise_Fee_Plan__c>();
                plist.add(p);
                sMap.put(unq, plist);
            }
            else{
                List<Batch_Wise_Fee_Plan__c> plist = new List<Batch_Wise_Fee_Plan__c>();
                //List<Batch_Wise_Fee_Plan__c> plist = sMap.get(unq);
                plist.add(p);
                sMap.put(unq, plist);
            }
        }
        //system.debug('sMap====='+JSON.serialize(sMap));  
        
    }
    
    public PageReference save() { 
        
        String [] contactUpdateFields = new String [] {'Program_Batch_Selection__c','Fee_Plan_Name__c','Actual_Fees__c',
            'Benefit_Applicable__c','Payment_Type__c','Refund_Applicable__c','Pro_Rata_Fees_Applicable__c','Tax_Code__c',
            'Pro_Rata_Fees_Applicable__c','Tenure_Type__c','Fee_Plan_Category_Master__c','Fee_Plan_Type__c','Tax_Applicable__c',
            'Batch_Name__c','Program_Name__c','Student_Name__c','School_Name__c'};
                
        // Obtaining the field name/token map for the Contact object
        Map<String,Schema.SObjectField> m = Schema.SObjectType.Program_Batch_Wise_Payment__c.fields.getMap();
        for (String fieldToCheck : contactUpdateFields) {
            // Check if the user has create access on the each field
            if (!m.get(fieldToCheck).getDescribe().isCreateable()) {
                ApexPages.addMessage(new ApexPages.Message(ApexPages.Severity.FATAL,'Insufficient access'));
                return null;
            }
        }
        
        Map<id,Id> plMap= new Map<id,Id>();
        for(Account_Program_Batch_Selection__c sc:proglist2){
            plMap.put(sc.Batch_Name__c,sc.id);
        }
     
           selist = new List < Program_Batch_Wise_Payment__c > ();
        for(Account_Program_Batch_Selection__c acnt: [select id, Program_Name__c,Batch_Name__c,Student_Name__c,School_Name__c,Tax_Code__c 
              from Account_Program_Batch_Selection__c where Student_Name__c=:opid and Batch_Name__c =:Rtid ]){
           
        
                  system.debug('wrlist>>>>>>>>>>>>>>>'+wrlist);
                  for(Batch_Wise_Fee_Plan__c wt:programlist){ 
                      system.debug('wrlist>>>>>>>>>>>>>>>'+wrlist);
                      if(wt.Select__c){
                          
                          Program_Batch_Wise_Payment__c oppt = new Program_Batch_Wise_Payment__c();
                          
                          oppt.Program_Batch_Selection__c = plMap.get(wt.Batch_Name__c) ;     
                          
                          oppt.Fee_Plan_Name__c=wt.id;
                          oppt.Actual_Fees__c=wt.Actual_Fees__c;
                          oppt.Benefit_Applicable__c=wt.Benefit_Applicable__c;
                          oppt.Payment_Type__c=wt.Payment_Type__c;
                          oppt.Refund_Applicable__c=wt.Refund_Applicable__c;
                          oppt.Pro_Rata_Fees_Applicable__c=wt.Pro_Rata_Fees_Applicable__c;
                          oppt.Tenure_Type__c=wt.Tenure_Type__c; 
                          oppt.Fee_Plan_Category_Master__c=wt.Fee_Plan_Category_Master__c;
                          oppt.Fee_Plan_Type__c=wt.Fee_Plan_Type__c;
                          oppt.Tax_Applicable__c=wt.Tax_Applicable__c;
                          
                          
                          oppt.Batch_Name__c=acnt.Batch_Name__c;
                          oppt.Program_Name__c=acnt.Program_Name__c;
                          oppt.Student_Name__c=acnt.Student_Name__c;
                          oppt.School_Name__c=acnt.School_Name__c;
                          oppt.Tax_Code__c=acnt.Tax_Code__c;
                          
                          selist.add(oppt);
                          system.debug('selist------------'+selist);
                      }           
                  }
        }
        
        insert selist;
        
        PageReference pageRef = new PageReference('/' + opid);
        pageRef.setRedirect(true);
        return pageRef;       
     }
    
    public PageReference cancel() {
        
        PageReference pageRef = new PageReference('/' + opid);
        pageRef.setRedirect(true);
        return pageRef;      
    }
    
    public class wrTra{
        
        public Batch_Wise_Fee_Plan__c  tra {get;set;}
        public Boolean chk{get;set;}
        
        public wrTra(Batch_Wise_Fee_Plan__c  doc){
            this.tra=doc;
            this.chk=false;
        }
    }   
}