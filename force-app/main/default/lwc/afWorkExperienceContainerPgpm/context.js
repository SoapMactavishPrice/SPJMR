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
                "HasCareerBreak__c",
                "TotalCareerBreak__c",
                "CareerBreakReason__c",

                "PriorWorkResponsibilities__c",

                "ApplyingUnderRestartInitiative__c",

                "HasSabbatical__c",
                "TotalSabbatical__c",
                "SabbaticalReason__c",
                "TakingSabbatical__c",

                "Batch__r.Application_End_Date__c"                
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
                "City__c",
                "OtherCity__c",
                "Currency__c",
                "IsCurrentJob__c",

                "OtherOrganizationName__c",
                "OtherIndustry__c",
                "OtherFunction__c",
                "OtherCurrency__c"
            ]
        },
        {
            logicalName: "careerBreak",
            sobject: "CareerBreak__c",
            parentLookupField: "Application__c",
            useSequenceKey: false,     // no sequence field used
            zeroIsBlank: true,
            childKeyField: "Id",
            fieldsToQuery: [
                "Id",
                "StartDate__c",
                "EndDate__c",
                "BreakType__c"
            ],
            filters: [{ field: "BreakType__c", value: "Career Break" }]
        },
        {
            logicalName: "sabbatical",
            sobject: "CareerBreak__c",
            parentLookupField: "Application__c",
            useSequenceKey: false,     // no sequence field used
            zeroIsBlank: true,
            childKeyField: "Id",
            fieldsToQuery: [
                "Id",
                "StartDate__c",
                "EndDate__c",
                "BreakType__c"
            ],
            filters: [{ field: "BreakType__c", value: "Sabbatical" }]
        }
    ]
};