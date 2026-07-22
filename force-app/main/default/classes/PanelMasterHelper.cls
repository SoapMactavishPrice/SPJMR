public class PanelMasterHelper {

    public static void processPanelEvaluations(List<PanelMaster__c> newList, Map<Id, PanelMaster__c> oldMap) {
        Set<Id> affectedPanelIds = new Set<Id>();
        Map<Id, Id> panelToTeamMap = new Map<Id, Id>();

        // Step 1: Identify panels whose Program_Team__c changed (on update) or are newly inserted
        for (PanelMaster__c panel : newList) {
            Id oldTeam = (oldMap != null && oldMap.containsKey(panel.Id)) ? oldMap.get(panel.Id).ProgramTeam__c : null;

            // Process if new team is added or changed
            if (panel.ProgramTeam__c != null && (Trigger.isInsert || panel.ProgramTeam__c != oldTeam)) {
                affectedPanelIds.add(panel.Id);
                panelToTeamMap.put(panel.Id, panel.ProgramTeam__c);
            }
        }

        if (affectedPanelIds.isEmpty()) return;

        //  Step 2: Get all bookings for affected panels
        Map<Id, List<ApplicationSlotBooking__c>> panelToBookings = new Map<Id, List<ApplicationSlotBooking__c>>();
        Set<Id> allBookingIds = new Set<Id>();
        for (ApplicationSlotBooking__c booking : [
            SELECT Id, Panel_Master__c
            FROM ApplicationSlotBooking__c
            WHERE Panel_Master__c IN :affectedPanelIds
        ]) {
            if (!panelToBookings.containsKey(booking.Panel_Master__c))
                panelToBookings.put(booking.Panel_Master__c, new List<ApplicationSlotBooking__c>());
            panelToBookings.get(booking.Panel_Master__c).add(booking);
            allBookingIds.add(booking.Id);
        }

        if (panelToBookings.isEmpty()) return;

        // Step 3: Get Program Team Members
        Set<Id> teamIds = new Set<Id>(panelToTeamMap.values());
        Map<Id, List<Program_Team_Members__c>> teamToMembers = new Map<Id, List<Program_Team_Members__c>>();
        for (Program_Team_Members__c member : [
            SELECT Id, Employee__c, Program_Team__c
            FROM Program_Team_Members__c
            WHERE Program_Team__c IN :teamIds
        ]) {
            if (!teamToMembers.containsKey(member.Program_Team__c))
                teamToMembers.put(member.Program_Team__c, new List<Program_Team_Members__c>());
            teamToMembers.get(member.Program_Team__c).add(member);
        }

     //  STEP 4: Delete existing evaluations for related bookings (not panels!)
        if (!allBookingIds.isEmpty()) {
            List<Evaluation__c> existingEvals = [
                SELECT Id 
                FROM Evaluation__c 
                WHERE Application_Slot_Booking__c IN :allBookingIds
            ];
            if (!existingEvals.isEmpty()) {
                delete existingEvals;
            }
        }

        //  Step 5: Create new Evaluations
        List<Evaluation__c> toInsert = new List<Evaluation__c>();
        for (Id panelId : affectedPanelIds) {
            Id teamId = panelToTeamMap.get(panelId);
            if (teamId == null || !teamToMembers.containsKey(teamId)) continue;
            List<Program_Team_Members__c> members = teamToMembers.get(teamId);
            List<ApplicationSlotBooking__c> bookings = panelToBookings.get(panelId);

            if (bookings == null || bookings.isEmpty()) continue;

            for (ApplicationSlotBooking__c booking : bookings) {
                for (Program_Team_Members__c member : members) {
                    Evaluation__c eval = new Evaluation__c(
                        Application_Slot_Booking__c = booking.Id,
                        Employee__c = member.Employee__c,
                        Status__c = 'Pending'
                    );
                    toInsert.add(eval);
                }
            }
        }

        if (!toInsert.isEmpty()) insert toInsert;
    }
}