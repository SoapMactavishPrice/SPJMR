public with sharing class CcavenueVfController {

    public String orderId { get; set; }
    public Decimal amount { get; set; }

    @RemoteAction
    public static Map<String, String> generateEncRequest(String formData) {

        Map<String, String> response = new Map<String, String>();

        // Fetch keys from Custom Metadata
        List<CC_Avenue_Key__mdt> keys = [
            SELECT MerchantId__c, AccessCode__c, Workingkey__c
            FROM CC_Avenue_Key__mdt
            LIMIT 1
        ];

        if (keys.isEmpty()) {
            response.put('error', 'CCAvenue keys not found');
            return response;
        }

        CC_Avenue_Key__mdt keyRec = keys[0];

        String merchantId = keyRec.MerchantId__c;
        String accessCode = keyRec.AccessCode__c;
        String workingKey = keyRec.Workingkey__c;

        // Generate unique order id
        String orderId = String.valueOf(DateTime.now().getTime());
        String amount = '200.00';

       String redirectUrl = URL.getOrgDomainUrl().toExternalForm()
    + '/apex/CCAvenueResponse';

        // Build plain text as per CCAvenue spec
        String plainText =
            'merchant_id=' + merchantId +
            '&order_id=' + orderId +
            '&amount=' + amount +
            '&currency=INR' +
            '&redirect_url=' + EncodingUtil.urlEncode(redirectUrl, 'UTF-8') +
            '&cancel_url=' + EncodingUtil.urlEncode(redirectUrl, 'UTF-8') +
            '&language=EN';

        // Encrypt request
        String encRequest = encryptCCAvenueRequest(plainText, workingKey);

        response.put('merchantId', merchantId);
        response.put('accessCode', accessCode);
        response.put('encRequest', encRequest);

        return response;
    }

    // AES-128 encryption as per CCAvenue
    private static String encryptCCAvenueRequest(String plainText, String workingKey) {

        Blob key = Crypto.generateDigest(
            'MD5',
            Blob.valueOf(workingKey)
        );

        Blob iv = Blob.valueOf('0000000000000000');

        Blob encrypted = Crypto.encrypt(
            'AES128',
            key,
            iv,
            Blob.valueOf(plainText)
        );

        return EncodingUtil.convertToHex(encrypted).toLowerCase();
    }
}