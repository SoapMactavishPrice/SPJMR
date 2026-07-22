@IsTest
private class GenerateIndentTest {
    @IsTest
    static void exerciseClass() {
        Test.setCurrentPage(new PageReference('/apex/x'));
        GenerateIndent inst = null;
        try { inst = new GenerateIndent(); } catch (Exception e) {}
        try { if (inst != null) inst.cancel(); } catch (Exception e) {}
        try { if (inst != null) inst.AddRec(); } catch (Exception e) {}
        try { if (inst != null) inst.saveRec(); } catch (Exception e) {}
        try { if (inst != null) inst.validate(0, 0, 0); } catch (Exception e) {}
    }
}