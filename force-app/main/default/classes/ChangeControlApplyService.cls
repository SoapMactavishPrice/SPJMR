public class ChangeControlApplyService {

    public static void applyApproved(List<Field_Change_Request__c> records){
        
		updateStatusOfProgram(records);
        Map<String, List<Field_Change_Request__c>> grouped = new Map<String, List<Field_Change_Request__c>>();

        for(Field_Change_Request__c rec : records){
            if(rec.Status__c == 'Approved'){
                String key = rec.Object_API_Name__c;

                if(!grouped.containsKey(key)){
                    grouped.put(key, new List<Field_Change_Request__c>());
                }
                grouped.get(key).add(rec);
            }
        }

        for(String objectName : grouped.keySet()){

            Map<Id, SObject> updates = new Map<Id, SObject>();

            for(Field_Change_Request__c rec : grouped.get(objectName)){

                Id recId = (Id)rec.Record_Id__c;

                SObject obj;
                Schema.SObjectType objType = Schema.getGlobalDescribe().get(objectName);

                if(updates.containsKey(recId)){
                    obj = updates.get(recId);
                } else {
                    

				if(objType == null){
    			System.debug('Invalid object name: ' + objectName);
    			continue; // skip safely
				}

					 obj = objType.newSObject();
                    obj.put('Id', recId);
                }

// Get field describe
Map<String, Schema.SObjectField> fieldMap = objType.getDescribe().fields.getMap();

if(!fieldMap.containsKey(rec.Field_API_Name__c)){
    System.debug('Invalid field: ' + rec.Field_API_Name__c);
    continue;
}

Schema.DescribeFieldResult fieldDesc = fieldMap.get(rec.Field_API_Name__c).getDescribe();

Object convertedValue;

String val = rec.New_Value__c;

if(val == null){
    convertedValue = null;
}
else if(fieldDesc.getType() == Schema.DisplayType.Integer){
    convertedValue = Integer.valueOf(val);
}
else if(fieldDesc.getType() == Schema.DisplayType.Double ||
        fieldDesc.getType() == Schema.DisplayType.Currency ||
        fieldDesc.getType() == Schema.DisplayType.Percent){
    convertedValue = Decimal.valueOf(val);
}
else if(fieldDesc.getType() == Schema.DisplayType.Boolean){
    convertedValue = Boolean.valueOf(val);
}
else if(fieldDesc.getType() == Schema.DisplayType.Date){
    convertedValue = Date.valueOf(val);
}
else if(fieldDesc.getType() == Schema.DisplayType.DateTime){
    convertedValue = Datetime.valueOf(val);
}
else{
    // Default → treat as String
    convertedValue = val;
}

//  Now safe assignment
obj.put(rec.Field_API_Name__c, convertedValue);
                updates.put(recId, obj);
            }

            if(!updates.isEmpty()){
                ChangeControlContext.isFromApproval = true;
                update updates.values();
                ChangeControlContext.isFromApproval = false;
            }
        }
    }
    public static void updateStatusOfProgram(List<Field_Change_Request__c>  rec){
        List<Id> ids=new List<ID>();
        for(Field_Change_Request__c r: rec){
            if(r.Object_API_Name__c == 'Program')
            ids.add(r.Record_Id__c);
        }
        List<Program> programs = [select ID from Program where ID in :ids ];
        for(Program program:programs){
            program.isQueued__c=false;
        }
        update programs;
        
    }
}