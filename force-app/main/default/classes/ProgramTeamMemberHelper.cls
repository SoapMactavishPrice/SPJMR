public class ProgramTeamMemberHelper {

    public static void processTeamMemberChanges(List<Program_Team_Members__c> newList, Map<Id, Program_Team_Members__c> oldMap) {
        Set<Id> teamIds = new Set<Id>();
        Set<Id> employeeChangedMembers = new Set<Id>();

        // Step 1: Identify affected Program Teams and members where Employee changed
        for (Program_Team_Members__c member : newList) {
            if (member.Program_Team__c != null)
                teamIds.add(member.Program_Team__c);

            if (Trigger.isUpdate && oldMap != null && oldMap.containsKey(member.Id)) {
                Program_Team_Members__c oldRec = oldMap.get(member.Id);
                if (oldRec.Employee__c != member.Employee__c) {
                    employeeChangedMembers.add(member.Id);
                }
            }
        }

        if (teamIds.isEmpty()) return;

        // Step 2: Fetch Panels related to these Program Teams
        Map<Id, PanelMaster__c> teamToPanel = new Map<Id, PanelMaster__c>(
            [SELECT Id, ProgramTeam__c FROM PanelMaster__c WHERE ProgramTeam__c IN :teamIds]
        );

        if (teamToPanel.isEmpty()) return;

        // Step 3: Fetch Bookings linked to these Panels
        Map<Id, List<ApplicationSlotBooking__c>> panelToBookings = new Map<Id, List<ApplicationSlotBooking__c>>();
        for (ApplicationSlotBooking__c booking : [
            SELECT Id, Panel_Master__c
            FROM ApplicationSlotBooking__c
            WHERE Panel_Master__c IN :teamToPanel.values()
        ]) {
            Id panelId = booking.Panel_Master__c;
            if (!panelToBookings.containsKey(panelId))
                panelToBookings.put(panelId, new List<ApplicationSlotBooking__c>());
            panelToBookings.get(panelId).add(booking);
        }

        if (panelToBookings.isEmpty()) return;

        // Step 4: Fetch existing Evaluations for all related Bookings (bulk)
        Set<Id> allBookingIds = new Set<Id>();
        for (List<ApplicationSlotBooking__c> bookings : panelToBookings.values()) {
            for (ApplicationSlotBooking__c b : bookings)
                allBookingIds.add(b.Id);
        }

        Map<Id, List<Evaluation__c>> bookingToEvaluations = new Map<Id, List<Evaluation__c>>();
        if (!allBookingIds.isEmpty()) {
            for (Evaluation__c e : [
                SELECT Id, Application_Slot_Booking__c, Employee__c
                FROM Evaluation__c
                WHERE Application_Slot_Booking__c IN :allBookingIds
            ]) {
                if (!bookingToEvaluations.containsKey(e.Application_Slot_Booking__c))
                    bookingToEvaluations.put(e.Application_Slot_Booking__c, new List<Evaluation__c>());
                bookingToEvaluations.get(e.Application_Slot_Booking__c).add(e);
            }
        }

        // Step 5: Prepare for DML
        List<Evaluation__c> toUpdate = new List<Evaluation__c>();
        List<Evaluation__c> toInsert = new List<Evaluation__c>();

        for (Program_Team_Members__c member : newList) {
            Id teamId = member.Program_Team__c;
            if (teamId == null) continue;

            PanelMaster__c panel = teamToPanel.get(teamId);
            if (panel == null) continue;

            List<ApplicationSlotBooking__c> bookings = panelToBookings.get(panel.Id);
            if (bookings == null || bookings.isEmpty()) continue;

            //  CASE 1: Employee changed → update all related evaluations for that employee (same team bookings)
            if (employeeChangedMembers.contains(member.Id)) {
                for (ApplicationSlotBooking__c booking : bookings) {
                    if (bookingToEvaluations.containsKey(booking.Id)) {
                        for (Evaluation__c eval : bookingToEvaluations.get(booking.Id)) {
                            if (eval.Employee__c != member.Employee__c) {
                                eval.Employee__c = member.Employee__c;
                                toUpdate.add(eval);
                            }
                        }
                    }
                }
            }

            //  CASE 2: New team member → create evaluations if not already existing
            for (ApplicationSlotBooking__c booking : bookings) {
                Boolean alreadyExists = false;

                if (bookingToEvaluations.containsKey(booking.Id)) {
                    for (Evaluation__c eval : bookingToEvaluations.get(booking.Id)) {
                        if (eval.Employee__c == member.Employee__c) {
                            alreadyExists = true;
                            break;
                        }
                    }
                }

                if (!alreadyExists) {
                    Evaluation__c newEval = new Evaluation__c(
                        Application_Slot_Booking__c = booking.Id,
                        Employee__c = member.Employee__c,
                        Status__c = 'Pending'
                    );
                    toInsert.add(newEval);
                }
            }
        }

        // Step 6: Perform DML
        if (!toUpdate.isEmpty()) update toUpdate;
        if (!toInsert.isEmpty()) insert toInsert;
    }
}