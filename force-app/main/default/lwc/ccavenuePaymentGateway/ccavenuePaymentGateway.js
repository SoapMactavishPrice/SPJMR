import { LightningElement, api } from 'lwc';
import getKeys from '@salesforce/apex/CcavenuePaymentHandler.generatePaymentLink';
import createOrUpdateOrder from '@salesforce/apex/CcavenuePaymentHandler.createOrUpdateOrder';
import { loadScript } from 'lightning/platformResourceLoader';
import CRYPTOJS from '@salesforce/resourceUrl/CryptoJS';

export default class CcavenuePaymentGateway extends LightningElement {

    isLoading = false;
    errorMessage = '';
    cryptoLoaded = false;
    disableButton = false;
    _programCode;

    @api
    get programCode() {
        return this._programCode;
    }

    set programCode(value) {
        this._programCode = value;
    }

    // 🔹 Load CryptoJS
    connectedCallback() {
        loadScript(this, CRYPTOJS)
            .then(() => {
                this.cryptoLoaded = true;
                console.log('Pgm Code ',this._programCode)
                console.log('CryptoJS loaded successfully');
            })
            .catch((error) => {
                this.errorMessage = 'Failed to load encryption library';
                console.error('CryptoJS load error:', error);
            });
    }

    // 🔹 Generate payment link
    getLink() {

        if (!this.cryptoLoaded) {
            this.errorMessage = 'Encryption library not ready yet, please try again';
            return;
        }

        this.isLoading = true;
        this.errorMessage = '';

        getKeys()
            .then((result) => {

                if (result.ERROR) {
                    this.errorMessage = result.ERROR;
                    return;
                }

                const { merchantId, accessCode, orderId, iv,redirect_url,payment_url } = result;

                // const redirectUrl = 
                //     'https://platform-energy-10--uat.sandbox.my.site.com/applicationportal/s/paymentpage';

                const amount = '200';
                console.log('Got Params: ',merchantId, accessCode, orderId, iv, redirect_url, payment_url);
                const plainText =
                    'merchant_id=' + merchantId +
                    '&order_id=' + orderId +
                    '&amount=' + amount +
                    '&currency=INR' +
                    '&redirect_url=' + redirect_url +
                    '&cancel_url=' + redirect_url +
                    '&language=EN' +
                    '&upiPaymentFlag=Intent,QR' +
                    '&billing_name='
                console.log('Order Id '+orderId)
                console.log('Plain Text '+plainText)

                // 🔹 Encrypt using metadata IV
                //const encRequest = this.encryptCCAvenue(plainText, workingKey, iv);

                const paymentUrl =payment_url;
                    // 'https://test.ccavenue.com/transaction/transaction.do?command=initiateTransaction'
                    //+ '&encRequest=' + encRequest
                    //+ '&access_code=' + accessCode;

                console.log('paymentUrl '+paymentUrl);
                console.log('Prg Code '+this.programCode)
                this.disableButton = true
                createOrUpdateOrder({ orderId: orderId, programCode: this.programCode })
                    .then((status) => {
                        console.log('Status is' +status)
                         if(status === 'paid'){
                            // Already paid → show success page directly
                            alert('Payment already completed.');
                        return;
   }       

    if(status === 'created'){
        window.open(paymentUrl, '_blank');
    }

                    })
                    .catch((error) => {
                        console.error('Error creating Order', JSON.stringify(error));
                        this.errorMessage = error.body?.message || 'Order creation failed';
                    });

            })
            .catch((error) => {
                console.error('Error fetching keys:', error);
                this.errorMessage = error.body?.message || 'Something went wrong';
            })
            .finally(() => {
                this.isLoading = false;
            });
    }

    // 🔹 Encryption Method Using Metadata IV
    encryptCCAvenue(plainText, workingKey, ivHex) {

        // MD5 hash of working key → AES-128 key
        const keyHash = CryptoJS.MD5(workingKey);

        // Parse IV from metadata (hex string)
        const iv = CryptoJS.enc.Hex.parse(ivHex);

        const encrypted = CryptoJS.AES.encrypt(
            CryptoJS.enc.Utf8.parse(plainText),
            keyHash,
            {
                iv: iv,
                mode: CryptoJS.mode.CBC,
                padding: CryptoJS.pad.Pkcs7
            }
        );

        return encrypted.ciphertext.toString(CryptoJS.enc.Hex).toLowerCase();
    }
}