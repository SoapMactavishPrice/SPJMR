public with sharing class EditAllProgramBatch { 
    
    public string currentRecID{get;set;}
    public Account acc {get;set;}    
    public List<Account_Program_Batch_Selection__c> programlist{get;set;}
    public List<Program_Batch_Wise_Payment__c> FeePlanlist{get;set;}
    public List<Program_Batch_Wise_Payment__c> bwList {get;set;}
    public Decimal ProgCount {get; set;}
    
    public EditAllProgramBatch(){
        
        currentRecID=ApexPages.CurrentPage().getparameters().get('id');
        
        acc=[ SELECT  Id, Name FROM Account  where id=:currentRecID];
        
        programlist=[ SELECT Id,Name,Program_Name__c,Batch_Name__c,Student_Name__c,Program_Status__c,Total_Fee_Amount__c,School_Name__c, 
                     Total_Amount_Received__c,Remaining_Amount__c,School_Name__r.Name,Batch_Name__r.Name,Program_Name__r.Name,Admission_Date__c,
                     Status__c,Reason_for_Withdrawal__c,Withdrawal_Request_Date__c,Session_Batch_Start_Date__c,Session_Batch_End_Date__c,
                     MG_Father_Corporate_Analytics__c, MG_Mother_Corporate_Analytics__c ,
                     School_Name__r.School_Head_Email__c,School_Name__r.School_Head_Name__c, Date_of_Admission__c, Illumine_Class_Name__c,
                     School_Name__r.Finance_Head__c
                     FROM Account_Program_Batch_Selection__c  where Student_Name__c=:acc.Id ];  //and Program_Status__c ='Draft'
        //and Program_Status__c ='Draft' 
        
        system.debug('programlist....'+programlist);
        system.debug('programlist....'+programlist.size());
        
        ProgCount=programlist.size();
        
        if(ProgCount == 0){
            ApexPages.Message msg = new ApexPages.Message(ApexPages.Severity.ERROR,'No Program to take Admission.!!!!!!');
            ApexPages.addMessage(msg);
        }
        
        Set<id> plset= new Set<id>();       
        for(Account_Program_Batch_Selection__c p:programlist){
            plset.add(p.id);
        }
        
        FeePlanlist=[ SELECT  Id,  Name,  Program_Name__c,  Batch_Name__c,Payment_Type__c,Fees__c,Payment_Source__c, 
                     Payment_Status__c,Program_Batch_Selection__c,Fee_Plan_Name__c,Benefit_Applicable__c,
                     Total_Amount_Received__c,  Remaining_Amount__c,  Total_Fee_Amount__c,  
                     Student_Name__c,  School_Name__c,  Total_Amount__c
                     FROM Program_Batch_Wise_Payment__c where Program_Batch_Selection__c IN: plset order by name];
        
        system.debug('FeePlanlist....'+FeePlanlist);
        system.debug('FeePlanlist....'+FeePlanlist.size());
    }
    
    
    Public Pagereference Save(){
        
         //this is for Security Source Scanner
        String [] progbatchUpdateFields = new String [] {'School_Head_Name__c','School_Head_Email__c','Status__c','Finance_Head__c'};
                
        // Obtaining the field name/token map for the program batchwise payment line item sibling object
        Map<String,Schema.SObjectField> credrecp = Schema.SObjectType.Account_Program_Batch_Selection__c.fields.getMap();
        for (String fieldToCheck : progbatchUpdateFields) {
            // Check if the user has create access on the each field
            if (!credrecp.get(fieldToCheck).getDescribe().isUpdateable()) {
                ApexPages.addMessage(new ApexPages.Message(ApexPages.Severity.FATAL, 'Insufficient access'));
                return null; 
            }
        }
        
        List<Account_Program_Batch_Selection__c> accprogList = new List<Account_Program_Batch_Selection__c>();
        List<Program_Batch_Wise_Payment__c> progbatchpaylist = new List<Program_Batch_Wise_Payment__c>();
        
        set<string> accpString1 = new set<string>();
        
        //add by shashank to collect student id
         Set<ID> studIDs = new Set<ID>(); 
        
        for(Account_Program_Batch_Selection__c op:programlist){
            
            if(op.Admission_Date__c > op.Session_Batch_End_Date__c ){
                ApexPages.addmessage(new ApexPages.message(ApexPages.severity.Error,'Admission Date Cannot Be Greater Than Session End Date'));
                return null;
            }
            
            else if(op.Admission_Date__c < op.Session_Batch_Start_Date__c ){
                ApexPages.addmessage(new ApexPages.message(ApexPages.severity.Error,'Admission Date Cannot Be Less Than Session Start Date'));
                return null;
            }

            else if(op.Admission_Date__c != null  ){
                op.Status__c='In Progress';
                op.School_Head_Email__c=op.School_Name__r.School_Head_Email__c ;
                op.School_Head_Name__c=op.School_Name__r.School_Head_Name__c;
                op.Finance_Head__c=op.School_Name__r.Finance_Head__c;
                studIDs.add(op.Student_Name__c);
            }
           
            accprogList.add(op);
        }
        System.debug('=====accprogList=========>'+accprogList);
        if(accprogList.size()>0){
            update accprogList;
            
        }
        
        /////////////////////////  PRO RATA   //////////////////////////////////////
        
        List<Program_Batch_Wise_Payment__c> ubwList = [SELECT Id,Program_Batch_Selection__r.Admission_Date__c  
                                                       FROM Program_Batch_Wise_Payment__c WHERE Program_Batch_Selection__c IN: accprogList];
        
        for(Program_Batch_Wise_Payment__c pbwp: ubwList){
            pbwp.Admission_Date__c = pbwp.Program_Batch_Selection__r.Admission_Date__c;
        }
        update ubwList;
        
          bwList= [ SELECT  Id,  Name,  Program_Name__c,  Batch_Name__c,  Payment_Type__c,  Fees__c,Payment_Source__c, 
                                    Payment_Status__c,Program_Batch_Selection__c,Fee_Plan_Name__c,Payment_Collection_Type__c,
                                    Benefit_Applicable__c,Difference_in_Months__c,  Admission_Date__c ,  
                                    Total_Amount_Received__c,Remaining_Amount__c,Actual_Amount_Per_Month__c, 
                                    Total_Fee_Amount__c,  Student_Name__c,  School_Name__c,Total_Amount__c,  
                                    No_Of_Instalment__c,Actual_Fees__c,Amount_Per_Month__c,Fees_without_Benefit__c,  
                                    No_Of_Instalment_Created__c,Pro_Rata_Fees_Applicable__c,Refund_Applicable__c, Tenure_Type__c , 
                                    Total_Pro_Rata_Fees__c,  No_of_Months__c,Cheque_Issue_Date__c,  Cheque_Deposit_Date__c,   
                                    Total_Benefit_Amount__c,  Cheque_Number__c,   Amount_Received__c,  Amount_Received_Date__c,  
                                    Date_of_Transaction__c, Grand_Total1__c,Pro_Rata_Updated__c
                                    FROM Program_Batch_Wise_Payment__c Where Program_Batch_Selection__c IN :accprogList
                                    AND Pro_Rata_Fees_Applicable__c=true];
        
        map<id,Program_Batch_Wise_Payment__c> progbatchwiseList = new map<id,Program_Batch_Wise_Payment__c>();
        map<id,Program_Batch_Wise_Instalment__c> batchWisemap = new map<id,Program_Batch_Wise_Instalment__c>();
        List<Program_Batch_Wise_Instalment__c> InstalToUpdate = new List<Program_Batch_Wise_Instalment__c>();    
    
    for(Program_Batch_Wise_Payment__c bw : bwList){
        progbatchwiseList.put(bw.id,bw);
        //  progbatchwiseList.put(bw.id,bw);    
     Decimal DiffAmt=0;
     Decimal dec=0;
     Boolean firsttimeCheck = false; 
     Decimal joterm=0;
      
    // ************For Monthly Wise Pro Rata*************************
    
    if(bw.Pro_Rata_Fees_Applicable__c==true && bw.Admission_Date__c!=Null &&
       bw.Tenure_Type__c=='Monthly' && bw.Pro_Rata_Updated__c==false){
       
       system.debug('inside meals*********');
       
        
        
        for(Program_Batch_Wise_Instalment__c pb :[SELECT  Id,Name,Amount_Received__c,Status__c,Remaining_Amount__c,
                                                  Total_Amount__c,Student_Name__c,Program_Name__c,Batch_Name__c,Batch_Name__r.Name,
                                                  Program_Batch_Wise_Payment__c, Instalment_Name__r.Name,
                                                  School_Name__r.Name, Student_Name__r.Name, Program_Name__r.Name, School_Name__c, 
                                                   Fee_Plan_Name__c,Program_Batch_Wise_Payment__r.Amount_Per_Month__c,
                                                  Program_Batch_Wise_Payment__r.Difference_in_Months__c, Instalment_Fees__c,
                                                  Program_Batch_Wise_Payment__r.Difference_In_Amount__c,GST_Amount__c, 
                                                  Program_Batch_Wise_Payment__r.Pro_Rata_Updated__c,Previous_Fees__c
                                                  FROM Program_Batch_Wise_Instalment__c Where Program_Batch_Wise_Payment__c=:bw.id]){
           system.debug('pb*'+pb);
           system.debug('pb** ** '+pb.Program_Batch_Wise_Payment__r.Difference_In_Amount__c);
           DiffAmt= pb.Program_Batch_Wise_Payment__r.Difference_In_Amount__c;
           system.debug('DiffAmt******'+DiffAmt);     
            if(firsttimeCheck == false){
                dec =  DiffAmt;
                system.debug('***dec*'+dec); 
                system.debug('***pb*'+pb); 
                system.debug('***pb*'+pb.Instalment_Fees__c); 
                if(dec >= pb.Instalment_Fees__c){
                    dec = dec - pb.Instalment_Fees__c; 
                    pb.Instalment_Fees__c = 0;
                    pb.Status__c='Opt-out';
                    pb.Previous_Fees__c=0;
                    pb.GST_Amount__c=0;
                    system.debug('Inside if***'+dec); 
                }
                else if(dec<=pb.Instalment_Fees__c){
                    pb.Instalment_Fees__c=pb.Instalment_Fees__c-dec;
                    dec=0;
                     //pb.Status__c='Opt-out';
                    system.debug('Inside else if***'+dec); 
                }
               InstalToUpdate.add(pb);
                firsttimeCheck = true;
            }
            else{
                if(dec>=pb.Instalment_Fees__c){
                     system.debug('Inside else if***'+dec); 
                     system.debug('***pb*'+pb.Instalment_Fees__c);
                     dec =  dec - Pb.Instalment_Fees__c;  
                     system.debug('dec***1st else if***'+dec); 
                     pb.Instalment_Fees__c=0;
                     pb.Status__c='Opt-out';
                     pb.Previous_Fees__c=0;
                     pb.GST_Amount__c=0;
                     InstalToUpdate.add(pb);
                } 
                if(dec<=pb.Instalment_Fees__c){
                     system.debug('Inside else if***'+dec); 
                     system.debug('***pb*'+pb.Instalment_Fees__c);
                     pb.Instalment_Fees__c=pb.Instalment_Fees__c-dec;
                     dec=0;
                     //pb.Status__c='Opt-out';
                     InstalToUpdate.add(pb);
                    //break;
                } 
             }
                batchWisemap.putAll(InstalToUpdate);
                bw.Pro_Rata_Updated__c=true;
                progbatchwiseList.put(bw.id,bw);
         }               
          
   }
   // ***************** For Term Wise Pro Rata************************
   
   if(bw.Pro_Rata_Fees_Applicable__c==true && bw.Admission_Date__c!=Null && bw.Tenure_Type__c=='Term' && bw.Pro_Rata_Updated__c==false){
       
       system.debug('inside Tution Fee*********');

        for(Program_Batch_Wise_Instalment__c pb :[SELECT  Id,  Name, Amount_Received__c,  Remaining_Amount__c,  Payment_Collection_Type__c,  
                                                  Amount_Received_Date__c, Payment_Realization_Date__c, 
                                                  Total_Amount__c,Student_Name__c,Program_Name__c,Batch_Name__c,Batch_Name__r.Name, 
                                                  Cheque_Number__c,Cheque_Issue_Date__c,  
                                                  Cheque_Deposit_Date__c,  Transaction_Reference_Number__c,  Date_of_Transaction__c,  
                                                  School_Name__r.Name, Student_Name__r.Name, Program_Name__r.Name, School_Name__c,  
                                                  Program_Batch_Wise_Payment__c, Instalment_Name__r.Name,GST_Amount__c,
                                                   Fee_Plan_Name__c,Program_Batch_Wise_Payment__r.Amount_Per_Month__c,
                                                  Program_Batch_Wise_Payment__r.Difference_in_Months__c, Instalment_Fees__c,
                                                  Program_Batch_Wise_Payment__r.Difference_In_Amount__c,
                                                  Program_Batch_Wise_Payment__r.Joining_Term__c,Term1__c
                                                  FROM Program_Batch_Wise_Instalment__c Where Program_Batch_Wise_Payment__c=:bw.id]){
           system.debug('pb*'+pb);
           DiffAmt= pb.Program_Batch_Wise_Payment__r.Difference_In_Amount__c;
           system.debug('DiffAmt******'+DiffAmt);   
           dec =  DiffAmt;
           joterm = pb.Program_Batch_Wise_Payment__r.Joining_Term__c;
           system.debug('joterm--------'+joterm);
           
           // For Joining Term= 2
           if(dec>=pb.Instalment_Fees__c && joterm==2 && pb.Term1__c==1){
               system.debug('inside if');
               dec=dec-pb.Instalment_Fees__c;
               system.debug('*dec******'+dec);
               pb.Instalment_Fees__c=0;
               pb.Previous_Fees__c=0;
                pb.GST_Amount__c=0;
               pb.Status__c='Opt-out';
               InstalToUpdate.add(pb);
           }
           
           // For Joining Term= 3
           if(dec>=pb.Instalment_Fees__c && joterm==3 && pb.Term1__c==1){
               system.debug('inside if');
               dec=dec-pb.Instalment_Fees__c;
               system.debug('*dec******'+dec);
               pb.Instalment_Fees__c=0;
               pb.Previous_Fees__c=0;
                pb.GST_Amount__c=0;
               pb.Status__c='Opt-out';
               InstalToUpdate.add(pb);
           }
           else if(dec>=pb.Instalment_Fees__c && joterm==3 && pb.Term1__c==2){
               system.debug('inside if');
               dec=dec-pb.Instalment_Fees__c;
               system.debug('*dec******'+dec);
               pb.Instalment_Fees__c=0;
               pb.Previous_Fees__c=0;
                pb.GST_Amount__c=0;
               pb.Status__c='Opt-out';
               InstalToUpdate.add(pb);
           }
           
           // For Joining Term= 4
           if(dec>=pb.Instalment_Fees__c && joterm==4 && pb.Term1__c==1){
               system.debug('inside if');
               dec=dec-pb.Instalment_Fees__c;
               system.debug('*dec******'+dec);
               pb.Instalment_Fees__c=0;
               pb.Previous_Fees__c=0;
                pb.GST_Amount__c=0;
               pb.Status__c='Opt-out';
               InstalToUpdate.add(pb);
           }
           else if(dec>=pb.Instalment_Fees__c && joterm==4 && pb.Term1__c==2){
               system.debug('inside if');
               dec=dec-pb.Instalment_Fees__c;
               system.debug('*dec******'+dec);
               pb.Instalment_Fees__c=0;
               pb.Previous_Fees__c=0;
                pb.GST_Amount__c=0;
                pb.Status__c='Opt-out';
               InstalToUpdate.add(pb);
           }
           else if(dec>=pb.Instalment_Fees__c && joterm==4 && pb.Term1__c==3){
               system.debug('inside if');
               dec=dec-pb.Instalment_Fees__c;
               system.debug('*dec******'+dec);
               pb.Instalment_Fees__c=0;
               pb.Previous_Fees__c=0;
                pb.GST_Amount__c=0;
                pb.Status__c='Opt-out';
               InstalToUpdate.add(pb);
           }
           
           // For Joining Term= 5
           if(dec>=pb.Instalment_Fees__c && joterm==5 && pb.Term1__c==1){
               system.debug('inside if');
               dec=dec-pb.Instalment_Fees__c;
               system.debug('*dec******'+dec);
               pb.Instalment_Fees__c=0;
               pb.Previous_Fees__c=0;
                pb.GST_Amount__c=0;
                pb.Status__c='Opt-out';
               InstalToUpdate.add(pb);
           }
           else if(dec>=pb.Instalment_Fees__c && joterm==5 && pb.Term1__c==2){
               system.debug('inside if');
               dec=dec-pb.Instalment_Fees__c;
               system.debug('*dec******'+dec);
               pb.Instalment_Fees__c=0;
               pb.Previous_Fees__c=0;
                pb.GST_Amount__c=0;
                pb.Status__c='Opt-out';
               InstalToUpdate.add(pb);
           }
           else if(dec>=pb.Instalment_Fees__c && joterm==5 && pb.Term1__c==3){
               system.debug('inside if');
               dec=dec-pb.Instalment_Fees__c;
               system.debug('*dec******'+dec);
               pb.Instalment_Fees__c=0;
               pb.Previous_Fees__c=0;
                pb.GST_Amount__c=0;
                pb.Status__c='Opt-out';
               InstalToUpdate.add(pb);
           }
           else if(dec>=pb.Instalment_Fees__c && joterm==5 && pb.Term1__c==4){
               system.debug('inside if');
               dec=dec-pb.Instalment_Fees__c;
               system.debug('*dec******'+dec);
               pb.Instalment_Fees__c=0;
               pb.Previous_Fees__c=0;
                pb.GST_Amount__c=0;
                pb.Status__c='Opt-out';
               InstalToUpdate.add(pb);
           }
           
           
           // For Joining Term= 6
           if(dec>=pb.Instalment_Fees__c && joterm==6 && pb.Term1__c==1){
               system.debug('inside if');
               dec=dec-pb.Instalment_Fees__c;
               system.debug('*dec******'+dec);
               pb.Instalment_Fees__c=0;
               pb.Previous_Fees__c=0;
                pb.GST_Amount__c=0;
                pb.Status__c='Opt-out';
               InstalToUpdate.add(pb);
           }
           else if(dec>=pb.Instalment_Fees__c && joterm==6 && pb.Term1__c==2){
               system.debug('inside if');
               dec=dec-pb.Instalment_Fees__c;
               system.debug('*dec******'+dec);
               pb.Instalment_Fees__c=0;
               pb.Previous_Fees__c=0;
                pb.GST_Amount__c=0;
                pb.Status__c='Opt-out';
               InstalToUpdate.add(pb);
           }
           else if(dec>=pb.Instalment_Fees__c && joterm==6 && pb.Term1__c==3){
               system.debug('inside if');
               dec=dec-pb.Instalment_Fees__c;
               system.debug('*dec******'+dec);
               pb.Instalment_Fees__c=0;
               pb.Previous_Fees__c=0;
                pb.GST_Amount__c=0;
                pb.Status__c='Opt-out';
               InstalToUpdate.add(pb);
           }
           
           else if(dec>=pb.Instalment_Fees__c && joterm==6 && pb.Term1__c==4){
               system.debug('inside if');
               dec=dec-pb.Instalment_Fees__c;
               system.debug('*dec******'+dec);
               pb.Instalment_Fees__c=0;
               pb.Previous_Fees__c=0;
                pb.GST_Amount__c=0;
                pb.Status__c='Opt-out';
               InstalToUpdate.add(pb);
           }
           
           else if(dec>=pb.Instalment_Fees__c && joterm==6 && pb.Term1__c==5){
               system.debug('inside if');
               dec=dec-pb.Instalment_Fees__c;
               system.debug('*dec******'+dec);
               pb.Instalment_Fees__c=0;
               pb.Previous_Fees__c=0;
                pb.GST_Amount__c=0;
                pb.Status__c='Opt-out';
               InstalToUpdate.add(pb);
           }
           
             batchWisemap.putAll(InstalToUpdate);
             bw.Pro_Rata_Updated__c=true;
             progbatchwiseList.put(bw.id,bw);
         }                     
   }
 }
        if(batchWisemap.size()>0){  
            checkRecursive.isFirstTime = false;
            update batchWisemap.values();
            update progbatchwiseList.values();
        }
        
        
       /* 
       // List<Account_Program_Batch_Selection__c> contactList = new List<Account_Program_Batch_Selection__c> (); 
       Set<Id> accountIdsSet = new Set<Id>();
        for ( Account_Program_Batch_Selection__c con : programlist ) {
                // for Father MG
                if (con.MG_Father_Corporate_Analytics__c != null && con.Admission_Date__c != Null ){
                    accountIdsSet.add(con.MG_Father_Corporate_Analytics__c);
                }
                // for Mother MG
                if (con.MG_Mother_Corporate_Analytics__c != null && con.Admission_Date__c != Null ){
                    accountIdsSet.add(con.MG_Mother_Corporate_Analytics__c);
                }
                
        }
            
        
        // For Father MG
            List<Corporate_Analytics__c> accountList = [Select Id, Name, Male_Employees_Child__c, No_of_Female_Employees_gets_Benefits__c,
                                                        MG_Seats_Admitted_For_Male__c, MG_Seats_Admitted_For_Female__c, 
                                                        (Select Id, Admission_Date__c,Father_Corporate_Benefit__c,Mother_Corporate_Benefit__c 
                                                         From MGFatherCorporateAnalytics__r where Admission_Date__c != Null)
                                                        From Corporate_Analytics__c Where Id IN : accountIdsSet];
            system.debug('accountList-----'+accountList);
            
            for (Corporate_Analytics__c acc : accountList) {
                List<Account_Program_Batch_Selection__c> relatedContacts = acc.MGFatherCorporateAnalytics__r;
                if ( relatedContacts != null ){
                    acc.MG_Seats_Admitted_For_Male__c = acc.MGFatherCorporateAnalytics__r.size();
                }
            } 
            update accountList;
        
        // For Mother MG
            List<Corporate_Analytics__c> accountList1 = [Select Id, Name, Male_Employees_Child__c, No_of_Female_Employees_gets_Benefits__c,
                                                         MG_Seats_Admitted_For_Male__c, MG_Seats_Admitted_For_Female__c, 
                                                         (Select Id, Admission_Date__c,Father_Corporate_Benefit__c, MG_Father_Corporate_Analytics__c,
                                                          MG_Mother_Corporate_Analytics__c, Mother_Corporate_Benefit__c 
                                                          From MGMotherCorporateAnalytics__r Where Admission_Date__c != Null)
                                                         From Corporate_Analytics__c Where Id IN : accountIdsSet];
            for (Corporate_Analytics__c acc : accountList1) {
                List<Account_Program_Batch_Selection__c> relatedContacts1 = acc.MGMotherCorporateAnalytics__r;
                if ( relatedContacts1 != null ){
                    acc.MG_Seats_Admitted_For_Female__c = acc.MGMotherCorporateAnalytics__r.size();
                }
            } 
            update accountList1;
              */
            
        pagereference pg= new pagereference('/'+currentRecID);
        pg.setRedirect(true);
        return pg;  
    }
    
    Public Pagereference Cancel(){
        
        pagereference pg=new pagereference('/'+currentRecID);
        pg.setRedirect(true);
        return pg;        
    }   
}