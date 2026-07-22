export const context = {
    parentLookupField: "Application__c",

    parents: [
        {
            logicalName: "application",
            recordName: "Application",
            sobject: "Application__c",

            fieldsToQuery: [
                "Id",
                "Application_Status__c",
                "Assignment_Status__c",

                /* ============================
                   PURPOSE STATEMENT FIELDS
                ============================ */
                "ShortTermLongTermGoal__c",
                "AdditonalInformationOnSelf__c",

                /* ============================
                   VISIBILITY CONTROLLERS
                   (Used for certificates section)
                ============================ */
                "ChoiceOfEssay__c",

                /* ============================
                   ESSAY FIELD
                ============================ */
                "Essay__c"

                /* ============================
                   REQUIRED DOCUMENT FIELDS
                ============================ */
                // "ClassX_Document__c",
                // "ClassXII_Document__c",
                // "Graduation_Document__c",
                // "Resume_Document__c",
                // "LOR_Academic_Document__c",
                // "LOR_Professional_Document__c",

                /* ============================
                   CONDITIONAL DOCUMENT FIELDS
                ============================ */
                // "Competitive_Certificates__c",
                // "Language_Certificates__c"
            ]
        }
    ],

    children: []
};