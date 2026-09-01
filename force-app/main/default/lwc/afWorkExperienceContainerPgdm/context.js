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
                "TotalIndustryExperience__c",
                "HasWorkExperience__c",

                "AdditionalWorkExperienceInMonths__c",
                "OverallVersatilityRating__c",

                "Batch__r.Application_End_Date__c",
                
                "PersonalResponsibilityLevel__c",
                "PersonalResponsibilityDescription__c",
                "ProfessionalResponsibilityLevel__c",
                "ProfessionalResponsibilityDescription__c",
                "ReferralSourceMulti__c",
                "OtherReferralSource__c",
                "InterestedInOtherProgram__c",
                "OtherProgramsInterestedIn__c",

                'RecordTypeId'
            ]
        },
        {
            logicalName: "graduationDetails",
            parentLookupField: "Application__c",
            recordName: "UG",
            sobject: "Academic_Detail__c",
            fieldsToQuery: ["Id","Name","MonthAndYearOfPassing__c"]
        },
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
                "Name_of_Organisation__c",
                "Designation__c",
                "Gross_Annual_CTC__c",
                "Responsibilities__c",
                "Start_Date__c",
                "End_Date__c",

                "Employment_Type__c",
                "Industry__c",
                "Function__c",
                "IsCurrentJob__c",

                "OtherOrganizationName__c",
                "OtherIndustry__c",
                "OtherFunction__c",
            ]
        },
        {
            logicalName: "achievements",
            sobject: "Academic_Achievements__c",
            parentLookupField: "Application__c",
            useSequenceKey: false,
            zeroIsBlank: true,
            childKeyField: "Id",

            fieldsToQuery: [
                "Id",
                "Title_of_the_Award__c",
                "Institute_Granting_the_Award__c",
                "Year__c",
                "Award_Position__c",
                "Level__c",
                "Describe_the_Award_Max_25_words__c"
            ]
        },
        {
            logicalName: "versatility",
            sobject: "Versatility__c",
            parentLookupField: "Application__c",
            useSequenceKey: false,
            zeroIsBlank: true,
            childKeyField: "Id",

            fieldsToQuery: [
                "Id",
                "Name_of_the_Activity__c",
                "Interest__c",
                "Proficiency__c",
                "Award__c",
                "Level__c",
                "Description__c"
            ]
        }
    ]
};