@IsTest
private class navigationLinkSetPicklistTest {
    @IsTest
    static void defaultValueAndPicklistRowsWork() {
        navigationLinkSetPicklist p = new navigationLinkSetPicklist();
        VisualEditor.DataRow def = p.getDefaultValue();
        System.assertNotEquals(null, def);
        VisualEditor.DynamicPickListRows rows = p.getValues();
        System.assertNotEquals(null, rows);
    }
}