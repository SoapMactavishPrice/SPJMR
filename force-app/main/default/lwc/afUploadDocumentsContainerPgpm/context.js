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
                "RequiredFilesUploaded__c",

                /* ============================
                   VISIBILITY CONTROLLERS
                   (Used for certificates section)
                ============================ */
                "CompetitiveExams__c",
                "LanguageProficiencyExams__c",
                "HasLanguageProficiency__c",
                "HasWorkExperience__c",
            ]
        },
        {
            logicalName: "personalDetails",
            recordName: "Personal Details",
            sobject: "Personal_Detail__c",
            fieldsToQuery: [
                "Id",

                // PERSONAL
                "PassportNumber__c",
                "AadhaarCardNumber__c",                
            ]
        },
        {
            logicalName: "basicAcademic",
            sobject: "BasicAcademicDetail__c",
            parentLookupField: "Application__c",
            recordName: "Basic",
            fieldsToQuery: [
                "Id",
                "Application__c",
                "AfterTen__c",
                "GraduationCompleted__c",
                "AnyPostGraduation__c"
            ]
        }
    ],

    children: [
        {
            logicalName: "workExperience",
            sobject: "Work_Experience__c",
            parentLookupField: "Application__c",
            useSequenceKey: false,     // no sequence field used
            zeroIsBlank: true,
            childKeyField: "Id",
            fieldsToQuery: [
                "Id",
                "Name"
            ]
        }
    ]
};