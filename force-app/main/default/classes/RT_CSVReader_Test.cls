@IsTest
private class RT_CSVReader_Test {

    // ============================================
    // Basic parsing - simple unquoted values
    // ============================================
    @IsTest
    static void testSimpleCsv() {
        String csv = 'a,b,c\n1,2,3';
        List<List<String>> rows = RT_CSVReader.read(csv);

        System.assertEquals(2, rows.size());
        System.assertEquals(new List<String>{'a','b','c'}, rows[0]);
        System.assertEquals(new List<String>{'1','2','3'}, rows[1]);
    }

    @IsTest
    static void testSingleRowNoTrailingNewline() {
        String csv = 'x,y,z';
        List<List<String>> rows = RT_CSVReader.read(csv);

        System.assertEquals(1, rows.size());
        System.assertEquals(new List<String>{'x','y','z'}, rows[0]);
    }

    @IsTest
    static void testTrailingNewlineDoesNotAddEmptyRow() {
        // After the final \n, pos == length so hasNext() is false -> no extra empty row
        String csv = 'a,b\n1,2\n';
        List<List<String>> rows = RT_CSVReader.read(csv);

        System.assertEquals(2, rows.size());
        System.assertEquals(new List<String>{'a','b'}, rows[0]);
        System.assertEquals(new List<String>{'1','2'}, rows[1]);
    }

    @IsTest
    static void testEmptyString() {
        List<List<String>> rows = RT_CSVReader.read('');
        System.assertEquals(0, rows.size());
    }

    @IsTest
    static void testEmptyFieldsBetweenCommas() {
        String csv = 'a,,c\n,,';
        List<List<String>> rows = RT_CSVReader.read(csv);

        System.assertEquals(2, rows.size());
        System.assertEquals(new List<String>{'a','','c'}, rows[0]);
        System.assertEquals(new List<String>{'','',''}, rows[1]);
    }

    // ============================================
    // Quoted fields
    // ============================================
    @IsTest
    static void testQuotedFields() {
        String csv = '"a","b","c"\n"1","2","3"';
        List<List<String>> rows = RT_CSVReader.read(csv);

        System.assertEquals(2, rows.size());
        System.assertEquals(new List<String>{'a','b','c'}, rows[0]);
        System.assertEquals(new List<String>{'1','2','3'}, rows[1]);
    }

    @IsTest
    static void testMixedQuotedAndUnquotedFields() {
        String csv = 'a,"b",c';
        List<List<String>> rows = RT_CSVReader.read(csv);

        System.assertEquals(1, rows.size());
        System.assertEquals(new List<String>{'a','b','c'}, rows[0]);
    }

    @IsTest
    static void testEscapedQuotesInsideQuotedField() {
        // CSV: "He said ""hello""" -> He said "hello"
        String csv = '"He said ""hello"""';
        List<List<String>> rows = RT_CSVReader.read(csv);

        System.assertEquals(1, rows.size());
        System.assertEquals(1, rows[0].size());
        System.assertEquals('He said "hello"', rows[0][0]);
    }

    @IsTest
    static void testCommaInsideQuotedField() {
        String csv = '"Smith, John",42';
        List<List<String>> rows = RT_CSVReader.read(csv);

        System.assertEquals(1, rows.size());
        System.assertEquals(new List<String>{'Smith, John','42'}, rows[0]);
    }

    @IsTest
    static void testNewlineInsideQuotedField() {
        // A literal newline inside quotes should NOT terminate the row
        String csv = '"line1\nline2",value2\nrow2col1,row2col2';
        List<List<String>> rows = RT_CSVReader.read(csv);

        System.assertEquals(2, rows.size());
        System.assertEquals('line1\nline2', rows[0][0]);
        System.assertEquals('value2', rows[0][1]);
        System.assertEquals(new List<String>{'row2col1','row2col2'}, rows[1]);
    }

    @IsTest
    static void testQuotedFieldAtEndOfString() {
        // Exercises peek() returning null when pos+1 >= length
        String csv = '"abc"';
        List<List<String>> rows = RT_CSVReader.read(csv);

        System.assertEquals(1, rows.size());
        System.assertEquals(new List<String>{'abc'}, rows[0]);
    }

