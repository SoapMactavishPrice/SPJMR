public without sharing class CcAvenueCryptoCompat {

    public static String encryptLikeCurrentLwc(String plainText, String workingKey, String ivHex) {
        if (String.isBlank(plainText)) {
            throw new AuraHandledException('plainText is required');
        }
        if (String.isBlank(workingKey)) {
            throw new AuraHandledException('workingKey is required');
        }
        if (String.isBlank(ivHex)) {
            throw new AuraHandledException('ivHex is required');
        }

        // CryptoJS.MD5(workingKey)
        Blob aesKey = Crypto.generateDigest('MD5', Blob.valueOf(workingKey));

        // CryptoJS.enc.Hex.parse(ivHex)
        Blob iv = EncodingUtil.convertFromHex(ivHex);

        // This is the closest Apex equivalent to CryptoJS AES/CBC/Pkcs7.
        Blob encrypted = Crypto.encrypt('AES128', aesKey, iv, Blob.valueOf(plainText));

        return EncodingUtil.convertToHex(encrypted).toLowerCase();
    }

    public static String buildEncryptedRequestLikeCurrentLwc(
        String merchantId,
        String orderId,
        String amount,
        String redirectUrl,
        String workingKey,
        String ivHex
    ) {
        String plainText =
            'merchant_id=' + merchantId +
            '&order_id=' + orderId +
            '&amount=' + amount +
            '&currency=INR' +
            '&redirect_url=' + redirectUrl +
            '&cancel_url=' + redirectUrl +
            '&language=EN' +
            '&upiPaymentFlag=Intent,QR' +
            '&billing_name=';

        return encryptLikeCurrentLwc(plainText, workingKey, ivHex);
    }

    public static String buildPaymentUrlLikeCurrentLwc(
        String basePaymentUrl,
        String accessCode,
        String merchantId,
        String orderId,
        String amount,
        String redirectUrl,
        String workingKey,
        String ivHex
    ) {
        String encRequest = buildEncryptedRequestLikeCurrentLwc(
            merchantId,
            orderId,
            amount,
            redirectUrl,
            workingKey,
            ivHex
        );

        return basePaymentUrl +
            '&encRequest=' + encRequest +
            '&access_code=' + accessCode;
    }
}