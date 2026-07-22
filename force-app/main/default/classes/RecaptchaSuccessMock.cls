@IsTest
private class RecaptchaSuccessMock implements HttpCalloutMock {
	@TestVisible
    public HttpResponse respond(HttpRequest req) {

        HttpResponse res = new HttpResponse();
        res.setStatusCode(200);
        res.setBody(
            '{"success":true,"score":0.9}'
        );

        return res;
    }
}