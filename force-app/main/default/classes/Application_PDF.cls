public class Application_PDF {
    public id qid {get;set;}
    public Application__c quo {get;set;}
    public Personal_Detail__c PDInfo{get;set;}
    public Address_Information_Application__c AddinfoPermanent{get;set;}
    public Address_Information_Application__c AddinfoCorrespondence{get;set;}
    public Academic_Detail__c AcaDetailX{get;set;}
    public Academic_Detail__c AcaDetailXII{get;set;}
    public Academic_Detail__c AcaDetailGrad{get;set;}
    public Academic_Detail__c AcaDetailPostGrad{get;set;}
    public Professional_Qualification__c ProfessQuali{get;set;}
    public Work_Experience__c WorkExp{get;set;}
    public Work_Experience__c WorkExpPrevioues{get;set;}
    public Competitive_Exam_Details__c CompExamDetailCAT{get;set;}
    public Competitive_Exam_Details__c CompExamDetailGMAT{get;set;}
    public Competitive_Exam_Details__c CompExamDetailGMATFocusEdition{get;set;}
    public Any_Academic_Break__c AAB{get;set;}
    public Academic_Achievements__c AAchivement{get;set;}
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
    public Information_Source__c InformationSource{get;set;}
    public ResponsibilityShouldered__c ResponsibilityShoulderedPersonal{get;set;}
    public ResponsibilityShouldered__c ResponsibilityShoulderedProfesional{get;set;}
    public Versatility__c Versatility{get;set;}
    public Program_Detail__c ProgramDetails{get;set;}
    // public QuoteLineItem quoitem {get;set;}
    public List<OrderItem> ActualQuoteLine{get;set;}
    public List<QuoteLineItem> qlList{get;set;}
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
    
    public Application_PDF(){
        
        qid = ApexPages.currentPage().getparameters().get('id');
        system.debug('qid'+qid);
        qlList = new List<QuoteLineItem>();
        // listwrap  = new List<wrapclass>();
        
        system.debug('Stage 1');
        
        quo=[SELECT AllowSelfSchedule__c,Applicant_Name__c,Applicant__c,Application_Number__c,Application_Stage__c,Application_Status__c,Checklist_Name__c,City__c,
             CreatedById,CreatedDate,CurrencyIsoCode,Date__c,Declaration_Text__c,Email__c,First_Name__c,Follow_up_Question__c,Id,IsDeleted,LastModifiedById,LastModifiedDate,
             LastReferencedDate,LastViewedDate,Last_Name__c,Name,Offer_Letter_Date__c,OwnerId,Phone__c,Program__c,Response_Values__c,script__c,SystemModstamp,
             Program__r.name
             FROM Application__c Where id=: qid];
        try{
            PDInfo=[SELECT AadhaarCardNumber__c,Alternate_E_mail__c,Application__c,Are_you_employed_with_one_of_SPJIMR_s_Pa__c,Blood_Group__c,Campus_Applied_For__c,Category__c,
                    CreatedById,CreatedDate,CurrencyIsoCode,Date_of_Birth_As_Per_10th_Marksheet__c,HaveAadhaar__c,HavePassport__c,Employer_Partner_Company__c,
                    Father_s_Name__c,First_Name__c,Gender__c,Id,Indian_Origin_Card_IOC__c,IsDeleted,LastModifiedById,LastModifiedDate,Last_Name__c,LinkedIn_Profile_URL__c,Marital_Status__c,
                    Middle_Name__c,Mobile_Number__c,Mother_s_Name__c,Name,Nationality__c,OwnerId,Parent_s_Mobile_Number__c,Passport_Issuing_Country__c,PassportNumber__c,
                    Passport_Valid_Till__c,Primary_E_mail__c,SystemModstamp,Title__c,Name_Of_Spouse__c,Contact_No_of_Spouse__c,Alternate_Mobile_Number__c 
                    FROM Personal_Detail__c where Application__c=: qid limit 1];
        } catch (Exception e) {
            PDInfo = new Personal_Detail__c();
        }
        try{
            AddinfoPermanent=[SELECT Address__c,Application__c,City_Correspondence__c,Country__c,CreatedById,CreatedDate,CurrencyIsoCode,District_Correspondence__c,Id,IsDeleted,
                              Is_permanent_address_same_as_address_for__c,LastActivityDate,LastModifiedById,LastModifiedDate,Name,OwnerId,Pincode__c,State__c,SystemModstamp,
                              Total_Work_Experience_in_Months__c,Type_of_Address__c 
                              FROM Address_Information_Application__c where Application__c=: qid and Type_of_Address__c='Permanent'limit 1];
        } catch (Exception e) {
            AddinfoPermanent = new Address_Information_Application__c();
        }
        try{
            AddinfoCorrespondence=[SELECT Address__c,Application__c,City_Correspondence__c,Country__c,CreatedById,CreatedDate,CurrencyIsoCode,District_Correspondence__c,Id,IsDeleted,
                                   Is_permanent_address_same_as_address_for__c,LastActivityDate,LastModifiedById,LastModifiedDate,Name,OwnerId,Pincode__c,State__c,SystemModstamp,
                                   Total_Work_Experience_in_Months__c,Type_of_Address__c 
                                   FROM Address_Information_Application__c where Application__c=: qid and Type_of_Address__c='Correspondence' limit 1];
        } catch (Exception e) {
            AddinfoCorrespondence = new Address_Information_Application__c();
        }
        try{
            AcaDetailX=[SELECT Application__c,Board_University__c,/*Conversion_Factor__c,*/CreatedById,CreatedDate,CurrencyIsoCode,Degree_Type__c,Degree__c,
                        Diploma_Name__c,Do_you_have_Academic_Break__c,Do_you_have_Professional_Qualification__c,Examination_ID__c,Id,IsDeleted,LastActivityDate,
                        LastModifiedById,LastModifiedDate,Marking_Scheme__c,Master_Degree_Percentage__c,Maximum_CGPA__c,Maximum_Marks__c,Mode_of_Study__c,MonthOfPassing__c,
                        Month_of_Commencement__c,Name,Obtained_CGPA__c,Obtained_Marks__c,OwnerId,Pattern_of_Examination__c,Qualifications__c,
                        Reason_for_Academic_Break__c,DegreeStatus__c,School_Institute__c,Specilization__c,/*State__c,*/Student_Name__c,SystemModstamp,YearOfPassing__c,
                        Year_of_Commencement__c FROM Academic_Detail__c where Application__c=: qid  and Qualifications__c = '10th' limit 1];
        } catch (Exception e) {
            AcaDetailX = new Academic_Detail__c();
        }
        try{
            AcaDetailXII=[SELECT Application__c,Board_University__c,/*Conversion_Factor__c,*/CreatedById,CreatedDate,CurrencyIsoCode,Degree_Type__c,Degree__c,
                          Diploma_Name__c,Do_you_have_Academic_Break__c,Do_you_have_Professional_Qualification__c,Examination_ID__c,Id,IsDeleted,LastActivityDate,
                          LastModifiedById,LastModifiedDate,Marking_Scheme__c,Master_Degree_Percentage__c,Maximum_CGPA__c,Maximum_Marks__c,Mode_of_Study__c,MonthOfPassing__c,
                          Month_of_Commencement__c,Name,Obtained_CGPA__c,Obtained_Marks__c,OwnerId,Pattern_of_Examination__c,Qualifications__c,
                          Reason_for_Academic_Break__c,DegreeStatus__c,School_Institute__c,Specilization__c,/*State__c,*/Student_Name__c,SystemModstamp,YearOfPassing__c,
                          Year_of_Commencement__c FROM Academic_Detail__c where Application__c=: qid  and Qualifications__c = '12th' limit 1];
        } catch (Exception e) {
            AcaDetailXII = new Academic_Detail__c();
        }
        try{
            AcaDetailGrad=[SELECT Application__c,Board_University__c,/*Conversion_Factor__c,*/CreatedById,CreatedDate,CurrencyIsoCode,Degree_Type__c,Degree__c,
                           Diploma_Name__c,Do_you_have_Academic_Break__c,Do_you_have_Professional_Qualification__c,Examination_ID__c,Id,IsDeleted,LastActivityDate,
                           LastModifiedById,LastModifiedDate,Marking_Scheme__c,Master_Degree_Percentage__c,Maximum_CGPA__c,Maximum_Marks__c,Mode_of_Study__c,MonthOfPassing__c,
                           Month_of_Commencement__c,Name,Obtained_CGPA__c,Obtained_Marks__c,OwnerId,Pattern_of_Examination__c,Qualifications__c,
                           Reason_for_Academic_Break__c,DegreeStatus__c,School_Institute__c,Specilization__c,/*State__c,*/Student_Name__c,SystemModstamp,YearOfPassing__c,
                           Year_of_Commencement__c,Specilization__r.name FROM Academic_Detail__c where Application__c=: qid  and Qualifications__c = 'Graduation' limit 1]; 
        } catch (Exception e) {
            AcaDetailGrad = new Academic_Detail__c();
        }
        try{
            AcaDetailPostGrad=[SELECT Application__c,Board_University__c,/*Conversion_Factor__c,*/CreatedById,CreatedDate,CurrencyIsoCode,Degree_Type__c,Degree__c,
                               Diploma_Name__c,Do_you_have_Academic_Break__c,Do_you_have_Professional_Qualification__c,Examination_ID__c,Id,IsDeleted,LastActivityDate,
                               LastModifiedById,LastModifiedDate,Marking_Scheme__c,Master_Degree_Percentage__c,Maximum_CGPA__c,Maximum_Marks__c,Mode_of_Study__c,MonthOfPassing__c,
                               Month_of_Commencement__c,Name,Obtained_CGPA__c,Obtained_Marks__c,OwnerId,Pattern_of_Examination__c,Qualifications__c,
                               Reason_for_Academic_Break__c,DegreeStatus__c,School_Institute__c,Specilization__c,/*State__c,*/Student_Name__c,SystemModstamp,YearOfPassing__c,
                               Year_of_Commencement__c,Specilization__r.name,Stream__c FROM Academic_Detail__c where Application__c=: qid  and Qualifications__c = 'Post Graduation' limit 1];
        } catch (Exception e) {
            AcaDetailPostGrad = new Academic_Detail__c();
        }
        try{
            ProfessQuali=[SELECT Academic_Professional_Achievements__c,Application__c,CreatedById,CreatedDate,CurrencyIsoCode,Extra_Curricular_Activities_If_Any__c,
                          Have_you_appeared_for_the_Executive_Asse__c,Id,Integrated_Reasoning__c,IsDeleted,LastActivityDate,LastModifiedById,LastModifiedDate,Level_Achieved__c,
                          Marks_Obtained__c,Mode_of_Study__c,Name,Name_of_Institute__c,Name_of_Qualification__c,OwnerId,Percentage__c,Qualification_Status__c,Quantitative__c,
                          Rank_Achieved__c,SystemModstamp,Total_Max_Marks__c,Total_Score__c,Verbal__c,Which_Year_Did_You_Appear__c,Year_of_Commencement_pq__c,Year_of_Passing_pq__c 
                          FROM Professional_Qualification__c where Application__c=: qid  limit 1];
        } catch (Exception e) {
            ProfessQuali = new Professional_Qualification__c();
        }
        try{
            WorkExp=[SELECT Application__c,Apply_Under_Restart_Initiative__c,Candidate__c,Career_Break_Details__c,Career_Break_End_Date__c,Career_Break_Start_Date__c,CreatedById,
                     CreatedDate,CurrencyIsoCode,Currency_Currency_you_draw__c,Current_Company__c,Department__c,Describe_Your_Role_Briefly__c,Designation__c,Did_You_Ever_Have_A_Career_Break__c,
                     Do_You_Have_Any_Work_Experience__c,Duration_in_Months_CareerBreak__c,Duration_in_Months_Sabbatical__c,Employment_Type__c,End_Date__c,
                     Experience_In_Current_Organisation_In_Y__c,Functional_Area__c,Function__c,Gross_Annual_CTC__c,Id,Industry__c,IsDeleted,/*Is_this_your_current_job__c,*/
                     Job_Profile__c,LastActivityDate,LastModifiedById,LastModifiedDate,Lead1__c,Linkedin_Profile_URL__c,Months_of_work_experience_beyond_above__c,Name,
                     Name_of_Organisation__c,Overall_Experience__c,OwnerId,Personal_Information__c,Reasons_If_Any__c,Reason_for_Career_Break__c,Reason_for_Sabbatical__c,
                     Sabbatical_Details__c,Sabbatical_End_Date__c,Sabbatical_Start_Date__c,Start_Date__c,Student__c,SystemModstamp,Total_Experience_In_Months__c,Total_WE__c,
                     Were_Are_You_On_A_Sabbatical__c,WE_Company_Address__c,WE_Designation__c,WE_From_Date__c,WE_Remuneration__c,WE_Reporting_Head_Designation__c,
                     WE_Reporting_Head__c,WE_To_Date__c,Willing_to_take_Sabbatical_from_current__c,Willing_to_take_Sabbatical__c,Working_with_SPJIMR_Partner_Company__c,
                     Years_of_Work_Experience__c FROM Work_Experience__c where Application__c=: qid  /*AND Is_this_your_current_job__c ='Current Job'*/ limit 1];
        } catch (Exception e) {
            WorkExp = new Work_Experience__c();
        }
        try{
            WorkExpPrevioues=[SELECT Application__c,Apply_Under_Restart_Initiative__c,Candidate__c,Career_Break_Details__c,Career_Break_End_Date__c,Career_Break_Start_Date__c,CreatedById,
                     CreatedDate,CurrencyIsoCode,Currency_Currency_you_draw__c,Current_Company__c,Department__c,Describe_Your_Role_Briefly__c,Designation__c,Did_You_Ever_Have_A_Career_Break__c,
                     Do_You_Have_Any_Work_Experience__c,Duration_in_Months_CareerBreak__c,Duration_in_Months_Sabbatical__c,Employment_Type__c,End_Date__c,
                     Experience_In_Current_Organisation_In_Y__c,Functional_Area__c,Function__c,Gross_Annual_CTC__c,Id,Industry__c,IsDeleted,/*Is_this_your_current_job__c,?*/
                     Job_Profile__c,LastActivityDate,LastModifiedById,LastModifiedDate,Lead1__c,Linkedin_Profile_URL__c,Months_of_work_experience_beyond_above__c,Name,
                     Name_of_Organisation__c,Overall_Experience__c,OwnerId,Personal_Information__c,Reasons_If_Any__c,Reason_for_Career_Break__c,Reason_for_Sabbatical__c,
                     Sabbatical_Details__c,Sabbatical_End_Date__c,Sabbatical_Start_Date__c,Start_Date__c,Student__c,SystemModstamp,Total_Experience_In_Months__c,Total_WE__c,
                     Were_Are_You_On_A_Sabbatical__c,WE_Company_Address__c,WE_Designation__c,WE_From_Date__c,WE_Remuneration__c,WE_Reporting_Head_Designation__c,
                     WE_Reporting_Head__c,WE_To_Date__c,Willing_to_take_Sabbatical_from_current__c,Willing_to_take_Sabbatical__c,Working_with_SPJIMR_Partner_Company__c,
                     Years_of_Work_Experience__c FROM Work_Experience__c where Application__c=: qid  /*AND Is_this_your_current_job__c ='Previous Job'*/ limit 1];
        } catch (Exception e) {
            WorkExpPrevioues = new Work_Experience__c();
        }
        try{
            CompExamDetailCAT=[SELECT Analytical_Writing_Percentile__c,Analytical_Writing_Score__c,Appeared_in_assessments_by__c,Application__c,Appointment_Number__c,
                            CAT_Overall_Percentile__c,CAT_Registration_Number__c,CAT_Year_of_Passing__c,CreatedById,CreatedDate,CurrencyIsoCode,
                            Data_interpretation_and_logical_re_perce__c,Data_interpretation_and_logical_re_score__c,Data_Type__c,Exam_Name__c,GMAT_ID__c,
                            GMAT_Result_Status__c,GMAT_Score_Issue_Date__c,Id,Integrated_Reasoning_Percentile__c,Integrated_Reasoning_Score__c,IsDeleted,LastActivityDate,
                            LastModifiedById,LastModifiedDate,Max_Possible_Out_Of__c,Name,Name_of_Test__c,Obtained_Score_Percentile__c,OwnerId,Percentile_Score__c,
                            Quantitative_ability_percentile__c,Quantitative_ability_score__c,Quantitative_Percentile__c,Quantitative_Score__c,SystemModstamp,Test_Date__c,
                            Verbal_ability_and_reading_comp_percenti__c,Verbal_ability_and_reading_comp_Scroe__c,Verbal_Percentile__c,Verbal_Score__c,Year_of_Passing__c,
                            CAT_Result_Status__c,Is_your_primary_email_ID_same_as_CAT_exa__c,CAT_Overall_Score__c,CAT_Score_Card__c
                            FROM Competitive_Exam_Details__c where Application__c=: qid  AND Exam_Name__c ='CAT' limit 1];
        } catch (Exception e) {
            CompExamDetailCAT = new Competitive_Exam_Details__c();
        }
        try{
            CompExamDetailGMAT=[SELECT Analytical_Writing_Percentile__c,Analytical_Writing_Score__c,Appeared_in_assessments_by__c,Application__c,Appointment_Number__c,
                            CAT_Overall_Percentile__c,CAT_Registration_Number__c,CAT_Year_of_Passing__c,CreatedById,CreatedDate,CurrencyIsoCode,
                            Data_interpretation_and_logical_re_perce__c,Data_interpretation_and_logical_re_score__c,Data_Type__c,Exam_Name__c,GMAT_ID__c,
                            GMAT_Result_Status__c,GMAT_Score_Issue_Date__c,Id,Integrated_Reasoning_Percentile__c,Integrated_Reasoning_Score__c,IsDeleted,LastActivityDate,
                            LastModifiedById,LastModifiedDate,Max_Possible_Out_Of__c,Name,Name_of_Test__c,Obtained_Score_Percentile__c,OwnerId,Percentile_Score__c,
                            Quantitative_ability_percentile__c,Quantitative_ability_score__c,Quantitative_Percentile__c,Quantitative_Score__c,SystemModstamp,Test_Date__c,
                            Verbal_ability_and_reading_comp_percenti__c,Verbal_ability_and_reading_comp_Scroe__c,Verbal_Percentile__c,Verbal_Score__c,Year_of_Passing__c,
                            CAT_Result_Status__c,GMAT_Overall_Score__c,GMAT_Overall_Percentile__c,GMAT_Score_Card__c
                            FROM Competitive_Exam_Details__c where Application__c=: qid  AND Exam_Name__c ='GMAT' limit 1];
        } catch (Exception e) {
            CompExamDetailGMAT = new Competitive_Exam_Details__c();
        }
        try{
            CompExamDetailGMATFocusEdition=[SELECT Analytical_Writing_Percentile__c,Analytical_Writing_Score__c,Appeared_in_assessments_by__c,Application__c,Appointment_Number__c,
                                            CAT_2020_2021_2022_Score_Card__c,CAT_Overall_Percentile__c,CAT_Registration_Number__c,CAT_Year_of_Passing__c,CreatedById,CreatedDate,
                                            CurrencyIsoCode,Data_interpretation_and_logical_re_perce__c,Data_interpretation_and_logical_re_score__c,Data_Type__c,DI_Percentile__c,
                                            DI_Score__c,Exam_Name__c,GMAT_Admit_Card__c,GMAT_Focus_Edition_Score_Card__c,GMAT_Focus_Edition_Test_Date__c,
                                            GMAT_Focus_Edition_Total_Percentile__c,GMAT_Focus_Edition_Total_Score__c,GMAT_FOCUS_ID_Appointment_Number__c,
                                            GMAT_FOCUS_ID__c,GMAT_ID__c,GMAT_Result_Status__c,GMAT_Score_Card__c,GMAT_Score_Issue_Date__c,GMAT_Total_Percentile__c,
                                            GMAT_Total_Score__c,Id,Integrated_Reasoning_Percentile__c,Integrated_Reasoning_Score__c,IsDeleted,LastActivityDate,LastModifiedById,
                                            LastModifiedDate,Max_Possible_Out_Of__c,Name,Name_of_Test__c,Obtained_Score_Percentile__c,OwnerId,Percentile_Score__c,
                                            QA_Percentile__c,QA_Score__c,Quantitative_ability_percentile__c,Quantitative_ability_score__c,Quantitative_Percentile__c,
                                            Quantitative_Score__c,Result_Status__c,SystemModstamp,Test_Date__c,VA_Percentile__c,VA_Score__c,Verbal_ability_and_reading_comp_percenti__c,
                                            Verbal_ability_and_reading_comp_Scroe__c,Verbal_Percentile__c,Verbal_Score__c,Year_of_Passing__c,GMAT_Focus_Edition_Result_Status__c,
                                            Overall_Score__c,Overall_Percentile__c
                                            FROM Competitive_Exam_Details__c where Application__c=: qid  AND Exam_Name__c ='GMAT Focus Edition' limit 1];
        } catch (Exception e) {
            CompExamDetailGMATFocusEdition = new Competitive_Exam_Details__c();
        }
        try{
            AAB=[SELECT id,name,Academic_Break__c,Application__c,Do_You_Have_An_Academic_Break__c,Reason_For_Academic_Break__c FROM Any_Academic_Break__c where Application__c=: qid  limit 1];
                            
        } catch (Exception e) {
            AAB = new Any_Academic_Break__c();
        }
        try{
            AAchivement=[SELECT Application__c,Award_Position__c,CreatedById,CreatedDate,CurrencyIsoCode,Describe_the_Award_Max_25_words__c,Id,Institute_Granting_the_Award__c,
                 IsDeleted,LastActivityDate,LastModifiedById,LastModifiedDate,Level__c,Name,OwnerId,SystemModstamp,Title_of_the_Award__c,Year__c 
                 FROM Academic_Achievements__c where Application__c=: qid  limit 1];
                            
        } catch (Exception e) {
            AAchivement = new Academic_Achievements__c();
        }
        try{
            GraduationDSW1=[SELECT Academic_Detail__c,Application__c,CreatedById,CreatedDate,CurrencyIsoCode,Id,IsDeleted,LastActivityDate,LastModifiedById,LastModifiedDate,
                           Maximum_Marks_SGPA__c,Name,Obtained_Marks_SGPA__c,Qualifications__c,SystemModstamp,Year_Semester_Name__c 
                           FROM Graduation_Details_Semester_wise__c where Application__c=: qid  and Year_Semester_Name__c = 'Semester 1' limit 1];
                            
        } catch (Exception e) {
            GraduationDSW1 = new Graduation_Details_Semester_wise__c();
        }
        try{
            GraduationDSW2=[SELECT Academic_Detail__c,Application__c,CreatedById,CreatedDate,CurrencyIsoCode,Id,IsDeleted,LastActivityDate,LastModifiedById,LastModifiedDate,
                           Maximum_Marks_SGPA__c,Name,Obtained_Marks_SGPA__c,Qualifications__c,SystemModstamp,Year_Semester_Name__c 
                           FROM Graduation_Details_Semester_wise__c where Application__c=: qid  and Year_Semester_Name__c = 'Semester 2' limit 1];
                            
        } catch (Exception e) {
            GraduationDSW2 = new Graduation_Details_Semester_wise__c();
        }
        try{
            GraduationDSW3=[SELECT Academic_Detail__c,Application__c,CreatedById,CreatedDate,CurrencyIsoCode,Id,IsDeleted,LastActivityDate,LastModifiedById,LastModifiedDate,
                           Maximum_Marks_SGPA__c,Name,Obtained_Marks_SGPA__c,Qualifications__c,SystemModstamp,Year_Semester_Name__c 
                           FROM Graduation_Details_Semester_wise__c where Application__c=: qid  and Year_Semester_Name__c = 'Semester 3' limit 1];
                            
        } catch (Exception e) {
            GraduationDSW3 = new Graduation_Details_Semester_wise__c();
        }
        try{
            GraduationDSW4=[SELECT Academic_Detail__c,Application__c,CreatedById,CreatedDate,CurrencyIsoCode,Id,IsDeleted,LastActivityDate,LastModifiedById,LastModifiedDate,
                           Maximum_Marks_SGPA__c,Name,Obtained_Marks_SGPA__c,Qualifications__c,SystemModstamp,Year_Semester_Name__c 
                           FROM Graduation_Details_Semester_wise__c where Application__c=: qid  and Year_Semester_Name__c = 'Semester 4' limit 1];
                            
        } catch (Exception e) {
            GraduationDSW4 = new Graduation_Details_Semester_wise__c();
        }
        try{
            GraduationDSW5=[SELECT Academic_Detail__c,Application__c,CreatedById,CreatedDate,CurrencyIsoCode,Id,IsDeleted,LastActivityDate,LastModifiedById,LastModifiedDate,
                           Maximum_Marks_SGPA__c,Name,Obtained_Marks_SGPA__c,Qualifications__c,SystemModstamp,Year_Semester_Name__c 
                           FROM Graduation_Details_Semester_wise__c where Application__c=: qid  and Year_Semester_Name__c = 'Semester 5' limit 1];
                            
        } catch (Exception e) {
            GraduationDSW5 = new Graduation_Details_Semester_wise__c();
        }
        try{
            GraduationDSW6=[SELECT Academic_Detail__c,Application__c,CreatedById,CreatedDate,CurrencyIsoCode,Id,IsDeleted,LastActivityDate,LastModifiedById,LastModifiedDate,
                           Maximum_Marks_SGPA__c,Name,Obtained_Marks_SGPA__c,Qualifications__c,SystemModstamp,Year_Semester_Name__c 
                           FROM Graduation_Details_Semester_wise__c where Application__c=: qid  and Year_Semester_Name__c = 'Semester 6' limit 1];
                            
        } catch (Exception e) {
            GraduationDSW6 = new Graduation_Details_Semester_wise__c();
        }
        try{
            GraduationDSW7=[SELECT Academic_Detail__c,Application__c,CreatedById,CreatedDate,CurrencyIsoCode,Id,IsDeleted,LastActivityDate,LastModifiedById,LastModifiedDate,
                           Maximum_Marks_SGPA__c,Name,Obtained_Marks_SGPA__c,Qualifications__c,SystemModstamp,Year_Semester_Name__c 
                           FROM Graduation_Details_Semester_wise__c where Application__c=: qid and Year_Semester_Name__c = 'Semester 7' limit 1];
                            
        } catch (Exception e) {
            GraduationDSW7 = new Graduation_Details_Semester_wise__c();
        }
        try{
            GraduationDSW8=[SELECT Academic_Detail__c,Application__c,CreatedById,CreatedDate,CurrencyIsoCode,Id,IsDeleted,LastActivityDate,LastModifiedById,LastModifiedDate,
                           Maximum_Marks_SGPA__c,Name,Obtained_Marks_SGPA__c,Qualifications__c,SystemModstamp,Year_Semester_Name__c 
                           FROM Graduation_Details_Semester_wise__c where Application__c=: qid and Year_Semester_Name__c = 'Semester 8' limit 1];
                            
        } catch (Exception e) {
            GraduationDSW8 = new Graduation_Details_Semester_wise__c();
        }
        try{
            GraduationDSW9=[SELECT Academic_Detail__c,Application__c,CreatedById,CreatedDate,CurrencyIsoCode,Id,IsDeleted,LastActivityDate,LastModifiedById,LastModifiedDate,
                           Maximum_Marks_SGPA__c,Name,Obtained_Marks_SGPA__c,Qualifications__c,SystemModstamp,Year_Semester_Name__c 
                           FROM Graduation_Details_Semester_wise__c where Application__c=: qid and Year_Semester_Name__c = 'Semester 9' limit 1];
                            
        } catch (Exception e) {
            GraduationDSW9 = new Graduation_Details_Semester_wise__c();
        }
        try{
            GraduationDSW10=[SELECT Academic_Detail__c,Application__c,CreatedById,CreatedDate,CurrencyIsoCode,Id,IsDeleted,LastActivityDate,LastModifiedById,LastModifiedDate,
                           Maximum_Marks_SGPA__c,Name,Obtained_Marks_SGPA__c,Qualifications__c,SystemModstamp,Year_Semester_Name__c 
                           FROM Graduation_Details_Semester_wise__c where Application__c=: qid and Year_Semester_Name__c = 'Semester 10' limit 1];
                            
        } catch (Exception e) {
            GraduationDSW10 = new Graduation_Details_Semester_wise__c();
        }
         try{
            GraduationDSWYear1=[SELECT Academic_Detail__c,Application__c,CreatedById,CreatedDate,CurrencyIsoCode,Id,IsDeleted,LastActivityDate,LastModifiedById,LastModifiedDate,
                           Maximum_Marks_SGPA__c,Name,Obtained_Marks_SGPA__c,Qualifications__c,SystemModstamp,Year_Semester_Name__c 
                           FROM Graduation_Details_Semester_wise__c where Application__c=: qid and Year_Semester_Name__c = 'Year 1' limit 1];
                            
        } catch (Exception e) {
            GraduationDSWYear1 = new Graduation_Details_Semester_wise__c();
        }
         try{
            GraduationDSWYear2=[SELECT Academic_Detail__c,Application__c,CreatedById,CreatedDate,CurrencyIsoCode,Id,IsDeleted,LastActivityDate,LastModifiedById,LastModifiedDate,
                           Maximum_Marks_SGPA__c,Name,Obtained_Marks_SGPA__c,Qualifications__c,SystemModstamp,Year_Semester_Name__c 
                           FROM Graduation_Details_Semester_wise__c where Application__c=: qid and Year_Semester_Name__c = 'Year 2' limit 1];
                            
        } catch (Exception e) {
            GraduationDSWYear2 = new Graduation_Details_Semester_wise__c();
        }
         try{
            GraduationDSWYear3=[SELECT Academic_Detail__c,Application__c,CreatedById,CreatedDate,CurrencyIsoCode,Id,IsDeleted,LastActivityDate,LastModifiedById,LastModifiedDate,
                           Maximum_Marks_SGPA__c,Name,Obtained_Marks_SGPA__c,Qualifications__c,SystemModstamp,Year_Semester_Name__c 
                           FROM Graduation_Details_Semester_wise__c where Application__c=: qid and Year_Semester_Name__c = 'Year 3' limit 1];
                            
        } catch (Exception e) {
            GraduationDSWYear3 = new Graduation_Details_Semester_wise__c();
        }
         try{
            GraduationDSWYear4=[SELECT Academic_Detail__c,Application__c,CreatedById,CreatedDate,CurrencyIsoCode,Id,IsDeleted,LastActivityDate,LastModifiedById,LastModifiedDate,
                           Maximum_Marks_SGPA__c,Name,Obtained_Marks_SGPA__c,Qualifications__c,SystemModstamp,Year_Semester_Name__c 
                           FROM Graduation_Details_Semester_wise__c where Application__c=: qid and Year_Semester_Name__c = 'Year 4' limit 1];
                            
        } catch (Exception e) {
            GraduationDSWYear4 = new Graduation_Details_Semester_wise__c();
        }
         try{
            GraduationDSWYear5=[SELECT Academic_Detail__c,Application__c,CreatedById,CreatedDate,CurrencyIsoCode,Id,IsDeleted,LastActivityDate,LastModifiedById,LastModifiedDate,
                           Maximum_Marks_SGPA__c,Name,Obtained_Marks_SGPA__c,Qualifications__c,SystemModstamp,Year_Semester_Name__c 
                           FROM Graduation_Details_Semester_wise__c where Application__c=: qid and Year_Semester_Name__c = 'Year 5' limit 1];
                            
        } catch (Exception e) {
            GraduationDSWYear5 = new Graduation_Details_Semester_wise__c();
        }
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
        }
       /* try{
            AcademicAchievements=[SELECT Application__c,Award_Position__c,CreatedById,CreatedDate,CurrencyIsoCode,Describe_the_Award_Max_25_words__c,Id,
                         Institute_Granting_the_Award__c,IsDeleted,LastActivityDate,LastModifiedById,LastModifiedDate,Level__c,Name,OwnerId,SystemModstamp,
                         Title_of_the_Award__c,Year__c FROM Academic_Achievements__c where Application__c=: qid limit 1];
                            
        } catch (Exception e) {
            AcademicAchievements = new Academic_Achievements__c();
        }*/
        try{
            ProgramDetails=[SELECT Application__c,CreatedById,CreatedDate,CurrencyIsoCode,Id,IsDeleted,Join_PGEMP_Batch__c,LastActivityDate,LastModifiedById,LastModifiedDate,
                            Name,OwnerId,Partner_School_Program__c,Partner_School_Specilisation__c,Partner_School__c,
                            Please_Note__c,Reasons_I_have_Specialization_1__c,Reasons_I_have_Specialization_2__c,Specialization_1_for__c,Specialization_2_for__c,SystemModstamp,
                            X1st_Programme_Applying_For__c,X2nd_Programme_Applying_For__c,X1st_Programme_Applying_For__r.name,X2nd_Programme_Applying_For__r.name,
                            Specialization_1_for__r.name,Specialization_2_for__r.name
                            FROM Program_Detail__c where Application__c=: qid limit 1];
                            
        } catch (Exception e) {
            ProgramDetails = new Program_Detail__c();
        }
    }   
    
    Public Pagereference Cancel(){
        pagereference pg=new pagereference('/'+qid);
        pg.setRedirect(true);
        return pg;        
    }
}