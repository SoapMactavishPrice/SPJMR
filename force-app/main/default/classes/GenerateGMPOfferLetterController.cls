public with sharing class GenerateGMPOfferLetterController {

    /* =========================
       Applicant Details
       ========================= */
    public String ApplicantName { get; set; }

    /* =========================
       Programme Dates
       ========================= */
    public String ProgrammeStartDate { get; set; }
    public String CampusReportingDate { get; set; }

    /* =========================
       Fee Payment Dates
       ========================= */
    public String PrepTermPaymentDate { get; set; }
    public String TuitionPaymentDate { get; set; }

    /* =========================
       Constructor
       ========================= */
    public GenerateGMPOfferLetterController() {

        // --- Applicant ---
       Map<String, String> params = ApexPages.currentPage().getParameters();
        Id admissionId = params.get('admissionId');

        if (admissionId == null) {
            return;
        }

        Admission_Decision__c adm = [
            SELECT Application__r.Applicant__r.Name
            FROM Admission_Decision__c
            WHERE Id = :admissionId
            LIMIT 1
        ];

        ApplicantName = adm.Application__r.Applicant__r.Name;
    }
}