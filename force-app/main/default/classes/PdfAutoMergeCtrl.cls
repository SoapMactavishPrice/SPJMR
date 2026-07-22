public class PdfAutoMergeCtrl {

    public List<String> pdfUrls { get; set; }

    public PdfAutoMergeCtrl() {
        String jsonData = ApexPages.currentPage().getParameters().get('data');

        if (String.isBlank(jsonData)) {
            pdfUrls = new List<String>();
            return;
        }

        pdfUrls = (List<String>) JSON.deserialize(jsonData, List<String>.class);
    }
}