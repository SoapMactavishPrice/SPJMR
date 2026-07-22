public class PdfToImageQueueable implements Queueable, Database.AllowsCallouts {

    private List<Id> pdfVersionIds;
    private Id parentRecordId; // ✅ target record

    // ================= CONSTRUCTOR =================
    public PdfToImageQueueable(List<Id> pdfVersionIds, Id parentRecordId) {
        System.debug('STEP 0 ▶ Constructor called');
        System.debug('PDF Version Ids received: ' + pdfVersionIds);
        this.pdfVersionIds = pdfVersionIds;
        this.parentRecordId = parentRecordId;
    }

    // ================= EXECUTE =================
    public void execute(QueueableContext context) {
        System.debug('STEP 1 ▶ Queueable execute() started');

        List<ContentVersion> pdfs = [
            SELECT Id, VersionData, Title, FirstPublishLocationId
            FROM ContentVersion
            WHERE Id IN :pdfVersionIds
        ];

        System.debug('STEP 2 ▶ PDFs fetched count: ' + pdfs.size());

        for (ContentVersion pdf : pdfs) {
            System.debug('--------------------------------------------------');
            System.debug('STEP 3 ▶ Processing PDF');
            System.debug('PDF ContentVersion Id: ' + pdf.Id);
            System.debug('PDF Title: ' + pdf.Title);
            System.debug('FirstPublishLocationId: ' + pdf.FirstPublishLocationId);

            try {
                processPdf(pdf);
            } catch (Exception e) {
                System.debug('❌ ERROR while processing PDF');
                System.debug('Message: ' + e.getMessage());
                System.debug('StackTrace: ' + e.getStackTraceString());
            }
        }

        System.debug('STEP 99 ▶ Queueable execute() finished');
    }

    // ================= MAIN PROCESS =================
    private void processPdf(ContentVersion pdf) {
        System.debug('STEP 4 ▶ processPdf() started');

        String pdfBase64 = EncodingUtil.base64Encode(pdf.VersionData);
        System.debug('STEP 5 ▶ PDF converted to Base64');
        System.debug('Base64 length: ' + pdfBase64.length());

        System.debug('STEP 6 ▶ Calling uploadPdfToPdfCo()');
        String uploadedPdfUrl = uploadPdfToPdfCo(pdf.Title, pdfBase64);

        System.debug('STEP 7 ▶ Uploaded PDF URL: ' + uploadedPdfUrl);

        if (uploadedPdfUrl == null) {
            System.debug('❌ STEP 7.1 ▶ Upload failed. Stopping processing.');
            return;
        }

        System.debug('STEP 8 ▶ Calling startImageConversion()');
        startImageConversion(uploadedPdfUrl, pdf);
    }

    // ================= STEP 1: UPLOAD PDF =================
    private String uploadPdfToPdfCo(String title, String base64Pdf) {
        System.debug('STEP 9 ▶ Upload PDF API call started');

        HttpRequest req = new HttpRequest();
        req.setEndpoint('callout:PDF_To_Image_API/v1/file/upload/base64');
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/json');
        req.setHeader('x-api-key', 'mjdsd7@gmail.com_tLAYuSRNRmy3zgc3SnaRl59K9Gy2Yap210M2xEL1PwheFTq8qUDAVaRGvX7OFGoQ');
        req.setBody(JSON.serialize(new Map<String, Object>{
            'file' => base64Pdf,
            'name' => title + '.pdf'
        }));

        System.debug('STEP 10 ▶ Upload request prepared');

        Http http = new Http();
        HttpResponse res = http.send(req);

        System.debug('STEP 11 ▶ Upload API response received');
        System.debug('Status Code: ' + res.getStatusCode());
        System.debug('Response Body: ' + res.getBody());

        if (res.getStatusCode() == 200) {
            Map<String, Object> result =
                (Map<String, Object>) JSON.deserializeUntyped(res.getBody());

            String url = (String) result.get('url');
            System.debug('STEP 12 ▶ PDF uploaded successfully');
            return url;
        }

        System.debug('❌ STEP 12.1 ▶ PDF upload failed');
        return null;
    }

    // ================= STEP 2: GET IMAGE URL LIST =================
    /*private void startImageConversion(String pdfUrl, ContentVersion pdf) {

        System.debug('STEP 13 ▶ Requesting image URL list from API');

        HttpRequest req = new HttpRequest();
       // req.setEndpoint('callout:PDF_To_Image_API/v1/pdf/convert/to/png');
        req.setEndpoint('callout:PDF_To_Image_API/v1/pdf/convert/to/jpg'); 
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/json');
      //  req.setHeader('x-api-key', 'PUT_API_KEY_IN_NAMED_CREDENTIAL');
        req.setHeader('x-api-key', 'mjdsd7@gmail.com_tLAYuSRNRmy3zgc3SnaRl59K9Gy2Yap210M2xEL1PwheFTq8qUDAVaRGvX7OFGoQ');
      //  req.setBody(JSON.serialize(new Map<String, Object>{
      //      'url' => pdfUrl,
      //      'pages' => '0-'
      //  }));
        req.setBody(JSON.serialize(new Map<String, Object>{
            'url' => pdfUrl,
               // 'pages' => '0-',
                'pages' => '0-4',
               // 'dpi' => 150,        // 🔥 reduce resolution (try 100 or 150)
                'dpi' => 96,        // 🔥 reduce resolution (try 100 or 150)
               // 'quality' => 70      // 🔥 reduce size
                'quality' => 65      // 🔥 reduce size
                }));


        Http http = new Http();
        HttpResponse res = http.send(req);

        System.debug('STEP 14 ▶ Convert API response received');
        System.debug('Status Code: ' + res.getStatusCode());
        System.debug('Response Body: ' + res.getBody());

        if (res.getStatusCode() != 200) {
            System.debug('❌ STEP 14.1 ▶ Conversion API failed');
            return;
        }

        Map<String, Object> response =
            (Map<String, Object>) JSON.deserializeUntyped(res.getBody());

        List<Object> rawUrls = (List<Object>) response.get('urls');
        List<String> urls = new List<String>();

        for (Object o : rawUrls) {
            urls.add((String)o);
        }

        System.debug('STEP 15 ▶ Total pages returned: ' + urls.size());

        // 🔥 Start chunk queueable (2 pages per job)
        System.debug('STEP 16 ▶ Enqueue first chunk job');

        System.enqueueJob(
            new PdfToImageChunkQueueable(urls, 0, parentRecordId, pdf.Title)
        );
    }*/
    // ================= STEP 2: GET IMAGE URL LIST (IN BATCHES) =================
   /* Final working
        private void startImageConversion(String pdfUrl, ContentVersion pdf) {
        
        System.debug('STEP 13 ▶ Requesting image URL list from API IN BATCHES');
        
        List<String> allUrls = new List<String>();
        
        Integer batchSize = 5; // ✅ 5 pages per API call
        Integer maxPages = 100; // safety cap (we'll break when API returns less)
        
        for (Integer start = 0; start < maxPages; start += batchSize) {
            
            Integer endPage = start + batchSize - 1;
            String pageRange = start + '-' + endPage;
            
            System.debug('STEP 13 ▶ Calling convert API for pages: ' + pageRange);
            
            HttpRequest req = new HttpRequest();
            req.setEndpoint('callout:PDF_To_Image_API/v1/pdf/convert/to/jpg');
            req.setMethod('POST');
            req.setHeader('Content-Type', 'application/json');
            req.setHeader('x-api-key', 'mjdsd7@gmail.com_tLAYuSRNRmy3zgc3SnaRl59K9Gy2Yap210M2xEL1PwheFTq8qUDAVaRGvX7OFGoQ');
            
            req.setBody(JSON.serialize(new Map<String, Object>{
                'url' => pdfUrl,
                    'pages' => pageRange,
                    'dpi' => 96,
                    'quality' => 65
                    }));
            
            Http http = new Http();
            HttpResponse res = http.send(req);
            
            System.debug('STEP 14 ▶ Convert API response for pages ' + pageRange);
            System.debug('Status Code: ' + res.getStatusCode());
            
            if (res.getStatusCode() != 200) {
                System.debug('❌ STEP 14.1 ▶ Conversion API failed for range: ' + pageRange);
                break;
            }
            
            Map<String, Object> response =
                (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
            
            List<Object> rawUrls = (List<Object>) response.get('urls');
            
            System.debug('STEP 15 ▶ Pages returned in this batch: ' + rawUrls.size());
            
            // If API returns 0 pages → no more pages left
            if (rawUrls == null || rawUrls.isEmpty()) {
                System.debug('STEP 15.1 ▶ No more pages returned. Stopping batching.');
                break;
            }
            
            for (Object o : rawUrls) {
                allUrls.add((String)o);
            }
            
            // If less than batchSize returned, means this was last batch
            if (rawUrls.size() < batchSize) {
                System.debug('STEP 15.2 ▶ Last batch detected. Stopping batching.');
                break;
            }
        }
        
        System.debug('STEP 16 ▶ TOTAL image URLs collected: ' + allUrls.size());
        
        if (allUrls.isEmpty()) {
            System.debug('❌ STEP 16.1 ▶ No images to process. Stopping.');
            return;
        }
        
        // 🔥 Start chunk queueable (2 pages per job)
        System.debug('STEP 17 ▶ Enqueue first chunk job');
        
        System.enqueueJob(
            new PdfToImageChunkQueueable(allUrls, 0, parentRecordId, pdf.Title)
        );
    } */
    // ================= STEP 2: GET IMAGE URL LIST (IN BATCHES) =================
/*private void startImageConversion(String pdfUrl, ContentVersion pdf) {
    
    System.debug('STEP 13 ▶ Requesting image URL list from API IN BATCHES');
    
    List<String> allUrls = new List<String>();
    
    Integer batchSize = 5; // ✅ 5 pages per API call
    Integer maxPages = 100; // safety cap
    
    for (Integer start = 0; start < maxPages; start += batchSize) {
        
        Integer endPage = start + batchSize - 1;
        String pageRange = start + '-' + endPage;
        
        System.debug('STEP 13 ▶ Calling convert API for pages: ' + pageRange);
        
        HttpRequest req = new HttpRequest();
        req.setEndpoint('callout:PDF_To_Image_API/v1/pdf/convert/to/jpg');
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/json');
        req.setHeader('x-api-key', 'mjdsd7@gmail.com_tLAYuSRNRmy3zgc3SnaRl59K9Gy2Yap210M2xEL1PwheFTq8qUDAVaRGvX7OFGoQ');
        
        req.setBody(JSON.serialize(new Map<String, Object>{
            'url' => pdfUrl,
            'pages' => pageRange,
            'dpi' => 96,
            'quality' => 65
        }));
        
        Http http = new Http();
        HttpResponse res = http.send(req);
        
        System.debug('STEP 14 ▶ Convert API response for pages ' + pageRange);
        System.debug('Status Code: ' + res.getStatusCode());
        
        if (res.getStatusCode() != 200) {
            System.debug('❌ STEP 14.1 ▶ Conversion API failed for range: ' + pageRange);
            break;
        }
        
        Map<String, Object> response =
            (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
        
        List<Object> rawUrls = (List<Object>) response.get('urls');
        
        System.debug('STEP 15 ▶ Pages returned in this batch: ' + (rawUrls == null ? 0 : rawUrls.size()));
        
        // ✅ ONLY stop when API returns 0 pages
        if (rawUrls == null || rawUrls.isEmpty()) {
            System.debug('STEP 15.1 ▶ No more pages returned. Stopping batching.');
            System.debug('STEP 15 ▶ Pages returned in this batch: ' + (rawUrls == null ? 0 : rawUrls.size()));
            System.debug('STEP 15 ▶ Current TOTAL collected so far: ' + allUrls.size());

            break;
        }
        
        for (Object o : rawUrls) {
            allUrls.add((String)o);
        }
    }
    
    System.debug('STEP 16 ▶ TOTAL image URLs collected: ' + allUrls.size());
    System.debug('🔥 FINAL URL LIST SIZE SENT TO CHUNK QUEUEABLE = ' + allUrls.size());

    if (allUrls.isEmpty()) {
        System.debug('❌ STEP 16.1 ▶ No images to process. Stopping.');
        return;
    }
    
    // 🔥 Start chunk queueable (2 pages per job)
    System.debug('STEP 17 ▶ Enqueue first chunk job');
    
    System.enqueueJob(
        new PdfToImageChunkQueueable(allUrls, 0, parentRecordId, pdf.Title)
    );
}*/
    private void startImageConversion(String pdfUrl, ContentVersion pdf) {

    System.debug('STEP 13 ▶ Converting ALL pages in one call');

    HttpRequest req = new HttpRequest();
    req.setEndpoint('callout:PDF_To_Image_API/v1/pdf/convert/to/jpg');
    req.setMethod('POST');
    req.setHeader('Content-Type', 'application/json');
    req.setHeader('x-api-key', 'mjdsd7@gmail.com_tLAYuSRNRmy3zgc3SnaRl59K9Gy2Yap210M2xEL1PwheFTq8qUDAVaRGvX7OFGoQ');

    req.setBody(JSON.serialize(new Map<String, Object>{
        'url' => pdfUrl,
        'pages' => '0-',     // ✅ ALL pages
        'dpi' => 96,
        'quality' => 65
    }));

    Http http = new Http();
    HttpResponse res = http.send(req);

    System.debug('STEP 14 ▶ Convert API response received');
    System.debug('Status Code: ' + res.getStatusCode());
    System.debug('Response Body: ' + res.getBody());

    if (res.getStatusCode() != 200) {
        System.debug('❌ Conversion failed');
        return;
    }

    Map<String, Object> response =
        (Map<String, Object>) JSON.deserializeUntyped(res.getBody());

    List<Object> rawUrls = (List<Object>) response.get('urls');

    System.debug('STEP 15 ▶ TOTAL pages returned: ' + (rawUrls == null ? 0 : rawUrls.size()));

    if (rawUrls == null || rawUrls.isEmpty()) {
        System.debug('❌ No pages returned');
        return;
    }

    List<String> urls = new List<String>();
    for (Object o : rawUrls) {
        urls.add((String)o);
    }

    System.debug('STEP 16 ▶ Enqueue chunk job with total images = ' + urls.size());

    System.enqueueJob(
        new PdfToImageChunkQueueable(urls, 0, parentRecordId, pdf.Title)
    );
}


}