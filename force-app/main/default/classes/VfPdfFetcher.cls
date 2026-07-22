public without sharing class VfPdfFetcher {
    
    @AuraEnabled
    public static Blob getVfPdfBlob(Id recordId) {
        
        Application__c app = [
            SELECT Id, Program__r.Program_Code__c
            FROM Application__c
            WHERE Id = :recordId
            LIMIT 1
        ];
        
        PageReference pr;
        
        if (app.Program__r.Program_Code__c == 'PGPM') {
            pr = Page.PGPM_Application_PDF;
        } else {
            pr = Page.GMP_Application_Form_PDF;
        }
        
        pr.getParameters().put('id', String.valueOf(recordId));
        
        if (Test.isRunningTest()) {
            return Blob.valueOf('Test PDF');
        }
        
        return pr.getContentAsPDF();
    }
    
    @AuraEnabled
    public static String getVfPdfBase64(Id recordId) {
        
        Application__c app = [
            SELECT Id, Program__r.Program_Code__c
            FROM Application__c
            WHERE Id = :recordId
            LIMIT 1
        ];
        
        PageReference pr;
        
        if (app.Program__r.Program_Code__c == 'PGPM') {
            pr = Page.PGPM_Application_PDF;
        } else {
            pr = Page.GMP_Application_Form_PDF;
        }
        
        pr.getParameters().put('id', String.valueOf(recordId));
        
        Blob pdfBlob;
        
        if (Test.isRunningTest()) {
            pdfBlob = Blob.valueOf('Test PDF');
        } else {
            pdfBlob = pr.getContentAsPDF();
        }
        
        return EncodingUtil.base64Encode(pdfBlob);
    }
}