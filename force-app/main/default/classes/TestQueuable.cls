public without sharing class TestQueuable implements Queueable{
	private Id userId;
    public TestQueuable(String userId){
        this.userId = userId;
    }
    
    public void execute(QueueableContext context){
         System.resetPasswordWithEmailTemplate(userId,true,'SPJIMR_New_User_Creation');
    }
}