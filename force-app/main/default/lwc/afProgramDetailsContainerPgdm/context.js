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
                "Program__c"
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
                "ProgramElegibilityAcceptance__c",
                // 🔥 NO Batch__c here — it belongs to Application
                'ProgrammesInterestedIn__c',
                'PrimaryProgramPreference__c',
                'SecondaryProgramPreference__c',
                'PrimarySpecialisationPreference__c',
                'SecondarySpecialisationPreference__c',
                'Reasons_I_have_Specialization_1__c',
                'Reasons_I_have_Specialization_2__c',
                'OtherSpecialisation1InterestReason__c',
                'OtherSpecialisation2InterestReason__c',
                'AreaOfInterest__c',
                'ReasonsForAreaOfInterest__c'
            ]
        },
    ],

    children: []
};