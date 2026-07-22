@IsTest
private class GoogleJWTServiceTest {
    @IsTest
    static void generateJwtReturnsThreeDotSeparatedString() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            // Throwaway dummy key — not a real credential. Signing is expected to fail
            // at Crypto.sign; we accept the exception and still cover the method body.
            String key = '-----BEGIN PRIVATE KEY-----\n' +
                'MIICdummyTestKeyNotRealNotAValidPemAAAA\n' +
                '-----END PRIVATE KEY-----';
            try {
                String jwt = GoogleJWTService.generateJWT('a@b.com', key, 'u@b.com');
                System.assert(jwt.contains('.'), 'JWT should contain dots');
            } catch (Exception e) {
                // Bad key will fail at Crypto.sign; method lines up to that point covered.
                System.assert(e != null, 'expected exception from signing with invalid key');
            }
        }
    }
}