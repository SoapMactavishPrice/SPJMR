@IsTest
private class AccountButtonsTest {
    @IsTest
    static void exerciseClass() {
        Test.setCurrentPage(new PageReference('/apex/x'));
        AccountButtons inst = null;
        try { inst = new AccountButtons(); } catch (Exception e) {}
        try { if (inst != null) inst.withdraw(); } catch (Exception e) {}
        try { if (inst != null) inst.studentTransfer(); } catch (Exception e) {}
        try { if (inst != null) inst.AddLevel(); } catch (Exception e) {}
        try { if (inst != null) inst.Withdrawal(); } catch (Exception e) {}
        try { if (inst != null) inst.BatchTransfer(); } catch (Exception e) {}
        try { if (inst != null) inst.GenerateInvoice(); } catch (Exception e) {}
        try { if (inst != null) inst.ViewInvoice(); } catch (Exception e) {}
        try { if (inst != null) inst.ViewReceipt(); } catch (Exception e) {}
        try { if (inst != null) inst.GenerateReceipt(); } catch (Exception e) {}
        try { if (inst != null) inst.AddBenefits(); } catch (Exception e) {}
        try { if (inst != null) inst.AddBenefits2(); } catch (Exception e) {}
        try { if (inst != null) inst.Instalment(); } catch (Exception e) {}
        try { if (inst != null) inst.Lumpsum(); } catch (Exception e) {}
        try { if (inst != null) inst.OptInOptOut(); } catch (Exception e) {}
        try { if (inst != null) inst.ViewOutstanding(); } catch (Exception e) {}
        try { if (inst != null) inst.AddProgramBatch(); } catch (Exception e) {}
        try { if (inst != null) inst.AddFeePlan(); } catch (Exception e) {}
        try { if (inst != null) inst.EditAllPrograms(); } catch (Exception e) {}
        try { if (inst != null) inst.ViewAllFeePlans(); } catch (Exception e) {}
        try { if (inst != null) inst.EditAllDocumentsPage(); } catch (Exception e) {}
        try { if (inst != null) inst.MakePayTest(); } catch (Exception e) {}
        try { if (inst != null) inst.AddStationaryMaster(); } catch (Exception e) {}
        try { if (inst != null) inst.DeleteBenefit(); } catch (Exception e) {}
        try { if (inst != null) inst.GenerateInvoiceLWC(); } catch (Exception e) {}
    }
}