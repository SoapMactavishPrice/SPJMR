public with sharing class ApplicationFormPDFController {

    public Application__c application {get;set;}
    public List<SectionVM> sections {get;set;}

    public ApplicationFormPDFController(ApexPages.StandardController std){
        application = (Application__c) std.getRecord();
        sections = new List<SectionVM>();
        loadData();
    }

    private void loadData() {

        // ✅ Fetch Application Form Record
        Application_Form__c form = [
            SELECT Id, Form_HTML__c
            FROM Application_Form__c
            WHERE Program__c = :application.Program__c
            LIMIT 1
        ];

        if(form == null || String.isBlank(form.Form_HTML__c)) return;

        // ✅ DOWNLOAD JSON FROM URL IN Form_HTML__c
        String jsonText = downloadJSON(form.Form_HTML__c);
        if(String.isBlank(jsonText)) return;

        // ✅ PARSE
        List<Object> formSections;
        try {
            formSections = (List<Object>) JSON.deserializeUntyped(jsonText);
        } catch (Exception ex) {
            System.debug('❌ JSON Parse Failed: ' + ex.getMessage());
            return;
        }

        // ✅ BUILD PDF DATA
        for (Object secObj : formSections) {
            Map<String, Object> secMap = (Map<String, Object>) secObj;

            SectionVM sec = new SectionVM();
            sec.sectionName = (String) secMap.get('label');
            sec.repeatable = (Boolean) secMap.get('repeatable');
            List<Object> fields = (List<Object>) secMap.get('fields');
            String objName = (String) secMap.get('objectApiName');

            // ✅ REPEATABLE SECTION
            if (sec.repeatable && objName != null) {
                List<Map<String, Object>> rows = fetchChildRecords(objName);

                for (Map<String, Object> childRow : rows) {
                    RowVM row = new RowVM();
                    for (Object f : fields) {
                        Map<String, Object> fMap = (Map<String, Object>) f;
                        String api = (String) fMap.get('apiName');
                        String label = (String) fMap.get('label');

                        String value = childRow.containsKey(api) ? String.valueOf(childRow.get(api)) : '';
                        row.cells.add(new CellVM(label, value));
                    }
                    sec.rows.add(row);
                }
            }

            // ✅ NON-REPEATABLE SECTION (Application__c fields)
            else {
                RowVM row = new RowVM();
                for (Object f : fields) {
                    Map<String, Object> fMap = (Map<String, Object>) f;
                    String api = (String) fMap.get('apiName');
                    String label = (String) fMap.get('label');

                    String value = safeGet(application, api);
                    row.cells.add(new CellVM(label, value));
                }
                sec.rows.add(row);
            }

            sections.add(sec);
        }
    }

    // ✅ DOWNLOAD JSON FROM URL
    private String downloadJSON(String url){
        Http h = new Http();
        HttpRequest req = new HttpRequest();
        req.setEndpoint(url);
        req.setMethod('GET');
        req.setHeader('Content-Type','application/json');

        HttpResponse res = h.send(req);
        return res.getBody();
    }

    // ✅ DYNAMIC CHILD QUERY
    private List<Map<String,Object>> fetchChildRecords(String objName){
        try {
            Schema.SObjectType objType = Schema.getGlobalDescribe().get(objName);
            if (objType == null) return new List<Map<String,Object>>();

            Map<String, Schema.SObjectField> fields = objType.getDescribe().fields.getMap();

            String soql = 'SELECT Id';
            for (String f : fields.keySet())
                soql += ', ' + f;

            if (fields.containsKey('Application__c'))
                soql += ' FROM ' + objName + ' WHERE Application__c = :application.Id';
            else
                return new List<Map<String,Object>>();

            List<SObject> sobjs = Database.query(soql);

            List<Map<String,Object>> output = new List<Map<String,Object>>();
            for (SObject sobj : sobjs) {
                Map<String,Object> r = new Map<String,Object>();
                for (String k : fields.keySet())
                    r.put(k, sobj.get(k));
                output.add(r);
            }
            return output;

        } catch (Exception e) {
            return new List<Map<String,Object>>();
        }
    }

    private String safeGet(SObject sobj, String api){
        try {
            Object val = sobj.get(api);
            return val == null ? '' : String.valueOf(val);
        } catch (Exception e) {
            return '';
        }
    }

    // DATA STRUCTURES
    public class SectionVM {
        public String sectionName {get;set;}
        public Boolean repeatable {get;set;}
        public List<RowVM> rows {get;set;}
        public SectionVM(){ rows = new List<RowVM>(); }
    }

    public class RowVM {
        public List<CellVM> cells {get;set;}
        public RowVM(){ cells = new List<CellVM>(); }
    }

    public class CellVM {
        public String label {get;set;}
        public String value {get;set;}
        public CellVM(String l, String v){ label = l; value = v; }
    }
}