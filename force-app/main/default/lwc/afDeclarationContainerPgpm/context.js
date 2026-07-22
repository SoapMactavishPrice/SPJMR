export const context = {
    parentLookupField: "Application__c",

    parents: [

        /*********************************************
         * 1) APPLICATION (root record)
         *********************************************/
        {
            logicalName: "application",
            recordName: "Application",
            sobject: "Application__c",
            fieldsToQuery: [
                "Id",
                "Application_Status__c",
                "Assignment_Status__c",
                "DeclarationDate__c",   // 🔥 ADDED because Batch__c is saved here
            ]
        },

        /*********************************************
         * 2) PERSONAL DETAIL (child of Application)
         *********************************************/
        {
            logicalName: "personalDetails",
            recordName: "Personal Details",
            sobject: "Personal_Detail__c",
            parentLookupField: "Application__c",
            fieldsToQuery: [
                "Id",
                "Application__c",
                // PERSONAL
                "First_Name__c",
                "Middle_Name__c",
                "Last_Name__c",            
            ]
        },
    ],

    children: []
};