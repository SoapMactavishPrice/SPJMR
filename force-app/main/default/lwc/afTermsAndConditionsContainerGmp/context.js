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
                   TERMS & CONDITIONS FIELDS
                ============================ */
                "ReferralSource__c",
                "ReferralName__c",
                "OtherProgrammeApplied__c",
                "OtherProgrammeRegNo__c",
                "AgreeToTerms__c",

                /* ============================
                   VISIBILITY CONTROLLERS
                   (Used for certificates section)
                ============================ */
                "CompetitiveExams__c",
                "LanguageProficiencyExams__c",
                "HasLanguageProficiency__c",
                "HasWorkExperience__c",

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

    children: []
};