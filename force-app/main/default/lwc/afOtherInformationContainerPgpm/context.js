export const context = {
    parentLookupField: "Application__c",

    parents: [
        {
            logicalName: "application",
            sobject: "Application__c",
            fieldsToQuery: [
                "Id",
                "Name",    // REQUIRED FIELD – MUST BE INCLUDED
                "Application_Status__c",
                "Assignment_Status__c",
                
                "AnyMedicalIssue__c",
                "MedicalIssueDetails__c",
                "UnderAnyMedication__c",
                "MedicationDetails__c",
                "ReferralSource__c",
                "OtherReferralSource__c",
                "InterestedInOtherProgram__c",
                "OtherProgramsInterestedIn__c",
                "AppliedInPastYear__c",
                "ProgramsAppliedInPastYear__c",
                "OtherProgramsAppliedInPastYear__c",

                "Batch__r.Application_End_Date__c",
                "Batch__r.Batch_Code__c",
                "Program_Code__c"
            ]
        },
    ],



    children: [
        {
            logicalName: "achievements",
            sobject: "Academic_Achievements__c",
            parentLookupField: "Application__c",
            useSequenceKey: false,     // no sequence field used
            zeroIsBlank: true,
            childKeyField: "Id",
            fieldsToQuery: [
                "Id",
                "Title_of_the_Award__c",
                "Institute_Granting_the_Award__c",
                "Year__c",
                "Award_Position__c",
                "Level__c",
                "Describe_the_Award_Max_25_words__c",
            ]
        },
        {
            logicalName: "questionnaire",
            sobject: "Questionnaire_Response__c",
            parentLookupField: "Application__c",
            useSequenceKey: false,
            childKeyField: "Id",
            fieldsToQuery: [
                "Id",
                "Question_Code__c",
                "Question_Text__c",
                "Answer_Type__c",
                "Answer_Value__c",
                "Section__c",
                "Sequence__c"
            ]
        }
    ]
};