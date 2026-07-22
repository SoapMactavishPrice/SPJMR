public class GenerateOfferLetterController {
    public String OfferDate_Formatted { get; set; }
    public String ApplicationNumber { get; set; }
    public String ApplicantName { get; set; }
    public String ApplicantAddress { get; set; }
    public String SpecialisationName { get; set; }
    public String FeeDate_Formatted { get; set; }
    public String onlineCommenceDate_Formatted { get; set; }
    public String oncampusCommenceDate_Formatted { get; set; }
    public String acceptanceFeeDateFormatted { get; set; }
    public String balanceAmountDateFormatted { get; set; }
    public String onlineFoundationDateFormatted { get; set; }
    public String BatchName { get; set; }
    public String firstName{get;set;}

    public GenerateOfferLetterController() {

        Map<String, String> params = ApexPages.currentPage().getParameters();
        Id admissionId = params.get('admissionId');

        if (admissionId == null) {
            return;
        }

        List<Admission_Decision__c> admList = [
            SELECT Application__r.Applicant__r.Name,
                   Application__r.Application_Number__c,
                   Application__r.Program__c,
                   Application__r.Applicant__c,
                   Offer_Letter_Date__c,
            		Application__c,
                   Specialisation_Master__r.Name,
                   Application__r.Batch__c
            FROM Admission_Decision__c
            WHERE Id = :admissionId
            LIMIT 1
        ];

        if (admList.isEmpty()) {
            return;
        }

        Admission_Decision__c adm = admList[0];

        // ---------- OFFER LETTER DATE ----------
        if (adm.Offer_Letter_Date__c != null) {

            Date offerDate = adm.Offer_Letter_Date__c;

            // Offer Letter Date
            OfferDate_Formatted = DateTime.newInstance(
                offerDate.year(), offerDate.month(), offerDate.day()
            ).format('dd/MM/yyyy');

            // Acceptance Date = +7 days
            Date acceptanceDate = offerDate.addDays(7);
            acceptanceFeeDateFormatted = DateTime.newInstance(
                acceptanceDate.year(), acceptanceDate.month(), acceptanceDate.day()
            ).format('dd/MM/yyyy');

            // Balance Amount Date = +14 days
            Date balanceDate = offerDate.addDays(14);
            balanceAmountDateFormatted = DateTime.newInstance(
                balanceDate.year(), balanceDate.month(), balanceDate.day()
            ).format('dd/MM/yyyy');
        }

        ApplicationNumber = adm.Application__r.Application_Number__c;
        ApplicantName = adm.Application__r.Applicant__r.Name;
		firstName = ApplicantName.split(' ')[0];
        // ---------- ADDRESS ----------
        List<Personal_Detail__c> listPersonalDetails = [SELECT Id, Corr_Address1__c, Corr_Address2__c FROM Personal_Detail__c LIMIT 1];
       /* List<Address_Information_Application__c> listAddress = [
            SELECT Address__c
            FROM Address_Information_Application__c
            WHERE Application__c = :adm.Application__c AND
            Type_of_Address__c='Permanent'
            LIMIT 1
        ];*/

        if (!listPersonalDetails.isEmpty()) {
            ApplicantAddress = listPersonalDetails[0].Corr_Address1__c +' '+ listPersonalDetails[0].Corr_Address2__c;
        }

        // ---------- BATCH ----------
        if (adm.Application__r.Batch__c != null) {

            List<ProgramCohort> listBatch = [
                SELECT Id, Application_Fee__c, Name,
                       Batch_Start_Date__c, Online_Foundation_Start_Date__c,
                       On_Campus_Program_Commence_Date__c
                FROM ProgramCohort
                WHERE Id = :adm.Application__r.Batch__c
                LIMIT 1
            ];

            if (!listBatch.isEmpty()) {

                ProgramCohort batch = listBatch[0];

                BatchName = batch.Name;

                // Specialisation
                List<Specialisation__c> listSpec = [
                    SELECT Specialisation_Name__r.Name
                    FROM Specialisation__c
                    WHERE Batch__c = :batch.Id
                    LIMIT 1
                ];

                if (!listSpec.isEmpty()) {
                    SpecialisationName = listSpec[0].Specialisation_Name__r.Name;
                }

                // Online Foundation Start Date
                if (batch.Online_Foundation_Start_Date__c != null) {
                    Date d = batch.Online_Foundation_Start_Date__c;

                    onlineFoundationDateFormatted = DateTime.newInstance(
                        d.year(), d.month(), d.day()
                    ).format('dd/MM/yyyy');
                }

                // Batch Start Date → online & on-campus commence date
                if (batch.Batch_Start_Date__c != null) {
                    Date s = batch.Batch_Start_Date__c;

                    String startDateFormatted = DateTime.newInstance(
                        s.year(), s.month(), s.day()
                    ).format('dd/MM/yyyy');

                    onlineCommenceDate_Formatted = startDateFormatted;
                    oncampusCommenceDate_Formatted = startDateFormatted;
                }
            }
        }
    }
}