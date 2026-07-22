public class FlowStringSplitter {

    @InvocableMethod(label='Split Semicolon String')
    public static List<List<String>> splitStrings(List<String> inputs) {
        List<List<String>> results = new List<List<String>>();

        for (String input : inputs) {
            if (String.isBlank(input)) {
                results.add(new List<String>());
            } else {
                results.add(input.split(';'));
            }
        }

        return results;
    }
}