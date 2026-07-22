public class SimpleMetadataService {

    public class SessionHeader { public String sessionId; }

    public class MetadataPort {
        public String endpoint_x;
        public SessionHeader SessionHeader;

        public MetadataPort() {
            endpoint_x = URL.getOrgDomainUrl().toExternalForm() + '/services/Soap/m/60.0';
            SessionHeader = new SessionHeader();
            SessionHeader.sessionId = UserInfo.getSessionId();
        }

        public Object readMetadata(String type_x, String[] fullNames) {
            return callSOAP('readMetadata', type_x, fullNames, null);
        }

        public Object updateMetadata(SimpleUpdateMetadata[] metadata, String metadataXml) {
            return callSOAP('updateMetadata', null, null, metadataXml);
        }

        private Object callSOAP(String action, String type_x, String[] fullNames, String metaXML) {

            String body = '';

            if (action == 'readMetadata') {
                body =
                    '<met:readMetadata>' +
                        '<met:type>' + type_x + '</met:type>' +
                        '<met:fullNames>' + fullNames[0] + '</met:fullNames>' +
                    '</met:readMetadata>';
            }
            else if (action == 'updateMetadata') {
                body =
                    '<met:updateMetadata>' +
                        metaXML +
                    '</met:updateMetadata>';
            }

            String envelope =
                '<?xml version="1.0" encoding="UTF-8"?>' +
                '<soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" ' +
                'xmlns:met="http://soap.sforce.com/2006/04/metadata" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">' +
                '<soapenv:Header>' +
                    '<met:SessionHeader>' +
                        '<met:sessionId>' + SessionHeader.sessionId + '</met:sessionId>' +
                    '</met:SessionHeader>' +
                '</soapenv:Header>' +
                '<soapenv:Body>' +
                    body +
                '</soapenv:Body>' +
                '</soapenv:Envelope>';

            HttpRequest req = new HttpRequest();
            req.setEndpoint(endpoint_x);
            req.setMethod('POST');
            req.setHeader('Content-Type', 'text/xml');
            req.setHeader('SOAPAction', action);
            req.setBody(envelope);

            Http http = new Http();
            HttpResponse res = http.send(req);

            return res.getBody();
        }
    }

    public class SimpleUpdateMetadata { public String fullName; }
}