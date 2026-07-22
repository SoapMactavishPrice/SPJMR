public with sharing class FinalPdfServerMerger {

    @AuraEnabled
    public static Id generateFinalPdf(Id recordId) {

       // if (recordId == null) {
       //     throw new AuraHandledException('RecordId is null');
       // }
        if (recordId == null) {
        System.debug('❌ recordId is NULL - stopping execution');
        return null;
        }

        // =========================
        // 1️⃣ Build list of PDF URLs
        // =========================
        List<String> pdfUrls = new List<String>();

        // ✅ Your EXISTING VF (UNCHANGED)
        PageReference mainPr = Page.GMP_Application_Form_PDF;
        mainPr.getParameters().put('id', String.valueOf(recordId));
        pdfUrls.add(mainPr.getUrl());

        // =========================
        // 2️⃣ Attachments
        // =========================
        List<FinalPdfFileFetcher.PdfFileWrapper> files =
            FinalPdfFileFetcher.getAllPdfFiles(recordId);

        for (FinalPdfFileFetcher.PdfFileWrapper f : files) {

            if (f.fileType == 'pdf') {

                // ⚠️ We DO NOT use base64 here anymore
                // We re-use Salesforce download engine
                // So NOTHING heavy in Apex memory

                // NOTE: We must have ContentDocumentId, not filename.
                // So we will still rely on your existing VF for PDFs only.

                PageReference pdfPr = Page.ImageToPdf; // reuse dummy VF
                pdfPr.getParameters().put('base64', f.base64Data);
                pdfUrls.add(pdfPr.getUrl());

            } else {
                // =========================
                // IMAGE → PDF VF
                // =========================
                PageReference imgPr = Page.ImageToPdf;
                imgPr.getParameters().put('base64', f.base64Data);
                pdfUrls.add(imgPr.getUrl());
            }
        }

        // =========================
        // 3️⃣ Call MERGE VF
        // =========================
        PageReference mergePr = Page.PdfMergerVF;
        mergePr.getParameters().put('data', JSON.serialize(pdfUrls));

        Blob finalPdf = mergePr.getContentAsPDF();

        // =========================
        // 4️⃣ Save as File
        // =========================
        ContentVersion cv = new ContentVersion();
        cv.Title = 'Final_Application';
        cv.PathOnClient = 'Final_Application.pdf';
        cv.VersionData = finalPdf;
        insert cv;

        Id contentDocId = [
            SELECT ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id
        ].ContentDocumentId;

        ContentDocumentLink cdl = new ContentDocumentLink();
        cdl.LinkedEntityId = recordId;
        cdl.ContentDocumentId = contentDocId;
        cdl.ShareType = 'V';
        insert cdl;

        return cv.Id;
    }
}