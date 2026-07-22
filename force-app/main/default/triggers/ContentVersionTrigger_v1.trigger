trigger ContentVersionTrigger_v1 on ContentVersion (after insert) {

    Set<Id> pdfVersionIds = new Set<Id>();

    for (ContentVersion cv : Trigger.new) {
        if (cv.FileType == 'PDF' && cv.ContentDocumentId != null) {
            pdfVersionIds.add(cv.Id);
        }
    }

    if (!pdfVersionIds.isEmpty()) {
        PdfTriggerHandler.processAsync(new List<Id>(pdfVersionIds));
    }
}