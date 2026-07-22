public class BatchGroupRenumberHandler {

    public static void renumberAfterDelete(List<AcademicYear> deletedGroups) {

        // 1️⃣ Collect affected Batch IDs
        Set<Id> batchIds = new Set<Id>();
        for (AcademicYear bg : deletedGroups) {
            if (bg.Batch__c != null) {
                batchIds.add(bg.Batch__c);
            }
        }
        if (batchIds.isEmpty()) return;

        // 2️⃣ Fetch remaining batch groups
        List<AcademicYear> remainingGroups = [
            SELECT Id, Batch__c, Batch_Group_Number__c
            FROM AcademicYear
            WHERE Batch__c IN :batchIds
            ORDER BY Batch__c, Batch_Group_Number__c
        ];

        // 3️⃣ Renumber sequentially per Batch
        Map<Id, Integer> counterMap = new Map<Id, Integer>();
        List<AcademicYear> updates = new List<AcademicYear>();
        Set<Id> affectedBatchGroupIds = new Set<Id>();

        for (AcademicYear bg : remainingGroups) {

            Integer nextNum = counterMap.containsKey(bg.Batch__c)
                ? counterMap.get(bg.Batch__c) + 1
                : 1;

            counterMap.put(bg.Batch__c, nextNum);

            if (bg.Batch_Group_Number__c != nextNum) {
                bg.Batch_Group_Number__c = nextNum;
                updates.add(bg);
                affectedBatchGroupIds.add(bg.Id);
            }
        }

        // 4️⃣ Update Batch Groups
        if (!updates.isEmpty()) {
            update updates;
        }
      

        
       // 4️⃣ Update Batch Groups
if (!updates.isEmpty()) {
    update updates;
}

// 5️⃣ Renumber Terms ONLY ONCE
if (!affectedBatchGroupIds.isEmpty()) {
    TriggerControl.skipTermRenumber = true;
    TermRenumberHandler.renumberAfterBatchGroupChange(affectedBatchGroupIds);
    TriggerControl.skipTermRenumber = false;
}

       
    }
   public static void renumberAfterRestore() {

    List<AcademicYear> groups = [
        SELECT Id,
               Batch__c,
               Batch_Group_Number__c
         //      Original_Batch_Group_Series_Number__c
        FROM AcademicYear];
      //  ORDER BY Batch__c, Original_Batch_Group_Series_Number__c
    

    Map<Id, Integer> counterMap = new Map<Id, Integer>();
    List<AcademicYear> updates = new List<AcademicYear>();
    Set<Id> affectedBatchGroupIds = new Set<Id>();

    for (AcademicYear bg : groups) {

        if (!counterMap.containsKey(bg.Batch__c)) {
            counterMap.put(bg.Batch__c, 1);
        }

        Integer nextNum = counterMap.get(bg.Batch__c);

        if (bg.Batch_Group_Number__c != nextNum) {
            bg.Batch_Group_Number__c = nextNum;
            updates.add(bg);
            affectedBatchGroupIds.add(bg.Id);
        }

        counterMap.put(bg.Batch__c, nextNum + 1);
    }

    if (!updates.isEmpty()) {
        update updates;
    }

    // 🔥 Renumber term codes also
    if (!affectedBatchGroupIds.isEmpty()) {
        TermRenumberHandler.renumberAfterBatchGroupChange(affectedBatchGroupIds);
    }
}
}