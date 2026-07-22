@IsTest
private class ContentVersionTriggerHandlerTest {
    @IsTest
    static void testSetFilePrefix_CoversAllBranches() {
        ContentVersion cvWithCustomTitle = new ContentVersion(
            Title = 'Original Title A',
            PathOnClient = 'fileA.txt',
            VersionData = Blob.valueOf('A'),
            Custom_Title_fileupload__c = 'Prefixed Title A'
        );

        ContentVersion cvWithBlankCustomTitle = new ContentVersion(
            Title = 'Original Title B',
            PathOnClient = 'fileB.txt',
            VersionData = Blob.valueOf('B'),
            Custom_Title_fileupload__c = ''
        );

        ContentVersion cvWithNullCustomTitle = new ContentVersion(
            Title = 'Original Title C',
            PathOnClient = 'fileC.txt',
            VersionData = Blob.valueOf('C')
        );

        List<ContentVersion> inputList = new List<ContentVersion>{
            cvWithCustomTitle,
            cvWithBlankCustomTitle,
            cvWithNullCustomTitle
        };

        Test.startTest();
        ContentVersionTriggerHandler.setFilePrefix(inputList);
        Test.stopTest();

        System.assertEquals('Prefixed Title A', cvWithCustomTitle.Title);
        System.assertEquals('Original Title B', cvWithBlankCustomTitle.Title);
        System.assertEquals('Original Title C', cvWithNullCustomTitle.Title);
    }
}