({
    openPdf : function(component, event, helper) {
        var recordId = component.get("v.recordId");

        // VF PDF URL
        var pdfUrl = '/apex/GenerateProgramPDF?id=' + recordId;

        // Open in new browser tab instantly
        window.open(pdfUrl, '_blank');

        // Close the action silently (no popup)
        $A.get("e.force:closeQuickAction").fire();
    }
})