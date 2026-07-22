@IsTest
public class AcademicFormControllerTest {

    // --------------------------------------------------
    // MOCK CALLOUT
    // --------------------------------------------------
    class UiApiMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setBody('{"picklistFieldValues":{"TestField":{"controllerName":null,"values":[{"label":"One","value":"One","defaultValue":false,"active":true,"validFor":["AAA"]}]}}}');
            return res;
        }
    }

    class UiApiMockFail implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(500);
            res.setBody('{}');
            return res;
        }
    }


    // --------------------------------------------------
    // MAIN METHOD TEST
    // --------------------------------------------------
    @IsTest
    static void testGetAllPicklists(){

        Test.setMock(HttpCalloutMock.class,new UiApiMock());

        Test.startTest();

        List<AcademicFormController.ObjectPicklistBundle> result =
            AcademicFormController.getAllPicklistsForObjects(
                new List<String>{'Account','Contact'},
                false,
                false
            );

        Test.stopTest();

        System.assert(result.size()>0);
    }



    // --------------------------------------------------
    // EMPTY INPUT
    // --------------------------------------------------
    @IsTest
    static void testEmptyInput(){

        List<AcademicFormController.ObjectPicklistBundle> result =
            AcademicFormController.getAllPicklistsForObjects(
                new List<String>(),
                false,
                true
            );

        System.assertEquals(0,result.size());
    }



    // --------------------------------------------------
    // NULL INPUT
    // --------------------------------------------------
    @IsTest
    static void testNullInput(){

        List<AcademicFormController.ObjectPicklistBundle> result =
            AcademicFormController.getAllPicklistsForObjects(
                null,
                null,
                null
            );

        System.assertEquals(0,result.size());
    }



    // --------------------------------------------------
    // INVALID OBJECT NAME
    // --------------------------------------------------
    @IsTest
    static void testInvalidObject(){

        Test.setMock(HttpCalloutMock.class,new UiApiMock());

        List<AcademicFormController.ObjectPicklistBundle> result =
            AcademicFormController.getAllPicklistsForObjects(
                new List<String>{'FakeObject__c'},
                false,
                true
            );

        System.assert(result[0].error!=null);
    }



    // --------------------------------------------------
    // INCLUDE INACTIVE TRUE
    // --------------------------------------------------
    @IsTest
    static void testIncludeInactive(){

        Test.setMock(HttpCalloutMock.class,new UiApiMock());

        List<AcademicFormController.ObjectPicklistBundle> result =
            AcademicFormController.getAllPicklistsForObjects(
                new List<String>{'Account'},
                true,
                false
            );

        System.assertNotEquals(null,result);
    }



    // --------------------------------------------------
    // CALLOUT FAILURE PATH
    // --------------------------------------------------
    @IsTest
    static void testCalloutFail(){

        Test.setMock(HttpCalloutMock.class,new UiApiMockFail());

        List<AcademicFormController.ObjectPicklistBundle> result =
            AcademicFormController.getAllPicklistsForObjects(
                new List<String>{'Account'},
                false,
                false
            );

        System.assertNotEquals(null,result);
    }



    // --------------------------------------------------
    // RECORD TYPE DTO TEST
    // --------------------------------------------------
    @IsTest
    static void testRecordTypeDTO(){

        AcademicFormController.RecordTypeInfoDTO dto =
            AcademicFormController.getRecordTypesByName(
                'Account',
                new List<String>{'Master'}
            );

        System.assertNotEquals(null,dto);
    }



    // --------------------------------------------------
    // RECORD TYPE EMPTY INPUT
    // --------------------------------------------------
    @IsTest
    static void testRecordTypeEmpty(){

        AcademicFormController.RecordTypeInfoDTO dto =
            AcademicFormController.getRecordTypesByName(
                null,
                null
            );

        System.assertEquals(0,dto.nameToId.size());
    }

}