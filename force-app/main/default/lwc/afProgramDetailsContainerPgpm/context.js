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
                "Batch__c",   // 🔥 ADDED because Batch__c is saved here
            ]
        },

        /*********************************************
         * 2) PROGRAMME DETAIL (child of Application)
         *********************************************/
        {
            logicalName: "programDetail",
            recordName: "ProgramDetail",
            sobject: "Program_Detail__c",
            parentLookupField: "Application__c",
            fieldsToQuery: [
                "Id",
                "Application__c",
                "ProgramElegibilityAcceptance__c"
                // 🔥 NO Batch__c here — it belongs to Application
            ]
        },
    ],

    children: []
};