public with sharing class LeadImportPageController {

    public String message { get; set; }

    

    public PageReference startBatch() {
        try {
            Database.executeBatch(new B2CImportBatch(), 200);
            message = 'Lead Import has started successfully.';
        } catch (Exception e) {
            message = 'Error starting Lead Import: ' + e.getMessage();
        }
        return null;
    }
}