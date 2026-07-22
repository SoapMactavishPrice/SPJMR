// context.js — Basic Details
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
                "Applicant__c"
            ]
        },
        {
            logicalName: "personalDetails",
            recordName: "Personal Details",
            sobject: "Personal_Detail__c",
            fieldsToQuery: [
                "Id",

                // PERSONAL
                "Title__c",
                "First_Name__c",
                "Middle_Name__c",
                "Last_Name__c",
                "Gender__c",
                "Date_of_Birth_As_Per_10th_Marksheet__c",
                "Age_as_on_Customisable_Date__c",
                "Application__r.Batch__r.CalculateAgeAsOf__c",
                "Application__r.Batch__r.UpperAgeBound__c",
                "Application__r.Batch__r.LowerAgeBound__c",
                "Nationality__c",
                "HavePassport__c",
                "PassportNumber__c",
                "PassportApplicationNumber__c",
                "AadhaarCardNumber__c",                
            ]
        },
        {
            logicalName: "contactDetails",
            recordName: "Personal Details",
            sobject: "Personal_Detail__c",

            // Fields we need to FETCH and SAVE
            fieldsToQuery: [
                "Id",

                // CONTACT
                "Primary_E_mail__c",
                "Alternate_E_mail__c",
                "Mobile_Number__c",
                "Alternate_Mobile_Number__c",
                "WhatsApp_Mobile_Number__c",
                "LinkedIn_Profile_URL__c",
            ],

            // filter is injected dynamically: Application__c = applicationId
            filters: []
        },
        {
            logicalName: "parentOrGuardian",
            recordName: "Personal Details",
            sobject: "Personal_Detail__c",
            fieldsToQuery: [
                "Id",

                // PARENTS/GUARDIAN
                "ParentOrGuardianDetails__c",                
            ]
        },
        {
            logicalName: "parentDetails",
            recordName: "Personal Details",
            sobject: "Personal_Detail__c",

            // Fields we need to FETCH and SAVE
            fieldsToQuery: [
                "Id",
                "FatherMotherSelection__c",
                
                // PARENTS
                "FatherTitle__c",
                "Father_s_Name__c",
                "Father_E_Mail_ID__c",
                "FatherIncome__c",
                "Parent_s_Mobile_Number__c",
                "FatherOccupation__c",
                "OtherFatherOccupation__c",

                // MOTHER
                "MotherTitle__c",
                "Mother_s_Name__c",
                "Mother_E_Mail_ID__c",
                "MotherIncome__c",
                "Mother_s_Mobile_Number__c",
                "MotherOccupation__c",
                "OtherMotherOccupation__c"

            ],

            // filter is injected dynamically: Application__c = applicationId
            filters: []
        },
        {
            logicalName: "guardianDetails",
            recordName: "Personal Details",
            sobject: "Personal_Detail__c",

            // Fields we need to FETCH and SAVE
            fieldsToQuery: [
                "Id",

                // GUARDIAN (conditional)
                "GuardianName__c",
                "GuardianEmail__c",
                "GuardianMobile__c",
                "GuardianOccupation__c",
                "OtherGuardianOccupation__c",
                "GuardianRelationship__c"
            ],

            // filter is injected dynamically: Application__c = applicationId
            filters: []
        },
        {
            logicalName: "correspondenceAddress",
            recordName: "Personal Details",
            sobject: "Personal_Detail__c",

            // Fields we need to FETCH and SAVE
            fieldsToQuery: [
                "Id",
                
                // ADDRESS FLAG
                "Is_Permanent_Same__c",

                // CORRESPONDENCE ADDRESS
                "Corr_Country__c",
                "Corr_State__c",
                
                "Corr_City__c",
                "Corr_Address1__c",
                "Corr_Address2__c",
                "Corr_Pincode__c",
                "Other_Corr_City__c",
                
                "Corr_Ind_Pincode__c"
            ],

            // filter is injected dynamically: Application__c = applicationId
            filters: []

        },
        {
            logicalName: "permanentAddress",
            recordName: "Personal Details",
            sobject: "Personal_Detail__c",

            // Fields we need to FETCH and SAVE
            fieldsToQuery: [
                "Id",

                // PERMANENT ADDRESS
                "Perm_Country__c",
                "Perm_State__c",
                
                "Perm_City__c",
                "Perm_Address1__c",
                "Perm_Address2__c",
                "Perm_Pincode__c",
                "Other_Perm_City__c",
                
                "Perm_Ind_Pincode__c"
            ],

            // filter is injected dynamically: Application__c = applicationId
            filters: []
        },
    ],

    // Document upload will be added here later:
    children: [
        // {
        //     logicalName: "documents",
        //     sobject: "Document_Details__c",
        //     parentLookupField: "Application__c",
        //     fieldsToQuery: [
        //         "Id",
        //         "Document_Type__c",
        //         "Document_Code__c",
        //         "ContentDocumentId__c"
        //     ],
        //     filters: [{ field: "Document_Code__c", value: "PSP" }]
        // }
    ]
};