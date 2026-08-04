public without sharing class ApplicationSlotBookingTriggerHelper {

    public static void deleteEvaluationsRecords(List<ApplicationSlotBooking__c> listAppSlotBookings){
        if(listAppSlotBookings.isEmpty()){
            return;
        }
        Set<Id> appSlotIds = new Set<Id>();
        for(ApplicationSlotBooking__c slot:listAppSlotBookings){
            appSlotIds.add(slot.Id);
        }
        List<Evaluation__c> listEvaluations = [SELECT Id FROM Evaluation__c WHERE
        Application_Slot_Booking__c IN:appSlotIds];

        if(!listEvaluations.isEmpty()){
            delete listEvaluations;
        }
    }
    
    public static void checkForDuplicateRounds(List<ApplicationSlotBooking__c> list_NewSlotBookings,Map<Id,ApplicationSlotBooking__c> newAppSlotMap){
        if(!list_NewSlotBookings.isEmpty()){
             Map<Id,Id> mapApplicationToRound = new Map<Id,Id>();
             Map<Id,Id> mapApplicationToSlot = new Map<Id,Id>();
            for(ApplicationSlotBooking__c slot:list_NewSlotBookings){
                if(!mapApplicationToRound.containsKey(slot.Id)){
                     mapApplicationToRound.put(slot.Application__c,slot.RoundMaster__c);
                     mapApplicationToSlot.put(slot.Id,slot.Application__c);
                }
               
            }
           List<ApplicationSlotBooking__c> list_ApplicationSlots = [SELECT Id, RoundMaster__c, Application__c FROM ApplicationSlotBooking__c WHERE Application__c IN :mapApplicationToRound.keySet()];
            for(ApplicationSlotBooking__c appSlot:list_ApplicationSlots){
                if(mapApplicationToSlot.containsKey(appSlot.Id) && mapApplicationToRound.get(appSlot.Application__c)== appSlot.RoundMaster__c){
                    newAppSlotMap.get(appSlot.Id).addError('An interview with the same round has already been booked for this application');
                }
            }
        }
    }
    
    public static void updateApplicationStateManagement(List<ApplicationSlotBooking__c> list_NewSlotBookings){
        if(!list_NewSlotBookings.isEmpty()){
            Map<Id,Id> mapSlotToApplication = new Map<Id,Id>();
            Map<Id,Integer> mapApplicationToSlotSize = new Map<Id,Integer>();
            Map<Id,Boolean> mapSlotToEval = new Map<Id,Boolean>();
            for(ApplicationSlotBooking__c slot:list_NewSlotBookings){
                if(!mapSlotToApplication.containsKey(slot.Id)){
                     mapSlotToApplication.put(slot.Id,slot.Application__c);
                     mapApplicationToSlotSize.put(slot.Application__c,0);
                }
               
            }
            List<ApplicationSlotBooking__c> list_ApplicationSlots = [SELECT Id,Application__c, RoundMaster__r.ApplicantStateToSetOnBooking__c FROM ApplicationSlotBooking__c WHERE Id IN:mapSlotToApplication.keySet()];
            List<Evaluation__c> list_Evaluations = [SELECT Id,Application_Slot_Booking__c FROM Evaluation__c WHERE Application_Slot_Booking__c IN:mapSlotToApplication.keySet()];
            if(list_Evaluations.size()>0){
                for(Evaluation__c eval:list_Evaluations){
                	mapSlotToEval.put(eval.Application_Slot_Booking__c,true);
            	}
            }

            Map<Id,String> suggestedStateWithApplication = new Map<Id,String>();
            
            if(list_ApplicationSlots.size()>0){
                	for(ApplicationSlotBooking__c appSlot:list_ApplicationSlots){
                        if(mapSlotToApplication.containsKey(appSlot.Id) && mapSlotToEval.containsKey(appSlot.Id)){
						mapApplicationToSlotSize.put(mapSlotToApplication.get(appSlot.Id),mapApplicationToSlotSize.get(appSlot.Application__c)+1);
                	}
                    suggestedStateWithApplication.put(appSlot.Application__c,appSlot?.RoundMaster__r?.ApplicantStateToSetOnBooking__c);
            	}
                
               List<Application__c> list_Applications = [SELECT Id FROM Application__c WHERE Id IN :mapApplicationToSlotSize.keySet()];
                if(list_Applications.size()>0){
                    List<Application__c> updateList = new List<Application__c>();
                    for(Application__c application:list_Applications){
                        Integer size = mapApplicationToSlotSize.get(application.Id);
                        String newStateManagement = 'Interview Round 1';
                        switch on size {
                            when 1{
                                newStateManagement = 'Interview Round 1';
                            }
                            when 2{
                             	 newStateManagement = 'Interview Round 2';   
                            }
                        }
                        application.Applicant_State_Management__c = suggestedStateWithApplication.get(application.Id) == null ? 'Interview Round 1' : suggestedStateWithApplication.get(application.Id);
                        updateList.add(application);
                    }
                    
                    if(!updateList.isEmpty()){
                        try{
                            update updateList;
                        }
                        catch(DMLException e){
                            system.debug('Could not Update Applicant State Management '+e.getMessage());
                        }
                    }
                }
            }
            
            
        }
    }

    private static Map<Id,Integer> getBookedCapacity(Set<Id> slotIds) {
        if(slotIds.isEmpty()){
            return new Map<Id,Integer>();
        }
        Map<Id,Integer> bookedCapacityMap = new Map<Id,Integer>();
        for(AggregateResult ar : [SELECT Count(Id) countVal, SlotMaster__c FROM ApplicationSlotBooking__c WHERE SlotMaster__c IN :slotIds GROUP BY SlotMaster__c]){
            bookedCapacityMap.put((Id)ar.get('SlotMaster__c'),Integer.valueOf((Integer)ar.get('countVal')));
        }

        if(bookedCapacityMap.isEmpty()){
            for(Id eachSlot : slotIds){
                bookedCapacityMap.put(eachSlot,0);
            }
        }

        if(bookedCapacityMap.keySet() != slotIds){
            for(Id eachSlot : slotIds){
                if(!bookedCapacityMap.containsKey(eachSlot)){
                    bookedCapacityMap.put(eachSlot,0);
                }
            }
        }

        return bookedCapacityMap;
    }

    public static void updateSlotBookedCapacity(Map<Id,ApplicationSlotBooking__c> bookingMap){
        if(bookingMap.isEmpty()){
            return;
        }
        Set<Id> slotIds = new Set<Id>();
        for(ApplicationSlotBooking__c booking : bookingMap.values()){
            if(booking.SlotMaster__c != null){
                slotIds.add(booking.SlotMaster__c);
            }
            
        }
        Map<Id,Integer> bookedCapacityMap = getBookedCapacity(slotIds);

        if(bookedCapacityMap.isEmpty()){
            return;
        }
        
        List<SlotMaster__c> slots = new List<SlotMaster__c>();
        for(Id eachSlot : bookedCapacityMap.keySet()){
            SlotMaster__c slot = new SlotMaster__c(Id = eachSlot, BookedCapacity__c = bookedCapacityMap.get(eachSlot));
            slots.add(slot);
        }

        if(!slots.isEmpty()){
            update slots;
        }

    }
}
    
   /*  
    public static void processEvaluations(List<ApplicationSlotBooking__c> newList, Map<Id, ApplicationSlotBooking__c> oldMap) {
        List<Evaluation__c> toInsert = new List<Evaluation__c>();
        List<Evaluation__c> toDelete = new List<Evaluation__c>();
        Set<Id> panelsToFetch = new Set<Id>();

        // Step 1: Identify records to process
        for (ApplicationSlotBooking__c booking : newList) {
            Id oldPanel = (oldMap != null && oldMap.containsKey(booking.Id)) ? oldMap.get(booking.Id).Panel_Master__c : null;
            Id newPanel = booking.Panel_Master__c;

            // Insert Scenario (no oldMap)
            if (oldMap == null && newPanel != null) {
                panelsToFetch.add(newPanel);
                continue;
            }

            // Update Scenarios
            if (oldMap != null) {
                // Case 1: Panel changed to blank → delete only
                if (oldPanel != null && newPanel == null) {
                    toDelete.addAll([
                        SELECT Id FROM Evaluation__c WHERE Application_Slot_Booking__c = :booking.Id
                    ]);
                    continue;
                }

                // Case 2: Panel changed → delete + recreate
                if (oldPanel != newPanel && newPanel != null) {
                    toDelete.addAll([
                        SELECT Id FROM Evaluation__c WHERE Application_Slot_Booking__c = :booking.Id
                    ]);
                    panelsToFetch.add(newPanel);
                }

                // Case 3: Panel unchanged or blank before & after → skip
            }
        }

        // Step 2: Perform deletions
        if (!toDelete.isEmpty()) delete toDelete;

        if (panelsToFetch.isEmpty()) return;

        // Step 3: Fetch Panels and related Teams
        Map<Id, PanelMaster__c> panelMap = new Map<Id, PanelMaster__c>(
            [SELECT Id, ProgramTeam__c FROM PanelMaster__c WHERE Id IN :panelsToFetch]
        );

        // Step 4: Collect all related Program Teams
        Set<Id> teamIds = new Set<Id>();
        for (PanelMaster__c p : panelMap.values()) {
            if (p.ProgramTeam__c != null) teamIds.add(p.ProgramTeam__c);
        }

        if (teamIds.isEmpty()) return;

        // Step 5: Fetch Program Team Members
        Map<Id, List<Program_Team_Members__c>> teamMembersMap = new Map<Id, List<Program_Team_Members__c>>();
        for (Program_Team_Members__c member : [
            SELECT Id, Employee__c, Program_Team__c 
            FROM Program_Team_Members__c 
            WHERE Program_Team__c IN :teamIds
        ]) {
            if (!teamMembersMap.containsKey(member.Program_Team__c)) {
                teamMembersMap.put(member.Program_Team__c, new List<Program_Team_Members__c>());
            }
            teamMembersMap.get(member.Program_Team__c).add(member);
        }

        // Step 6: Create new Evaluations
        for (ApplicationSlotBooking__c booking : newList) {
            Id newPanel = booking.Panel_Master__c;
            if (newPanel == null || !panelMap.containsKey(newPanel)) continue;

            PanelMaster__c panel = panelMap.get(newPanel);
            if (panel.ProgramTeam__c == null || !teamMembersMap.containsKey(panel.ProgramTeam__c)) continue;

            for (Program_Team_Members__c member : teamMembersMap.get(panel.ProgramTeam__c)) {
                Evaluation__c eval = new Evaluation__c(
                    Application_Slot_Booking__c = booking.Id,
                    Employee__c = member.Employee__c,
                    Status__c = 'Pending'
                );
                toInsert.add(eval);
            }
        }

        // Step 7: Insert new evaluations
        if (!toInsert.isEmpty()) insert toInsert;
    }
}
*/