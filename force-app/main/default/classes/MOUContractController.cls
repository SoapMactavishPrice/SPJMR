public with sharing class MOUContractController {

    /* ============================================
       PROGRAM PICKLIST OPTIONS
    ============================================ */
    @AuraEnabled(cacheable=true)
    public static List<Map<String,String>> getProgramOptions() {

        List<Map<String,String>> result = new List<Map<String,String>>();

        for (Program p : [
            SELECT Id, Name
            FROM Program
            ORDER BY Name
        ]) {
            result.add(new Map<String,String>{
                'label' => p.Name,
                'value' => String.valueOf(p.Id)
            });
        }

        return result;
    }

    /* ============================================
       SLAB MATCHING LOGIC
    ============================================ */
    @AuraEnabled
    public static Map<String,Object> resolveSlab(Id programId, Integer participants) {

        if (programId == null || participants == null) {
            return null;
        }

        List<Slab__c> slabs = [
            SELECT Id, Name, Start_Range__c, End_Range__c
            FROM Slab__c
            WHERE Program_Master__c = :programId
              AND Start_Range__c <= :participants
              AND End_Range__c >= :participants
            LIMIT 1
        ];

        if (slabs.isEmpty()) {
            return null;
        }

        Slab__c slab = slabs[0];

        return new Map<String,Object>{
            'id'    => slab.Id,
            'name'  => slab.Name,
            'start' => slab.Start_Range__c,
            'end'   => slab.End_Range__c
        };
    }

    /* ============================================
       PRIMARY CONTACT FETCH (NULL SAFE)
       Company + Parent Company
    ============================================ */
    @AuraEnabled(cacheable=true)
    public static Map<String,Object> getPrimaryContacts(
        Id leadId,
        Integer pageSize,
        Integer pageNumber
    ) {

        if (leadId == null) {
            return new Map<String,Object>{
                'records' => new List<Company_Contacts__c>(),
                'total'   => 0
            };
        }

        Lead ld = [
            SELECT Id, Company_Master__c
            FROM Lead
            WHERE Id = :leadId
            LIMIT 1
        ];

        if (ld.Company_Master__c == null) {
            return new Map<String,Object>{
                'records' => new List<Company_Contacts__c>(),
                'total'   => 0
            };
        }

        Company_Master__c comp = [
            SELECT Id, Parent_Company_Master__c
            FROM Company_Master__c
            WHERE Id = :ld.Company_Master__c
            LIMIT 1
        ];

        Set<Id> companyIds = new Set<Id>();
        companyIds.add(comp.Id);

        if (comp.Parent_Company_Master__c != null) {
            companyIds.add(comp.Parent_Company_Master__c);
        }

        Integer offsetVal = (pageNumber - 1) * pageSize;

        List<Company_Contacts__c> contacts = [
            SELECT Id, Name, Email__c,
                   Company_Master__r.Name
            FROM Company_Contacts__c
            WHERE Company_Master__c IN :companyIds
              AND Primary_Contact__c = true
            ORDER BY Company_Master__r.Name
            LIMIT :pageSize
            OFFSET :offsetVal
        ];

        Integer totalCount = [
            SELECT COUNT()
            FROM Company_Contacts__c
            WHERE Company_Master__c IN :companyIds
              AND Primary_Contact__c = true
        ];

        return new Map<String,Object>{
            'records' => contacts,
            'total'   => totalCount
        };
    }

    /* ============================================
       SAVE CONTRACT + PROGRAMS + PRIMARY CONTACTS
       ✅ Slab is OPTIONAL Now
    ============================================ */
    @AuraEnabled
    public static String saveMOUContract(
        MOU_Contract__c mou,
        List<Map<String,Object>> programRows,
        List<Id> selectedContactIds,
        Id leadId
    ) {

        try {

            /* ----------------------------
               BASIC VALIDATIONS
            ---------------------------- */
            if (leadId == null)
                throw new AuraHandledException('LeadId is missing.');

            if (mou == null)
                throw new AuraHandledException('Contract details missing.');

            if (programRows == null || programRows.isEmpty())
                throw new AuraHandledException('Please add at least one Program row.');

            /* ----------------------------
               INSERT PARENT CONTRACT
            ---------------------------- */
            mou.Lead__c = leadId;
            insert mou;

            /* ----------------------------
               INSERT CHILD PROGRAMS
               ✅ Slab Optional
            ---------------------------- */
            List<MOU_Contract_Programs__c> children =
                new List<MOU_Contract_Programs__c>();

            Integer rowIndex = 0;

            for (Map<String,Object> row : programRows) {

                rowIndex++;

                Id programId = (Id) row.get('programId');

                Integer participants =
                    Integer.valueOf(String.valueOf(row.get('participants')));

                Id slabId = (Id) row.get('slabId');

                // Program Required
                if (programId == null)
                    throw new AuraHandledException(
                        'Program missing in row #' + rowIndex
                    );

                // Participants Required
                if (participants == null || participants <= 0)
                    throw new AuraHandledException(
                        'Participants invalid in row #' + rowIndex
                    );

                // ✅ Slab is OPTIONAL → No validation

                children.add(new MOU_Contract_Programs__c(
                    MOU_Contract__c = mou.Id,
                    Program_Master__c = programId,
                    No_of_Participants__c = participants,
                    Slab__c = slabId   // ✅ Can be NULL
                ));
            }

            insert children;

            /* ----------------------------
               INSERT PRIMARY CONTACTS
            ---------------------------- */
            if (selectedContactIds != null && !selectedContactIds.isEmpty()) {

                List<MOU_Contract_Primary_Contacts__c> primaryList =
                    new List<MOU_Contract_Primary_Contacts__c>();

                for (Id cid : selectedContactIds) {
                    primaryList.add(new MOU_Contract_Primary_Contacts__c(
                        MOU_Contract__c = mou.Id,
                        Company_Contacts__c = cid
                    ));
                }

                insert primaryList;
            }

            return 'SUCCESS: Contract, Programs & Primary Contacts Saved Successfully!';

        }
        catch (DmlException de) {
            throw new AuraHandledException(
                'DML ERROR: ' + de.getDmlMessage(0)
            );
        }
        catch (AuraHandledException ae) {
            throw ae;
        }
        catch (Exception e) {
            throw new AuraHandledException(
                'GENERAL ERROR: ' + e.getMessage()
            );
        }
    }
}