import { LightningElement, api } from 'lwc';

export default class RecaptchaWidget extends LightningElement {
    @api siteKey;
    _widgetId;
    _renderInProgress = false;
    _rendered = false;
    token = '';

    renderedCallback() {
        if (this._rendered || this._renderInProgress || !this.siteKey) {
            return;
        }
        const host = this.template.querySelector('[data-host]');
        if (!host) {
            return;
        }
        this._renderInProgress = true;
        this.initWidget(host);
    }

    async initWidget(host) {
        try {
            await this.ensureScript();
            await this.ensureReady();
            const g = window.grecaptcha;
            this._widgetId = g.render(host, {
                sitekey: this.siteKey,
                theme: 'light',
                size: 'normal',
                tabindex: 0,
                callback: (token) => {
                    this.token = token;
                    this.dispatchEvent(new CustomEvent('verified', { detail: { token } }));
                },
                'expired-callback': () => {
                    this.token = '';
                    this.dispatchEvent(new CustomEvent('expired'));
                },
                'error-callback': () => {
                    this.token = '';
                    this.dispatchEvent(new CustomEvent('captchaerror'));
                }
            });
            this._rendered = true;
        } catch (e) {
            console.error('reCAPTCHA init failed', e);
            this.dispatchEvent(new CustomEvent('loaderror', { detail: { message: e?.message } }));
        } finally {
            this._renderInProgress = false;
        }
    }

    @api
    getResponse() {
        if (typeof this._widgetId === 'number' && window.grecaptcha) {
            try {
                return window.grecaptcha.getResponse(this._widgetId) || this.token || '';
            } catch (e) {
                console.error('getResponse failed', e);
            }
        }
        return this.token || '';
    }

    @api
    reset() {
        if (typeof this._widgetId === 'number' && window.grecaptcha) {
            try {
                window.grecaptcha.reset(this._widgetId);
            } catch (e) {
                console.error('reset failed', e);
            }
        }
        this.token = '';
    }

    ensureScript() {
        return new Promise((resolve, reject) => {
            if (window.grecaptcha && window.grecaptcha.render) {
                resolve();
                return;
            }
            const existing = document.querySelector('script[src*="google.com/recaptcha/api.js"]');
            if (existing) {
                if (window.grecaptcha && window.grecaptcha.render) {
                    resolve();
                } else {
                    existing.addEventListener('load', () => resolve());
                    existing.addEventListener('error', () => reject(new Error('reCAPTCHA script error')));
                }
                return;
            }
            const s = document.createElement('script');
            s.src = 'https://www.google.com/recaptcha/api.js?hl=en';
            s.async = true;
            s.defer = true;
            s.onload = () => resolve();
            s.onerror = () => reject(new Error('reCAPTCHA script load failed'));
            document.head.appendChild(s);
        });
    }

    ensureReady() {
        return new Promise((resolve) => {
            const g = window.grecaptcha;
            if (g && typeof g.render === 'function') {
                resolve();
                return;
            }
            if (g && typeof g.ready === 'function') {
                g.ready(() => resolve());
                return;
            }
            const start = Date.now();
            const t = setInterval(() => {
                if (window.grecaptcha && window.grecaptcha.render) {
                    clearInterval(t);
                    resolve();
                } else if (Date.now() - start > 15000) {
                    clearInterval(t);
                    resolve();
                }
            }, 50);
        });
    }
}