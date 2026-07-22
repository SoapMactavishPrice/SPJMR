public with sharing class FacultyPortal {
    
    public class BookingWrapper {
        @AuraEnabled public ApplicationSlotBooking__c booking { get; set; }
        @AuraEnabled public String evaluationStatus { get; set; }
    }
    
    @AuraEnabled(cacheable=true)
    public static List<SlotMaster__c> getSlotMasterList() {
        String currentUserEmail = UserInfo.getUserEmail();

        List<Account> accList = [
            SELECT Id FROM Account
            WHERE PersonEmail = :currentUserEmail
            LIMIT 1
        ];

        if (accList.isEmpty()) {
            return new List<SlotMaster__c>();
        }

        Account accountEmp = accList[0];

        Set<Id> panelIds = new Set<Id>();
        for (PanelInterviewer__c ptm : [
            SELECT Id, Account__c, PanelMaster__c FROM PanelInterviewer__c
            WHERE Account__c = :accountEmp.Id
        ]) {
            if (ptm.PanelMaster__c != null) panelIds.add(ptm.PanelMaster__c);
        }

        Set<Id> slotIds = new Set<Id>();
        for (ApplicationSlotBooking__c booking : [
            SELECT SlotMaster__c FROM ApplicationSlotBooking__c
            WHERE Panel_Master__c IN :panelIds
            AND SlotMaster__c != null
        ]) {
            slotIds.add(booking.SlotMaster__c);
        }

        return [
            SELECT Id, Name, SlotDate__c, SlotStartTime__c, SlotEndtime__c,
                   Location__c, Status__c, Mode__c,
                   Capacity__c, BookedCapacity__c
            FROM SlotMaster__c
            WHERE Id IN :slotIds
            ORDER BY SlotDate__c ASC, SlotStartTime__c ASC
        ];
    }

    @AuraEnabled(cacheable=true)
    public static List<BookingWrapper> getAssignedSlotBookings() {
        String currentUserEmail = UserInfo.getUserEmail();
        List<ScoringTemplate__c> sctemp = [SELECT Id FROM ScoringTemplate__c LIMIT 3];
        system.debug('Templates are '+sctemp);
        /*Account accountEmp = [
SELECT Id FROM Account WHERE PersonEmail = :currentUserEmail LIMIT 1
];*/
        List<Account> accList = [
            SELECT Id FROM Account 
            WHERE PersonEmail = :currentUserEmail 
            LIMIT 1
        ];
        
        if (accList.isEmpty()) {
            return new List<BookingWrapper>();
        }
        
        Account accountEmp = accList[0];
        
        
        // 2️ Get Program Teams
        Set<Id> panelIds = new Set<Id>();
        for (PanelInterviewer__c ptm : [
            SELECT Id,Account__c,PanelMaster__c FROM PanelInterviewer__c 
            WHERE Account__c = :accountEmp.Id
        ]) {
            if (ptm.PanelMaster__c != null) panelIds.add(ptm.PanelMaster__c);
        }
        system.debug('Got Panel Ids '+panelIds);
        // get panels
        // Set<Id> panelIds = new Set<Id>();
        // for (PanelMaster__c p : [
        //     SELECT Id FROM PanelMaster__c WHERE ProgramTeam__c IN :programTeamIds
        // ]) panelIds.add(p.Id);
        
        //Get Application Slot Bookings with Evaluations
        List<ApplicationSlotBooking__c> bookings = [
            SELECT Id, Name,
            Application__c,
            Application__r.Name,
            Application__r.Applicant__c,
            Application__r.Applicant__r.Name,
            Panel_Master__c,
            Panel_Master__r.Name,
            RoundMaster__c,
            RoundMaster__r.Name,
            SlotMaster__c,
            SlotMaster__r.Name,
            SlotMaster__r.SlotStartTime__c,
            SlotMaster__r.SlotEndtime__c,
            SlotMaster__r.SlotDate__c,
            (SELECT Id, Status__c FROM Evaluations__r)
            FROM ApplicationSlotBooking__c
            WHERE Panel_Master__c IN :panelIds
            ORDER BY CreatedDate DESC
        ];
        
        List<BookingWrapper> wrappedList = new List<BookingWrapper>();
        system.debug('Found Bookings '+bookings);
        for (ApplicationSlotBooking__c b : bookings) {
            String status = 'Pending';
            if (b.Evaluations__r != null && !b.Evaluations__r.isEmpty()) {
                Boolean hasComplete = false;
                for (Evaluation__c e : b.Evaluations__r) {
                    if (e.Status__c == 'Complete') {
                        hasComplete = true;
                        break;
                    }
                }
                status = hasComplete ? 'Complete' : 'Pending';
            }
            BookingWrapper bw = new BookingWrapper();
            bw.booking = b;
            bw.evaluationStatus = status;
            wrappedList.add(bw);
        }
        system.debug('Returning Wrapper '+wrappedList);
        return wrappedList;
    }
}