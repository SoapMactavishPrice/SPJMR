public without sharing class ApplicantPasswordResetHandler {

    public static void handleAfterInsert(List<Applicant_Password_Reset__e> events){
         Set<Id> userIds = new Set<Id>();
		List<user> UpdateList = new List<User>();
        for (Applicant_Password_Reset__e eventRecord : events) {
            if (String.isNotBlank(eventRecord.User_Id__c)) {
                Id userId;
				
                try {
                    
					ResetPasswordResult res = system.resetPassword(userId,true);
                    system.debug('Res:'+res);
                    UpdateList.add(new User(Id=userId,Temp_Pass__c=res.getPassword()));
                    //system.debug('Res: '+success);
                } catch (Exception e) {
                    system.debug('Exception: '+e.getMessage());
                    continue;
                }
                   update UpdateList;
                	
                }
            }

       
    }
}