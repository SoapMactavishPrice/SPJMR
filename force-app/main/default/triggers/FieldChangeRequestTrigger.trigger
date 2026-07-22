trigger FieldChangeRequestTrigger on Field_Change_Request__c (after update) {
     List<Field_Change_Request__c> approved = new List<Field_Change_Request__c>();

    for(Field_Change_Request__c rec : Trigger.new){
        Field_Change_Request__c oldRec = Trigger.oldMap.get(rec.Id);

        if(rec.Status__c == 'Approved' && oldRec.Status__c != 'Approved'){
            approved.add(rec);
        }
    }

    if(!approved.isEmpty()){
        ChangeControlApplyService.applyApproved(approved);
    }

}