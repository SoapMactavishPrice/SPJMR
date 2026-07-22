trigger updateBenifitLogicBatch on Batch_Wise_Benefit__c(after insert, after update, before delete) {
    
    System.debug('Object msgIn trigger');
    Set < Id > setacccid = new Set < Id > ();
    
    if (Trigger.isInsert) {
        
        map<string,List<Batch_Wise_Instalment__c>> mapBatchWiseIns = new  map<string,List<Batch_Wise_Instalment__c>>();
        List<String> batchFeeWisList = new List<String>();
        for (Batch_Wise_Benefit__c acc: trigger.new) {
            batchFeeWisList.add(acc.Batch_Wise_Fee_Plan__c);
        }
        
        
        List < Batch_Wise_Instalment__c > batchInvList = new List < Batch_Wise_Instalment__c >();
        batchInvList = [select Batch_Wise_Fee_Plan__c, Name, Exclude_Benefit__c, Instalment_Fees__c from Batch_Wise_Instalment__c where Batch_Wise_Fee_Plan__c in : batchFeeWisList and Exclude_Benefit__c != true];
        
        for(Batch_Wise_Instalment__c b:batchInvList){
            List<Batch_Wise_Instalment__c> bwI = new List<Batch_Wise_Instalment__c>();
            
            if(mapBatchWiseIns.containsKey(b.Batch_Wise_Fee_Plan__c)){
                bwI = mapBatchWiseIns.get(b.Batch_Wise_Fee_Plan__c);
                bwI.add(b);
                mapBatchWiseIns.put(b.Batch_Wise_Fee_Plan__c,bwI);
            }else{
                bwI.add(b);
                  mapBatchWiseIns.put(b.Batch_Wise_Fee_Plan__c,bwI);
            }
            
          
        }
        
         List < Batch_Wise_Instalment__c > bwInvList = new List < Batch_Wise_Instalment__c > ();
        for (Batch_Wise_Benefit__c acc: trigger.new) {
            System.debug('Object msgIn trigger=' + acc.Is_Benefit_in_Percentage__c);
            setacccid.add(acc.Id);
           // List < Batch_Wise_Instalment__c > bwInv = [select Batch_Wise_Fee_Plan__c, Name, Exclude_Benefit__c, Instalment_Fees__c from Batch_Wise_Instalment__c where Batch_Wise_Fee_Plan__c =: acc.Batch_Wise_Fee_Plan__c and Exclude_Benefit__c != true];
            List < Batch_Wise_Instalment__c > bwInv = new List < Batch_Wise_Instalment__c > ();
            bwInv = mapBatchWiseIns.get(acc.Batch_Wise_Fee_Plan__c);
            System.debug('Object msgtt' + bwInv);
            
            if (acc.Is_Benefit_in_Percentage__c == true && acc.Benefit_Percentage__c > 0) {
                for (Batch_Wise_Instalment__c b: bwInv) {
                    b.Instalment_Fees__c = (b.Instalment_Fees__c - ((b.Instalment_Fees__c * acc.Benefit_Percentage__c) / 100)).setScale(2, RoundingMode.FLOOR);
                    system.debug('b.Instalment_Fees__c******'+b.Instalment_Fees__c);
                }
                
                //update bwInv;
                bwInvList.addAll(bwInv);
            } else if (acc.Is_Benefit_in_Percentage__c == false && acc.Benefit_Value__c > 0) {
                System.debug('Object msgIn triggere 4=' + acc.Benefit_Value__c);
                
                for (Batch_Wise_Instalment__c b: bwInv) {
                    b.Instalment_Fees__c = (b.Instalment_Fees__c - (acc.Benefit_Value__c / bwInv.size())).setScale(2, RoundingMode.FLOOR);
                    system.debug('b.Instalment_Fees__c******'+b.Instalment_Fees__c);
                }
                //update bwInv;
                bwInvList.addAll(bwInv);
            }
        }
        update bwInvList;
    }
    
    if (Trigger.isDelete) {
        
        map<string ,List < Batch_Wise_Benefit__c >> bwb1 = new map<string,List < Batch_Wise_Benefit__c >>();
        List<string> batchWiseList = new List<string> ();
        
         List < Batch_Wise_Benefit__c > bwbList2 = new  List < Batch_Wise_Benefit__c >();
         
         List < Batch_Wise_Instalment__c > bwInv2 = new  List < Batch_Wise_Instalment__c >();  
        
        for (Batch_Wise_Benefit__c acc: trigger.old) {
            
            
            batchWiseList.add(acc.Batch_Wise_Fee_Plan__c);
        }
        
        System.debug('batchWiseList='+batchWiseList);
        
         bwbList2 = [select id,Is_Benefit_in_Percentage__c,Benefit_Percentage__c,Benefit_Value__c,Batch_Wise_Fee_Plan__c from Batch_Wise_Benefit__c where Batch_Wise_Fee_Plan__c IN : batchWiseList ORDER BY CreatedDate ASC NULLS LAST];

         bwInv2 = [select Previous_Fees__c,Batch_Wise_Fee_Plan__c, Name, Exclude_Benefit__c, Instalment_Fees__c from Batch_Wise_Instalment__c where Batch_Wise_Fee_Plan__c IN :batchWiseList and Exclude_Benefit__c != true];

        for(Batch_Wise_Benefit__c b:bwbList2){
            
            List<Batch_Wise_Benefit__c>  bwList = new  List<Batch_Wise_Benefit__c>();
            if(bwb1.containsKey(b.Batch_Wise_Fee_Plan__c)){
                bwList =bwb1.get(b.Batch_Wise_Fee_Plan__c);
                bwList.add(b);
                bwb1.put(b.Batch_Wise_Fee_Plan__c,bwList);
            }else{
                bwList.add(b);
                 bwb1.put(b.Batch_Wise_Fee_Plan__c,bwList);
            }
           
        }
         map<string ,List < Batch_Wise_Instalment__c >> bwIns1 = new map<string,List < Batch_Wise_Instalment__c >>();
         for(Batch_Wise_Instalment__c b:bwInv2){
            
            List<Batch_Wise_Instalment__c>  bwList = new  List<Batch_Wise_Instalment__c>();
            if(bwIns1.containsKey(b.Batch_Wise_Fee_Plan__c)){
                bwList =bwIns1.get(b.Batch_Wise_Fee_Plan__c);
                bwList.add(b);
                bwIns1.put(b.Batch_Wise_Fee_Plan__c,bwList);
            }else{
                bwList.add(b);
                 bwIns1.put(b.Batch_Wise_Fee_Plan__c,bwList);
            }
           
        }
        
        
         List < Batch_Wise_Instalment__c > bwInvForUpdate  = new List < Batch_Wise_Instalment__c >();
        
        for (Batch_Wise_Benefit__c acc: trigger.old) {
            System.debug('Object msgIn trigger=' + acc.Is_Benefit_in_Percentage__c);
            setacccid.add(acc.Id);
            
            List < Batch_Wise_Benefit__c > bwbList = new List < Batch_Wise_Benefit__c >();
           // List < Batch_Wise_Benefit__c > bwbList = [select id,Is_Benefit_in_Percentage__c,Benefit_Percentage__c,Benefit_Value__c,Batch_Wise_Fee_Plan__c from Batch_Wise_Benefit__c where  id !=: acc.Id and Batch_Wise_Fee_Plan__c =: acc.Batch_Wise_Fee_Plan__c ORDER BY CreatedDate ASC NULLS LAST];
            
            bwbList = bwb1.get(acc.Batch_Wise_Fee_Plan__c); 
            
            boolean f = false;
            
            Integer ctr=0;
            for (Batch_Wise_Benefit__c bw: bwbList) {
                
                if(bw.id!=acc.Id)
                {
                    f=true;
                System.debug('Object msgIn trigger=' + bw.Is_Benefit_in_Percentage__c);
                List < Batch_Wise_Instalment__c > bwInv  = new List < Batch_Wise_Instalment__c >();
                //List < Batch_Wise_Instalment__c > bwInv = [select Previous_Fees__c,Batch_Wise_Fee_Plan__c, Name, Exclude_Benefit__c, Instalment_Fees__c from Batch_Wise_Instalment__c where Batch_Wise_Fee_Plan__c =: bw.Batch_Wise_Fee_Plan__c and Exclude_Benefit__c != true];
                    
                 bwInv =    bwIns1.get(bw.Batch_Wise_Fee_Plan__c);
                    
                System.debug('Object msgtt' + bwInv);
                
                if (bw.Is_Benefit_in_Percentage__c == true && bw.Benefit_Percentage__c > 0) {
                    for (Batch_Wise_Instalment__c b: bwInv) {
                        if(ctr==0){
                            b.Instalment_Fees__c = (b.Previous_Fees__c - ((b.Previous_Fees__c * bw.Benefit_Percentage__c) / 100)).setScale(2, RoundingMode.FLOOR);
                        }
                        else{
                            b.Instalment_Fees__c = (b.Instalment_Fees__c - ((b.Instalment_Fees__c * bw.Benefit_Percentage__c) / 100)).setScale(2, RoundingMode.FLOOR);
                        }
                    }
                    
                    //update bwInv;
                    bwInvForUpdate.addAll(bwInv);
                } else if (bw.Is_Benefit_in_Percentage__c == false && bw.Benefit_Value__c > 0) {
                    System.debug('Object msgIn triggere 4=' + bw.Benefit_Value__c);
                    
                    for (Batch_Wise_Instalment__c b: bwInv) {
                        if(ctr==0){
                            (b.Instalment_Fees__c = b.Previous_Fees__c - (bw.Benefit_Value__c / bwInv.size())).setScale(2, RoundingMode.FLOOR);
                        }
                        else{
                            (b.Instalment_Fees__c = b.Instalment_Fees__c - (bw.Benefit_Value__c / bwInv.size())).setScale(2, RoundingMode.FLOOR);
                        }
                    }                    
                    //update bwInv; 
                    bwInvForUpdate.addAll(bwInv);
                }
                ctr++;   
            }
            }
            
           // if(bwbList.size()==0){
            if(f==false){
                List<Batch_Wise_Instalment__c> bwInv = new List<Batch_Wise_Instalment__c>();
              //  List<Batch_Wise_Instalment__c> bwInv = [select Batch_Wise_Fee_Plan__c,Previous_Fees__c,Name,Exclude_Benefit__c,Instalment_Fees__c from Batch_Wise_Instalment__c where Batch_Wise_Fee_Plan__c =:acc.Batch_Wise_Fee_Plan__c and Exclude_Benefit__c!=true];
              
                bwInv = bwIns1.get(acc.Batch_Wise_Fee_Plan__c);
                System.debug('Object msgtt'+bwInv);            
                
                for(Batch_Wise_Instalment__c b :bwInv){
                    b.Instalment_Fees__c = (b.Previous_Fees__c).setScale(2, RoundingMode.FLOOR);
                }
                //update bwInv; 
                bwInvForUpdate.addAll(bwInv);            
            }  
        } 
       update bwInvForUpdate;
        System.debug('bwInvForUpdate'+bwInvForUpdate);
    }
}