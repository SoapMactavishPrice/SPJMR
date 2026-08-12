public without sharing class VFC_DomainsController {

    public String parentOrigin { get; private set; }
    public String loginLink {get; private set;}
    public VFC_DomainsController() {
           List<Network> networks = [
            SELECT Id
            FROM Network
            WHERE Name = 'webtolead'
            LIMIT 1
        ];

        if (networks.size()>0) {
            String baseUrl = Network.getLoginUrl(networks[0].Id);
            parentOrigin = baseUrl.substringBefore('.com') + '.com';

        }

        List<Network> applicationPortal = [
            SELECT Id
            FROM Network
            WHERE Name = 'Application Portal'
            LIMIT 1
        ];

         if (applicationPortal.size()>0) {
            loginLink = Network.getLoginUrl(applicationPortal[0].Id);
             system.debug(loginLink);
            //loginLink = portalLink.substringBefore('.com') + '.com';

        }
    }

}