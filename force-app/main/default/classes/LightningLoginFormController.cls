global class LightningLoginFormController {

    public LightningLoginFormController() {
        
    }

    /**
     * Login method using Site.login() - validates both email and password
     * @param username Email/Username of the user
     * @param password Password of the user
     * @return Map containing success status, redirect URL, and error message
     */
    // @AuraEnabled
    // public static Map<String, Object> login(String username, String password) {
    //     Map<String, Object> result = new Map<String, Object>();
        
    //     try {
    //         // Validate input
    //         if (String.isBlank(username) || String.isBlank(password)) {
    //             result.put('success', false);
    //             result.put('error', 'Please enter both email and password.');
    //             return result;
    //         }
            
    //         // Get home page URL for redirect after successful login
    //         String homePageUrl = getHomePageUrl();
            
    //         // Use Site.login() - this validates both email and password
    //         // Returns PageReference with redirect URL on success, throws exception on failure
    //         ApexPages.PageReference loginRef = Site.login(username, password, homePageUrl);
            
    //         if (loginRef != null) {
    //             // Use the home page URL we constructed (not from PageReference)
    //             // This ensures we redirect to the correct relative path
    //             result.put('success', true);
    //             result.put('redirectUrl', homePageUrl);
    //         } else {
    //             result.put('success', false);
    //             result.put('error', 'Login failed. Please check your credentials.');
    //         }
            
    //     } catch (Exception ex) {
    //         // Handle login errors
    //         String errorMsg = ex.getMessage();
    //         if (errorMsg.contains('INVALID_LOGIN') || 
    //             errorMsg.contains('Invalid username, password') ||
    //             errorMsg.contains('Authentication failure')) {
    //             result.put('success', false);
    //             result.put('error', 'Invalid email or password. Please try again.');
    //         } else {
    //             result.put('success', false);
    //             result.put('error', 'An error occurred during login. Please try again.');
    //         }
    //         System.debug('Login error: ' + errorMsg);
    //     }
        
    //     return result;
    // }

    @AuraEnabled
    public static String login(String username, String password) {
        // Get home page URL for redirect after successful login
        // Use getHomePageUrl() instead of ApexPages.currentPage() which doesn't work in LWC context
        String startUrl = getHomePageUrl();
        
        // If startUrl is null or empty, use default
        if (String.isBlank(startUrl)) {
            startUrl = '/studentportal/';
        }

        ApexPages.PageReference pr = Site.login(username, password, startUrl);

        if (pr == null) {
            // Invalid credentials or other error
            throw new AuraHandledException('Invalid username or password.');
        }

        // Return the URL that logs in the user and redirects to /student
        return pr.getUrl();
    }
    
    /**
     * Gets the home page URL for the current community
     * Returns the home page route /student/
     * @return Home page URL (relative path)
     */
    @AuraEnabled
    public static String getHomePageUrl() {
        try {
            // Return the home page route /student/
            // This is the configured home page route for the community
            return '/studentportal/';
        } catch (Exception ex) {
            System.debug('Error getting home page URL: ' + ex.getMessage());
            return '/studentportal/';
        }
    }

    /**
     * Returns true if the current user is a guest (not logged in) in the community.
     * Used on the login page to force logged-in users to be logged out so they see the login form.
     */
    @AuraEnabled(cacheable=false)
    public static Boolean isGuestUser() {
        try {
            return Auth.CommunitiesUtil.isGuestUser();
        } catch (Exception e) {
            // Not in community context (e.g. App Preview); treat as guest so we don't redirect
            return true;
        }
    }
    
    @AuraEnabled
    public static Boolean getIsUsernamePasswordEnabled() {
        Auth.AuthConfiguration authConfig = getAuthConfig();
        return authConfig.getUsernamePasswordEnabled();
    }

    @AuraEnabled
    public static Boolean getIsSelfRegistrationEnabled() {
        Auth.AuthConfiguration authConfig = getAuthConfig();
        return authConfig.getSelfRegistrationEnabled();
    }

    @AuraEnabled
    public static String getSelfRegistrationUrl() {
        Auth.AuthConfiguration authConfig = getAuthConfig();
        if (authConfig.getSelfRegistrationEnabled()) {
            return authConfig.getSelfRegistrationUrl();
        }
        return null;
    }

    @AuraEnabled
    public static String getForgotPasswordUrl() {
        Auth.AuthConfiguration authConfig = getAuthConfig();
        return authConfig.getForgotPasswordUrl();
    }
    
    @TestVisible
    private static Auth.AuthConfiguration getAuthConfig(){
        Id networkId = Network.getNetworkId();
        Auth.AuthConfiguration authConfig = new Auth.AuthConfiguration(networkId,'');
        return authConfig;
    }

    @AuraEnabled
    global static String setExperienceId(String expId) {
        // Return null if there is no error, else it will return the error message 
        try {
            if (expId != null) {
                Site.setExperienceId(expId);
            }
            return null; 
        } catch (Exception ex) {
            return ex.getMessage();            
        }
    }   
}