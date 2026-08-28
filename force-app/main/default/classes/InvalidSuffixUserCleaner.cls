public with sharing class InvalidSuffixUserCleaner {

    private static final String SUFFIX = '.invalid';

    public class CleanupResult {
        public Integer totalApplicationNamesProvided = 0;
        public List<String> applicationNamesNotFound = new List<String>();
        public Integer applicationsMatched = 0;
        public Integer usersMatchedBeforeFilter = 0;
        public Integer usersEligibleForUpdate = 0;
        public Integer usersSkippedDueToConflict = 0;
        public Integer usersUpdatedSuccessfully = 0;
        public Integer usersFailedToUpdate = 0;
        public List<String> conflictDetails = new List<String>();
        public List<String> failureDetails = new List<String>();
    }

    public static CleanupResult cleanUserInvalidSuffix(List<String> applicationNames) {
        CleanupResult result = new CleanupResult();

        if (applicationNames == null || applicationNames.isEmpty()) {
            System.debug(LoggingLevel.WARN, 'InvalidSuffixUserCleaner: No Application Names provided.');
            return result;
        }

        Set<String> appNameSet = new Set<String>();
        for (String n : applicationNames) {
            if (String.isNotBlank(n)) {
                appNameSet.add(n);
            }
        }
        result.totalApplicationNamesProvided = appNameSet.size();

        List<Application__c> apps = queryApplications(appNameSet);

        Set<String> foundAppNames = new Set<String>();
        Set<String> personEmails = new Set<String>();

        for (Application__c app : apps) {
            foundAppNames.add(app.Name);
            if (app.Applicant__r != null && String.isNotBlank(app.Applicant__r.PersonEmail)) {
                personEmails.add(app.Applicant__r.PersonEmail);
            }
        }

        for (String n : appNameSet) {
            if (!foundAppNames.contains(n)) {
                result.applicationNamesNotFound.add(n);
            }
        }
        result.applicationsMatched = apps.size();

        System.debug('===== APPLICATION LOOKUP SUMMARY =====');
        System.debug('Application Names provided: ' + result.totalApplicationNamesProvided);
        System.debug('Applications matched: ' + result.applicationsMatched);
        System.debug('Application Names not found: ' + result.applicationNamesNotFound);
        System.debug('Distinct Applicant PersonEmails resolved: ' + personEmails.size());

        if (personEmails.isEmpty()) {
            System.debug(LoggingLevel.WARN, 'InvalidSuffixUserCleaner: No Applicant PersonEmail values resolved. Nothing to do.');
            return result;
        }

        List<User> matchedUsers = [
            SELECT Id, Email, Username
            FROM User
            WHERE Email IN :personEmails
        ];
        result.usersMatchedBeforeFilter = matchedUsers.size();

        Map<Id, User> candidateUsers = new Map<Id, User>();
        Map<Id, String> proposedUsernames = new Map<Id, String>();

        for (User u : matchedUsers) {
            Boolean emailNeedsChange = (u.Email != null && u.Email.endsWith(SUFFIX));
            Boolean usernameNeedsChange = (u.Username != null && u.Username.endsWith(SUFFIX));

            if (!emailNeedsChange && !usernameNeedsChange) {
                continue;
            }

            String newEmail = emailNeedsChange ? u.Email.removeEnd(SUFFIX) : u.Email;
            String newUsername = usernameNeedsChange ? u.Username.removeEnd(SUFFIX) : u.Username;

            User copy = new User(Id = u.Id, Email = newEmail, Username = newUsername);
            candidateUsers.put(u.Id, copy);

            if (usernameNeedsChange) {
                proposedUsernames.put(u.Id, newUsername);
            }
        }
        result.usersEligibleForUpdate = candidateUsers.size();

        System.debug('===== USER MATCH SUMMARY =====');
        System.debug('Users matched by Email (before .invalid filter): ' + result.usersMatchedBeforeFilter);
        System.debug('Users eligible for update (.invalid suffix present): ' + result.usersEligibleForUpdate);

        if (candidateUsers.isEmpty()) {
            System.debug('InvalidSuffixUserCleaner: No eligible Users to update.');
            return result;
        }

        Set<String> conflictingUsernames = detectUsernameConflicts(proposedUsernames, candidateUsers);

        List<User> usersToUpdate = new List<User>();

        for (Id uid : candidateUsers.keySet()) {
            User u = candidateUsers.get(uid);
            String proposedUsername = proposedUsernames.get(uid);

            if (proposedUsername != null && conflictingUsernames.contains(proposedUsername)) {
                result.usersSkippedDueToConflict++;
                String msg = 'Skipped User Id=' + uid + ' due to Username conflict. Proposed Username=' + proposedUsername;
                result.conflictDetails.add(msg);
                System.debug(LoggingLevel.WARN, msg);
                continue;
            }
            usersToUpdate.add(u);
        }

        if (!usersToUpdate.isEmpty()) {
            List<Database.SaveResult> saveResults = Database.update(usersToUpdate, false);

            for (Integer i = 0; i < saveResults.size(); i++) {
                Database.SaveResult sr = saveResults[i];
                if (sr.isSuccess()) {
                    result.usersUpdatedSuccessfully++;
                } else {
                    result.usersFailedToUpdate++;
                    String errMsg = 'User update failed for Id=' + usersToUpdate[i].Id + ' | Errors=' + sr.getErrors();
                    result.failureDetails.add(errMsg);
                    System.debug(LoggingLevel.ERROR, errMsg);
                }
            }
        }

        System.debug('===== USER UPDATE SUMMARY =====');
        System.debug('Users skipped due to conflict: ' + result.usersSkippedDueToConflict);
        System.debug('Users updated successfully: ' + result.usersUpdatedSuccessfully);
        System.debug('Users failed to update: ' + result.usersFailedToUpdate);
        System.debug('===== COMPLETE =====');

        return result;
    }

    private static List<Application__c> queryApplications(Set<String> appNameSet) {
        return [
            SELECT Id, Name, Applicant__c, Applicant__r.PersonEmail
            FROM Application__c
            WHERE Name IN :appNameSet
              AND Applicant__c != null
        ];
    }

    private static Set<String> detectUsernameConflicts(Map<Id, String> proposedUsernames, Map<Id, User> candidateUsers) {
        Set<String> conflictingUsernames = new Set<String>();

        if (proposedUsernames.isEmpty()) {
            return conflictingUsernames;
        }

        Set<String> proposedValues = new Set<String>(proposedUsernames.values());

        List<User> existingMatches = [
            SELECT Id, Username
            FROM User
            WHERE Username IN :proposedValues
        ];

        for (User existing : existingMatches) {
            if (!proposedUsernames.containsKey(existing.Id)) {
                conflictingUsernames.add(existing.Username);
            }
        }

        Map<String, Integer> usernameCounts = new Map<String, Integer>();
        for (String uname : proposedUsernames.values()) {
            usernameCounts.put(uname, (usernameCounts.containsKey(uname) ? usernameCounts.get(uname) : 0) + 1);
        }
        for (String uname : usernameCounts.keySet()) {
            if (usernameCounts.get(uname) > 1) {
                conflictingUsernames.add(uname);
            }
        }

        return conflictingUsernames;
    }
}