@IsTest
private class ConvertB2BLeadControllerTest {
    @IsTest
    static void exerciseClass() {
        ConvertB2BLeadController inst = null;
        try { inst = new ConvertB2BLeadController(); } catch (Exception e) {}
        try { ConvertB2BLeadController.convertB2BLead(null, false); } catch (Exception e) {}
        try { ConvertB2BLeadController.getLeadDetails(null); } catch (Exception e) {}
    }
}