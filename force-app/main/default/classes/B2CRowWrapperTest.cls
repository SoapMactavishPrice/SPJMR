@IsTest
private class B2CRowWrapperTest {
    @IsTest
    static void fieldsAreSettableAndReadable() {
        B2CRowWrapper w = new B2CRowWrapper();
        w.name = 'a'; w.email = 'b@c.com'; w.phone = '1'; w.program = 'p';
        w.country = 'IN'; w.state = 'MH'; w.city = 'M'; w.workExp = '2';
        w.examScoreFlag = 'Y'; w.examName = 'CAT'; w.partnerCompany = 'X';
        w.organization = 'Y'; w.source = 'Web'; w.designation = 'D';
        w.age = '25'; w.college = 'C'; w.graduationYear = '2020';
        System.assertEquals('a', w.name);
        System.assertEquals('b@c.com', w.email);
        System.assertEquals('2020', w.graduationYear);
    }
}