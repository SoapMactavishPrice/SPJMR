// context-entrance-exam.js
export const context = {
    parentLookupField: "Application__c",
    parents: [
        {
            logicalName: "application",
            sobject: "Application__c",
            fieldsToQuery: [
                "Id",
                "Application_Status__c",
                "Assignment_Status__c",
                "Batch__r.Name",
                'CompetitiveExams__c'
            ]
        },        
        {
            logicalName: "personalDetails",
            recordName: "Personal Details",
            sobject: "Personal_Detail__c",
            fieldsToQuery: [
                "Id",
                "Primary_E_mail__c"
            ]
        },

        // One parent per section (exam). Each maps to one Competitive_Exam_Details__c record
        {
            logicalName: "gmat",
            recordName: "GMAT",
            sobject: "Competitive_Exam_Details__c",
            fieldsToQuery: [
                "Id","Exam_Name__c","GMAT_Appointment_No__c",
                "GMAT_ID__c","Test_Date__c","Result_Status__c","GMAT_Score_Issue_Date__c",
                "GMAT_Total_Score__c","GMAT_Total_Percentile__c",
                "Quantitative_Score__c","Quantitative_Percentile__c",
                "Verbal_Score__c","Verbal_Percentile__c",
            ]
        },
        {
            logicalName: "cat",
            recordName: "CAT",
            sobject: "Competitive_Exam_Details__c",
            fieldsToQuery: [
                "Id","Exam_Name__c",
                "CAT_Registration_Number__c","CAT_Year_of_Exam__c","Result_Status__c",
                "CAT_Overall_Score__c","CAT_Overall_Percentile__c",
                "CatVerbalReadingComprehensionPercentile__c","CatVerbalReadingComprehensionScore__c",
                "Data_interpretation_and_logical_re_score__c","Data_interpretation_and_logical_re_perce__c",
                "CAT_Quantitative_Aptitude__c","CAT_Quantitative_Aptitude_Percentile__c",
                "Is_your_primary_email_ID_same_as_CAT_exa__c",
                "CAT_E_Mail__c"
            ]
        },
        {
            logicalName: "gmatFocus",
            recordName: "GMAT Focus",
            sobject: "Competitive_Exam_Details__c",
            fieldsToQuery: [
                "Id","Exam_Name__c","GMAT_FOCUS_ID_Appointment_Number__c",
                "GMAT_FOCUS_ID__c","GMAT_Focus_Edition_Test_Date__c","Result_Status__c",
                "GMAT_Focus_Edition_Score_Issue_Date__c", "GMAT_Focus_Edition_Total_Score__c", "GMAT_Focus_Edition_Total_Percentile__c",
                "GMAT_Focus_Edition_Quantitative_Reasonin__c", "GMAT_FE_Quantitative_Reasoning_Perce__c", 
                "GMAT_Focus_Edition_Verbal_Reasoning__c","GMAT_FE_Verbal_Reasoning_Perce__c",
                "GMAT_Focus_Edition_Data_Insights__c","GMAT_FE_Data_Insights_Percentile__c",
            ]
        }
    ],
    children: []
};