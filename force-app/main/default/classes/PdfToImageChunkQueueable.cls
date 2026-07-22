public class PdfToImageChunkQueueable implements Queueable, Database.AllowsCallouts {

    List<String> urls;
    Integer index;
    Id parentId;
    String title;

    // ================= CONSTRUCTOR =================
    public PdfToImageChunkQueueable(List<String> urls, Integer index, Id parentId, String title) {
        System.debug('CHUNK ▶ Constructor called');
        System.debug('Start index: ' + index);
        this.urls = urls;
        this.index = index;
        this.parentId = parentId;
        this.title = title;
    }

    // ================= EXECUTE =================
    public void execute(QueueableContext qc) {

        System.debug('CHUNK ▶ Execute started at index: ' + index);

        List<ContentVersion> toInsert = new List<ContentVersion>();

        Integer processed = 0;

        // ✅ Only 2 images per execution (SAFE for heap)
        while (index < urls.size() && processed < 2) {

            System.debug('CHUNK ▶ Downloading page: ' + (index + 1));

            HttpRequest req = new HttpRequest();
            req.setEndpoint(urls[index]);
            req.setMethod('GET');

            Http http = new Http();
            HttpResponse res = http.send(req);

            if (res.getStatusCode() == 200) {

                ContentVersion img = new ContentVersion();
                img.Title = title + '_Page_' + (index + 1);
                img.PathOnClient = title + '_Page_' + (index + 1) + '.png';
                img.VersionData = res.getBodyAsBlob();
                img.IsMajorVersion = true;

                toInsert.add(img);

                System.debug('CHUNK ▶ Page downloaded successfully');
            } else {
                System.debug('❌ CHUNK ▶ Failed to download page: ' + (index + 1));
            }

            index++;
            processed++;
        }

        System.debug('CHUNK ▶ Inserting images count: ' + toInsert.size());
        insert toInsert;

        // ================= LINK TO PARENT =================
        List<ContentDocumentLink> links = new List<ContentDocumentLink>();

        for (ContentVersion cv : [
            SELECT ContentDocumentId FROM ContentVersion WHERE Id IN :toInsert
        ]) {
            links.add(new ContentDocumentLink(
                ContentDocumentId = cv.ContentDocumentId,
                LinkedEntityId = parentId,
                ShareType = 'V',
                Visibility = 'AllUsers'
            ));
        }

        System.debug('CHUNK ▶ Linking images to parent: ' + parentId);
        insert links;

        System.debug('CHUNK ▶ Inserted & linked ' + toInsert.size() + ' images');

        // ================= ENQUEUE NEXT CHUNK =================
        if (index < urls.size()) {
            System.debug('CHUNK ▶ More pages pending, enqueue next job from index: ' + index);
            System.enqueueJob(new PdfToImageChunkQueueable(urls, index, parentId, title));
        } else {
            System.debug('CHUNK ▶ All pages processed successfully ✅');
        }
    }
}