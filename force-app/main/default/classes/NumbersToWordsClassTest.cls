@IsTest
private class NumbersToWordsClassTest {
    @IsTest
    static void convertHandlesAllMagnitudes() {
        NumbersToWordsClass c = new NumbersToWordsClass();
        // Small
        System.assert(c.convert(0).startsWith('Zero'));
        System.assert(c.convert(5).startsWith('Five'));
        System.assert(c.convert(19).startsWith('Nineteen'));
        // Tens
        System.assert(c.convert(20).startsWith('Twenty'));
        System.assert(c.convert(45).startsWith('Forty'));
        // Hundreds
        System.assert(c.convert(105).contains('Hundred'));
        // Thousands
        System.assert(c.convert(1000).contains('Thousand'));
        System.assert(c.convert(15000).contains('Thousand'));
        // Lakhs / Crores (Indian)
        System.assert(c.convert(100000).contains('Lakh'));
        System.assert(c.convert(2500000).contains('Lakh'));
        System.assert(c.convert(10000000).contains('Crore'));
        System.assert(c.convert(120000000).contains('Crore'));
        // Property-driven convert() (no-arg) using numberval
        c.numberval = 42;
        c.convert();
        System.assertNotEquals(null, c.wordText);
        c.wordText = 'x';
        System.assertEquals('x', c.wordText);
    }
}