public class c_RFQ_Buttons {
    
    public string v_rid{get;set;}
    
    public c_RFQ_Buttons() {
        v_rid = ApexPages.CurrentPage().getparameters().get('id');        
    }
    
    public pageReference f_page_call(String p_page) {
        PageReference pageRef = new PageReference(p_page);
        pageRef.setRedirect(false);
        return pageRef;
    }
    
    public pageReference f_AddProduct() {
        return f_page_call('/apex/addProductOnRFQ?id=' + v_rid);
    }
    
    public pageReference f_EditProduct() {
        return f_page_call('/apex/EditAllRFQlineItems?id=' + v_rid);
    }
    
    public pageReference f_AddEditRFQVendor() {
        return f_page_call('/apex/AddEditRFQVendor?id=' + v_rid);
    }    

    public pageReference f_VendorProductMap() {
        return f_page_call('/apex/RFQVendorProductMap?id=' + v_rid);
    }
    
    public pageReference f_VendorProductMapEdit() {
        return f_page_call('/apex/RFQVendorProductMapEdit?id=' + v_rid);
    }
    
    public pageReference f_SendMailtoVendor() {
        return f_page_call('/apex/RFQSendMailtoVendor?id=' + v_rid);
    }
    
    public pageReference f_SendPDF() {
        return f_page_call('/apex/RFQSendMailPDFtoVendor?id=' + v_rid);
    }
    
    public pageReference f_RFXResponseEditor() {
        return f_page_call('/apex/RFXResponseEditor?id=' + v_rid);
    }
    
    public pageReference f_AwardRFQtoVendor() {
        return f_page_call('/apex/Award_RFQ_to_Vendor?id=' + v_rid);
    }
    
    public pageReference f_RFQApprover() {
        return f_page_call('/apex/RFQApprover?id=' + v_rid);
    }

    public pageReference f_CreatePO() {
        return f_page_call('/apex/CreatePO?id=' + v_rid);
    }


}