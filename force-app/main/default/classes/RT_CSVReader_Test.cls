@IsTest
public class RT_CSVReader_Test {
    
    @IsTest
    static void testBasicCSV() {
        String csv =
            '"Id","Name","Status"\n' +
            '"1","John","Submitted"\n' +
            '"2","Jane","Approved"';

        List<List<String>> rows = RT_CSVReader.read(csv);

        System.assertEquals(3, rows.size());
        System.assertEquals('Id', rows[0][0]);
        System.assertEquals('Jane', rows[2][1]);
    }

    @IsTest
    static void testEmptyField() {
        String csv =
            '"Id","Name","Status"\n' +
            '"1","","Submitted"';

        List<List<String>> rows = RT_CSVReader.read(csv);

        System.assertEquals('', rows[1][1]);  // Empty field
    }

    @IsTest
    static void testEscapedQuotes() {
        String csv =
            '"Id","Notes"\n' +
            '"1","He said ""Hello"""';

        List<List<String>> rows = RT_CSVReader.read(csv);

        System.assertEquals('He said "Hello"', rows[1][1]);
    }

    @IsTest
    static void testMultiLine() {
        String csv =
            '"Id","Description"\n' +
            '"1","Line1\nLine2"';

        List<List<String>> rows = RT_CSVReader.read(csv);

        System.assertEquals('Line1\nLine2', rows[1][1]);
    }

    @IsTest
    static void testTrailingComma() {
        String csv =
            '"Id","Name","Status"\n' +
            '"1","John","Submitted",';

        List<List<String>> rows = RT_CSVReader.read(csv);

        System.assertEquals(4, rows[1].size());
        System.assertEquals('', rows[1][3]); // trailing empty field
    }
}