    @IsTest
    static void testEmptyQuotedField() {
        String csv = '"",value';
        List<List<String>> rows = RT_CSVReader.read(csv);

        System.assertEquals(1, rows.size());
        System.assertEquals(new List<String>{'','value'}, rows[0]);
    }

    // ============================================
    // Line-ending normalization
    // ============================================
    @IsTest
    static void testCRLFNormalization() {
        String csv = 'a,b\r\n1,2\r\n3,4';
        List<List<String>> rows = RT_CSVReader.read(csv);

        System.assertEquals(3, rows.size());
        System.assertEquals(new List<String>{'a','b'}, rows[0]);
        System.assertEquals(new List<String>{'1','2'}, rows[1]);
        System.assertEquals(new List<String>{'3','4'}, rows[2]);
    }

    @IsTest
    static void testLoneCRNormalization() {
        String csv = 'a,b\r1,2\r3,4';
        List<List<String>> rows = RT_CSVReader.read(csv);

        System.assertEquals(3, rows.size());
        System.assertEquals(new List<String>{'a','b'}, rows[0]);
        System.assertEquals(new List<String>{'1','2'}, rows[1]);
        System.assertEquals(new List<String>{'3','4'}, rows[2]);
    }

    @IsTest
    static void testMixedLineEndings() {
        String csv = 'a,b\r\n1,2\n3,4\r5,6';
        List<List<String>> rows = RT_CSVReader.read(csv);

        System.assertEquals(4, rows.size());
        System.assertEquals(new List<String>{'a','b'}, rows[0]);
        System.assertEquals(new List<String>{'1','2'}, rows[1]);
        System.assertEquals(new List<String>{'3','4'}, rows[2]);
        System.assertEquals(new List<String>{'5','6'}, rows[3]);
    }

    // ============================================
    // Multiple rows / realistic data
    // ============================================
    @IsTest
    static void testMultipleRowsRealistic() {
        String csv = 'Name,Age,City\n"Doe, Jane",30,"New York"\nBob,25,LA';
        List<List<String>> rows = RT_CSVReader.read(csv);

        System.assertEquals(3, rows.size());
        System.assertEquals(new List<String>{'Name','Age','City'}, rows[0]);
        System.assertEquals(new List<String>{'Doe, Jane','30','New York'}, rows[1]);
        System.assertEquals(new List<String>{'Bob','25','LA'}, rows[2]);
    }

    // ============================================
    // Direct iterator usage (constructor, iterator(), hasNext(), next())
    // ============================================
    @IsTest
    static void testIteratorDirectUsage() {
        RT_CSVReader reader = new RT_CSVReader('a,b\n1,2');

        System.assert(reader.iterator() === reader);

        List<List<String>> collected = new List<List<String>>();
        while (reader.hasNext()) {
            collected.add(reader.next());
        }

        System.assertEquals(2, collected.size());
        System.assertEquals(new List<String>{'a','b'}, collected[0]);
        System.assertEquals(new List<String>{'1','2'}, collected[1]);
        System.assertEquals(false, reader.hasNext());
    }

    @IsTest
    static void testForEachIteration() {
        RT_CSVReader reader = new RT_CSVReader('h1,h2\nv1,v2\nv3,v4');
        Integer count = 0;
        for (List<String> row : reader) {
            count++;
        }
        System.assertEquals(3, count);
    }

    // ============================================
    // Whitespace / single column edge cases
    // ============================================
    @IsTest
    static void testSingleColumnRows() {
        String csv = 'onlyvalue1\nonlyvalue2';
        List<List<String>> rows = RT_CSVReader.read(csv);

        System.assertEquals(2, rows.size());
        System.assertEquals(new List<String>{'onlyvalue1'}, rows[0]);
        System.assertEquals(new List<String>{'onlyvalue2'}, rows[1]);
    }

    @IsTest
    static void testQuotedFieldFollowedByMoreQuotedFieldsWithEscapes() {
        String csv = '"a""b",c,"d""e""f"';
        List<List<String>> rows = RT_CSVReader.read(csv);

        System.assertEquals(1, rows.size());
        System.assertEquals(new List<String>{'a"b','c','d"e"f'}, rows[0]);
    }
}