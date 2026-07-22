public class RT_CSVReader implements Iterable<List<String>>, Iterator<List<String>> {

    private String csv;
    private Integer length;
    private Integer pos = 0;

    public RT_CSVReader(String csvString) {
        this.csv = normalizeLF(csvString);
        this.length = this.csv.length();
    }

    // Normalize CRLF → LF, CR → LF
    private static String normalizeLF(String s) {
        return s.replace('\r\n', '\n').replace('\r', '\n');
    }

    public static List<List<String>> read(String csvString) {
        RT_CSVReader reader = new RT_CSVReader(csvString);
        List<List<String>> rows = new List<List<String>>();
        for (List<String> row : reader) {
            rows.add(row);
        }
        return rows;
    }

    public Iterator<List<String>> iterator() {
        return this;
    }

    public Boolean hasNext() {
        return pos < length;
    }

    public List<String> next() {
        return parseRow();
    }

    // -------------------------------------------------------------
    // Core CSV parsing logic (RFC-compliant)
    // -------------------------------------------------------------
    private List<String> parseRow() {
        List<String> row = new List<String>();
        String current = '';
        Boolean inQuotes = false;

        while (pos < length) {
            String ch = csv.substring(pos, pos + 1);

            // Inside quoted cell
            if (inQuotes) {

                // Escaped quote ""
                if (ch == '"' && peek() == '"') {
                    current += '"';
                    pos += 2;
                    continue;
                }

                // Closing quote
                if (ch == '"') {
                    inQuotes = false;
                    pos++;
                    continue;
                }

                // Regular character
                current += ch;
                pos++;
                continue;
            }

            // Outside quoted cell
            if (ch == '"') {
                inQuotes = true;
                pos++;
                continue;
            }

            // Comma = end of cell
            if (ch == ',') {
                row.add(current);
                current = '';
                pos++;
                continue;
            }

            // Newline = end of row
            if (ch == '\n') {
                pos++;
                row.add(current);
                return row;
            }

            // Normal char
            current += ch;
            pos++;
        }

        // End of string → final value
        row.add(current);
        return row;
    }

    // Look ahead 1 character without consuming it
    private String peek() {
        if (pos + 1 >= length) return null;
        return csv.substring(pos + 1, pos + 2);
    }
}