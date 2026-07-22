/**
 * @description Builds signed JWTs for Google service-account OAuth (RS256),
 * used by the Google Calendar integration to obtain access tokens.
 */
public class GoogleJWTService {

    private static String base64UrlEncode(String input) {
        String base64 = EncodingUtil.base64Encode(Blob.valueOf(input));
        return base64.replace('+', '-').replace('/', '_').replace('=', '');
    }

    private static String base64UrlEncode(Blob input) {
        String base64 = EncodingUtil.base64Encode(input);
        return base64.replace('+', '-').replace('/', '_').replace('=', '');
    }

    /**
     * @description Generates a signed RS256 JWT for Google service-account authentication.
     * @param clientEmail The service-account client email used as the JWT issuer.
     * @param privateKey The service-account private key (PEM or JSON-escaped) used to sign the JWT.
     * @param userToImpersonate The user email to impersonate via domain-wide delegation.
     * @return The signed JWT as a header.claim.signature string.
     */
    public static String generateJWT(String clientEmail, String privateKey, String userToImpersonate) {
        Long now = Datetime.now().getTime() / 1000;
        Long exp = now + 3600; // 1 hour

        // Header
        String header = '{"alg":"RS256","typ":"JWT"}';

        // Claim Set
        Map<String, Object> claims = new Map<String, Object>{
            'iss' => clientEmail,
            'scope' => 'https://www.googleapis.com/auth/calendar',
            'aud' => 'https://oauth2.googleapis.com/token',
            'exp' => exp,
            'iat' => now,
            'sub' => userToImpersonate
        };

        String claimSet = JSON.serialize(claims);

        String encodedHeader = base64UrlEncode(header);
        String encodedClaim = base64UrlEncode(claimSet);

        String toSign = encodedHeader + '.' + encodedClaim;

        // Convert private key to Blob. Bulletproof against formatting: tolerates real
        // multi-line PEM, the raw JSON value (literal backslash-n), surrounding markers,
        // and any stray whitespace — leaves only valid base64 before decoding.
        String cleanKey = privateKey
            .replaceAll('-----[^-]*-----', '')  // strip PEM BEGIN/END markers (any text between dashes)
            .replace('\\n', '')                 // strip literal backslash-n (JSON-escaped newlines)
            .replaceAll('[^A-Za-z0-9+/=]', ''); // strip whitespace and any remaining non-base64 chars
        Blob privateKeyBlob = EncodingUtil.base64Decode(cleanKey);

        Blob signature = Crypto.sign('RSA-SHA256', Blob.valueOf(toSign), privateKeyBlob);
        String encodedSignature = base64UrlEncode(signature);

        return encodedHeader + '.' + encodedClaim + '.' + encodedSignature;
    }
}