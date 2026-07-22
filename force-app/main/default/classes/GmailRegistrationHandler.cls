global class GmailRegistrationHandler
implements Auth.RegistrationHandler {

    global User createUser(Id portalId, Auth.UserData data) {
        User userDet = [
            SELECT Id, Name, Email, Username
            FROM User
            WHERE Email = :data.email
            LIMIT 1
        ];
        return userDet;
    }

    global void updateUser(Id userId, Id portalId, Auth.UserData data) {
    }
}