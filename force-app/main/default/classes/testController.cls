public class testController {
     private Boolean initialized = false;

    private String programmeNames = '';
    private String username = '';
    private String firstName = '';
    private String resetPasswordUrl = '';

    public Id contactIdPassedCtrl { get; set; }

    public String getProfileName() {
        initialise();

        List<User> usersFromContact = [
            SELECT Profile.Name
            FROM User
            WHERE ContactId = :contactIdPassedCtrl
            LIMIT 1
        ];

        if (!usersFromContact.isEmpty()) {
            return usersFromContact[0].Profile.Name;
        }

        return '';
    }

    public String getFirstName() {
        initialise();
        return String.isBlank(firstName) ? 'Applicant' : firstName;
    }

    public String getUsername() {
        initialise();
        return username;
    }

    public String getProgrammeNames() {
        initialise();
        return programmeNames;
    }

    public String getResetPasswordUrl() {
        initialise();
        return resetPasswordUrl;
    }

    private void initialise() {

        if (initialized) {
            return;
        }
        initialized = true;

        resetPasswordUrl =
            'https://platform-energy-10--devorg.sandbox.my.site.com/applicationportal/s/';

        if (contactIdPassedCtrl == null) {
            return;
        }

        List<Account> applicants = [
            SELECT Id,FirstName,RecordType.Name,Phone
            FROM Account
            WHERE Id = :contactIdPassedCtrl
            LIMIT 1
        ];

        if (applicants.isEmpty()) {
            return;
        }

        Account applicant = applicants[0];

        firstName = applicant.FirstName;
        username = applicant.RecordType.Name;
        programmeNames = applicant.Phone;
    }

}