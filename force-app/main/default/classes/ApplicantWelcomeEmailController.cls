public without sharing class ApplicantWelcomeEmailController {

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

        List<User> applicants = [
            SELECT Name,FirstName,
                   Username,
                   Programs_Applied__c
            FROM User
            WHERE ContactId = :contactIdPassedCtrl
            LIMIT 1
        ];

        if (applicants.isEmpty()) {
            return;
        }

        User applicant = applicants[0];

        firstName = applicant.FirstName;
        username = applicant.Username;
        programmeNames = applicant.Programs_Applied__c;
    }
}