import { LightningElement, api } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import login from '@salesforce/apex/LightningLoginFormController.login';
import isGuestUser from '@salesforce/apex/LightningLoginFormController.isGuestUser';
import bgImage from '@salesforce/resourceUrl/loginBackground';
import studentBg from '@salesforce/resourceUrl/Student_Banner';
import googleLogo from '@salesforce/resourceUrl/GoogleLogo';

export default class SpjimrLoginComp extends LightningElement {
   
    @api studentLoginBgImg;
    @api emailSVG;
    @api passwordSVG;
    email = '';
    password = '';
    showPassword = false;
    isLoading = false;
    errorMessage = '';
    bgUrl = bgImage;
    googleLogoUrl = googleLogo;
    // bgUrl = 'https://platform-energy-10--devorg.sandbox.my.salesforce.com/sfc/dist/version/download/?oid=00DC1000002cd5h&ids=068C10000064dnJ&d=%2Fa%2FC1000000gmwH%2FIv6Jpg8D51Qr8Nq11cAPSP1f99NYWL6kfWHkItINGLM&asPdf=false';

    connectedCallback() {
        // Force user to be guest when login page loads: if already logged in, redirect to logout
        isGuestUser()
            .then((guest) => {
                if (guest === false) {
                    const loginPath = window.location.pathname || '/studentportal/login';
                    const retURL = encodeURIComponent(loginPath + (window.location.search || ''));
                    const logoutUrl = `${window.location.pathname.replace(/\/[^/]*$/, '')}/secur/logout.jsp?retURL=${retURL}`;
                    try {
                        if (window.top !== window) {
                            window.top.location.replace(logoutUrl);
                        } else {
                            window.location.replace(logoutUrl);
                        }
                    } catch (e) {
                        window.location.replace(logoutUrl);
                    }
                    return;
                }
                this.handleLoginPageReady();
            })
            .catch(() => {
                this.handleLoginPageReady();
            });
    }

    handleLoginPageReady() {
        // Clear any logout flag and dispatch so header clears user name
        try {
            sessionStorage.removeItem('studentLogout');
            if (window.top !== window && window.top.sessionStorage) {
                window.top.sessionStorage.removeItem('studentLogout');
            }
        } catch (e) { /* ignore */ }
        try {
            window.dispatchEvent(new CustomEvent('studentlogout'));
            if (window.top !== window) window.top.dispatchEvent(new CustomEvent('studentlogout'));
        } catch (e) { /* ignore */ }

        // Check for login error in URL parameters (when redirected back from failed login)
        const urlParams = new URLSearchParams(window.location.search);
        const loginError = urlParams.get('loginError');
        const errorCode = urlParams.get('error');
        const errorMsg = urlParams.get('errorMsg');

        if (loginError || errorCode || errorMsg ||
            (window.location.pathname.includes('/secur/login.jsp') && window.location.search)) {
            if (loginError || errorCode || errorMsg) {
                this.errorMessage = 'Please enter correct username or password.';
                this.showToast('Login Failed', this.errorMessage, 'error');
            }
            const cleanUrl = window.location.pathname;
            window.history.replaceState({}, document.title, cleanUrl);
        }
    }

    get studentLoginBgImgUrl() {
        return this.studentLoginBgImg ? `/sfsites/c/cms/media/${this.studentLoginBgImg}` : null;
    }

    get emailSVGUrl() {
        return this.emailSVG ? `/sfsites/c/cms/media/${this.emailSVG}` : null;
    }

    get passwordSVGUrl() {
        return this.passwordSVG ? `/sfsites/c/cms/media/${this.passwordSVG}` : null;
    }

    get passwordFieldType() {
        return this.showPassword ? 'text' : 'password';
    }

    get passwordIconName() {
        return this.showPassword ? 'utility:hide' : 'utility:preview';
    }

    togglePasswordVisibility(event) {
        event.preventDefault();
        event.stopPropagation();
        this.showPassword = !this.showPassword;
    }

