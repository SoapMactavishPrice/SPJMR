@IsTest(seeAllData=true)
public class TestMe {

    @IsTest
    static void testLoadWithRealCSV() {

        // 🔹 Real ContentDocumentId (provided by you)
        Id contentDocumentId = '069C1000006HugfIAC';

        // 🔹 Program code (must exist in org data)
        String programCode = 'GMP'; // <-- change ONLY if needed

        Test.startTest();

      
        System.enqueueJob(
            new InterviewQueueableProcess(
                contentDocumentId,
                programCode
            )
        );

        Test.stopTest();

        
    }
}