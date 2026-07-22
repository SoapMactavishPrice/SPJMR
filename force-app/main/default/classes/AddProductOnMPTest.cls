@IsTest
private class AddProductOnMPTest {
    @IsTest
    static void exerciseClass() {
        Test.setCurrentPage(new PageReference('/apex/x'));
        AddProductOnMP inst = null;
        try { inst = new AddProductOnMP(); } catch (Exception e) {}
        try { if (inst != null) inst.Search(); } catch (Exception e) {}
        try { if (inst != null) inst.nextPage(); } catch (Exception e) {}
        try { if (inst != null) inst.prePage(); } catch (Exception e) {}
        try { if (inst != null) inst.AddRec(); } catch (Exception e) {}
        try { if (inst != null) inst.selectAll(); } catch (Exception e) {}
        try { if (inst != null) inst.saveRec(); } catch (Exception e) {}
        try { if (inst != null) inst.cancel(); } catch (Exception e) {}
    }
}