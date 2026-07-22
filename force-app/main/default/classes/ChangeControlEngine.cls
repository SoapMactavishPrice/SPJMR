public class ChangeControlEngine {

    public static List<Field_Change_Request__c> handleBeforeUpdate(String objectName,
                                          List<SObject> newList,
                                          Map<Id, SObject> oldMap){

        // Load policies
        Map<String, Change_Control__c> policyMap = new Map<String, Change_Control__c>();

        for(Change_Control__c pol : [
            SELECT Object_API_Name__c, Field_API_Name__c, Requires_Approval__c
            FROM Change_Control__c
            WHERE Object_API_Name__c = :objectName
            AND Active__c = TRUE
        ]){
            policyMap.put(pol.Field_API_Name__c, pol);
        }

        List<Field_Change_Request__c> requests = new List<Field_Change_Request__c>();

        for(SObject newRec : newList){
            System.debug('Travsesing listr '+ newList);
            SObject oldRec = oldMap.get((Id)newRec.get('Id'));

            for(String fieldName : policyMap.keySet()){
                System.debug('field name '+ fieldName);


                Change_Control__c pol = policyMap.get(fieldName);
                System.debug('POL. :::'+ pol);

                if(!pol.Requires_Approval__c) continue;
SYstem.debug('values of id'+ oldMap.get('11WC1000000HWpuMAG'));
                Object newVal = newRec.get(fieldName);
                Object oldVal = oldRec.get(fieldName);
                Boolean isQueued=(Boolean)oldRec.get('isQueued__c');
               System.debug('Inside comparison ' + newVal + '   ::: '+ oldVal);


                if(newVal != oldVal){
                    if(!isQueued){
                        // Create request
                    Field_Change_Request__c req = new Field_Change_Request__c();
                    req.Record_Id__c = String.valueOf(newRec.get('Id'));
                    req.Object_API_Name__c = objectName;
                    req.Field_API_Name__c = fieldName;
                    req.Old_Value__c = String.valueOf(oldVal);
                    req.New_Value__c = String.valueOf(newVal);
                    req.Status__c = 'Pending';
                    req.Requested_By__c = UserInfo.getUserId();

                    requests.add(req);

                    // Revert change
                    newRec.put(fieldName, oldVal);
                    newRec.put('isQueued__c', true);
                    }
                    else{
                        newRec.addError('Can not create new update request as there is already a change request in queue.');
                    }

                    
                }
            }
        }
		List<Field_Change_Request__c> reqClone=new List<Field_Change_Request__c>();
                                            
      System.debug('requests ::: '+ requests);
        if(!requests.isEmpty()){
            insert requests;
        }
            return requests;
    }
}