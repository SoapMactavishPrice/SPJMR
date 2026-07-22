public class ProgramPicklistUpdater {

    public static void updatePicklist(List<Program> programs) {

        Set<String> newValues = new Set<String>();
        for (Program p : programs) {
            if (p.Name != null) newValues.add(p.Name.trim());
        }
        if (newValues.isEmpty()) return;

        SimpleMetadataService.MetadataPort svc = new SimpleMetadataService.MetadataPort();

        // STEP 1 — READ existing Global Picklist XML
        String readXml = (String) svc.readMetadata('GlobalValueSet', new String[]{ 'Program_Picklist' });

        // Extract existing values
        Set<String> existing = new Set<String>();
        List<String> extracted = readXml.split('<value>');
        for (String block : extracted) {
            if (block.contains('<fullName>')) {
                String val = block.substringAfter('<fullName>').substringBefore('</fullName>');
                existing.add(val);
            }
        }

        // STEP 2 — Merge new values
        List<String> allValues = new List<String>();
        allValues.addAll(existing);
        for (String v : newValues) {
            if (!existing.contains(v)) allValues.add(v);
        }

        // STEP 3 — Build XML
        String body = '';
        for (String val : allValues) {
            body +=
                '<value>' +
                '<fullName>' + val + '</fullName>' +
                '<default>false</default>' +
                '<label>' + val + '</label>' +
                '</value>';
        }

        String finalXml =
            '<met:metadata xsi:type="met:GlobalValueSet">' +
                '<met:fullName>Program_Picklist</met:fullName>' +
                '<met:sorted>false</met:sorted>' +
                '<met:customValueSet>' +
                    body +
                '</met:customValueSet>' +
            '</met:metadata>';

        // STEP 4 — Do update
        svc.updateMetadata(new SimpleMetadataService.SimpleUpdateMetadata[]{ 
            new SimpleMetadataService.SimpleUpdateMetadata()
        }, finalXml);
    }
}