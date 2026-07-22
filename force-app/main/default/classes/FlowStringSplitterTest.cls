@IsTest
private class FlowStringSplitterTest {
    @IsTest
    static void splitsAndHandlesBlank() {
        List<String> inputs = new List<String>{'a;b;c', '', null, 'x'};
        List<List<String>> results = FlowStringSplitter.splitStrings(inputs);
        System.assertEquals(4, results.size());
        System.assertEquals(3, results[0].size());
        System.assertEquals('a', results[0][0]);
        System.assertEquals(0, results[1].size());
        System.assertEquals(0, results[2].size());
        System.assertEquals(1, results[3].size());
        System.assertEquals('x', results[3][0]);
    }
}