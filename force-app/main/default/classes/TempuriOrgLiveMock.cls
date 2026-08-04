@IsTest
public class TempuriOrgLiveMock implements WebServiceMock {

    public String transactionData =
        '101\t2026-04-01 10:30:00\n' +   // valid
        '102\tnot-a-date\n' +            // bad datetime -> skipped
        'badrow\n' +                     // < 2 columns  -> skipped
        '\n' +                           // blank line   -> skipped
        '103\t2026-04-01 11:00:00';      // valid

    public void doInvoke(
        Object stub,
        Object request,
        Map<String, Object> response,
        String endpoint,
        String soapAction,
        String requestName,
        String responseNS,
        String responseName,
        String responseType
    ) {
        Object resp = Type.forName(responseType).newInstance();
        if (resp instanceof tempuriOrgLive.GetTransactionsLogResponse_element) {
            tempuriOrgLive.GetTransactionsLogResponse_element r =
                (tempuriOrgLive.GetTransactionsLogResponse_element) resp;
            r.GetTransactionsLogResult = 'OK';
            r.strDataList = transactionData;
        }
        response.put('response_x', resp);
    }
}