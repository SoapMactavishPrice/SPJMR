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
                "HasExamScores__c",
                "PlannedExamDate__c",
                "PlannedEntranceExams__c",
                "CompetitiveExams__c",
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
                "PrimaryPartnerSchoolPreference__c",
                "PrimaryPartnerProgramPreference__c",
                "PrimaryPartnerSpecializationPreference__c",
                "SecondaryPartnerSchoolPreference__c",
                "SecondaryPartnerProgramPreference__c",
                "SecondaryPartnerSpecializationPreference__c"
                // 🔥 NO Batch__c here — it belongs to Application
            ]
        },

        /*********************************************
         * 3) COMPETITIVE EXAM DETAILS
         *    One record per exam type
         *********************************************/

        // -------- GMAT --------
        {
            logicalName: "gmat",
            recordName: "GMAT",
            sobject: "Competitive_Exam_Details__c",
            parentLookupField: "Application__c",
            fieldsToQuery: [
                "Id",
                "Application__c",
                "Exam_Name__c",
                "GMAT_Total_Score__c"
            ],
            filter: { Exam_Name__c: "GMAT" }
        },

        // -------- GRE --------
        {
            logicalName: "gre",
            recordName: "GRE",
            sobject: "Competitive_Exam_Details__c",
            parentLookupField: "Application__c",
            fieldsToQuery: [
                "Id",
                "Application__c",
                "Exam_Name__c",
                "GRE_Total_Score__c"
            ],
            filter: { Exam_Name__c: "GRE" }
        },

        // -------- CAT --------
        {
            logicalName: "cat",
            recordName: "CAT",
            sobject: "Competitive_Exam_Details__c",
            parentLookupField: "Application__c",
            fieldsToQuery: [
                "Id",
                "Application__c",
                "Exam_Name__c",
                "CAT_Overall_Percentile__c"
            ],
            filter: { Exam_Name__c: "CAT" }
        },

        // -------- XAT --------
        {
            logicalName: "xat",
            recordName: "XAT",
            sobject: "Competitive_Exam_Details__c",
            parentLookupField: "Application__c",
            fieldsToQuery: [
                "Id",
                "Application__c",
                "Exam_Name__c",
                "XAT_Total_Percentile__c"
            ],
            filter: { Exam_Name__c: "XAT" }
        },

        // -------- NMAT --------
        {
            logicalName: "nmat",
            recordName: "NMAT",
            sobject: "Competitive_Exam_Details__c",
            parentLookupField: "Application__c",
            fieldsToQuery: [
                "Id",
                "Application__c",
                "Exam_Name__c",
                "Total_NMAT_Score_Obtained__c"
            ],
            filter: { Exam_Name__c: "NMAT" }
        },

        // -------- GMAT Focus --------
        {
            logicalName: "gmatFocus",
            recordName: "GMAT Focus",
            sobject: "Competitive_Exam_Details__c",
            parentLookupField: "Application__c",
            fieldsToQuery: [
                "Id",
                "Application__c",
                "Exam_Name__c",
                "GMAT_Focus_Edition_Total_Score__c"
            ],
            filter: { Exam_Name__c: "GMAT Focus" }
        },
        {
            logicalName: "basicAcademic",
            sobject: "BasicAcademicDetail__c",
            parentLookupField: "Application__c",
            recordName: "Basic",
            fieldsToQuery: [
                "Id",
                "Application__c",
                "GraduationCompleted__c",
                "ExpectedGraduationDate__c"
            ]
        },
        {
            logicalName: "ugAcademic",
            sobject: "Academic_Detail__c",
            parentLookupField: "Application__c",
            recordName: "UG",
            fieldsToQuery: [
                "Id",
                "Application__c",
                "MonthAndYearOfPassing__c",
                "DegreeStatus__c"
            ],
            filter: { Name: "UG" }
        }
    ],

    children: []
};