// context-entrance-exam.js
export const context = {
    parentLookupField: "Application__c",
    parents: [
        {
            logicalName: "application",
            sobject: "Application__c",
            fieldsToQuery: [
                "Id",
                "CompetitiveExams__c",
                "HasLanguageProficiency__c",
                "LanguageProficiencyExams__c",
                "Application_Status__c",
                "Assignment_Status__c",
                "Batch__r.Name",
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
                "Id","Exam_Name__c",
                "GMAT_ID__c","Test_Date__c",
                "Quantitative_Score__c","Verbal_Score__c","Analytical_Writing_Score__c","Integrated_Reasoning_Score__c","GMAT_Total_Score__c"
            ]
        },
        {
            logicalName: "gre",
            recordName: "GRE",
            sobject: "Competitive_Exam_Details__c",
            fieldsToQuery: [
                "Id","Exam_Name__c",
                "GRE_ID__c","GreMonthAndYear__c",
                "GRE_Analytical_Reasoning__c","GRE_Analytical_Writing__c","GRE_Quantitative_Reasoning__c","GRE_Total_Score__c"
            ]
        },
        {
            logicalName: "cat",
            recordName: "CAT",
            sobject: "Competitive_Exam_Details__c",
            fieldsToQuery: [
                "Id","Exam_Name__c",
                "CAT_Registration_Number__c","CAT_Year_of_Exam__c",
                "CAT_Quantitative_Aptitude__c","Is_your_primary_email_ID_same_as_CAT_exa__c","CAT_E_Mail__c","Data_interpretation_and_logical_re_score__c","CatVerbalReadingComprehensionScore__c","CAT_Overall_Percentile__c"
            ]
        },
        {
            logicalName: "xat",
            recordName: "XAT",
            sobject: "Competitive_Exam_Details__c",
            fieldsToQuery: [
                "Id","Exam_Name__c",
                "XAT_ID__c","XAT_Year_of_Exam__c",
                "XAT_Quantitative_Analytical_Ability__c","XAT_Verbal_Logical_Ability__c","XAT_Decision_Making__c","XAT_Total_Percentile__c"
            ]
        },
        {
            logicalName: "nmat",
            recordName: "NMAT",
            sobject: "Competitive_Exam_Details__c",
            fieldsToQuery: [
                "Id","Exam_Name__c",
                "NMAT_ID__c","NmatMonthAndYearOfExam__c",
                "NMAT_Quantitative_Skills_Score_Obtained__c","NMAT_Language_Skills_Score_Obtained__c","NMAT_Logical_Reasoning_Score_Obtained__c","Total_NMAT_Score_Obtained__c"
            ]
        },
        {
            logicalName: "gmatFocus",
            recordName: "GMAT Focus",
            sobject: "Competitive_Exam_Details__c",
            fieldsToQuery: [
                "Id","Exam_Name__c",
                "GMAT_FOCUS_ID__c","GMAT_Focus_Edition_Test_Date__c",
                "GMAT_Focus_Edition_Quantitative_Reasonin__c","GMAT_Focus_Edition_Verbal_Reasoning__c","GMAT_Focus_Edition_Data_Insights__c","GMAT_Focus_Edition_Total_Score__c"
            ]
        },
        {
            logicalName: "toefl",
            recordName: "TOEFL",
            sobject: "Competitive_Exam_Details__c",
            fieldsToQuery: [
                "Id","Exam_Name__c",
                "TOEFL_ID__c","TOEFL_Year_of_Exam__c",
                "TOEFL_Reading__c","TOEFL_Listening__c","TOEFL_Speaking__c","TOEFL_Writing__c","TOEFL_Total_Score__c"
            ]
        },
        {
            logicalName: "ielts",
            recordName: "IELTS",
            sobject: "Competitive_Exam_Details__c",
            fieldsToQuery: [
                "Id","Exam_Name__c",
                "IELTS_ID__c","IELTS_Year_of_Exam__c",
                "IELTS_Reading__c","IELTS_Listening__c","IELTS_Speaking__c","IELTS_Writing__c","IELTS_Overall_Band_Score__c","IELTS_CEFR_Level__c"
            ]
        }
    ],
    children: []
};