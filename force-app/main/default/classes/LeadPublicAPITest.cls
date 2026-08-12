@IsTest(seeAllData=true)
private class LeadPublicAPITest {

    @IsTest
    static void createLead_handlesMalformedBodyViaCatchPath() {
        RestRequest req = new RestRequest();
        req.requestURI = '/services/apexrest/createLead';
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf('not-json{{{');
        RestContext.request = req;
        RestContext.response = new RestResponse();

        Test.startTest();
        LeadPublicAPI.createLead();
        Test.stopTest();

        // The service should have thrown -> outer catch sets 400
        System.assertEquals(400, RestContext.response.statusCode);
        String body = RestContext.response.responseBody.toString();
        System.assert(body.contains('success'), 'Response should be JSON shaped with success key');
    }

    @IsTest
    static void createLead_emptyArrayBodyReturnsSuccessOutcome() {
        RestRequest req = new RestRequest();
        req.requestURI = '/services/apexrest/createLead';
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf('[]');
        RestContext.request = req;
        RestContext.response = new RestResponse();

        Test.startTest();
        LeadPublicAPI.createLead();
        Test.stopTest();

       
        System.assertNotEquals(null, RestContext.response.responseBody);
        System.assertEquals(201, RestContext.response.statusCode, 'Empty array should succeed with 201');
    }

    @IsTest
    static void createLead_singleRowWithMissingFieldsHitsSuccessPath() {
        // Build a syntactically valid payload with a row that fails the service's row-level
        // validation. The service should still complete without throwing, so the success branch
        // of the outer controller is exercised (apiLog Response/Status + res.statusCode = outcome.statusCode).
        String body = '[{"FirstName":"A","LastName":"","Email":"","Phone":"","Programme":"","CampaignId":""}]';
        RestRequest req = new RestRequest();
        req.requestURI = '/services/apexrest/createLead';
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf(body);
        RestContext.request = req;
        RestContext.response = new RestResponse();

        Test.startTest();
        LeadPublicAPI.createLead();
        Test.stopTest();

        System.assertNotEquals(null, RestContext.response.responseBody);
        System.assertNotEquals(null, RestContext.response.statusCode);
    }

    @IsTest
    static void leadWrapper_fieldsAreSettable() {
        LeadPublicAPI.LeadWrapper w = new LeadPublicAPI.LeadWrapper();
        w.FirstName = 'A';
        w.LastName = 'B';
        w.Email = 'a@b.com';
        w.Phone = '1234567890';
        w.Programme = 'GMP';
        w.CampaignId = '7011s00000XXXXXAAA';
        System.assertEquals('A', w.FirstName);
        System.assertEquals('B', w.LastName);
        System.assertEquals('GMP', w.Programme);
    }
}