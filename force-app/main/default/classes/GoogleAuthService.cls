/**
 * @description Exchanges a signed service-account JWT for a Google OAuth access
 *   token (jwt-bearer flow). Credentials (client_email + private key) come from
 *   Google_Calendar_Config__mdt via GoogleCalendarHelper — never hard-coded.
 *   (SE-1047)
 */
public class GoogleAuthService {

    private static final String TOKEN_URI = 'https://oauth2.googleapis.com/token';

    /**
     * @description Thrown when service-account credentials are missing or the
     *   Google token exchange fails.
     */
    public class GoogleAuthException extends Exception {}

    /**
     * @description Test-only access-token override. When set during a test run, the
     *   token exchange (JWT signing + callout) is bypassed and this value is returned,
     *   so callout-heavy flows can be covered without a live private key. Has no effect
     *   outside test context (guarded by Test.isRunningTest()).
     */
    @TestVisible
    private static String tokenOverride;

    /**
     * @description Exchanges a signed service-account JWT for a Google OAuth2
     *   access token using the jwt-bearer flow.
     * @param userEmail Workspace user to impersonate (sub claim, domain-wide delegation).
     * @return OAuth2 access token.
     */
    public static String getAccessToken(String userEmail) {
        if (Test.isRunningTest() && String.isNotBlank(tokenOverride)) {
            return tokenOverride;
        }
        String clientEmail = GoogleCalendarHelper.getServiceAccountEmail('Default');
        String privateKey  = GoogleCalendarHelper.getPrivateKey('Default');

        if (String.isBlank(clientEmail) || String.isBlank(privateKey)) {
            throw new GoogleAuthException(
                'Google service-account credentials not configured (Google_Calendar_Config__mdt "Default").'
            );
        }

        String jwt = GoogleJWTService.generateJWT(clientEmail, privateKey, userEmail);

        HttpRequest req = new HttpRequest();
        req.setEndpoint(TOKEN_URI);
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/x-www-form-urlencoded');
        req.setBody(
            'grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer' +
            '&assertion=' + jwt
        );

        HttpResponse res = new Http().send(req);

        Map<String, Object> tokenResponse =
            (Map<String, Object>) JSON.deserializeUntyped(res.getBody());

        Object token = tokenResponse.get('access_token');
        if (token == null) {
            throw new GoogleAuthException(
                'Token exchange failed (HTTP ' + res.getStatusCode() + '): ' + res.getBody()
            );
        }
        return (String) token;
    }
}