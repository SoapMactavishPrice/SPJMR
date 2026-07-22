@IsTest
private class PdfAutoMergeCtrlTest {
    @IsTest
    static void blankParamYieldsEmptyList() {
        Test.setCurrentPage(new PageReference('/apex/x'));
        PdfAutoMergeCtrl c = new PdfAutoMergeCtrl();
        System.assertNotEquals(null, c.pdfUrls);
        System.assertEquals(0, c.pdfUrls.size());
    }
    @IsTest
    static void jsonParamIsDeserialized() {
        PageReference pr = new PageReference('/apex/x');
        pr.getParameters().put('data', '["a","b","c"]');
        Test.setCurrentPage(pr);
        PdfAutoMergeCtrl c = new PdfAutoMergeCtrl();
        System.assertEquals(3, c.pdfUrls.size());
        System.assertEquals('a', c.pdfUrls[0]);
    }
}