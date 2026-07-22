public class CustomNotificationTriggerHelper {
    
    //Shares record with Community User if the record is inserted from Community Site
    public static void shareRecordWithCustomerCommunityUser(List<CustomNotification__c> newList){
        Id userId = UserInfo.getUserId();
        List<User> runningUser = [SELECT Id FROM User 
                                  WHERE Profile.UserLicense.Name = 'Customer Community Plus Login'
                                  AND Id=:userId];
         
        if(runningUser.isEmpty()){
            return;
        }
				        
    }
}