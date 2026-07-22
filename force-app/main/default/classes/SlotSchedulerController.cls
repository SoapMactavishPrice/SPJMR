public without sharing class SlotSchedulerController {
    
    /**
     * Fetch slots in a 5-day rolling window
     * starting from the earliest upcoming slot
     * based on SlotDate__c + SlotStartTime__c.
     * 
     
     */

     @AuraEnabled
     public static List<RoundMaster__c> getAvailableRounds(String pgmCode){
        try {
            List<RoundMaster__c> listRounds = [SELECT Id,Name,RoundNumber__c 
            FROM RoundMaster__c
            WHERE Program__r.Program_Code__c = :pgmCode ORDER BY RoundNumber__c];
            if(!listRounds.isEmpty()){
                return listRounds;
            }
            return new List<RoundMaster__c>();
            
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
     }

     @AuraEnabled
     public static List<PanelMaster__c> getPanels(String pgmCode){
        try {
            List<PanelMaster__c> listPanels = [SELECT Id,Name,ProgramTeam__r.Name FROM PanelMaster__c 
            WHERE ProgramTeam__r.Program__r.Program_Code__c =:pgmCode
            ];
            if(!listPanels.isEmpty()){
                return listPanels;
            }
            return new List<PanelMaster__c>();
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
     }

@AuraEnabled
public static String bookSlotsBulk(String params, List<Id> applicationIds) {
    if (String.isBlank(params)) {
        throw new AuraHandledException('No params found');
    }
    if (applicationIds == null || applicationIds.isEmpty()) {
        throw new AuraHandledException('No applications selected');
    }

    try {
        Map<String, Object> mapParams =
            (Map<String, Object>) JSON.deserializeUntyped(params);

        Id slotId  = (Id) mapParams.get('slotId');
        Id roundId = (Id) mapParams.get('roundId');
        Id panelId = (Id) mapParams.get('panelId');

        Set<Id> appIdSet = new Set<Id>(applicationIds);

        List<ApplicationSlotBooking__c> existing =
            [SELECT Id, Application__r.Name
             FROM ApplicationSlotBooking__c
             WHERE Application__c IN :appIdSet
             AND SlotMaster__c = :slotId];

        if (!existing.isEmpty()) {
            String errApps = '';
            for (ApplicationSlotBooking__c rec : existing) {
                errApps += rec.Application__r.Name + ', ';
            }
            throw new AuraHandledException(
                'This slot is already booked for: ' + errApps
            );
        }

        List<ApplicationSlotBooking__c> toInsert = new List<ApplicationSlotBooking__c>();
        for (Id appId : appIdSet) {
            toInsert.add(new ApplicationSlotBooking__c(
                Application__c = appId,
                SlotMaster__c = slotId,
                RoundMaster__c = roundId,
                Panel_Master__c = panelId,
                BookingState__c = 'Booked'
            ));
        }

        insert toInsert;
        return 'Booking successful';

    } catch (AuraHandledException ahe) {
        // ✅ Let Salesforce send this message to LWC as-is
        throw ahe;
    } catch (Exception e) {
        // ✅ Only wrap unexpected exceptions
        throw new AuraHandledException(
            'Unexpected error while booking slots: ' + e.getMessage()
        );
    }
}




    @AuraEnabled
    public static Boolean getBookedSlots(String pgmCode,String slotId){
        try {
            List<ApplicationSlotBooking__c> bookedSlots = [
                SELECT Id FROM ApplicationSlotBooking__c
                WHERE SlotMaster__c=:slotId AND
                Application__r.Program__r.Program_Code__c = :pgmCode
                AND Application__r.Applicant__r.PersonEmail  = :UserInfo.getUserEmail()
            ];

            system.debug(bookedSlots.size());

            if(bookedSlots.isEmpty()){
                return true;
            }
            return false;
            
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    @AuraEnabled
    public static List<LocationMaster__c> getLocations(){
        try {
            List<LocationMaster__c> listLocations = [SELECT Id,LocationName__c,Name,Status__c
            FROM LocationMaster__c WHERE Status__c = 'Available'
            ORDER BY LocationName__c ASC];

            if(listLocations.isEmpty()){
                return new List<LocationMaster__c>();
            }
            return listLocations;

        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    @AuraEnabled
    public static List<SlotMaster__c> getSlots(String programCode, String locationId) {
        System.debug('programCode: ' + programCode);
        System.debug('locationId: ' + locationId);
        
        if (String.isBlank(programCode) || String.isBlank(locationId)) {
            return new List<SlotMaster__c>();
        }
        
        Date today = Date.today(); 
        Time nowTime = Time.newInstance(System.now().hour(), System.now().minute(), System.now().second(), 0);
        
        // ✅ Step 1: Find earliest upcoming slot (today with future time OR future dates)
        List<SlotMaster__c> earliestList = [
            SELECT SlotDate__c, SlotStartTime__c, Capacity__c,BookedCapacity__c
            FROM SlotMaster__c
            WHERE Program_Master__r.Program_Code__c = :programCode
              AND LocationMaster__c = :locationId
              AND (
                    SlotDate__c > :today OR
                    (SlotDate__c = :today AND SlotStartTime__c > :nowTime)
                  )
            ORDER BY SlotDate__c ASC, SlotStartTime__c ASC
            LIMIT 1
        ];
        
        if (earliestList.isEmpty()) {
            return new List<SlotMaster__c>();
        }
        
        SlotMaster__c earliest = earliestList[0];
        Date windowStart = earliest.SlotDate__c;
        Date windowEnd = windowStart.addDays(50);
        
        // ✅ Step 2: Return slots inside the window
        return [
            SELECT Id, Name, Program_Master__c, LocationMaster__c,
                   SlotDate__c, SlotStartTime__c, SlotEndTime__c,
                   Capacity__c, BookedCapacity__c,LocationMaster__r.LocationName__c
            FROM SlotMaster__c
            WHERE Program_Master__r.Program_Code__c = :programCode
              AND LocationMaster__c = :locationId
              AND SlotDate__c >= :windowStart
              AND SlotDate__c < :windowEnd
            ORDER BY SlotDate__c ASC, SlotStartTime__c ASC
        ];
    }
    
    
    /**
     * Book a slot safely with FOR UPDATE to prevent double booking.
     */
    @AuraEnabled
    public static String bookSlot(Id slotId, String programCode) {
        
        if (slotId == null || String.isBlank(programCode) == null ) {
            throw new AuraHandledException('Missing parameters.');
        }
        //system.debug(bookingInfo +'is the boolking info');
        
            User u = [
            SELECT Id, AccountId 
            FROM User
            WHERE Id = :UserInfo.getUserId()
            LIMIT 1
        ];
            
            List<Application__c> apps = [
            SELECT Id FROM Application__c
            WHERE Applicant__c = :u.AccountId AND Program__r.Program_Code__c = :programCode
            LIMIT 1
        ];
            
            if (apps.isEmpty()) {
                throw new AuraHandledException('Application not found.');
            }
            
            String applicationId = apps[0].Id;
            
            
            // ✅ Step 1: Lock slot row to prevent concurrent booking
            List<SlotMaster__c> slotList = [
            SELECT Id, Capacity__c, BookedCapacity__c
            FROM SlotMaster__c
            WHERE Id = :slotId
            FOR UPDATE
        ];
            
            if (slotList.isEmpty()) {
                throw new AuraHandledException('Slot not found.');
            }
            
            SlotMaster__c slot = slotList[0];
            System.debug('slot: ' + slot);
            // ✅ Step 2: Check capacity
            if (slot?.BookedCapacity__c >= slot.Capacity__c) {
                throw new AuraHandledException('Slot full. Please choose another slot.');
            }
            
            List<RoundMaster__c> rounds = [
            SELECT Id
            FROM RoundMaster__c
            WHERE Program__r.Program_Code__c = :programCode
            ORDER BY RoundNumber__c ASC
            LIMIT 1
        ];
            
            // ✅ (Optional) Create booking record
            insert new ApplicationSlotBooking__c(
                Application__c = applicationId,
            SlotMaster__c = slot.Id,
            BookingState__c = 'Booked',
            RoundMaster__c = rounds[0].Id
                );
            
            return 'Booking successful';
        

        // else{
        //     Map<String,Object> bookingDetails =  (Map<String,Object>) JSON.deserializeUntyped(bookingInfo);
        //     String bookingId = (String) bookingDetails.get('bookingId');
        //     List<ApplicationSlotBooking__c> AppSlotList = [SELECT Id 
        //    FROM ApplicationSlotBooking__c 
        //    WHERE Id=:bookingId LIMIT 1];
            
        //     if(AppSlotList.size()>0){
        //         List<SlotMaster__c> slotList = [
        //     SELECT Id, Capacity__c, BookedCapacity__c
        //     FROM SlotMaster__c
        //     WHERE Id = :slotId
        //     FOR UPDATE
        // ];
        //         if (slotList[0]?.BookedCapacity__c >= slotList[0].Capacity__c) {
        //             throw new AuraHandledException('Slot full. Please choose another slot.');
        //         }
                
        //         AppSlotList[0].SlotMaster__c = slotId;
        //         try{
        //             update AppSlotList;
        //             return 'Rescheduled successfully';
        //         }
        //         catch(DmlException e){
        //             system.debug('Could not update Booking '+e.getMessage()+ ' at Line '+e.getLineNumber());
        //         }
        //     }
        // }
        
    //    return ''; 
    }

    
}