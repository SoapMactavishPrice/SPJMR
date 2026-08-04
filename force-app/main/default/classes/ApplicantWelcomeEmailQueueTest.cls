@IsTest
private class ApplicantWelcomeEmailQueueTest {

    
    @IsTest
    static void testFormatProgrammeList_Empty() {

        System.assertEquals(
            '',
            ApplicantWelcomeEmailQueue.formatProgrammeList(
                new List<String>()
            )
        );
    }

    @IsTest
    static void testFormatProgrammeList_One() {

        System.assertEquals(
            'PGDM',
            ApplicantWelcomeEmailQueue.formatProgrammeList(
                new List<String>{'PGDM'}
            )
        );
    }

    @IsTest
    static void testFormatProgrammeList_Two() {

        System.assertEquals(
            'PGDM and GMP',
            ApplicantWelcomeEmailQueue.formatProgrammeList(
                new List<String>{'PGDM', 'GMP'}
            )
        );
    }

    @IsTest
    static void testFormatProgrammeList_Three() {

        System.assertEquals(
            'PGDM, GMP, and PGP',
            ApplicantWelcomeEmailQueue.formatProgrammeList(
                new List<String>{'PGDM', 'GMP', 'PGP'}
            )
        );
    }
}