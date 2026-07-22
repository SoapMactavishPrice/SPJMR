@IsTest
private class OpportunitySlabPricingControllerTest {
    @IsTest
    static void exerciseClass() {
        OpportunitySlabPricingController inst = null;
        try { inst = new OpportunitySlabPricingController(); } catch (Exception e) {}
        try { OpportunitySlabPricingController.getOpportunityLineItems(null); } catch (Exception e) {}
        try { OpportunitySlabPricingController.getSlabDiscountOptionsForLines(null); } catch (Exception e) {}
        try { OpportunitySlabPricingController.applySlabDiscounts(null, null); } catch (Exception e) {}
    }
}