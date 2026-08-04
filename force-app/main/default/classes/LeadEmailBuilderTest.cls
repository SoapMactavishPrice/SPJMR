@IsTest
private class LeadEmailBuilderTest {

    @IsTest
    static void testBuildNormalEmailSingleProgram() {

        Lead l = new Lead(
            FirstName = 'Navaneeth',
            LastName = 'Hari'
        );
        l.Id = '00Q000000000001AAA';

        LeadEmailBuilder.EmailBuilderWrapper wrapper =
            new LeadEmailBuilder.EmailBuilderWrapper();

        wrapper.l = l;
        wrapper.communityUrl = 'https://community.test.com';
        wrapper.programs = new List<String>{ 'PGDM' };

        String body = LeadEmailBuilder.buildNormalEmail(wrapper);

        System.assert(body.contains('Navaneeth Hari'));
        System.assert(body.contains('PGDM'));
        System.assert(body.contains('/VerifyLead?leadId=' + l.Id));
    }

    @IsTest
    static void testBuildNormalEmailMultiplePrograms() {

        Lead l = new Lead(
            FirstName = 'John',
            LastName = 'Doe'
        );
        l.Id = '00Q000000000002AAA';

        LeadEmailBuilder.EmailBuilderWrapper wrapper =
            new LeadEmailBuilder.EmailBuilderWrapper();

        wrapper.l = l;
        wrapper.communityUrl = 'https://community.test.com';
        wrapper.programs = new List<String>{
            'PGDM',
            'GMP',
            'PGEMP'
        };

        String body = LeadEmailBuilder.buildNormalEmail(wrapper);

        System.assert(body.contains('PGDM'));
        System.assert(body.contains('GMP'));
        System.assert(body.contains('PGEMP'));
        System.assert(body.contains('Verify Email'));
    }

    @IsTest
    static void testBuildNormalEmailWithUser() {

        Lead l = new Lead(
            FirstName = 'Jane',
            LastName = 'Smith'
        );

        LeadEmailBuilder.EmailBuilderWrapper wrapper =
            new LeadEmailBuilder.EmailBuilderWrapper();

        wrapper.l = l;
        wrapper.username = 'jane.smith@test.com';
        wrapper.communityUrl = 'https://community.test.com';
        wrapper.programs = new List<String>{
            'PGDM',
            'PGEMP'
        };

        String body = LeadEmailBuilder.buildNormalEmailWithUser(wrapper);

        System.assert(body.contains('Jane'));
        System.assert(body.contains('jane.smith@test.com'));
        System.assert(body.contains('/applicationportal'));
        System.assert(body.contains('PGDM'));
        System.assert(body.contains('PGEMP'));
    }

    @IsTest
    static void testBuildNormalEmailNullNames() {

        Lead l = new Lead();
        l.Id = '00Q000000000003AAA';

        LeadEmailBuilder.EmailBuilderWrapper wrapper =
            new LeadEmailBuilder.EmailBuilderWrapper();

        wrapper.l = l;
        wrapper.communityUrl = 'https://community.test.com';
        wrapper.programs = new List<String>{ 'PGDM' };

        String body = LeadEmailBuilder.buildNormalEmail(wrapper);

        System.assert(
            body.contains('Dear Applicant'),
            'Should default to Applicant when first name is blank'
        );
    }

    @IsTest
    static void testBuildNormalEmailNoPrograms() {

        Lead l = new Lead(
            FirstName = 'Test',
            LastName = 'User'
        );
        l.Id = '00Q000000000004AAA';

        LeadEmailBuilder.EmailBuilderWrapper wrapper =
            new LeadEmailBuilder.EmailBuilderWrapper();

        wrapper.l = l;
        wrapper.communityUrl = 'https://community.test.com';
        wrapper.programs = new List<String>();

        String body = LeadEmailBuilder.buildNormalEmail(wrapper);

        System.assertNotEquals(null, body);
    }
}