    handleForgotPassword(event) {
        event.preventDefault();
        // Redirect to forgot password page
        window.location.href = '/studentportal/ForgotPassword';
    }
    handleGoogleLogin() {

        window.location.href =
            '/student/services/auth/sso/Google';
    }

    // async handleSubmit(event) {
    //     event.preventDefault();
        
    //     // Validate form
    //     if (!this.email || !this.password) {
    //         this.showToast('Validation Error', 'Please enter both email and password.', 'error');
    //         return;
    //     }

    //     this.isLoading = true;
    //     this.errorMessage = '';

    //     try {
    //         // Use Site.login() - validates both email and password
    //         const loginResult = await login({ 
    //             username: this.email, 
    //             password: this.password 
    //         });
            
    //         console.log('Login result:', loginResult);
    //         if (loginResult.success) {
    //             // Redirect to home page on successful login
    //             let redirectUrl = loginResult.redirectUrl || '/s/';
                
    //             // Ensure it's a relative path (not a full URL)
    //             // If it starts with http:// or https://, extract just the path
    //             if (redirectUrl.startsWith('http://') || redirectUrl.startsWith('https://')) {
    //                 try {
    //                     const urlObj = new URL(redirectUrl);
    //                     redirectUrl = urlObj.pathname + (urlObj.search || '');
    //                 } catch (e) {
    //                     console.error('Error parsing URL:', e);
    //                     redirectUrl = '/s/';
    //                 }
    //             }
                
    //             // Ensure it starts with /
    //             if (!redirectUrl.startsWith('/')) {
    //                 redirectUrl = '/' + redirectUrl;
    //             }
                
    //             console.log('Redirecting to:', redirectUrl);
    //             window.location.replace(redirectUrl);
    //         } else {
    //             this.isLoading = false;
    //             this.errorMessage = loginResult.error || 'Invalid email or password.';
    //             this.showToast('Login Failed', this.errorMessage, 'error');
    //         }
            
    //     } catch (error) {
    //         this.isLoading = false;
    //         console.error('Login error:', error);
    //         this.errorMessage = 'An error occurred during login. Please try again.';
    //         this.showToast('Login Error', this.errorMessage, 'error');
    //     }
    // }


    async handleSubmit(event) {
        event.preventDefault();
        event.stopPropagation();
        
        // Validate form
        if (!this.email || !this.password) {
            this.errorMessage = 'Please enter both email and password.';
            this.showToast('Validation Error', this.errorMessage, 'error');
            return;
        }

        this.isLoading = true;
        this.errorMessage = '';

        try {
            const url = await login({ username: this.email, password: this.password });
            
            let target;
            
            // Check if URL is already absolute (starts with http:// or https://)
            if (url.startsWith('http://') || url.startsWith('https://')) {
                // Use the absolute URL directly
                target = url;
            } else {
                // URL is relative; prepend current origin + site path
                const origin = window.location.origin;
                const sitePath = '/studentportal'; // root of your site
                // If url already starts with '/student', just combine origin + url
                target = url.startsWith('/studentportal')
                    ? origin + url
                    : origin + sitePath + url;
            }

            console.log('Redirecting to:', target);
            window.location.href = target;
        } catch (error) {
            this.isLoading = false;
            console.error('Login error:', error);
            this.errorMessage = error!=null ? 'Please enter correct username or password.':'';
            this.showToast('Login Failed', this.errorMessage, 'error');
        }
    }

    showToast(title, message, variant) {
        const evt = new ShowToastEvent({
            title: title,
            message: message,
            variant: variant,
        });
        this.dispatchEvent(evt);
    }

    // Clear error message when user starts typing
    handleEmailChange(event) {
        this.email = event.target.value;
        if (this.errorMessage) {
            this.errorMessage = '';
        }
    }

    handlePasswordChange(event) {
        this.password = event.target.value;
        if (this.errorMessage) {
            this.errorMessage = '';
        }
    }
}