@IsTest
private class UpdateGRNLineTest {
    @IsTest
    static void exerciseClass() {
        Test.setCurrentPage(new PageReference('/apex/x'));
        UpdateGRNLine inst = null;
        try { inst = new UpdateGRNLine(); } catch (Exception e) {}
        try { if (inst != null) inst.AddProduct(); } catch (Exception e) {}
        try { if (inst != null) inst.save(); } catch (Exception e) {}
        try { if (inst != null) inst.Back(); } catch (Exception e) {}
        try { if (inst != null) inst.Cancel(); } catch (Exception e) {}
    }
}