public with sharing class ApplicationSectionDataController {

    @AuraEnabled(cacheable=true)
    public static Id getApplicationId(Id verificationId) {
        if (verificationId == null) return null;

        return [
            SELECT Application__c
            FROM Application_Verification__c
            WHERE Id = :verificationId
            LIMIT 1
        ].Application__c;
    }

    @AuraEnabled(cacheable=true)
    public static String fetchAllSections(Id applicationId) {

        if (applicationId == null) {
            throw new AuraHandledException('Application Id is required');
        }

        Map<String, Object> request = new Map<String, Object>();

        List<Map<String, Object>> parents  = new List<Map<String, Object>>();
        List<Map<String, Object>> children = new List<Map<String, Object>>();

        /* ================= APPLICATION ================= */
        parents.add(new Map<String, Object>{
            'logicalName' => 'application',
            'sobject'     => 'Application__c',
            'fields'      => new List<String>{
                'Id','Name','Application_Status__c',
                'ReferralSource__c','ReferralName__c',
                'AgreeToTerms__c'
            },
            'filters' => new List<Object>{
                new Map<String,Object>{ 'field' => 'Id', 'value' => applicationId }
            }
        });

        /* ================= PERSONAL DETAILS ================= */
        parents.add(new Map<String, Object>{
            'logicalName' => 'basicDetails',
            'sobject'     => 'Personal_Detail__c',
            'fields'      => new List<String>{
                'Id','Title__c','First_Name__c','Middle_Name__c','Last_Name__c',
                'Gender__c','Date_of_Birth_As_Per_10th_Marksheet__c',
                'Primary_E_mail__c','Alternate_E_mail__c',
                'Mobile_Number__c','Alternate_Mobile_Number__c','WhatsApp_Mobile_Number__c',
                'GuardianName__c','GuardianEmail__c',
                'GuardianMobile__c','GuardianOccupation__c'
            },
            'filters' => new List<Object>{
                new Map<String,Object>{ 'field' => 'Application__c', 'value' => applicationId }
            }
        });

        /* ================= ACADEMICS ================= */
        parents.add(buildAcademicParent('tenth','10th',applicationId));
        parents.add(buildAcademicParent('twelth','12th',applicationId));
        parents.add(buildAcademicParent('diploma','Diploma',applicationId));
        parents.add(buildAcademicParent('ug','UG',applicationId));
        parents.add(buildAcademicParent('pg','PG',applicationId));

        /* ================= SEMESTER (UG ONLY) ================= */
      /* children.add(new Map<String, Object>{
            'logicalName' => 'semesterMarksByAcademic',
            'sobject' => 'Graduation_Details_Semester_wise__c',
            'fields' => new List<String>{
                'Id',
                'Academic_Detail__c',
                'Year_Semester_Name__c',
                'Maximum_Marks_SGPA__c',
                'Obtained_Marks_SGPA__c'
            },
            'parentLookupField' => 'Academic_Detail__c',
            'useSequenceKey' => true,
            'childKeyField' => 'Year_Semester_Name__c',
            'groupByParentId' => true,
            'parentLogicalNames' => new List<String>{ 'ug', 'diploma', 'pg' }
        }); */
        
        /* ================= SEMESTER (UG + DIPLOMA + PG) ================= */
      children.add(new Map<String, Object>{
       'logicalName' => 'semesterMarksByAcademic',
        'sobject' => 'Graduation_Details_Semester_wise__c',
        'fields' => new List<String>{
        'Id',
        'Academic_Detail__c',
        'Year_Semester_Name__c',
        'Maximum_Marks_SGPA__c',
        'Obtained_Marks_SGPA__c'
        },
        'parentLookupField' => 'Academic_Detail__c',
         'useSequenceKey' => true,
         'childKeyField' => 'Year_Semester_Name__c',
         'groupByParentId' => true,

          // ✅ NOW WORKS FOR ALL THREE
           'parentLogicalNames' => new List<String>{
            'diploma',
             'ug',
             'pg'
    }
});

        
       

        /* ================= ENTRANCE EXAMS ================= */
        children.add(new Map<String, Object>{
            'logicalName' => 'entranceExams',
            'sobject' => 'Competitive_Exam_Details__c',
            'fields' => new List<String>{
                'Id','Exam_Name__c',
                'GMAT_Focus_Edition_Total_Score__c',
                'GMAT_Total_Score__c',
                'GRE_Total_Score__c',
                'TOEFL_Total_Score__c'
            },
            'parentLookupField' => 'Application__c',
            'useSequenceKey' => false,
            'childKeyField' => 'Id',
            'filters' => new List<Object>{
                new Map<String,Object>{ 'field' => 'Application__c', 'value' => applicationId }
            }
        });

        /* ================= WORK EXPERIENCE ================= */
        children.add(new Map<String, Object>{
            'logicalName' => 'workExperience',
            'sobject' => 'Work_Experience__c',
            'fields' => new List<String>{
                'Id','Name_of_Organisation__c','Designation__c',
                'Start_Date__c','End_Date__c',
                'Gross_Annual_CTC__c','Responsibilities__c'
            },
            'parentLookupField' => 'Application__c',
            'useSequenceKey' => false,
            'childKeyField' => 'Id',
            'filters' => new List<Object>{
                new Map<String,Object>{ 'field' => 'Application__c', 'value' => applicationId }
            }
        });

        request.put('parents', parents);
        request.put('children', children);

        Map<String, Object> response =
            AcademicControllerVerification.fetchDynamic(JSON.serialize(request));

        return JSON.serialize(response);
    }

    private static Map<String,Object> buildAcademicParent(String logicalName, String level, Id applicationId) {
        return new Map<String, Object>{
            'logicalName' => logicalName,
            'sobject'     => 'Academic_Detail__c',
            'fields'      => new List<String>{
                'Id','Name','Board_University__c','School_Institute__c',
                'MonthAndYearOfPassing__c','Marking_Scheme__c',
                'Maximum_Marks__c','Obtained_Marks__c'
            },
            'filters' => new List<Object>{
                new Map<String,Object>{ 'field' => 'Application__c', 'value' => applicationId },
                new Map<String,Object>{ 'field' => 'Name', 'value' => level }
            }
        };
    }
}