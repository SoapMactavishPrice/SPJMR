public with sharing class GmpHeapDataGenerator implements Queueable {

    private Integer remainingApplications;
    private Integer chunkSize;
    private Integer startIndex;

    private Boolean isCleanup;
    private Datetime cleanupCutoff;

    public GmpHeapDataGenerator(Integer remainingApplications, Integer chunkSize, Integer startIndex) {
        this.remainingApplications = remainingApplications;
        this.chunkSize = chunkSize;
        this.startIndex = startIndex;
    }

    public GmpHeapDataGenerator(Datetime cleanupCutoff, Integer chunkSize) {
        this.cleanupCutoff = cleanupCutoff;
        this.chunkSize = chunkSize;
        this.isCleanup = true;
    }


    public void execute(QueueableContext qc) {

        if (isCleanup) {
            cleanupChunk();
            return;
        }

        Integer currentChunk = Math.min(chunkSize, remainingApplications);

        generate(startIndex, currentChunk);

        remainingApplications -= currentChunk;
        startIndex += currentChunk;

        if (remainingApplications > 0) {
            System.enqueueJob(new GmpHeapDataGenerator(remainingApplications, chunkSize, startIndex));
        }
    }


    private static final List<String> FIRST_NAMES = new List<String>{'Arjun','Meera','Rahul','Devika','Kiran','Ananya','Rohan','Priya','Aman','Neha'};
    private static final List<String> LAST_NAMES = new List<String>{'Nair','Sharma','Iyer','Rao','Patel','Menon','Singh','Das','Khan','Joseph'};
    private static final List<String> CITIES = new List<String>{'Mumbai','Delhi','Bengaluru','Chennai','Hyderabad','Pune','Kochi','Ahmedabad'};
    private static final List<String> INSTITUTIONS = new List<String>{
        'Indian Institute of Technology', 'National Institute of Technology', 'University of Mumbai',
        'Delhi University', 'BITS Pilani', 'XLRI Jamshedpur', 'SP Jain School of Global Management'
    };
    private static final List<String> ADDRESS_PARTS = new List<String>{
        'Prestige Technology Park Phase II', 'Financial District Commercial Tower',
        'Knowledge Park Institutional Zone', 'Metro Business Hub', 'Corporate Avenue Block C'
    };

    public static void generate(Integer startIndex, Integer applicationCount) {
        LookupBag bag = loadLookups();
        List<Application__c> apps = new List<Application__c>();

        for (Integer i = startIndex; i < startIndex + applicationCount; i++) {
            apps.add(buildApplication(i, bag));
        }
        insert apps;

        List<Program_Detail__c> programDetails = new List<Program_Detail__c>();
        List<Personal_Detail__c> personalDetails = new List<Personal_Detail__c>();
        List<BasicAcademicDetail__c> basicAcademicDetails = new List<BasicAcademicDetail__c>();
        List<Academic_Detail__c> academicDetails = new List<Academic_Detail__c>();
        List<Competitive_Exam_Details__c> examDetails = new List<Competitive_Exam_Details__c>();
        List<Work_Experience__c> workExperiences = new List<Work_Experience__c>();
        List<CareerBreak__c> careerBreaks = new List<CareerBreak__c>();
        List<Professional_Qualification__c> qualifications = new List<Professional_Qualification__c>();

        for (Integer i = 0; i < apps.size(); i++) {
            Application__c app = apps[i];
            programDetails.add(buildProgramDetail(app.Id, bag));
            personalDetails.add(buildPersonalDetail(app.Id, bag, i));
            basicAcademicDetails.add(buildBasicAcademic(app.Id));
            buildAcademicDetails(app.Id, academicDetails, i);
            buildExamDetails(app.Id, examDetails, i);
            buildWorkExperiences(app.Id, workExperiences, i);
            buildCareerBreaks(app.Id, careerBreaks, i);
            buildQualifications(app.Id, qualifications, i);
        }

        insert programDetails;
        insert personalDetails;
        insert basicAcademicDetails;
        insert academicDetails;
        insert examDetails;
        insert workExperiences;
        insert careerBreaks;
        insert qualifications;
    }

    private static Application__c buildApplication(Integer i, LookupBag bag) {
        return new Application__c(
            Name = 'GMP-STRESS-' + i,
            Application_Status__c = 'Initiated',
            Application_Stage__c = 'Application Submitted',
            HasExamScores__c = 'Yes',
            PlannedExamDate__c = Date.today().addDays(30 + i),
            PlannedEntranceExams__c = 'GMAT GRE CAT XAT NMAT IELTS TOEFL PTE',
            CompetitiveExams__c = 'GMAT;GRE;CAT;XAT;NMAT',
            Batch__c = bag.batchId,
            Program__c = '11WC1000000HWptMAG',
            RecordTypeId = '012C1000001lQWLIA2'
        );
    }

    private static Program_Detail__c buildProgramDetail(Id appId, LookupBag bag) {
        return new Program_Detail__c(
            Application__c = appId,
            PrimaryPartnerSchoolPreference__c = bag.primarySchoolPrefId,
            SecondaryPartnerSchoolPreference__c = bag.secondarySchoolPrefId,
            PrimaryPartnerProgramPreference__c = bag.primaryProgramPrefId,
            SecondaryPartnerProgramPreference__c = bag.secondaryProgramPrefId,
            PrimaryPartnerSpecializationPreference__c = bag.primarySpecPrefId,
            SecondaryPartnerSpecializationPreference__c = bag.secondarySpecPrefId
        );
    }

    private static String pick(List<String> vals, Integer i) {
        return vals[Math.mod(i, vals.size())];
    }

    private static String longAddress(Integer i) {
        return pick(ADDRESS_PARTS, i) + ', ' + pick(ADDRESS_PARTS, i+1) + ', ' + pick(CITIES, i) + ', India';
    }

    private class LookupBag {
        Id batchId;
        Id countryId;
        Id primarySchoolPrefId;
        Id secondarySchoolPrefId;
        Id primaryProgramPrefId;
        Id secondaryProgramPrefId;
        Id primarySpecPrefId;
        Id secondarySpecPrefId;
    }

    private static LookupBag loadLookups() {
        LookupBag b = new LookupBag();
        b.batchId = fetchOne('ProgramCohort');
        b.countryId = fetchOne('Country_Master__c');
        b.primarySchoolPrefId = fetchOne('BatchPartnerSchool__c');
        b.secondarySchoolPrefId = b.primarySchoolPrefId;
        b.primaryProgramPrefId = fetchOne('BatchPartnerProgram__c');
        b.secondaryProgramPrefId = b.primaryProgramPrefId;
        b.primarySpecPrefId = fetchOne('Specialisation__c');
        b.secondarySpecPrefId = b.primarySpecPrefId;
        return b;
    }

    private static Id fetchOne(String objectName) {
        List<SObject> rows = Database.query('SELECT Id FROM ' + objectName + ' LIMIT 1');
        return rows.isEmpty() ? null : (Id)rows[0].get('Id');
    }

    private static Personal_Detail__c buildPersonalDetail(Id appId, LookupBag bag, Integer i) {
        String first = pick(FIRST_NAMES, i);
        String last = pick(LAST_NAMES, i);
        String city = pick(CITIES, i);
        return new Personal_Detail__c(
            Application__c = appId,
            Title__c = 'Mr',
            First_Name__c = first,
            Middle_Name__c = 'Kumar',
            Last_Name__c = last,
            Gender__c = 'Male',
            Date_of_Birth_As_Per_10th_Marksheet__c = Date.today().addYears(-25).addDays(i),
            Age_as_on_Customisable_Date__c = 27,
            Nationality__c = 'Indian',
            HavePassport__c = 'Yes',
            PassportNumber__c = 'P' + String.valueOf(9000000 + i),
            PassportApplicationNumber__c = 'PA' + String.valueOf(7000000 + i),
            AadhaarCardNumber__c = String.valueOf(900000000000L + i),
            Primary_E_mail__c = 'candidate' + i + '@mail.com',
            Alternate_E_mail__c = 'candidate.alt' + i + '@mail.com',
            LinkedIn_Profile_URL__c = 'https://linkedin.com/in/candidate' + i,
            Mobile_Number__c = '987650' + String.valueOf(1000 + i),
            Alternate_Mobile_Number__c = '987651' + String.valueOf(1000 + i),
            WhatsApp_Mobile_Number__c = '987652' + String.valueOf(1000 + i),
            ParentOrGuardianDetails__c = 'Parents',
            FatherMotherSelection__c = 'Father;Mother',
            FatherTitle__c = 'Mr',
            Father_s_Name__c = 'Rajesh ' + last,
            FatherOccupation__c = 'Business',
            OtherFatherOccupation__c = 'Global supply chain consulting and infrastructure contracting business owner',
            FatherIncome__c = '3–5 Lakhs',
            Father_E_Mail_ID__c = 'father' + i + '@mail.com',
            Parent_s_Mobile_Number__c = '987654' + String.valueOf(1000 + i),
            MotherTitle__c = 'Dr',
            Mother_s_Name__c = 'Sunita ' + last,
            MotherOccupation__c = 'Teacher',
            OtherMotherOccupation__c = 'Senior academic coordinator and curriculum specialist',
            MotherIncome__c = '3–5 Lakhs',
            Mother_E_Mail_ID__c = 'mother' + i + '@mail.com',
            Mother_s_Mobile_Number__c = '987655' + String.valueOf(1000 + i),
            GuardianName__c = 'Guardian ' + first,
            GuardianEmail__c = 'guardian' + i + '@mail.com',
            GuardianMobile__c = '987653' + String.valueOf(1000 + i),
            GuardianRelationship__c = 'Uncle',
            GuardianOccupation__c = 'Consultant',
            OtherGuardianOccupation__c = 'Independent financial transformation advisor',
            Corr_Country__c = bag.countryId,
            Perm_Country__c = bag.countryId,
            Corr_Address1__c = longAddress(i),
            Corr_Address2__c = longAddress(i+1),
            Perm_Address1__c = longAddress(i+2),
            Perm_Address2__c = longAddress(i+3),
            Other_Corr_City__c = city,
            Other_Perm_City__c = city,
            Corr_Pincode__c = '5600' + String.valueOf(100 + Math.mod(i, 899)),
            Perm_Pincode__c = '5600' + String.valueOf(100 + Math.mod(i, 899))
        );
    }

    private static BasicAcademicDetail__c buildBasicAcademic(Id appId) {
        return new BasicAcademicDetail__c(
            Application__c = appId,
            GraduationCompleted__c = 'Yes'
        );
    }

    private static void buildAcademicDetails(Id appId, List<Academic_Detail__c> target, Integer seed) {
        List<String> levels = new List<String>{'10th','12th','Diploma','UG','PG'};
        for (String level : levels) {
            target.add(new Academic_Detail__c(
                Application__c = appId,
                Name = level,
                OtherCollege__c = pick(INSTITUTIONS, seed) + ' ' + level + ' Campus for Management and Applied Studies',
                OtherUniversity__c = pick(INSTITUTIONS, seed) + ' International University of Business and Technology',
                OtherState__c = pick(CITIES, seed),
                Degree__c = 'Other',
                Mode_of_Study__c = 'Full Time',
                Percentage__c = 100,
                Pattern_of_Examination__c = 'Year wise',
                MonthAndYearOfPassing__c = Date.today().addDays(-20)
            ));
        }
    }

    private static void buildExamDetails(Id appId, List<Competitive_Exam_Details__c> target, Integer seed) {
        String center = pick(CITIES, seed) + ' International Testing Center';
        target.add(new Competitive_Exam_Details__c(Application__c=appId, Exam_Name__c='GMAT', GMAT_Total_Score__c=650, GMAT_ID__c='GMAT'+seed, Test_Date__c=Date.today().addDays(-30)));
        target.add(new Competitive_Exam_Details__c(Application__c=appId, Exam_Name__c='GRE', GRE_Total_Score__c=320, GRE_ID__c='GRE'+seed, GreMonthAndYear__c=Date.today().addDays(-20)));
        target.add(new Competitive_Exam_Details__c(Application__c=appId, Exam_Name__c='CAT', CAT_Overall_Percentile__c=95, CAT_Registration_Number__c='CAT'+seed, CAT_Year_of_Exam__c='2025'));
        target.add(new Competitive_Exam_Details__c(Application__c=appId, Exam_Name__c='XAT', XAT_Total_Percentile__c=91, XAT_ID__c='XAT'+seed, XAT_Year_of_Exam__c='2025'));
        target.add(new Competitive_Exam_Details__c(Application__c=appId, Exam_Name__c='NMAT', Total_NMAT_Score_Obtained__c=245, NMAT_ID__c='NMAT'+seed, NmatMonthAndYearOfExam__c=Date.today().addDays(-20)));
        target.add(new Competitive_Exam_Details__c(Application__c=appId, Exam_Name__c='GMAT Focus', GMAT_Focus_Edition_Total_Score__c=695, GMAT_FOCUS_ID__c='GMATF'+seed, GMAT_Focus_Edition_Test_Date__c=Date.today().addDays(-20)));
        target.add(new Competitive_Exam_Details__c(Application__c=appId, Exam_Name__c='IELTS', IELTS_ID__c='IELTS'+seed, IELTS_Year_of_Exam__c='2025'));
        target.add(new Competitive_Exam_Details__c(Application__c=appId, Exam_Name__c='TOEFL', TOEFL_ID__c='TOEFL'+seed, TOEFL_Year_of_Exam__c='2025'));
    }

    private static void buildWorkExperiences(Id appId, List<Work_Experience__c> target, Integer seed) {
        for (Integer i = 0; i < 5; i++) {
            target.add(new Work_Experience__c(
                Application__c = appId,
                //Name = 'Global Enterprise Financial Analytics Consulting Services Role ' + seed + '-' + i,
                Name_of_Organisation__c = 'Global Enterprise Financial Analytics Consulting Services Private Limited',
                Designation__c = 'Senior Associate Strategy Transformation and Commercial Analytics',
                Gross_Annual_CTC__c = 10000000,
                Responsibilities__c = 'Led cross functional analytics transformation initiatives, stakeholder reporting, commercial performance analysis, budgeting governance, operational excellence execution, and executive review preparation across multiple business units.'
            ));
        }
    }

    private static void buildCareerBreaks(Id appId, List<CareerBreak__c> target, Integer seed) {
        for (Integer i = 0; i < 3; i++) {
            target.add(new CareerBreak__c(
                Application__c = appId,
                //Name = 'Career Break ' + seed + '-' + i,
                StartDate__c = Date.today().addMonths(-18),
                EndDate__c = Date.today().addMonths(-6)
            ));
        }
    }

    private static void buildQualifications(Id appId, List<Professional_Qualification__c> target, Integer seed) {
        for (Integer i = 0; i < 3; i++) {
            target.add(new Professional_Qualification__c(
                Application__c = appId,
                //Name = 'Professional Qualification ' + seed + '-' + i,
                Name_of_Qualification__c = 'Advanced Professional Certification in Business Analytics and Strategic Decision Making',
                Name_of_Institute__c = 'International Institute for Executive Professional Education and Leadership'
            ));
        }
    }
    
    private void cleanupChunk() {

        List<Application__c> apps = [
            SELECT Id
            FROM Application__c
            WHERE CreatedDate >= :cleanupCutoff
            AND Name LIKE 'GMP-STRESS-%'
            LIMIT :chunkSize
        ];

        if (apps.isEmpty()) {
            System.debug('Cleanup completed. No more generated records found.');
            return;
        }

        Set<Id> appIds = new Set<Id>();

        for(Application__c app : apps){
            appIds.add(app.Id);
        }

        delete [
            SELECT Id
            FROM Professional_Qualification__c
            WHERE Application__c IN :appIds
        ];

        delete [
            SELECT Id
            FROM CareerBreak__c
            WHERE Application__c IN :appIds
        ];

        delete [
            SELECT Id
            FROM Work_Experience__c
            WHERE Application__c IN :appIds
        ];

        delete [
            SELECT Id
            FROM Competitive_Exam_Details__c
            WHERE Application__c IN :appIds
        ];

        delete [
            SELECT Id
            FROM Academic_Detail__c
            WHERE Application__c IN :appIds
        ];

        delete [
            SELECT Id
            FROM BasicAcademicDetail__c
            WHERE Application__c IN :appIds
        ];

        delete [
            SELECT Id
            FROM Personal_Detail__c
            WHERE Application__c IN :appIds
        ];

        delete [
            SELECT Id
            FROM Program_Detail__c
            WHERE Application__c IN :appIds
        ];

        delete apps;

        System.debug(
            'Deleted cleanup batch: ' + apps.size() + ' applications'
        );

        // Check if more records exist
        Integer remaining = [
            SELECT COUNT()
            FROM Application__c
            WHERE CreatedDate >= :cleanupCutoff
            AND Name LIKE 'GMP-STRESS-%'
        ];

        if(remaining > 0){
            System.enqueueJob(new GmpHeapDataGenerator(cleanupCutoff, chunkSize));
        } else {
            System.debug('All GMP stress records deleted.');
        }
    }   
}