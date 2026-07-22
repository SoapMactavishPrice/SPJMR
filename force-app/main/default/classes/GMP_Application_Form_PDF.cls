public class GMP_Application_Form_PDF {
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
    public List<CareerBreak__c> cb{get;set;}
    public Work_Experience__c WorkExp{get;set;}
    public Work_Experience__c WorkExpPrevioues{get;set;}
    public List<Work_Experience__c> WorkExpList{ get;set;}
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
   // public List<Academic_Achievements__c>  AAchivementdynamic{ get; set; }
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
   // public Information_Source__c InformationSource{get;set;}
   // public ResponsibilityShouldered__c ResponsibilityShoulderedPersonal{get;set;}
   // public ResponsibilityShouldered__c ResponsibilityShoulderedProfesional{get;set;}
   // public Versatility__c Versatility{get;set;}
   // public Program_Detail__c ProgramDetails{get;set;}
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
    
    public GMP_Application_Form_PDF(){
        
        qid = ApexPages.currentPage().getparameters().get('id');
        system.debug('qid'+qid);
       // qlList = new List<QuoteLineItem>();
        // listwrap  = new List<wrapclass>();
        
        system.debug('Stage 1');
        
        quo=[SELECT Id,Name,Application_Number__c,HasExamScores__c,CompetitiveExams__c,PlannedExamDate__c,Batch__r.name,HasWorkExperience__c,ShortTermLongTermGoal__c,AdditonalInformationOnSelf__c,ChoiceOfEssay__c,Essay__c,ReferralSource__c,ReferralName__c,
             OtherProgrammeApplied__c,OtherProgrammeRegNo__c,RequiredFilesUploaded__c,Batch__r.CalculateAgeAsOf__c,HasCareerBreak__c,CareerBreakReason__c
             FROM Application__c Where id=: qid];
          try{
        cb=[Select id,name,Application__c,StartDate__c,StartDateFormula__c,EndDate__c,EndDateFormula__c,CareerBreakInMonths__c from CareerBreak__c  where Application__c=: qid];

        } catch (Exception e) {
            profQualList = new List<Professional_Qualification__c>();
        }
        /*try{
            AppBatch=[SELECT Allow_Exchange_Participation__c,Allow_Multi_Program_Batch__c,Allow_Previous_Batch_Same_Programme__c,Allow_Re_Evaluation__c,Application_End_Date__c,Application_Fee__c,Application_Start_Date__c,
                Batch_Base_Currency__c,Batch_Code__c,Batch_Credit_Hours__c,Batch_End_Date__c,Batch_Group_Year__c,Batch_Header__c,Batch_Intake_AICTE__c,Batch_Intake__c,Batch_Pattern__c,Batch_Start_Date__c,Batch_Status__c,
                Batch_Sub_Type__c,Batch_Terms__c,Batch_Type__c,CalculateAgeAsOf__c,Cannot_Exceed_Program_Intake__c,CreatedById,CreatedDate,Credit_Period__c,CurrencyIsoCode,CurrentMemberCount,Description,Division__c,
                EndDate,Id,IsDeleted,is_Active__c,Is_Completed__c,Is_Student_Exchange__c,LastModifiedById,LastModifiedDate,LastReferencedDate,LastViewedDate,MaximumMemberCount,Name,No_of_Months__c,Number_of_Batch_Group__c,
                Online_Foundation_Start_Date__c,On_Campus_Program_Commence_Date__c,Open_Window_Period__c,Phases_Per_Term__c,ProgramId,Program_Code__c,Program_Name__c,Re_Evaluation_Applicable_to__c,School_Name__c,
                School_Wise_Program__c,Session_Duration__c,Short_Batch_Code__c,Specialisation_Change_End_Date__c,Specialisation_Change_Start_Date__c,StartDate,Status,SystemModstamp,Term_1_End_Date__c,Term_1_Start_Date__c,
                Term_2_End_Date__c,Term_2_Start_Date__c,Term_3_End_Date__c,Term_3_Start_Date__c,Term_4_End_Date__c,Term_4_Start_Date__c,Term_5_End_Date__c,Term_5_Start_Date__c,Term_6_End_Date__c,Term_6_Start_Date__c,
                Term_7_End_Date__c,Term_7_Start_Date__c,Term_8_End_Date__c,Term_8_Start_Date__c,Term_9_End_Date__c,Term_9_Start_Date__c,Term_10_End_Date__c,Term_10_Start_Date__c,Years__c 
                FROM ProgramCohort where Application__c=: qid limit 1];
        } catch (Exception e) {
            AppBatch = new ProgramCohort();
        }*/
        try{
            PDInfo=[SELECT Id,Name,Application__c,Title__c,First_Name__c,Middle_Name__c,Last_Name__c,Gender__c,Date_of_Birth_As_Per_10th_Marksheet__c,Age_as_on_Customisable_Date__c,Primary_E_mail__c,Alternate_E_mail__c,Mobile_Number__c,Alternate_Mobile_Number__c,
                    WhatsApp_Mobile_Number__c,LinkedIn_Profile_URL__c,FatherTitle__c,Father_s_Name__c,MotherTitle__c,Mother_s_Name__c,GuardianName__c,Father_E_Mail_ID__c,Mother_E_Mail_ID__c,GuardianEmail__c,Parent_s_Mobile_Number__c,
                    Mother_s_Mobile_Number__c,GuardianMobile__c,
                    FatherOccupation__c,MotherOccupation__c,GuardianOccupation__c,FatherIncome__c,MotherIncome__c,Corr_Country__r.name,Perm_Country__r.name,Corr_State__r.name,
                    Perm_State__r.name,Corr_City__r.name,Perm_City__r.name,Corr_Address1__c,Perm_Address1__c,Corr_Address2__c,Perm_Address2__c,Corr_Pincode__c,Perm_Pincode__c,
                    OtherFatherOccupation__c,OtherMotherOccupation__c,OtherGuardianOccupation__c,Corr_Ind_Pincode__c,Corr_Ind_Pincode__r.name,Perm_Ind_Pincode__c,Perm_Ind_Pincode__r.name,
                    Other_Corr_City__c,Other_Perm_City__c,Age__c,GuardianRelationship__c,Nationality__c,HavePassport__c,PassportNumber__c,/*Do_you_have_Aadhaar_Card__c,*/AadhaarCardNumber__c,
                    PassportApplicationNumber__c
                    FROM Personal_Detail__c where Application__c=: qid limit 1];
        } catch (Exception e) {
            PDInfo = new Personal_Detail__c();
        }
        /* try{
            FamilyFater=[SELECT id,name,Annual_Family_Income_Exclude__c,Application__c,Contact_Details_Email_ID__c,Contact_Number__c,Current_Annual_Income_Last_FY__c,Designation__c,Full_Name__c,Occupation__c,
                         Parents_Guardian__c,Qualifications__c,Question__c,Question_Response__c,Retired__c
                         from Family__c where Application__c=: qid and Parents_Guardian__c='Father' limit 1];
        } catch (Exception e) {
            FamilyFater = new Family__c();
        }
         try{
            FamilyMother=[SELECT id,name,Annual_Family_Income_Exclude__c,Application__c,Contact_Details_Email_ID__c,Contact_Number__c,Current_Annual_Income_Last_FY__c,Designation__c,Full_Name__c,Occupation__c,
                         Parents_Guardian__c,Qualifications__c,Question__c,Question_Response__c,Retired__c
                          from Family__c where Application__c=: qid and Parents_Guardian__c='Mother' limit 1];
        } catch (Exception e) {
            FamilyMother = new Family__c();
        }*/
       /* try{
            AddinfoPermanent=[SELECT Address__c,Application__c,City_Correspondence__c,Country__c,CreatedById,CreatedDate,CurrencyIsoCode,District_Correspondence__c,Id,IsDeleted,
                              Is_permanent_address_same_as_address_for__c,LastActivityDate,LastModifiedById,LastModifiedDate,Name,OwnerId,Pincode__c,State__c,SystemModstamp,
                              Total_Work_Experience_in_Months__c,Type_of_Address__c,Address_Line_2__c,Country_Permanent__c,State_Permanent__c,District_Permanent__c,City_Permanent__c,
                              Permanent_Address_Line_1__c,Permanent_Address_Line_2__c,Pincode_Permanent__c
                              FROM Address_Information_Application__c where Application__c=: qid and Type_of_Address__c='Permanent'limit 1];
        } catch (Exception e) {
            AddinfoPermanent = new Address_Information_Application__c();
        }
        try{
            AddinfoCorrespondence=[SELECT Address__c,Application__c,City_Correspondence__c,Country__c,CreatedById,CreatedDate,CurrencyIsoCode,District_Correspondence__c,Id,IsDeleted,
                                   Is_permanent_address_same_as_address_for__c,LastActivityDate,LastModifiedById,LastModifiedDate,Name,OwnerId,Pincode__c,State__c,SystemModstamp,
                                   Total_Work_Experience_in_Months__c,Type_of_Address__c,Address_Line_2__c,Permanent_Address_Line_1__c,Permanent_Address_Line_2__c,Pincode_Permanent__c 
                                   FROM Address_Information_Application__c where Application__c=: qid and Type_of_Address__c='Correspondence' limit 1];
        } catch (Exception e) {
            AddinfoCorrespondence = new Address_Information_Application__c();
        }*/
        try{
            AcaDetailX=[SELECT Id,Name,Application__c,School_Institute__c,Board_University__c,MonthAndYearOfPassingFormula__c,Marking_Scheme__c,Percentage__c
                        FROM Academic_Detail__c where Application__c=: qid  and Name = '10th' limit 1];
        } catch (Exception e) {
            AcaDetailX = new Academic_Detail__c();
        }
        try{
            AcaDetailXII=[SELECT Id,Name,Application__c,School_Institute__c,Board_University__c,MonthAndYearOfPassingFormula__c,Marking_Scheme__c,Percentage__c
                          FROM Academic_Detail__c where Application__c=: qid  and Name = '12th' limit 1];
        } catch (Exception e) {
            AcaDetailXII = new Academic_Detail__c();
        }
        try{
            AcaDetailDiploma=[SELECT Id,Name,Application__c,School_Institute__c,Board_University__c,Diploma_Name__c,MonthAndYearOfPassingFormula__c,Marking_Scheme__c,Percentage__c
                          FROM Academic_Detail__c where Application__c=: qid  and Name = 'Diploma' limit 1];
        } catch (Exception e) {
            AcaDetailDiploma = new Academic_Detail__c();
        }
        try{
            AcaDetailGrad=[SELECT Id,Name,Application__c,MonthAndYearOfPassingFormula__c,School_Institute__c,Board_University__c,Degree__c,Mode_of_Study__c,Specialization_Name__c,State__c,
                           Marking_Scheme__c,Pattern_of_Examination__c,Maximum_Marks__c,Obtained_Marks__c,College__c,College__r.name,OtherCollege__c,OtherDegree__c,
                           College__r.CollegeName__c,University__r.UniversityName__c,State__r.Name,OtherUniversity__c,Percentage__c 
                           FROM Academic_Detail__c where Application__c=: qid  and Name = 'UG' limit 1]; 
        } catch (Exception e) {
            AcaDetailGrad = new Academic_Detail__c();
        }
        try{
            AcaDetailPostGrad=[SELECT Id,Name,Application__c,MonthAndYearOfPassingFormula__c,School_Institute__c,Board_University__c,Degree__c,Mode_of_Study__c,Specialization_Name__c,State__c,
                               Marking_Scheme__c,Pattern_of_Examination__c,Maximum_Marks__c,Obtained_Marks__c,College__c,College__r.name,OtherCollege__c,OtherDegree__c,
                               College__r.CollegeName__c,University__r.UniversityName__c,State__r.Name,OtherUniversity__c,Percentage__c 
                               FROM Academic_Detail__c where Application__c=: qid  and Name = 'PG' limit 1];
        } catch (Exception e) {
            AcaDetailPostGrad = new Academic_Detail__c();
        }
        /*try{
            ProfessQuali=[SELECT Academic_Professional_Achievements__c,Application__c,CreatedById,CreatedDate,CurrencyIsoCode,Extra_Curricular_Activities_If_Any__c,
                          Have_you_appeared_for_the_Executive_Asse__c,Id,Integrated_Reasoning__c,IsDeleted,LastActivityDate,LastModifiedById,LastModifiedDate,Level_Achieved__c,
                          Marks_Obtained__c,Mode_of_Study__c,Name,Name_of_Institute__c,Name_of_Qualification__c,OwnerId,Qualification_Status__c,Quantitative__c,
                          Rank_Achieved__c,SystemModstamp,Total_Max_Marks__c,Total_Score__c,Verbal__c,Which_Year_Did_You_Appear__c,Year_of_Commencement_pq__c,Year_of_Passing_pq__c,
                          Percentage_Actual__c
                          FROM Professional_Qualification__c where Application__c=: qid  limit 1];
        } catch (Exception e) {
            ProfessQuali = new Professional_Qualification__c();
        }*/
         try{
            profQualList=[SELECT Id,Name,Application__c,Name_of_Qualification__c,Name_of_Institute__c,Rank_Achieved__c,Level_Achieved__c,Total_Max_Marks__c,Marks_Obtained__c,Percentage_Actual__c
                          FROM Professional_Qualification__c where Application__c=: qid];
        } catch (Exception e) {
            profQualList = new List<Professional_Qualification__c>();
        }
        /*try{
            WorkExp=[SELECT Application__c,Apply_Under_Restart_Initiative__c,Candidate__c,Career_Break_Details__c,Career_Break_End_Date__c,Career_Break_Start_Date__c,CreatedById,
                     CreatedDate,CurrencyIsoCode,Currency_Currency_you_draw__c,Current_Company__c,Department__c,Describe_Your_Role_Briefly__c,Designation__c,Did_You_Ever_Have_A_Career_Break__c,
                     Do_You_Have_Any_Work_Experience__c,Duration_in_Months_CareerBreak__c,Duration_in_Months_Sabbatical__c,Employment_Type__c,End_Date__c,
                     Experience_In_Current_Organisation_In_Y__c,Functional_Area__c,Function__c,Gross_Annual_CTC__c,Id,Industry__c,IsDeleted,Is_this_your_current_job__c,
                     Job_Profile__c,LastActivityDate,LastModifiedById,LastModifiedDate,Lead1__c,Linkedin_Profile_URL__c,Months_of_work_experience_beyond_above__c,Name,
                     Name_of_Organisation__c,Overall_Experience__c,OwnerId,Personal_Information__c,Reasons_If_Any__c,Reason_for_Career_Break__c,Reason_for_Sabbatical__c,
                     Sabbatical_Details__c,Sabbatical_End_Date__c,Sabbatical_Start_Date__c,Start_Date__c,Student__c,SystemModstamp,Total_Experience_In_Months__c,Total_WE__c,
                     Were_Are_You_On_A_Sabbatical__c,WE_Company_Address__c,WE_Designation__c,WE_From_Date__c,WE_Remuneration__c,WE_Reporting_Head_Designation__c,
                     WE_Reporting_Head__c,WE_To_Date__c,Willing_to_take_Sabbatical_from_current__c,Willing_to_take_Sabbatical__c,Working_with_SPJIMR_Partner_Company__c,
                     Years_of_Work_Experience__c,Responsibilities__c FROM Work_Experience__c where Application__c=: qid  AND Is_this_your_current_job__c ='Current Job' limit 1];
        } catch (Exception e) {
            WorkExp = new Work_Experience__c();
        }*/
        /*try{
            WorkExpPrevioues=[SELECT Application__c,Apply_Under_Restart_Initiative__c,Candidate__c,Career_Break_Details__c,Career_Break_End_Date__c,Career_Break_Start_Date__c,CreatedById,
                     CreatedDate,CurrencyIsoCode,Currency_Currency_you_draw__c,Current_Company__c,Department__c,Describe_Your_Role_Briefly__c,Designation__c,Did_You_Ever_Have_A_Career_Break__c,
                     Do_You_Have_Any_Work_Experience__c,Duration_in_Months_CareerBreak__c,Duration_in_Months_Sabbatical__c,Employment_Type__c,End_Date__c,
                     Experience_In_Current_Organisation_In_Y__c,Functional_Area__c,Function__c,Gross_Annual_CTC__c,Id,Industry__c,IsDeleted,Is_this_your_current_job__c,
                     Job_Profile__c,LastActivityDate,LastModifiedById,LastModifiedDate,Lead1__c,Linkedin_Profile_URL__c,Months_of_work_experience_beyond_above__c,Name,
                     Name_of_Organisation__c,Overall_Experience__c,OwnerId,Personal_Information__c,Reasons_If_Any__c,Reason_for_Career_Break__c,Reason_for_Sabbatical__c,
                     Sabbatical_Details__c,Sabbatical_End_Date__c,Sabbatical_Start_Date__c,Start_Date__c,Student__c,SystemModstamp,Total_Experience_In_Months__c,Total_WE__c,
                     Were_Are_You_On_A_Sabbatical__c,WE_Company_Address__c,WE_Designation__c,WE_From_Date__c,WE_Remuneration__c,WE_Reporting_Head_Designation__c,
                     WE_Reporting_Head__c,WE_To_Date__c,Willing_to_take_Sabbatical_from_current__c,Willing_to_take_Sabbatical__c,Working_with_SPJIMR_Partner_Company__c,
                     Years_of_Work_Experience__c,Responsibilities__c FROM Work_Experience__c where Application__c=: qid  AND Is_this_your_current_job__c ='Previous Job' limit 1];
        } catch (Exception e) {
            WorkExpPrevioues = new Work_Experience__c();
        }*/
        try{
            WorkExpList =[SELECT Id,Name,Application__c,Name_of_Organisation__c,Designation__c,Gross_Annual_CTC__c,Responsibilities__c,Start_Date__c,End_Date__c,Start_Date_Formula__c,
                          End_Date_Formula__c
                         FROM Work_Experience__c where Application__c=: qid];
        } catch (Exception e) {
            WorkExpList  = New List<Work_Experience__c>();
        }
        try{
            CompExamDetailCAT=[SELECT Id,Name,Application__c,Exam_Name__c,CAT_Overall_Percentile__c,CAT_Registration_Number__c,CAT_Year_of_Exam__c,Is_your_primary_email_ID_same_as_CAT_exa__c,CAT_Quantitative_Aptitude__c,
                               Data_interpretation_and_logical_re_score__c,CatVerbalReadingComprehensionScore__c,CAT_E_Mail__c
                              FROM Competitive_Exam_Details__c where Application__c=: qid  AND Exam_Name__c ='CAT' limit 1];
        } catch (Exception e) {
            CompExamDetailCAT = new Competitive_Exam_Details__c();
        }
        try{
            CompExamDetailGMAT=[SELECT Id,Name,Application__c,Exam_Name__c,GMAT_Total_Score__c,GMAT_ID__c,Test_Date__c,Verbal_Score__c,Quantitative_Score__c,Analytical_Writing_Score__c,Integrated_Reasoning_Score__c
                               FROM Competitive_Exam_Details__c where Application__c=: qid  AND Exam_Name__c ='GMAT' limit 1];
        } catch (Exception e) {
            CompExamDetailGMAT = new Competitive_Exam_Details__c();
        }
        try{
            CompExamDetailGMATFocusEdition=[SELECT Id,Name,Application__c,Exam_Name__c,GMAT_FOCUS_ID__c,GMAT_Focus_Edition_Test_Date__c,GMAT_Focus_Edition_Quantitative_Reasonin__c,GMAT_Focus_Edition_Verbal_Reasoning__c,GMAT_Focus_Edition_Data_Insights__c,
                                            GMAT_Focus_Edition_Total_Score__c
                                            FROM Competitive_Exam_Details__c where Application__c=: qid  AND Exam_Name__c ='GMAT Focus' limit 1];
        } catch (Exception e) {
            CompExamDetailGMATFocusEdition = new Competitive_Exam_Details__c();
        }
        try{
            CompExamDetailNMAT=[SELECT Id,Name,Application__c,Exam_Name__c,Total_NMAT_Score_Obtained__c,NMAT_ID__c,NmatMonthAndYearOfExamFormula__c,NMAT_Quantitative_Skills_Score_Obtained__c,NMAT_Logical_Reasoning_Score_Obtained__c,
                                NMAT_Language_Skills_Score_Obtained__c
                                FROM Competitive_Exam_Details__c where Application__c=: qid  AND Exam_Name__c ='NMAT' limit 1];
        } catch (Exception e) {
            CompExamDetailNMAT = new Competitive_Exam_Details__c();
        }
        try{
            CompExamDetailGRE=[SELECT Id,Name,Application__c,Exam_Name__c,GRE_ID__c,GRE_Analytical_Reasoning__c,GRE_Quantitative_Reasoning__c,GRE_Analytical_Writing__c,GRE_Total_Score__c,GreMonthAndYearFormula__c
                               FROM Competitive_Exam_Details__c where Application__c=: qid  AND Exam_Name__c ='GRE' limit 1];
        } catch (Exception e) {
            CompExamDetailGRE = new Competitive_Exam_Details__c();
        }
        try{
            CompExamDetailXAT=[SELECT Id,Name,Application__c,Exam_Name__c,XAT_Total_Percentile__c,XAT_ID__c,XAT_Year_of_Exam__c,XAT_Quantitative_Analytical_Ability__c,XAT_Verbal_Logical_Ability__c,
                               XAT_Decision_Making__c
                               FROM Competitive_Exam_Details__c where Application__c=: qid  AND Exam_Name__c ='XAT' limit 1];
        } catch (Exception e) {
            CompExamDetailXAT = new Competitive_Exam_Details__c();
        }
        try{
            CompExamDetailTOEFL=[SELECT Id,Name,Application__c,Exam_Name__c,TOEFL_ID__c,TOEFL_Year_of_Exam__c,TOEFL_Reading__c,TOEFL_Listening__c,TOEFL_Speaking__c,TOEFL_Writing__c,TOEFL_Total_Score__c
                                FROM Competitive_Exam_Details__c where Application__c=: qid  AND Exam_Name__c ='TOEFL' limit 1];
        } catch (Exception e) {
            CompExamDetailTOEFL = new Competitive_Exam_Details__c();
        }
        try{
            CompExamDetailIELTS=[SELECT Id,Name,Application__c,Exam_Name__c,IELTS_ID__c,IELTS_Year_of_Exam__c,IELTS_Reading__c,IELTS_Listening__c,IELTS_Speaking__c,IELTS_Writing__c,IELTS_Overall_Band_Score__c,IELTS_CEFR_Level__c
                                 FROM Competitive_Exam_Details__c where Application__c=: qid  AND Exam_Name__c ='IELTS' limit 1];
        } catch (Exception e) {
            CompExamDetailIELTS = new Competitive_Exam_Details__c();
        }
        /* Clean commeneted 
        try{
            AAB=[SELECT id,name,Academic_Break__c,Application__c,Do_You_Have_An_Academic_Break__c,Reason_For_Academic_Break__c,Year__c FROM Any_Academic_Break__c where Application__c=: qid  limit 1];
                            
        } catch (Exception e) {
            AAB = new Any_Academic_Break__c();
        }*/
        try{
            BAD=[SELECT id,name,ExpectedGraduationDate__c,GraduationCompleted__c,HasAcademicBreak__c,AcademicBreakYear__c,AcademicBreakReason__c,AnyPostGraduation__c,HasProfessionalQualification__c,
                 ExtraCurricularActivities__c,CertificationDetails__c,Publications__c
                 FROM BasicAcademicDetail__c where Application__c=: qid  limit 1];
                            
        } catch (Exception e) {
            BAD = new BasicAcademicDetail__c();
        }
        /* Clean commeneted 
        try{
            AAchivement=[SELECT Application__c,Award_Position__c,CreatedById,CreatedDate,CurrencyIsoCode,Describe_the_Award_Max_25_words__c,Id,Institute_Granting_the_Award__c,
                 IsDeleted,LastActivityDate,LastModifiedById,LastModifiedDate,Level__c,Name,OwnerId,SystemModstamp,Title_of_the_Award__c,Year__c 
                 FROM Academic_Achievements__c where Application__c=: qid  limit 1];
                            
        } catch (Exception e) {
            AAchivement = new Academic_Achievements__c();
        }*/
        /* Clean commeneted 
        try {
            AAchivementdynamic = [SELECT Application__c,Award_Position__c,CreatedById,CreatedDate,CurrencyIsoCode,Describe_the_Award_Max_25_words__c,Id,Institute_Granting_the_Award__c,
                 IsDeleted,LastActivityDate,LastModifiedById,LastModifiedDate,Level__c,Name,OwnerId,SystemModstamp,Title_of_the_Award__c,Year__c 
                 FROM Academic_Achievements__c where Application__c=: qid ORDER BY CreatedDate ASC ];
        } catch (Exception e) {
            AAchivementdynamic = new List<Academic_Achievements__c>();
        }*/
        
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
        /* Clean commeneted 
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
        }*/
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
        /* Clean commeneted start
        try{
            InformationSource=[SELECT Application__c,CreatedById,CreatedDate,CurrencyIsoCode,Follow_up_Question__c,How_Did_you_get_to_know_about_SPJIMR__c,Id,
                               Interested_in_knowing_other_Programmes__c,IsDeleted,LastActivityDate,LastModifiedById,LastModifiedDate,Lead__c,Name,OwnerId,SystemModstamp,
                               Interested_in_knowing_other_Programmes__r.name
                               FROM Information_Source__c where Application__c=: qid limit 1];
                            
        } catch (Exception e) {
            InformationSource = new Information_Source__c();
        }
        try{
            ResponsibilityShoulderedPersonal =[SELECT Activity_Type__c,Application__c,CreatedById,CreatedDate,CurrencyIsoCode,Describe_Briefly_50_Words__c,Id,
                                               IsDeleted,LastActivityDate,LastModifiedById,LastModifiedDate,LastReferencedDate,LastViewedDate,Level__c,Name,OwnerId,SystemModstamp 
                                               FROM ResponsibilityShouldered__c where Application__c=: qid and Activity_Type__c = 'Personal' limit 1];
                            
        } catch (Exception e) {
            ResponsibilityShoulderedPersonal  = new ResponsibilityShouldered__c();
        }
        try{
            ResponsibilityShoulderedProfesional=[SELECT Activity_Type__c,Application__c,CreatedById,CreatedDate,CurrencyIsoCode,Describe_Briefly_50_Words__c,Id,
                                                 IsDeleted,LastActivityDate,LastModifiedById,LastModifiedDate,LastReferencedDate,LastViewedDate,Level__c,Name,OwnerId,SystemModstamp 
                                                 FROM ResponsibilityShouldered__c where Application__c=: qid and Activity_Type__c = 'Professional' limit 1];
                            
        } catch (Exception e) {
            ResponsibilityShoulderedProfesional = new ResponsibilityShouldered__c();
        }

        try{
            Versatility=[SELECT Application__c,Award__c,CreatedById,CreatedDate,CurrencyIsoCode,Describe_the_AwardMax_25_words__c,Id,Interest__c,IsDeleted,LastActivityDate,
                         LastModifiedById,LastModifiedDate,LastReferencedDate,LastViewedDate,Level__c,Name,Name_of_the_Activity__c,Overall_Versatility_Rating__c,OwnerId,
                         Proficiency__c,SystemModstamp 
                         FROM Versatility__c where Application__c=: qid limit 1];
                            
        } catch (Exception e) {
            Versatility = new Versatility__c();
        } Clean commeneted end */
       /* try{
            AcademicAchievements=[SELECT Application__c,Award_Position__c,CreatedById,CreatedDate,CurrencyIsoCode,Describe_the_Award_Max_25_words__c,Id,
                         Institute_Granting_the_Award__c,IsDeleted,LastActivityDate,LastModifiedById,LastModifiedDate,Level__c,Name,OwnerId,SystemModstamp,
                         Title_of_the_Award__c,Year__c FROM Academic_Achievements__c where Application__c=: qid limit 1];
                            
        } catch (Exception e) {
            AcademicAchievements = new Academic_Achievements__c();
        }*/
        /* Clean commeneted start
        try{
            ProgramDetails=[SELECT Application__c,CreatedById,CreatedDate,CurrencyIsoCode,Id,IsDeleted,Join_PGEMP_Batch__c,LastActivityDate,LastModifiedById,LastModifiedDate,
                            Mention_your_Interest_1__c,Mention_your_Interest_2__c,Name,OwnerId,Partner_School_Program__c,Partner_School_Specilisation__c,Partner_School__c,
                            Please_Note__c,Reasons_I_have_Specialization_1__c,Reasons_I_have_Specialization_2__c,Specialization_1_for__c,Specialization_2_for__c,SystemModstamp,
                            X1st_Programme_Applying_For__c,X2nd_Programme_Applying_For__c,X1st_Programme_Applying_For__r.name,X2nd_Programme_Applying_For__r.name,
                            Specialization_1_for__r.name,Specialization_2_for__r.name
                            FROM Program_Detail__c where Application__c=: qid limit 1];
                            
        } catch (Exception e) {
            ProgramDetails = new Program_Detail__c();
        } Clean commeneted end */
        // Step 1: Passport Size Photo records Start
        passportPhotoUrl = '';

        // Your existing code to populate passportPhotoUrl
        List<Document_Details__c> docListPassportSizePhoto = [SELECT Id, Name  FROM Document_Details__c WHERE Application_No__c = :qid AND Document_Code__c = 'PASSPORT_PHOTO' LIMIT 1];

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
    
    Public Pagereference Cancel(){
        pagereference pg=new pagereference('/'+qid);
        pg.setRedirect(true);
        return pg;        
    }
}