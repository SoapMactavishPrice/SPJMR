// patched context.js with Year_Semester_Name__c as childKeyField and numeric sequence 1..10
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
                "Batch__r.MinGradPercentRequired__c"
            ]
        },
        {
            logicalName: "tenth",
            recordName: "10th",
            sobject: "Academic_Detail__c",
            fieldsToQuery: [ "Id", "Name", "Board_University__c", "School_Institute__c", "MonthAndYearOfPassing__c", "Marking_Scheme__c", "Maximum_Marks__c", "Obtained_Marks__c", "Percentage__c", "Conversion_Factor__c" ]
        },
        {
            logicalName: "twelfth",
            recordName: "12th",
            sobject: "Academic_Detail__c",
            fieldsToQuery: [ "Id", "Name", "Board_University__c", "School_Institute__c", "MonthAndYearOfPassing__c", "Marking_Scheme__c", "Maximum_Marks__c", "Obtained_Marks__c", "Percentage__c", "Conversion_Factor__c" ]
        },
        {
            logicalName: "diploma",
            recordName: "Diploma",
            sobject: "Academic_Detail__c",
            fieldsToQuery: [ "Id", "Name", "Board_University__c", "School_Institute__c", "Diploma_Name__c", "MonthAndYearOfCommencement__c", "MonthAndYearOfPassing__c", "Marking_Scheme__c", "Maximum_Marks__c", "Obtained_Marks__c", "Percentage__c", "Conversion_Factor__c" ]
        },
        {
            logicalName: "graduation",
            recordName: "UG",
            sobject: "Academic_Detail__c",
            fieldsToQuery: ["Id","Name","Pattern_of_Examination__c","State__c","OtherState__c","University__c","OtherUniversity__c","College__c","OtherCollege__c","Mode_of_Study__c","Degree_Type__c","Degree__c","OtherDegree__c","Specialization_Name__c"]
        },
        {
            logicalName: "graduationDetails",
            recordName: "UG",
            sobject: "Academic_Detail__c",
            fieldsToQuery: ["Id","Name","MonthAndYearOfCommencement__c","MonthAndYearOfPassing__c","Marking_Scheme__c","Maximum_Marks__c","Obtained_Marks__c","Percentage__c","Conversion_Factor__c","DegreeStatus__c"]
        },
        {
            logicalName: "postGraduation",
            recordName: "PG",
            sobject: "Academic_Detail__c",
            fieldsToQuery: ["Id","Name","Pattern_of_Examination__c","State__c","OtherState__c","University__c","OtherUniversity__c","College__c","OtherCollege__c","Mode_of_Study__c","Degree_Type__c","Degree__c","OtherDegree__c","Specialization_Name__c"]
        },
        {
            logicalName: "postGraduationDetails",
            recordName: "PG",
            sobject: "Academic_Detail__c",
            fieldsToQuery: ["Id","Name","MonthAndYearOfCommencement__c","MonthAndYearOfPassing__c","Marking_Scheme__c","Maximum_Marks__c","Obtained_Marks__c","Percentage__c","Conversion_Factor__c","DegreeStatus__c"]
        },
        {
            logicalName: "basicAcademic",
            recordName: "Basic",
            sobject: "BasicAcademicDetail__c",
            fieldsToQuery: ["Id","Name","GraduationCompleted__c","ExpectedGraduationDate__c"]
        },
        {
            logicalName: "publications",
            recordName: "Basic",
            sobject: "BasicAcademicDetail__c",
            fieldsToQuery: ["Id","Name","Publications__c"]
        },
        {
            logicalName: "importantCertification",
            recordName: "Basic",
            sobject: "BasicAcademicDetail__c",
            fieldsToQuery: ["Id","Name","CertificationDetails__c"]
        },
        {
            logicalName: "extraCurricular",
            recordName: "Basic",
            sobject: "BasicAcademicDetail__c",
            fieldsToQuery: ["Id","Name","ExtraCurricularActivities__c"]
        },
        {
            logicalName: "haveProfessionalQualification",
            recordName: "Basic",
            sobject: "BasicAcademicDetail__c",
            fieldsToQuery: ["Id","Name","HasProfessionalQualification__c"]
        },
        {
            logicalName: "havePostGrad",
            recordName: "Basic",
            sobject: "BasicAcademicDetail__c",
            fieldsToQuery: ["Id","Name","AnyPostGraduation__c"]
        },
        {
            logicalName: "haveAcademicBreak",
            recordName: "Basic",
            sobject: "BasicAcademicDetail__c",
            fieldsToQuery: ["Id","Name","HasAcademicBreak__c","AcademicBreakYear__c","AcademicBreakReason__c"]
        },
        {
            logicalName: "after10",
            recordName: "Basic",
            sobject: "BasicAcademicDetail__c",
            fieldsToQuery: ["Id","Name","AfterTen__c"]
        }
    ],

    children: [
        {
            logicalName: "semester",
            sobject: "Graduation_Details_Semester_wise__c",
            parentRecordName: "UG",
            parentLookupField: "Academic_Detail__c",
            childKeyField: "Year_Semester_Name__c",
            useSequenceKey: true,
            zeroIsBlank: true,
            fieldsToQuery: ["Id","Year_Semester_Name__c","Maximum_Marks_SGPA__c","Obtained_Marks_SGPA__c"]
        },
        {
            logicalName: "year",
            sobject: "Graduation_Details_Semester_wise__c",
            parentRecordName: "UG",
            parentLookupField: "Academic_Detail__c",
            childKeyField: "Year_Semester_Name__c",
            useSequenceKey: true,
            zeroIsBlank: true,
            fieldsToQuery: ["Id","Year_Semester_Name__c","Maximum_Marks_SGPA__c","Obtained_Marks_SGPA__c"]
        },
        {
            logicalName: "postSemester",
            sobject: "Graduation_Details_Semester_wise__c",
            parentRecordName: "PG",
            parentLookupField: "Academic_Detail__c",
            childKeyField: "Year_Semester_Name__c",
            useSequenceKey: true,
            zeroIsBlank: true,
            fieldsToQuery: ["Id","Year_Semester_Name__c","Maximum_Marks_SGPA__c","Obtained_Marks_SGPA__c"]
        },
        {
            logicalName: "postYear",
            sobject: "Graduation_Details_Semester_wise__c",
            parentRecordName: "PG",
            parentLookupField: "Academic_Detail__c",
            childKeyField: "Year_Semester_Name__c",
            useSequenceKey: true,
            zeroIsBlank: true,
            fieldsToQuery: ["Id","Year_Semester_Name__c","Maximum_Marks_SGPA__c","Obtained_Marks_SGPA__c"]
        },
        {
            logicalName: "professionalQualification",
            sobject: "Professional_Qualification__c",
            parentLookupField: "Application__c",
            useSequenceKey: false,
            zeroIsBlank: true,
            fieldsToQuery: ["Id","Name_of_Qualification__c","Name_of_Institute__c","Rank_Achieved__c","Level_Achieved__c","Total_Max_Marks__c","Marks_Obtained__c"]
        },
        {
            logicalName: "personalDetails",
            sobject: "Personal_Detail__c",
            parentLookupField: "Application__c",
            zeroIsBlank: true,
            useSequenceKey: false,
            fieldsToQuery: [
                "Id",
                // PERSONAL
                "Date_of_Birth_As_Per_10th_Marksheet__c",
            ]
        },
    ]
};