@IsTest
private class RecaptchaFailureMock implements HttpCalloutMock {
	@TestVisible
    public HttpResponse respond(HttpRequest req) {

        HttpResponse res = new HttpResponse();
        res.setStatusCode(200);
        res.setBody(
            '{"success":false,"error-codes":["invalid-input-response"]}'
        );

        return res;
    }
}