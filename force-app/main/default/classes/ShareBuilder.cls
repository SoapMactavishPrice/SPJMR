public class ShareBuilder {

    public static List<SObject> buildShares(
        String objectApiName,
        Map<Id, Id> recordToProgramMap,
        Map<Id, List<Program_Team_Members__c>> programMembers
    ) {

        List<SObject> shareRecords = new List<SObject>();

        String shareObjectName = objectApiName.replace('__c','__Share');
        system.debug('share Object name: '+shareObjectName);
        system.debug('recordToProgramMap: '+recordToProgramMap);
        system.debug('programMembers: '+programMembers);
        for (Id recordId : recordToProgramMap.keySet()) {

            Id programId = recordToProgramMap.get(recordId);
            system.debug('Program Id: '+programId);
            List<Program_Team_Members__c> members =
                programMembers.get(programId);
            system.debug('Members '+members);
            if (members == null) continue;

            for (Program_Team_Members__c member : members) {
                system.debug('Access Level '+member.AccessLevel__c);
                if (String.isBlank(member.AccessLevel__c)) continue;

                SObject share =
                    (SObject) Type.forName(shareObjectName).newInstance();

                share.put('ParentId', recordId);
                share.put('UserOrGroupId', member.User__c);
                share.put('AccessLevel', member.AccessLevel__c);
                share.put('RowCause', 'Manual');
                system.debug('Adding Share Record to List: '+share);
                shareRecords.add(share);
            }
        }

        return shareRecords;
    }
}