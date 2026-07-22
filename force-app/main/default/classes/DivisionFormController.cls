public with sharing class DivisionFormController {

    @AuraEnabled(cacheable=true)
    public static List<Option> getDivisionGroups() {
        List<Option> options = new List<Option>();
        for (Division_Group__c dg : [
            SELECT Id, Name, Is_Specialiation__c
            FROM Division_Group__c
         /* WHERE Name IN (  //start 1001
                'Elective',
                'Fundamental',
                'Specialisation major',
                'Specialisation minor'
            )//1001 end */
            ORDER BY Name
        ]) {
            options.add(new Option(dg.Id, dg.Name, dg.Is_Specialiation__c == true));
        }
        return options;
    }

    /**
     * Get batch-enabled specialisations for a term (Division -> Term -> Batch -> Specialisation).
     * AcademicTerm has AcademicYear.Batch__c; Specialisation__c has Batch__c.
     */
    @AuraEnabled(cacheable=true)
    public static List<Option> getSpecialisationsForTerm(Id termId) {
        List<Option> options = new List<Option>();
        if (termId == null) return options;
        try {
            AcademicTerm term = [SELECT AcademicYear.Batch__c FROM AcademicTerm WHERE Id = :termId LIMIT 1];
            if (term.AcademicYear == null || term.AcademicYear.Batch__c == null) return options;
            Id batchId = term.AcademicYear.Batch__c;
            for (Specialisation__c s : [
                SELECT Id, Name, Specialisation_Name__c, Specialisation_Name__r.Name
                FROM Specialisation__c
                WHERE Batch__c = :batchId
                AND Is_Active__c = true
                ORDER BY Specialisation_Name__r.Name NULLS LAST, Name
            ]) {
                String label = (s.Specialisation_Name__r != null && String.isNotBlank(s.Specialisation_Name__r.Name))
                    ? s.Specialisation_Name__r.Name
                    : (String.isNotBlank(s.Name) ? s.Name : ('Specialisation ' + s.Id));
                options.add(new Option(s.Id, label));
            }
        } catch (Exception e) {
            throw new AuraHandledException('Error fetching specialisations: ' + e.getMessage());
        }
        return options;
    }

    /** Returns Batch__c Id for the term's AcademicYear; used to filter Specialisation record picker. */
    @AuraEnabled(cacheable=true)
    public static Id getBatchIdForTerm(Id termId) {
        if (termId == null) return null;
        try {
            AcademicTerm term = [SELECT AcademicYear.Batch__c FROM AcademicTerm WHERE Id = :termId LIMIT 1];
            return (term.AcademicYear != null) ? term.AcademicYear.Batch__c : null;
        } catch (Exception e) {
            return null;
        }
    }

    @AuraEnabled(cacheable=true)
    public static List<Option> getTermOptions(String batchGroupId) {
        List<Option> options = new List<Option>();
        List<AcademicTerm> terms;
    
        if (String.isNotBlank(batchGroupId)) {
            terms = [
                SELECT Id, Name, AcademicYear.Name
                FROM AcademicTerm
                WHERE AcademicYearId = :batchGroupId
                ORDER BY Term_Start_Date__c DESC NULLS LAST
                LIMIT 500
            ];
        } else {
            terms = [
                SELECT Id, Name, AcademicYear.Name
                FROM AcademicTerm
                WHERE AcademicYearId != null
                ORDER BY Term_Start_Date__c DESC NULLS LAST
                LIMIT 500
            ];
        }
    
        for (AcademicTerm t : terms) {
            String termName = String.isNotBlank(t.Name) ? t.Name : ('Term ' + t.Id);
            String batchGroupName = (t.AcademicYear != null && String.isNotBlank(t.AcademicYear.Name))
                ? t.AcademicYear.Name : null;
            options.add(new Option(t.Id, termName, batchGroupName));
        }
        return options;
    }

    @AuraEnabled(cacheable=true)
    public static String getSObjectTypeName(Id recordId) {
        if (recordId == null) return null;
        return recordId.getSObjectType().getDescribe().getName();
    }

    @AuraEnabled(cacheable=true)
    public static DivisionFormData getDivision(Id recordId) {
        if (recordId == null) return null;
        List<Division__c> divs = [
            SELECT Id, Name, Division_Name__c, SPJIMR_Division_Code__c, Term__c,
                   Division_Group__c, Division_Group__r.Name, Division_Group__r.Is_Specialiation__c,
                   SPJIMR_Specialisation__c,
                   Is_Active__c, Capacity__c, Division_Color__c, OwnerId,
                   CreatedBy.Name, LastModifiedBy.Name, Owner.Name
            FROM Division__c
            WHERE Id = :recordId
            LIMIT 1
        ];
        if (divs.isEmpty()) return null;
        Division__c d = divs[0];
        DivisionFormData data = new DivisionFormData();
        data.recordId = d.Id;
        data.divisionNumber = d.Name;
        data.divisionName = d.Division_Name__c;
        data.divisionCode = d.SPJIMR_Division_Code__c;
        data.termId = d.Term__c;
        data.divisionGroupId = d.Division_Group__c;
        data.divisionGroupName = d.Division_Group__r != null ? d.Division_Group__r.Name : null;
        data.divisionGroupIsSpecialisation = d.Division_Group__r != null
            && d.Division_Group__r.Is_Specialiation__c == true;
        data.specialisationId = d.SPJIMR_Specialisation__c;
        data.isActive = d.Is_Active__c == true;
        data.capacity = d.Capacity__c != null ? Integer.valueOf(d.Capacity__c) : null;
        data.divisionColor = d.Division_Color__c;
        data.ownerId = d.OwnerId;
        data.createdByName = d.CreatedBy != null ? d.CreatedBy.Name : null;
        data.lastModifiedByName = d.LastModifiedBy != null ? d.LastModifiedBy.Name : null;
        data.ownerName = d.Owner != null ? d.Owner.Name : null;
        return data;
    }

    @AuraEnabled
public static Id saveDivision(String payload) {
    try {
        DivisionFormData data = (DivisionFormData) JSON.deserialize(payload, DivisionFormData.class);
        Division__c d;

        if (data.recordId != null) {
            d = [SELECT Id FROM Division__c WHERE Id = :data.recordId LIMIT 1];
        } else {
            d = new Division__c();
        }

        d.Division_Name__c = data.divisionName;
        d.Term__c = data.termId;
        d.Division_Group__c = data.divisionGroupId;
        d.SPJIMR_Specialisation__c = data.specialisationId;
        d.Is_Active__c = data.isActive;
        d.Capacity__c = data.capacity;
        d.Division_Color__c = data.divisionColor;

        upsert d;

        return d.Id;

    } catch (DmlException e) {
        throw new AuraHandledException(e.getDmlMessage(0));
    }
}

    public class Option {
        @AuraEnabled public String value;
        @AuraEnabled public String label;
        @AuraEnabled public String subLabel;
        /** True when Division_Group__c.Is_Specialiation__c is true (division group options only). */
        @AuraEnabled public Boolean isSpecialisation;
        public Option(Id value, String label) {
            this.value = value != null ? String.valueOf(value) : '';
            this.label = label != null ? label : '';
            this.subLabel = null;
            this.isSpecialisation = false;
        }
        public Option(Id value, String label, String subLabel) {
            this.value = value != null ? String.valueOf(value) : '';
            this.label = label != null ? label : '';
            this.subLabel = subLabel;
            this.isSpecialisation = false;
        }
        public Option(Id value, String label, Boolean isSpecialisation) {
            this.value = value != null ? String.valueOf(value) : '';
            this.label = label != null ? label : '';
            this.subLabel = null;
            this.isSpecialisation = isSpecialisation == true;
        }
    }

    public class DivisionFormData {
        @AuraEnabled public Id recordId;
        @AuraEnabled public String divisionNumber;
        @AuraEnabled public String divisionName;
        @AuraEnabled public String divisionCode;
        @AuraEnabled public Id termId;
        @AuraEnabled public Id divisionGroupId;
        @AuraEnabled public String divisionGroupName;
        /** Mirrors Division_Group__c.Is_Specialiation__c for the selected division group. */
        @AuraEnabled public Boolean divisionGroupIsSpecialisation;
        @AuraEnabled public Id specialisationId;
        @AuraEnabled public Boolean isActive;
        @AuraEnabled public Integer capacity;
        @AuraEnabled public String divisionColor;
        @AuraEnabled public Id ownerId;
        @AuraEnabled public String createdByName;
        @AuraEnabled public String lastModifiedByName;
        @AuraEnabled public String ownerName;
    }
}