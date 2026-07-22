public with sharing class ContentVersionTriggerHandler {

    public static void setFilePrefix(List<ContentVersion> newList) {
        for (ContentVersion cv : newList) {
            if (String.isNotBlank(cv.Custom_Title_fileupload__c)) {
                cv.Title = cv.Custom_Title_fileupload__c;
            }
        }
    }
}