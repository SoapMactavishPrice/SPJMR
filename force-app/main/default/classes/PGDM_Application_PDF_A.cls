public class PGDM_Application_PDF_A {
    public id qid {get;set;}
    public Application__c quo {get;set;}
    public ProgramCohort AppBatch {get;set;}
    public Personal_Detail__c PDInfo{get;set;}
   // public Family__c FamilyFater{get;set;}
   // public Family__c FamilyMother{get;set;}
   // public Address_Information_Application__c AddinfoPermanent{get;set;}
   // public Address_Information_Application__c AddinfoCorrespondence{get;set;}
    public Academic_Detail__c AcaDetailX{get;set;}
    public Academic_Detail__c AcaDetailXII{get;set;}
    public Academic_Detail__c AcaDetailGrad{get;set;}
    public Academic_Detail__c AcaDetailDiploma{get;set;}
    public Academic_Detail__c AcaDetailPostGrad{get;set;}    
    public Professional_Qualification__c ProfessQuali{get;set;}
    public List<Professional_Qualification__c> profQualList{get;set;}
    public List<Questionnaire_Response__c> QuestionnaireResponse{get;set;}
    public List<CareerBreak__c> cb{get;set;}
    public List<CareerBreak__c> sb{get;set;}
    public Work_Experience__c WorkExp{get;set;}
    public Work_Experience__c WorkExpPrevioues{get;set;}
    public List<Work_Experience__c> WorkExpList{ get;set;}
    public List<Work_Experience__c> PreviousWorkExpList { get; set; }
    public List<Work_Experience__c> WorkExpLastestList{ get;set;}
    public Competitive_Exam_Details__c CompExamDetailCAT{get;set;}
    public Competitive_Exam_Details__c CompExamDetailGMAT{get;set;}
    public Competitive_Exam_Details__c CompExamDetailGMATFocusEdition{get;set;}
    public Competitive_Exam_Details__c CompExamDetailNMAT{get;set;}
    public Competitive_Exam_Details__c CompExamDetailGRE{get;set;}
    public Competitive_Exam_Details__c CompExamDetailXAT{get;set;}
    public Competitive_Exam_Details__c CompExamDetailTOEFL{get;set;}
    public Competitive_Exam_Details__c CompExamDetailIELTS{get;set;}
   // public Any_Academic_Break__c AAB{get;set;}
    public BasicAcademicDetail__c BAD{get;set;}
   // public Academic_Achievements__c AAchivement{get;set;}
    public List<Academic_Achievements__c>  AAchivementdynamic{ get; set; }
    public Graduation_Details_Semester_wise__c GraduationDSW1{get;set;}
    public Graduation_Details_Semester_wise__c GraduationDSW2{get;set;}
    public Graduation_Details_Semester_wise__c GraduationDSW3{get;set;}
    public Graduation_Details_Semester_wise__c GraduationDSW4{get;set;}
    public Graduation_Details_Semester_wise__c GraduationDSW5{get;set;}
    public Graduation_Details_Semester_wise__c GraduationDSW6{get;set;}
    public Graduation_Details_Semester_wise__c GraduationDSW7{get;set;}
    public Graduation_Details_Semester_wise__c GraduationDSW8{get;set;}
    public Graduation_Details_Semester_wise__c GraduationDSW9{get;set;}
    public Graduation_Details_Semester_wise__c GraduationDSW10{get;set;}
    public Graduation_Details_Semester_wise__c GraduationDSWYear1{get;set;}
    public Graduation_Details_Semester_wise__c GraduationDSWYear2{get;set;}
    public Graduation_Details_Semester_wise__c GraduationDSWYear3{get;set;}
    public Graduation_Details_Semester_wise__c GraduationDSWYear4{get;set;}
    public Graduation_Details_Semester_wise__c GraduationDSWYear5{get;set;}
    public Questionnaire_Response__c QuestionnaireResponse1{get;set;}
    public Questionnaire_Response__c QuestionnaireResponse2{get;set;}
    public Questionnaire_Response__c QuestionnaireResponse3{get;set;}
    public Questionnaire_Response__c QuestionnaireResponse4{get;set;}
    public Questionnaire_Response__c QuestionnaireResponse5{get;set;}
   // public Information_Source__c InformationSource{get;set;}
   // public ResponsibilityShouldered__c ResponsibilityShoulderedPersonal{get;set;}
   // public ResponsibilityShouldered__c ResponsibilityShoulderedProfesional{get;set;}
   // public Versatility__c Versatility{get;set;}
    public Program_Detail__c ProgramDetails{get;set;}
    public String certificateImageURL { get; set; }
    public List<String> imageUrls { get; set; }
    public List<String> pdfUrls { get; set; }
    public String certificateImageBase64 { get; set; }
    public String passportPhotoUrl { get; set; }
    // public QuoteLineItem quoitem {get;set;}
    public List<OrderItem> ActualQuoteLine{get;set;}
   // public List<QuoteLineItem> qlList{get;set;}
    public List<Opportunity> oppList{get;set;}
    public Product2 prod {get;set;}
    public string quoteNo{get;set;}
    public string Contactname{get;set;}
    public string PortofLoading{get;set;}
    public string PortofDischarge{get;set;}
    public string Validfrom{get;set;}
    public string IncoTerms{get;set;}
    public string ShippingCondition{get;set;}
    public decimal customercode{get;set;}
    public string PaymentTerms{get;set;}
    public string BillTo{get;set;}
    public string ShipTo{get;set;}
    public string emailId{get;set;}
    //  public List<wrapclass> listwrap{get; set;}
    // List<Wrapper> wrapperList = new List<Wrapper>();
    public double quoteLineItemCount{get;set;}
    public String body{get;set;}
    public String subject{get;set;}
    public string CC_Addresses{get;set;}
    public string BCC_Addresses{get;set;}
    public string financialYear;
    public date Qdate;
    public string ownerAlias;
    public string accountName;
    public string accountShortName;
    public string factoryName;
    public Boolean hasPassportPhoto {get;set;}
    public Boolean hasAADHAAR {get;set;}
    public Boolean hasDOC_PASSPORT {get;set;}
    public Boolean hasCLASS_X_CERTIFICATE {get;set;}
    public Boolean hasCLASS_X_MARKSHEET {get;set;}
    public Boolean hasCLASS_XII_CERTIFICATE {get;set;}
    public Boolean hasCLASS_XII_MARKSHEET {get;set;}
    public Boolean hasGRAD_CERTIFICATE {get;set;}
    public Boolean hasGRAD_MARKSHEET {get;set;}
    public Boolean hasCONVERSION_FACTOR {get;set;}
    public Boolean hasOFFER_LETTER {get;set;}
    public Boolean hasACHIEVEMENTS {get;set;}
    public Boolean hasWORK_EXP_1 {get;set;}
    public Boolean hasWORK_EXP_2 {get;set;}
    public Boolean hasWORK_EXP_3 {get;set;}
    public Boolean hasWORK_EXP_4 {get;set;}
    public Boolean hasWORK_EXP_5 {get;set;}
    public Boolean hasSALARY_SLIP {get;set;}
    public Boolean hasCAT_SCORE_CARD {get;set;}
    public Boolean hasGMAT_ADMIT_CARD {get;set;}
    public Boolean hasGMAT_SCORE_CARD {get;set;}
    public Boolean hasGMAT_FOCUS_SCORE_CARD {get;set;}
    public PGDM_Application_PDF_A(){
        
        qid = ApexPages.currentPage().getparameters().get('id');
        system.debug('qid'+qid);
       // qlList = new List<QuoteLineItem>();
        // listwrap  = new List<wrapclass>();
        
        system.debug('Stage 1');
        
        quo=[SELECT Id,Name,Application_Number__c,HasExamScores__c,CompetitiveExams__c,PlannedExamDate__c,Batch__r.name,HasWorkExperience__c,ShortTermLongTermGoal__c,AdditonalInformationOnSelf__c,ChoiceOfEssay__c,Essay__c,ReferralName__c,
             OtherProgrammeApplied__c,OtherProgrammeRegNo__c,RequiredFilesUploaded__c,Batch__r.CalculateAgeAsOf__c,HasCareerBreak__c,CareerBreakReason__c,
             TotalIndustryExperience__c,HasSabbatical__c,SabbaticalReason__c,ApplyingUnderRestartInitiative__c,TakingSabbatical__c,AnyMedicalIssue__c,
             MedicalIssueDetails__c,UnderAnyMedication__c,MedicationDetails__c,ReferralSource__c,OtherReferralSource__c,InterestedInOtherProgram__c,
             OtherProgramsInterestedIn__c,AppliedInPastYear__c,ProgramsAppliedInPastYear__c,OtherProgramsAppliedInPastYear__c,DeclarationDate__c,
             PriorWorkResponsibilities__c
             FROM Application__c Where id=: qid];
        try{
        ProgramDetails=[Select id,name,ProgramElegibilityAcceptance__c
            from Program_Detail__c  where Application__c=: qid];

        } catch (Exception e) {
            ProgramDetails = new Program_Detail__c();
        }
        try{
            PDInfo=[SELECT Id,Name,Application__c,Title__c,First_Name__c,Middle_Name__c,Last_Name__c,Gender__c,Date_of_Birth_As_Per_10th_Marksheet__c,Age_as_on_Customisable_Date__c,Primary_E_mail__c,Alternate_E_mail__c,Mobile_Number__c,Alternate_Mobile_Number__c,
                    WhatsApp_Mobile_Number__c,LinkedIn_Profile_URL__c,FatherTitle__c,Father_s_Name__c,MotherTitle__c,Mother_s_Name__c,GuardianName__c,Father_E_Mail_ID__c,Mother_E_Mail_ID__c,GuardianEmail__c,Parent_s_Mobile_Number__c,
                    Mother_s_Mobile_Number__c,GuardianMobile__c,
                    FatherOccupation__c,MotherOccupation__c,GuardianOccupation__c,FatherIncome__c,MotherIncome__c,Corr_Country__r.name,Perm_Country__r.name,Corr_State__r.name,
                    Perm_State__r.name,Corr_City__r.name,Perm_City__r.name,Corr_Address1__c,Perm_Address1__c,Corr_Address2__c,Perm_Address2__c,Corr_Pincode__c,Perm_Pincode__c,
                    OtherFatherOccupation__c,OtherMotherOccupation__c,OtherGuardianOccupation__c,Corr_Ind_Pincode__c,Corr_Ind_Pincode__r.name,Perm_Ind_Pincode__c,Perm_Ind_Pincode__r.name,
                    Other_Corr_City__c,Other_Perm_City__c,Is_Permanent_Same__c,Marital_Status__c,Name_Of_Spouse__c,Contact_No_of_Spouse__c,Category__c,Nationality__c,
                    HavePassport__c,PassportNumber__c,AadhaarCardNumber__c,FormattedAge__c,GuardianRelationship__c,
                    Corr_Ind_City__r.Name,Perm_Ind_City__r.Name,Other_Corr_Ind_City__c,Other_Perm_Ind_City__c,OtherCategory__c
                    
                    FROM Personal_Detail__c where Application__c=: qid limit 1];
        } catch (Exception e) {
            PDInfo = new Personal_Detail__c();
        }
        try{
            BAD=[SELECT id,name,ExpectedGraduationDate__c,GraduationCompleted__c,HasAcademicBreak__c,AcademicBreakYear__c,AcademicBreakReason__c,AnyPostGraduation__c,HasProfessionalQualification__c,
                 ExtraCurricularActivities__c,CertificationDetails__c,Publications__c,AcademicBreakAfter__c
                 FROM BasicAcademicDetail__c where Application__c=: qid  limit 1];
                            
        } catch (Exception e) {
            BAD = new BasicAcademicDetail__c();
        }
        try{
            AcaDetailX=[SELECT Id,Name,Application__c,School_Institute__c,Board_University__c,MonthAndYearOfPassingFormula__c,Marking_Scheme__c,Percentage__c,Maximum_Marks__c,
                        Obtained_Marks__c,Conversion_Factor__c,OtherState__c,Other_Board_University__c,ConversionFormula__c
                        FROM Academic_Detail__c where Application__c=: qid  and Name = '10th' limit 1];
        } catch (Exception e) {
            AcaDetailX = new Academic_Detail__c();
        }
        try{
            AcaDetailXII=[SELECT Id,Name,Application__c,School_Institute__c,Board_University__c,MonthAndYearOfPassingFormula__c,Marking_Scheme__c,Percentage__c,Maximum_Marks__c,
                          Obtained_Marks__c,Conversion_Factor__c,OtherState__c,Other_Board_University__c,ConversionFormula__c
                          FROM Academic_Detail__c where Application__c=: qid  and Name = '12th' limit 1];
        } catch (Exception e) {
            AcaDetailXII = new Academic_Detail__c();
        }
        try{
            AcaDetailDiploma=[SELECT Id,Name,Application__c,School_Institute__c,Board_University__c,Diploma_Name__c,MonthAndYearOfPassingFormula__c,Marking_Scheme__c,Percentage__c,
                              Maximum_Marks__c,Obtained_Marks__c,Conversion_Factor__c,OtherState__c,Other_Board_University__c,ConversionFormula__c
                          FROM Academic_Detail__c where Application__c=: qid  and Name = 'Diploma' limit 1];
        } catch (Exception e) {
            AcaDetailDiploma = new Academic_Detail__c();
        }
        try{
            AcaDetailGrad=[SELECT Id,Name,Application__c,MonthAndYearOfPassingFormula__c,School_Institute__c,Board_University__c,Degree__c,Mode_of_Study__c,Specialization_Name__c,State__c,
                           Marking_Scheme__c,Pattern_of_Examination__c,Maximum_Marks__c,Obtained_Marks__c,College__c,College__r.name,OtherCollege__c,OtherDegree__c,
                           College__r.CollegeName__c,University__r.UniversityName__c,State__r.Name,OtherUniversity__c,Percentage__c,Degree_Type__c,MonthAndYearOfCommencementFormula__c,
                           Conversion_Factor__c,OtherState__c,ConversionFormula__c
                           FROM Academic_Detail__c where Application__c=: qid  and Name = 'UG' limit 1]; 
        } catch (Exception e) {
            AcaDetailGrad = new Academic_Detail__c();
        }
        try{
            GraduationDSW1=[SELECT Id,Name,Academic_Detail__c,Academic_Detail__r.Pattern_of_Examination__c,Year_Semester_Name__c,Maximum_Marks_SGPA__c,Obtained_Marks_SGPA__c 
                           FROM Graduation_Details_Semester_wise__c where Academic_Detail__c=: AcaDetailGrad.id and Academic_Detail__r.Pattern_of_Examination__c ='Semester wise' and Year_Semester_Name__c = '1' limit 1];
                            
        } catch (Exception e) {
            GraduationDSW1 = new Graduation_Details_Semester_wise__c();
        }
        try{
            GraduationDSW2=[SELECT Id,Name,Academic_Detail__c,Academic_Detail__r.Pattern_of_Examination__c,Year_Semester_Name__c,Maximum_Marks_SGPA__c,Obtained_Marks_SGPA__c
                           FROM Graduation_Details_Semester_wise__c where Academic_Detail__c=: AcaDetailGrad.id  and Academic_Detail__r.Pattern_of_Examination__c ='Semester wise' and Year_Semester_Name__c = '2' limit 1];
                            
        } catch (Exception e) {
            GraduationDSW2 = new Graduation_Details_Semester_wise__c();
        }
        try{
            GraduationDSW3=[SELECT Id,Name,Academic_Detail__c,Academic_Detail__r.Pattern_of_Examination__c,Year_Semester_Name__c,Maximum_Marks_SGPA__c,Obtained_Marks_SGPA__c 
                           FROM Graduation_Details_Semester_wise__c where Academic_Detail__c=: AcaDetailGrad.id  and Academic_Detail__r.Pattern_of_Examination__c ='Semester wise'and Year_Semester_Name__c = '3' limit 1];
                            
        } catch (Exception e) {
            GraduationDSW3 = new Graduation_Details_Semester_wise__c();
        }
        try{
            GraduationDSW4=[SELECT Id,Name,Academic_Detail__c,Academic_Detail__r.Pattern_of_Examination__c,Year_Semester_Name__c,Maximum_Marks_SGPA__c,Obtained_Marks_SGPA__c 
                           FROM Graduation_Details_Semester_wise__c where Academic_Detail__c=: AcaDetailGrad.id  and Academic_Detail__r.Pattern_of_Examination__c ='Semester wise' and Year_Semester_Name__c = '4' limit 1];
                            
        } catch (Exception e) {
            GraduationDSW4 = new Graduation_Details_Semester_wise__c();
        }
        try{
            GraduationDSW5=[SELECT Id,Name,Academic_Detail__c,Academic_Detail__r.Pattern_of_Examination__c,Year_Semester_Name__c,Maximum_Marks_SGPA__c,Obtained_Marks_SGPA__c 
                           FROM Graduation_Details_Semester_wise__c where Academic_Detail__c=: AcaDetailGrad.id  and Academic_Detail__r.Pattern_of_Examination__c ='Semester wise' and Year_Semester_Name__c = '5' limit 1];
                            
        } catch (Exception e) {
            GraduationDSW5 = new Graduation_Details_Semester_wise__c();
        }
        try{
            GraduationDSW6=[SELECT Id,Name,Academic_Detail__c,Academic_Detail__r.Pattern_of_Examination__c,Year_Semester_Name__c,Maximum_Marks_SGPA__c,Obtained_Marks_SGPA__c 
                           FROM Graduation_Details_Semester_wise__c where Academic_Detail__c=: AcaDetailGrad.id  and Academic_Detail__r.Pattern_of_Examination__c ='Semester wise' and Year_Semester_Name__c = '6' limit 1];
                            
        } catch (Exception e) {
            GraduationDSW6 = new Graduation_Details_Semester_wise__c();
        }
        try{
            GraduationDSW7=[SELECT Id,Name,Academic_Detail__c,Academic_Detail__r.Pattern_of_Examination__c,Year_Semester_Name__c,Maximum_Marks_SGPA__c,Obtained_Marks_SGPA__c 
                           FROM Graduation_Details_Semester_wise__c where Academic_Detail__c=: AcaDetailGrad.id and Academic_Detail__r.Pattern_of_Examination__c ='Semester wise' and Year_Semester_Name__c = '7' limit 1];
                            
        } catch (Exception e) {
            GraduationDSW7 = new Graduation_Details_Semester_wise__c();
        }
        try{
            GraduationDSW8=[SELECT Id,Name,Academic_Detail__c,Academic_Detail__r.Pattern_of_Examination__c,Year_Semester_Name__c,Maximum_Marks_SGPA__c,Obtained_Marks_SGPA__c 
                           FROM Graduation_Details_Semester_wise__c where Academic_Detail__c=: AcaDetailGrad.id and Academic_Detail__r.Pattern_of_Examination__c ='Semester wise' and Year_Semester_Name__c = '8' limit 1];
                            
        } catch (Exception e) {
            GraduationDSW8 = new Graduation_Details_Semester_wise__c();
        }
        try{
            GraduationDSW9=[SELECT Academic_Detail__c,Application__c,CreatedById,CreatedDate,CurrencyIsoCode,Id,IsDeleted,LastActivityDate,LastModifiedById,LastModifiedDate,
                           Maximum_Marks_SGPA__c,Name,Obtained_Marks_SGPA__c,OwnerId,Qualifications__c,SystemModstamp,Year_Semester_Name__c 
                           FROM Graduation_Details_Semester_wise__c where Academic_Detail__c=: AcaDetailGrad.id and Academic_Detail__r.Pattern_of_Examination__c ='Semesterwise' and Year_Semester_Name__c = '9' limit 1];
                            
        } catch (Exception e) {
            GraduationDSW9 = new Graduation_Details_Semester_wise__c();
        }
        try{
            GraduationDSW10=[SELECT Academic_Detail__c,Application__c,CreatedById,CreatedDate,CurrencyIsoCode,Id,IsDeleted,LastActivityDate,LastModifiedById,LastModifiedDate,
                           Maximum_Marks_SGPA__c,Name,Obtained_Marks_SGPA__c,OwnerId,Qualifications__c,SystemModstamp,Year_Semester_Name__c 
                           FROM Graduation_Details_Semester_wise__c where Academic_Detail__c=: AcaDetailGrad.id and Academic_Detail__r.Pattern_of_Examination__c ='Semesterwise' and Year_Semester_Name__c = '10' limit 1];
                            
        } catch (Exception e) {
            GraduationDSW10 = new Graduation_Details_Semester_wise__c();
        }
        try{
            GraduationDSWYear1=[SELECT Id,Name,Academic_Detail__c,Academic_Detail__r.Pattern_of_Examination__c,Year_Semester_Name__c,Maximum_Marks_SGPA__c,Obtained_Marks_SGPA__c  
                           FROM Graduation_Details_Semester_wise__c where Academic_Detail__c=: AcaDetailGrad.id and Academic_Detail__r.Pattern_of_Examination__c ='Year wise' and Year_Semester_Name__c = '1' limit 1];
                            
        } catch (Exception e) {
            GraduationDSWYear1 = new Graduation_Details_Semester_wise__c();
        }
         try{
            GraduationDSWYear2=[SELECT Id,Name,Academic_Detail__c,Academic_Detail__r.Pattern_of_Examination__c,Year_Semester_Name__c,Maximum_Marks_SGPA__c,Obtained_Marks_SGPA__c 
                           FROM Graduation_Details_Semester_wise__c where Academic_Detail__c=: AcaDetailGrad.id and Academic_Detail__r.Pattern_of_Examination__c ='Year wise' and Year_Semester_Name__c = '2' limit 1];
                            
        } catch (Exception e) {
            GraduationDSWYear2 = new Graduation_Details_Semester_wise__c();
        }
         try{
            GraduationDSWYear3=[SELECT Id,Name,Academic_Detail__c,Academic_Detail__r.Pattern_of_Examination__c,Year_Semester_Name__c,Maximum_Marks_SGPA__c,Obtained_Marks_SGPA__c
                           FROM Graduation_Details_Semester_wise__c where Academic_Detail__c=: AcaDetailGrad.id and Academic_Detail__r.Pattern_of_Examination__c ='Year wise' and Year_Semester_Name__c = '3' limit 1];
                            
        } catch (Exception e) {
            GraduationDSWYear3 = new Graduation_Details_Semester_wise__c();
        }
         try{
            GraduationDSWYear4=[SELECT Id,Name,Academic_Detail__c,Academic_Detail__r.Pattern_of_Examination__c,Year_Semester_Name__c,Maximum_Marks_SGPA__c,Obtained_Marks_SGPA__c 
                           FROM Graduation_Details_Semester_wise__c where Academic_Detail__c=: AcaDetailGrad.id and Academic_Detail__r.Pattern_of_Examination__c ='Year wise' and Year_Semester_Name__c = '4' limit 1];
                            
        } catch (Exception e) {
            GraduationDSWYear4 = new Graduation_Details_Semester_wise__c();
        }
         try{
            GraduationDSWYear5=[SELECT Id,Name,Academic_Detail__c,Academic_Detail__r.Pattern_of_Examination__c,Year_Semester_Name__c,Maximum_Marks_SGPA__c,Obtained_Marks_SGPA__c 
                           FROM Graduation_Details_Semester_wise__c where Academic_Detail__c=: AcaDetailGrad.id and Academic_Detail__r.Pattern_of_Examination__c ='Year wise' and Year_Semester_Name__c = '5' limit 1];
                            
        } catch (Exception e) {
            GraduationDSWYear5 = new Graduation_Details_Semester_wise__c();
        }
        try{
            AcaDetailPostGrad=[SELECT Id,Name,Application__c,MonthAndYearOfPassingFormula__c,School_Institute__c,Board_University__c,Degree__c,Mode_of_Study__c,Specialization_Name__c,State__c,
                               Marking_Scheme__c,Pattern_of_Examination__c,Maximum_Marks__c,Obtained_Marks__c,College__c,College__r.name,OtherCollege__c,OtherDegree__c,
                               College__r.CollegeName__c,University__r.UniversityName__c,State__r.Name,OtherUniversity__c,Percentage__c,DegreeStatus__c,Conversion_Factor__c,
                               OtherState__c,MonthAndYearOfCommencementFormula__c,ConversionFormula__c
                               FROM Academic_Detail__c where Application__c=: qid  and Name = 'PG' limit 1];
        } catch (Exception e) {
            AcaDetailPostGrad = new Academic_Detail__c();
        }
         try{
            profQualList=[SELECT Id,Name,Application__c,Name_of_Qualification__c,Name_of_Institute__c,Rank_Achieved__c,Level_Achieved__c,Total_Max_Marks__c,Marks_Obtained__c,
                          Percentage_Actual__c,Qualification_Status__c,Year_of_Passing_pq__c,Name_of_Qualification_Picklist__c,Name_of_Institute_Picklist__c,
                          Year_of_Commencement_pq__c
                          FROM Professional_Qualification__c where Application__c=: qid];
        } catch (Exception e) {
            profQualList = new List<Professional_Qualification__c>();
        }
        try{
            WorkExpLastestList =[SELECT Id,Name,Application__c,Name_of_Organisation__c,OtherOrganizationName__c,Designation__c,Gross_Annual_CTC__c,Responsibilities__c,
                                 Start_Date__c,End_Date__c,Start_Date_Formula__c,End_Date_Formula__c,Total_Experience_In_Months__c,Employment_Type__c,
                                 City__c,City__r.name,OtherCity__c,Currency__c,OtherCurrency__c,IsCurrentJob__c,Industry__c,OtherIndustry__c,Function__c,OtherFunction__c       
                         FROM Work_Experience__c where Application__c=: qid  ORDER BY End_Date__c DESC NULLS FIRST LIMIT 1];
        } catch (Exception e) {
            WorkExpLastestList  = New List<Work_Experience__c>();
        }
        try{
            CompExamDetailCAT=[SELECT Id,Name,Result_Status__c,CAT_Registration_Number__c,Is_your_primary_email_ID_same_as_CAT_exa__c,CAT_Overall_Score__c,
            CAT_Overall_Percentile__c,CatVerbalReadingComprehensionScore__c,CatVerbalReadingComprehensionPercentile__c,Data_interpretation_and_logical_re_score__c,
            Data_interpretation_and_logical_re_perce__c,CAT_Quantitative_Aptitude__c,CAT_Quantitative_Aptitude_Percentile__c                   
            FROM Competitive_Exam_Details__c where Application__c=: qid  AND Exam_Name__c ='CAT' limit 1];
        } catch (Exception e) {
            CompExamDetailCAT = new Competitive_Exam_Details__c();
        }
        try{
            CompExamDetailGMAT=[SELECT Id,Name,Result_Status__c,GMAT_ID__c,GMAT_Appointment_No__c,Test_Date__c,GMAT_Score_Issue_Date__c,GMAT_Total_Score__c,
            GMAT_Total_Percentile__c,Quantitative_Score__c,Quantitative_Percentile__c,Verbal_Score__c,Verbal_Percentile__c                    
            FROM Competitive_Exam_Details__c where Application__c=: qid  AND Exam_Name__c ='GMAT' limit 1];
        } catch (Exception e) {
            CompExamDetailGMAT = new Competitive_Exam_Details__c();
        }
        try{
            CompExamDetailGMATFocusEdition=[SELECT Id,Name,Result_Status__c,GMAT_FOCUS_ID__c,GMAT_FOCUS_ID_Appointment_Number__c,GMAT_Focus_Edition_Test_Date__c,
            GMAT_Focus_Edition_Score_Issue_Date__c,GMAT_Focus_Edition_Total_Score__c,GMAT_Focus_Edition_Total_Percentile__c,GMAT_Focus_Edition_Quantitative_Reasonin__c,
            GMAT_FE_Quantitative_Reasoning_Perce__c,GMAT_Focus_Edition_Verbal_Reasoning__c,GMAT_FE_Verbal_Reasoning_Perce__c,GMAT_Focus_Edition_Data_Insights__c,
            GMAT_FE_Data_Insights_Percentile__c                                
            FROM Competitive_Exam_Details__c where Application__c=: qid  AND Exam_Name__c ='GMAT Focus' limit 1];
        } catch (Exception e) {
            CompExamDetailGMATFocusEdition = new Competitive_Exam_Details__c();
        }
        passportPhotoUrl = '';

        // Your existing code to populate passportPhotoUrl
        List<Document_Details__c> docListPassportSizePhoto = [SELECT Id, Name  FROM Document_Details__c WHERE Application_No__c = :qid AND Document_Code__c = 'PASSPORT_PHOTO' LIMIT 1];
        
        List<Document_Details__c> docListDOC_CAT_SCORE_CARD = [SELECT Id, Name  FROM Document_Details__c WHERE Application_No__c = :qid AND Document_Code__c = 'DOC_CAT_SCORE_CARD' LIMIT 1];
        hasCAT_SCORE_CARD = false;
        if (!docListDOC_CAT_SCORE_CARD.isEmpty()) {
            List<ContentDocumentLink> CAT_SCORE_CARDDocLinks = [
                SELECT Id
                FROM ContentDocumentLink
                WHERE LinkedEntityId = :docListDOC_CAT_SCORE_CARD[0].Id
                LIMIT 1
            ];
            hasCAT_SCORE_CARD = !CAT_SCORE_CARDDocLinks.isEmpty();
        }
        List<Document_Details__c> docListDOC_GMAT_SCORE_CARD = [SELECT Id, Name  FROM Document_Details__c WHERE Application_No__c = :qid AND Document_Code__c = 'DOC_GMAT_SCORE_CARD' LIMIT 1];
        hasGMAT_SCORE_CARD = false;
        if (!docListDOC_GMAT_SCORE_CARD.isEmpty()) {
            List<ContentDocumentLink> GMAT_SCORE_CARDDocLinks = [
                SELECT Id
                FROM ContentDocumentLink
                WHERE LinkedEntityId = :docListDOC_GMAT_SCORE_CARD[0].Id
                LIMIT 1
            ];
            hasGMAT_SCORE_CARD = !GMAT_SCORE_CARDDocLinks.isEmpty();
        }
        List<Document_Details__c> docListDOC_GMAT_FOCUS_SCORE_CARD = [SELECT Id, Name  FROM Document_Details__c WHERE Application_No__c = :qid AND Document_Code__c = 'DOC_GMAT_FOCUS_SCORE_CARD' LIMIT 1];
        hasGMAT_FOCUS_SCORE_CARD = false;
        if (!docListDOC_GMAT_FOCUS_SCORE_CARD.isEmpty()) {
            List<ContentDocumentLink> GMAT_FOCUS_SCORE_CARDocLinks = [
                SELECT Id
                FROM ContentDocumentLink
                WHERE LinkedEntityId = :docListDOC_GMAT_FOCUS_SCORE_CARD[0].Id
                LIMIT 1
            ];
            hasGMAT_FOCUS_SCORE_CARD = !GMAT_FOCUS_SCORE_CARDocLinks.isEmpty();
        }
        
        if (!docListPassportSizePhoto.isEmpty()) {
            List<ContentDocumentLink> docLinks = [
                SELECT ContentDocumentId 
                FROM ContentDocumentLink 
                WHERE LinkedEntityId = :docListPassportSizePhoto[0].Id
            ];

            if (!docLinks.isEmpty()) {
                List<ContentVersion> fileList = [
                    SELECT Id, Title, FileExtension, ContentDocumentId
                    FROM ContentVersion
                    WHERE ContentDocumentId = :docLinks[0].ContentDocumentId
                      AND IsLatest = true
                ];

                if (!fileList.isEmpty()) {
                    passportPhotoUrl = '/sfc/servlet.shepherd/version/download/' + fileList[0].Id;
                }
            }
        }
        // Step 1: Passport Size Photo records End
        imageUrls = new List<String>();
        pdfUrls = new List<String>();
        
        // 🎯 Required output order based on Document_Name__r.Name
        List<String> orderedNames = new List<String>{
            'DOC_RESUME',   
                'Class 10 Mark Sheet',
                'Class 12 Mark Sheet', 
                'DOC_CLASS_X',
                'DOC_CLASS_XII',
                'DOC_DIPLOMA',        
                'DOC_GRAD',
                'DOC_POST_GRAD',
                'DOC_COMPETITIVE_GRE',
                'DOC_COMPETITIVE_GMAT',
                'DOC_COMPETITIVE_CAT',
                'DOC_COMPETITIVE_XAT',
                'DOC_COMPETITIVE_NMAT',
                'DOC_COMPETITIVE_GMATFocus',
                'DOC_LANGUAGE_TOEFL',
                'DOC_LANGUAGE_IELTS'
                // 'DOC_APPOINTMENT_ORDER'   
                };
                    
                    // Step 1: Get all Document_Details__c records (excluding photo)
                    List<Document_Details__c> docList = [
                        SELECT Id, Document_Code__c
                        FROM Document_Details__c
                        WHERE Application_No__c = :qid AND Document_Code__c != 'PASSPORT_PHOTO'
                    ];
        
        // Map: DocumentName → ContentDocumentId(s)
        Map<String, List<Id>> docNameToContentIds = new Map<String, List<Id>>();
        
        if (!docList.isEmpty()) {
            List<Id> docIds = new List<Id>();
            for (Document_Details__c d : docList) {
                docIds.add(d.Id);
            }
            
            // Step 2: Fetch file links
            List<ContentDocumentLink> docLinks = [
                SELECT ContentDocumentId, LinkedEntityId
                FROM ContentDocumentLink
                WHERE LinkedEntityId IN :docIds
            ];
            
            // Prepare mapping
            for (ContentDocumentLink link : docLinks) {
                for (Document_Details__c d : docList) {
                    if (d.Id == link.LinkedEntityId && d.Document_Code__c != null) {
                        String key = d.Document_Code__c.trim();
                        if (!docNameToContentIds.containsKey(key)) {
                            docNameToContentIds.put(key, new List<Id>());
                        }
                        docNameToContentIds.get(key).add(link.ContentDocumentId);
                    }
                }
            }
        }
        
        // Step 3: Now fetch files in ⚡YOUR required order
        for (String docName : orderedNames) {
            
            if (docNameToContentIds.containsKey(docName)) {
                
                List<ContentVersion> fileList = [
                    SELECT Title, FileExtension, ContentDocumentId
                    FROM ContentVersion
                    WHERE ContentDocumentId IN :docNameToContentIds.get(docName)
                    AND IsLatest = true  ORDER BY ContentSize DESC  // 🔥 now larger files show first
                    
                ];
                
                for (ContentVersion file : fileList) {
                    String ext = file.FileExtension != null ? file.FileExtension.toLowerCase() : '';
                    String fileUrl = '/sfc/servlet.shepherd/document/download/' + file.ContentDocumentId;
                    
                    if (ext == 'jpg' || ext == 'jpeg' || ext == 'png' || ext == 'gif') {
                        imageUrls.add(fileUrl);
                    } else if (ext == 'pdf') {
                        pdfUrls.add(fileUrl);
                    }
                }
            }
        }
    }
    public Work_Experience__c latestWorkExp {
        get {
            if(WorkExpLastestList != null && !WorkExpLastestList.isEmpty()){
                return WorkExpLastestList[0];
            }
            return new Work_Experience__c();
        }
    }
    Public Pagereference Cancel(){
        pagereference pg=new pagereference('/'+qid);
        pg.setRedirect(true);
        return pg;        
    }
}