public with sharing class GenerateProgramPDFController {

    public Id avId { get; set; }

    public GenerateProgramPDFController() {
        avId = ApexPages.currentPage().getParameters().get('id');
    }

    public PageReference redirectToPDF() {

        // Query Application Verification → Application → Program
        Application_Verification__c av = [
            SELECT Id,
                   Application__r.Id,
                   Application__r.Program__r.Name
            FROM Application_Verification__c
            WHERE Id = :avId
            LIMIT 1
        ];

        String programName = av.Application__r.Program__r.Name;
        String appId = av.Application__r.Id;

        // === PROGRAM 1 : GMP ===
        if(programName == 'Global Programme in Management (GMP)') {
            PageReference pg = new PageReference('/apex/GMP_Application_Form_PDF?id=' + appId);
            pg.setRedirect(true);
            return pg;
        }

        // === PROGRAM 2 : PGPM ===
        if(programName == 'Post Graduate Programme in Management (PGPM)') {
            PageReference pg = new PageReference('/apex/Application_PDF?id=' + appId);
            pg.setRedirect(true);
            return pg;
        }

        // DEFAULT: Show error page
        PageReference err = new PageReference('/apex/ErrorPage?msg=PROGRAM_NOT_SUPPORTED');
        err.setRedirect(true);
        return err;
    }
}