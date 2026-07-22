@IsTest
private class LeadPublicAPIExceptionTest {
    @IsTest
    static void canBeThrownAndCaught() {
        Boolean caught = false;
        try {
            throw new LeadPublicAPIException('boom');
        } catch (LeadPublicAPIException e) {
            caught = true;
            System.assertEquals('boom', e.getMessage());
        }
        System.assert(caught, 'Exception should have been caught');
    }
}