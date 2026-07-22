public with sharing class ConvertApplicantController {

    /* ---------------- WRAPPER ---------------- */
    public class GMPApplicationWrapper {
        @AuraEnabled public String applicationNumber;
        @AuraEnabled public String applicantName;
        @AuraEnabled public String applicantStateManagement;
        @AuraEnabled public Id Id;
        @AuraEnabled public String applicationUrl;
    }

    /* ---------------- OFFER ACCEPTED LIST ---------------- */
    @AuraEnabled(cacheable=true)
    public static List<GMPApplicationWrapper> getGMPApplications() {

        List<GMPApplicationWrapper> result = new List<GMPApplicationWrapper>();

        for (Application__c app : [
            SELECT Id,
                   Application_Number__c,
                   Applicant__r.Name,
                   Applicant_State_Management__c
            FROM Application__c
            WHERE Applicant_State_Management__c = 'Offer Accepted'
            AND Id NOT IN (
                SELECT Applicant__c
                FROM Account
                WHERE RecordType.DeveloperName = 'Student'
                AND Applicant__c != null
            )
            ORDER BY Applicant__r.Name
        ]) {
            GMPApplicationWrapper w = new GMPApplicationWrapper();
            w.Id = app.Id;
            w.applicationNumber = app.Application_Number__c;
            w.applicantName = app.Applicant__r != null ? app.Applicant__r.Name : '';
            w.applicantStateManagement = app.Applicant_State_Management__c;
            w.applicationUrl = '/' + app.Id;
            result.add(w);
        }
        return result;
    }

    /* ---------------- CONVERT TO STUDENT ---------------- */
    @AuraEnabled
    public static void convertToStudent(List<Id> applicationIds) {

        try {

            if (applicationIds == null || applicationIds.isEmpty()) {
                throw new AuraHandledException('No applications selected');
            }

            /* 1️⃣ Student Record Type */
            Id studentRtId = [
                SELECT Id
                FROM RecordType
                WHERE SObjectType = 'Account'
                AND DeveloperName = 'Student'
                AND IsPersonType = true
                LIMIT 1
            ].Id;

            /* 2️⃣ Applications */
            Map<Id, Application__c> appMap = new Map<Id, Application__c>([
                SELECT Id, Application_Number__c, Program__c
                FROM Application__c
                WHERE Id IN :applicationIds
            ]);

            /* 3️⃣ Personal Details */
            Map<Id, Personal_Detail__c> personalMap = new Map<Id, Personal_Detail__c>();
            for (Personal_Detail__c pd : [
                SELECT Application__c,
                       First_Name__c, Middle_Name__c, Last_Name__c,
                       Gender__c,
                       Mobile_Number__c, Primary_E_mail__c, Alternate_E_mail__c,
                       Alternate_Mobile_Number__c
                       
                FROM Personal_Detail__c
                WHERE Application__c IN :applicationIds
            ]) {
                personalMap.put(pd.Application__c, pd);
            }

            /* 4️⃣ Admission Decision */
            Map<Id, Admission_Decision__c> decisionMap = new Map<Id, Admission_Decision__c>();
            for (Admission_Decision__c ad : [
                SELECT Application__c,  Specialisation_Master__c, Offer_Accepted__c
                FROM Admission_Decision__c
                WHERE Application__c IN :applicationIds
            ]) {
                decisionMap.put(ad.Application__c, ad);
            }
            
            

            /* 5️⃣ Work Experience */
            Map<Id, List<Work_Experience__c>> workExpMap = new Map<Id, List<Work_Experience__c>>();
            for (Work_Experience__c we : [
                SELECT Application__c,
                       Name_of_Organisation__c,
                       Designation__c,
                       Gross_Annual_CTC__c,
                       Start_Date__c,
                       End_Date__c
                  //   Responsibilities__c
                FROM Work_Experience__c
                WHERE Application__c IN :applicationIds
            ]) {
                if (!workExpMap.containsKey(we.Application__c)) {
                    workExpMap.put(we.Application__c, new List<Work_Experience__c>());
                }
                workExpMap.get(we.Application__c).add(we);
            }

            /* 6️⃣ Create Students */
            List<Account> students = new List<Account>();

            for (Id appId : applicationIds) {

                Application__c app = appMap.get(appId);
                Personal_Detail__c pd = personalMap.get(appId);
                Admission_Decision__c ad = decisionMap.get(appId);
                
                Boolean isEligibleForSpecialization = ad != null && ad.Offer_Accepted__c == true && ad.Specialisation_Master__c != null;

                Account student = new Account();
                student.RecordTypeId = studentRtId;
                student.Applicant__c = appId;

                String firstName = pd?.First_Name__c;
                String middleName = pd?.Middle_Name__c;
                String lastName = pd?.Last_Name__c;

                if (String.isBlank(lastName)) {
                    lastName = !String.isBlank(firstName) ? firstName : 'Student';
                    firstName = null;
                }

                student.FirstName = firstName;

                student.LastName = lastName;

               
                student.Registration_Number__c = app.Application_Number__c;
              
                
                

                student.Gender__c = pd?.Gender__c;
               

                student.PersonMobilePhone = pd?.Mobile_Number__c;
                student.PersonEmail = pd?.Primary_E_mail__c;
                student.Alternate_E_mail__c = pd?.Alternate_E_mail__c;
                student.Telephone_No__c = pd?.Alternate_Mobile_Number__c;

                 students.add(student);
            }

            insert students;
            
            
            

            /* 🔑 Query PersonContactId */
            Map<Id, Account> studentMap = new Map<Id, Account>([
                SELECT Id, Applicant__c, PersonContactId
                FROM Account
                WHERE Id IN :students
            ]);
            
            
/* 🔁 Map Application → Student */
Map<Id, Account> applicationToStudentMap = new Map<Id, Account>();
for (Account acc : studentMap.values()) {
    applicationToStudentMap.put(acc.Applicant__c, acc);
}
  
    //Map document details to student
     
// 1️⃣ Fetch existing documents linked to Application
List<Document_Details__c> docsToUpdate = [
    SELECT Id, Application_No__c, Student_Name__c
    FROM Document_Details__c
    WHERE Application_No__c IN :applicationIds
];

// 2️⃣ Update Student lookup
for (Document_Details__c doc : docsToUpdate) {

    Account student = applicationToStudentMap.get(doc.Application_No__c);
    if (student == null) continue;

    doc.Student_Name__c = student.Id; // ✅ link to student
}


// 3️⃣ Update records
if (!docsToUpdate.isEmpty()) {
    update docsToUpdate;
}

       


            /* 7️⃣ Person Employment */
            List<PersonEmployment> empList = new List<PersonEmployment>();

            for (Account student : studentMap.values()) {
                List<Work_Experience__c> weList = workExpMap.get(student.Applicant__c);
                if (weList == null) continue;

                for (Work_Experience__c we : weList) {
                    PersonEmployment pe = new PersonEmployment();
                    pe.RelatedPersonId = student.PersonContactId;
                    pe.Name = we.Name_of_Organisation__c;
                    pe.Position = we.Designation__c;
                    pe.AnnualIncome = we.Gross_Annual_CTC__c;
                    pe.StartDate = we.Start_Date__c;
                    pe.EndDate = we.End_Date__c;
              //      pe.SPJIMR_Responsibilities_Functions__c = we.Responsibilities__c;
                    empList.add(pe);
                }
            }

            if (!empList.isEmpty()) insert empList;

            /* 8️⃣ Program Enrollment */
            Set<String> existingKeys = new Set<String>();

            for (ProgramEnrollment pe : [
                SELECT AccountId, ProgramId
                FROM ProgramEnrollment
                WHERE AccountId IN :studentMap.keySet()
            ]) {
                existingKeys.add(pe.AccountId + '-' + pe.ProgramId);
            }

            List<ProgramEnrollment> enrollments = new List<ProgramEnrollment>();

            for (Account student : studentMap.values()) {
                Application__c app = appMap.get(student.Applicant__c);
                if (app == null || app.Program__c == null) continue;

                String key = student.Id + '-' + app.Program__c;
                if (existingKeys.contains(key)) continue;
                
                

                ProgramEnrollment pe = new ProgramEnrollment();
                pe.AccountId = student.Id;
                pe.ProgramId = app.Program__c;
                enrollments.add(pe);
            }

            if (!enrollments.isEmpty()) {
    insert enrollments;
}
            
           Map<Id, ProgramEnrollment> enrollmentByStudent = new Map<Id, ProgramEnrollment>();

for (ProgramEnrollment pe : [
    SELECT Id, AccountId
    FROM ProgramEnrollment
    WHERE AccountId IN :studentMap.keySet()
]) {
    enrollmentByStudent.put(pe.AccountId, pe);
}

            
List<Student_Specialisation__c> specsToInsert = new List<Student_Specialisation__c>();

for (Id appId : applicationIds) {

    Account student = applicationToStudentMap.get(appId);
    Admission_Decision__c ad = decisionMap.get(appId);

    Boolean isEligibleForSpecialization =
        ad != null &&
        ad.Offer_Accepted__c == true &&
        ad.Specialisation_Master__c != null;
    

    if (!isEligibleForSpecialization) continue;

    ProgramEnrollment pe = enrollmentByStudent.get(student.Id);
    if (pe == null) continue;

    Student_Specialisation__c ss = new Student_Specialisation__c();
    ss.Specialisation_Master__c = ad.Specialisation_Master__c;
    ss.Program_Enrollment__c = pe.Id; // ✅ correct linkage
    ss.Specialisation_Type__c='Major';

    specsToInsert.add(ss);
}


if (!specsToInsert.isEmpty()) {
    insert specsToInsert;
}
            
            
           
   /* ======================================================
               9️⃣ Competitive Exam → PersonExamination (NEW)
               ====================================================== */
            
            Map<String, Id> examNameToIdMap = new Map<String, Id>(); 
            
            for (Examination ex : [ SELECT Id, Name FROM Examination ]) { 
                
                examNameToIdMap.put(ex.Name.trim().toUpperCase(), ex.Id); 
            }
            
            
      List<PersonExamination> peList = new List<PersonExamination>();

            for (Competitive_Exam_Details__c ce : [
                SELECT Application__c, Exam_Name__c,
                       GMAT_ID__c, GMAT_Total_Score__c, Quantitative_Score__c,
                       Verbal_Score__c, Analytical_Writing_Score__c,
                       Integrated_Reasoning_Score__c, Test_Date__c,

                       GMAT_FOCUS_ID__c, GMAT_Focus_Edition_Total_Score__c,
                       GMAT_Focus_Edition_Quantitative_Reasonin__c,
                       GMAT_Focus_Edition_Verbal_Reasoning__c,
                       GMAT_Focus_Edition_Data_Insights__c,
                       GMAT_Focus_Edition_Test_Date__c,

                       GRE_ID__c, GRE_Total_Score__c,
                       GRE_Quantitative_Reasoning__c,
                       GRE_Analytical_Writing__c,
                       GRE_Analytical_Reasoning__c,
                       GreMonthAndYear__c, GreMonthAndYearFormula__c,

                       CAT_Registration_Number__c, CAT_Quantitative_Aptitude__c,
                       CatVerbalReadingComprehensionScore__c,
                       CAT_Overall_Percentile__c, CAT_Year_of_Exam__c,

                       XAT_ID__c, XAT_Quantitative_Analytical_Ability__c,
                       XAT_Verbal_Logical_Ability__c,
                       XAT_Decision_Making__c, XAT_Total_Percentile__c,
                       XAT_Year_of_Exam__c,

                       NMAT_ID__c, Total_NMAT_Score_Obtained__c,
                       NMAT_Quantitative_Skills_Score_Obtained__c,
                       NMAT_Language_Skills_Score_Obtained__c,
                       NMAT_Logical_Reasoning_Score_Obtained__c,
                       NmatMonthAndYearOfExam__c, NmatMonthAndYearOfExamFormula__c,

                       TOEFL_ID__c, TOEFL_Total_Score__c,
                       TOEFL_Reading__c, TOEFL_Listening__c,
                       TOEFL_Speaking__c, TOEFL_Writing__c,
                       TOEFL_Year_of_Exam__c,

                       IELTS_ID__c, IELTS_Overall_Band_Score__c,
                       IELTS_Reading__c, IELTS_Listening__c,
                       IELTS_Speaking__c, IELTS_Writing__c,
                       IELTS_CEFR_Level__c, IELTS_Year_of_Exam__c
                FROM Competitive_Exam_Details__c
                WHERE Application__c IN :applicationIds
            ]) {

      Account student1 = applicationToStudentMap.get(ce.Application__c); 
                if (student1 == null) continue; 
                if (String.isBlank(ce.Exam_Name__c)) 
                    continue; 
                Id examId = examNameToIdMap.get(ce.Exam_Name__c.trim().toUpperCase()); if (examId == null) continue; 
                PersonExamination pe = new PersonExamination(); pe.AccountId = student1.Id; // ✅ Person Account 
                pe.ExaminationId = examId; 
                
                

                /* === Exam-wise mapping exactly as per your table === */

                String examName = ce.Exam_Name__c.trim().toUpperCase();

                     if (examName == 'GMAT') {
                     pe.Exam_Registration_Number__c = ce.GMAT_ID__c;
                     pe.Score = ce.GMAT_Total_Score__c?.intValue();
                     pe.Quantitative_Score__c = ce.Quantitative_Score__c;
                     pe.Verbal_Score__c = ce.Verbal_Score__c;
                     pe.Analytical_Writing_Score__c = ce.Analytical_Writing_Score__c;
                     pe.Integrated_Reasoning_Score__c = ce.Integrated_Reasoning_Score__c;
                     pe.ExaminationDate = ce.Test_Date__c;
                     }
                else if (ce.Exam_Name__c == 'GMAT Focus') {
                    pe.Exam_Registration_Number__c = ce.GMAT_FOCUS_ID__c;
                    pe.Score = ce.GMAT_Focus_Edition_Total_Score__c?.intValue();
                    pe.Quantitative_Reasoning__c = ce.GMAT_Focus_Edition_Quantitative_Reasonin__c;
                    pe.GMAT_Focus_Edition_Verbal_Reasoning__c = ce.GMAT_Focus_Edition_Verbal_Reasoning__c;
                    pe.GMAT_Focus_Edition_Data_Insights__c = ce.GMAT_Focus_Edition_Data_Insights__c;
                    pe.ExaminationDate = ce.GMAT_Focus_Edition_Test_Date__c;
                }
                else if (ce.Exam_Name__c == 'GRE') {
                    pe.Exam_Registration_Number__c = ce.GRE_ID__c;
                    pe.Score = ce.GRE_Total_Score__c?.intValue();
                    pe.Quantitative_Reasoning__c = ce.GRE_Quantitative_Reasoning__c;
                    pe.Analytical_Writing_Score__c = ce.GRE_Analytical_Writing__c;
                    pe.GRE_Analytical_Reasoning__c = ce.GRE_Analytical_Reasoning__c;
                    pe.ExaminationDate = ce.GreMonthAndYear__c;
                   
                }
                else if (ce.Exam_Name__c == 'CAT') {
                    pe.Exam_Registration_Number__c = ce.CAT_Registration_Number__c;
                    pe.Quantitative_Aptitude__c = ce.CAT_Quantitative_Aptitude__c;
                    pe.CAT_Verbal_Reading_Comprehension_Score__c =
                        ce.CatVerbalReadingComprehensionScore__c;
                    pe.Total_Percentile__c = ce.CAT_Overall_Percentile__c;
                    pe.Year_of_Exam__c = ce.CAT_Year_of_Exam__c;
                    pe.CAT_E_Mail__c=ce.CAT_E_Mail__c;
                    pe.Is_your_primary_email_ID_same_as_CAT_exa__c=ce.Is_your_primary_email_ID_same_as_CAT_exa__c;
                    
                }
                else if (ce.Exam_Name__c == 'XAT') {
                    pe.Exam_Registration_Number__c = ce.XAT_ID__c;
                    pe.Quantitative_Analytical_Ability__c =
                        ce.XAT_Quantitative_Analytical_Ability__c;
                    pe.XAT_Verbal_Logical_Ability__c = ce.XAT_Verbal_Logical_Ability__c;
                    pe.XAT_Decision_Making__c = ce.XAT_Decision_Making__c;
                    pe.Total_Percentile__c = ce.XAT_Total_Percentile__c;
                    pe.Year_of_Exam__c = ce.XAT_Year_of_Exam__c;
                }
                else if (ce.Exam_Name__c == 'NMAT') {
                    pe.Exam_Registration_Number__c = ce.NMAT_ID__c;
                    pe.Score = ce.Total_NMAT_Score_Obtained__c?.intValue();
                    pe.Quantitative_Score__c =
                        ce.NMAT_Quantitative_Skills_Score_Obtained__c;
                    pe.NMAT_Language_Skills_Score_Obtained__c =
                        ce.NMAT_Language_Skills_Score_Obtained__c;
                    pe.NMAT_Logical_Reasoning_Score_Obtained__c =
                        ce.NMAT_Logical_Reasoning_Score_Obtained__c;
                    pe.ExaminationDate = ce.NmatMonthAndYearOfExam__c;
                   
                }
                else if (ce.Exam_Name__c == 'TOEFL') {
                    pe.Exam_Registration_Number__c = ce.TOEFL_ID__c;
                    pe.Score = ce.TOEFL_Total_Score__c?.intValue();
                    pe.Reading__c = ce.TOEFL_Reading__c;
                    pe.Listening__c = ce.TOEFL_Listening__c;
                    pe.Speaking__c = ce.TOEFL_Speaking__c;
                    pe.Writing__c = ce.TOEFL_Writing__c;
                    pe.Year_of_Exam__c = ce.TOEFL_Year_of_Exam__c;
                }
                else if (ce.Exam_Name__c == 'IELTS') {
                    pe.Exam_Registration_Number__c = ce.IELTS_ID__c;
                    pe.Score = ce.IELTS_Overall_Band_Score__c?.intValue();
                    pe.Reading__c = ce.IELTS_Reading__c;
                    pe.Listening__c = ce.IELTS_Listening__c;
                    pe.Speaking__c = ce.IELTS_Speaking__c;
                    pe.Writing__c = ce.IELTS_Writing__c;
                    pe.IELTS_CEFR_Level__c = ce.IELTS_CEFR_Level__c;
                    pe.Year_of_Exam__c = ce.IELTS_Year_of_Exam__c;
                }

                peList.add(pe);
            }

            if (!peList.isEmpty()) insert peList;
}
        
        catch (Exception e) {
            throw new AuraHandledException('Student conversion failed: ' + e.getMessage());
        }
    }
    
}