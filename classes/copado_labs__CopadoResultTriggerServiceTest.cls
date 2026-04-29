@isTest
private class CopadoResultTriggerServiceTest {
    // Updated XML content to match the exact format expected by the service
    static final String TEST_XML_CONTENT = '<?xml version="1.0" encoding="utf-8"?>' +
    '<CxXMLResults DeepLink="https://checkmarx.example.com/CxWebClient/ViewerMain.aspx?scanid=1000227&amp;projectid=100" ScanTime="2024-10-24T09:13:01">' +
        '<Query id="1234" categories="PCI DSS v3.2;PCI DSS (3.2) - 6.5.1 - Injection flaws - particularly SQL injection,OWASP Top 10 2013;A1-Injection,FISMA 2014;System And Information Integrity,NIST SP 800-53;SI-10 Information Input Validation (P1)" cweId="89" name="SQL_Injection" group="CSharp_High_Risk" Severity="High" Language="CSharp" LanguageHash="1363215419077432" LanguageChangeDate="2023-01-15T00:00:00.0000000" SeverityIndex="3" QueryPath="CSharp\\Cx\\CSharp High Risk\\SQL Injection Version:1" QueryVersionCode="430">' +
            '<Result NodeId="10000" FileName="UserController.cs" Status="New" Line="42" Column="9" FalsePositive="False" Severity="High" AssignToUser="" state="0" Remark="" DeepLink="https://checkmarx.example.com/CxWebClient/ViewerMain.aspx?scanid=1000227&amp;projectid=100&amp;pathid=2" SeverityIndex="3">' +
                '<Path ResultId="1000" PathId="2" SimilarityId="1765812516">' +
                    '<PathNode>' +
                        '<FileName>UserController.cls</FileName>' +
                        '<Line>42</Line>' +
                        '<Column>9</Column>' +
                        '<NodeId>1</NodeId>' +
                        '<Name>ExecuteQuery</Name>' +
                        '<Type></Type>' +
                        '<Length>12</Length>' +
                        '<Snippet><Line><Code>var result = ExecuteQuery(query);</Code></Line></Snippet>' +
                    '</PathNode>' +
                '</Path>' +
            '</Result>' +
        '</Query>' +
        '<Query id="5678" categories="OWASP Top 10 2013;A3-Cross-Site Scripting (XSS)" cweId="79" name="Reflected_XSS_All_Clients" group="CSharp_Medium_Risk" Severity="Medium" Language="CSharp" LanguageHash="1363215419077432" LanguageChangeDate="2023-01-15T00:00:00.0000000" SeverityIndex="2">' +
            '<Result NodeId="20000" FileName="DatabaseHelper.cls" Status="New" Line="25" Column="35" FalsePositive="False" Severity="Medium" AssignToUser="" state="0" Remark="" DeepLink="https://checkmarx.example.com/CxWebClient/ViewerMain.aspx?scanid=1000227&amp;projectid=100&amp;pathid=15" SeverityIndex="2">' +
                '<Path ResultId="2000" PathId="15" SimilarityId="1948726043">' +
                    '<PathNode>' +
                        '<FileName>DatabaseHelper.cls</FileName>' +
                        '<Line>25</Line>' +
                        '<Column>35</Column>' +
                        '<NodeId>1</NodeId>' +
                        '<Name>query</Name>' +
                        '<Type></Type>' +
                        '<Length>5</Length>' +
                        '<Snippet><Line><Code>command.CommandText = query;</Code></Line></Snippet>' +
                    '</PathNode>' +
                '</Path>' +
            '</Result>' +
        '</Query>' +
        '<Query id="9012" categories="OWASP Top 10 2013;A3-XSS" cweId="79" name="Stored_XSS" group="CSharp_Medium_Risk" Severity="Medium" Language="CSharp" LanguageHash="1363215419077432" LanguageChangeDate="2023-01-15T00:00:00.0000000" SeverityIndex="2">' +
            '<Result NodeId="30000" FileName="Index.trigger" Status="New" Line="15" Column="35" FalsePositive="False" Severity="Medium" AssignToUser="" state="0" Remark="" DeepLink="https://checkmarx.example.com/CxWebClient/ViewerMain.aspx?scanid=1000227&amp;projectid=100&amp;pathid=25" SeverityIndex="2">' +
                '<Path ResultId="3000" PathId="25" SimilarityId="1948726044">' +
                    '<PathNode>' +
                        '<FileName>Index.trigger</FileName>' +
                        '<Line>15</Line>' +
                        '<Column>35</Column>' +
                        '<NodeId>1</NodeId>' +
                        '<Name>userInput</Name>' +
                        '<Type></Type>' +
                        '<Length>3</Length>' +
                        '<Snippet><Line><Code>@Html.Raw(Model.UserInput)</Code></Line></Snippet>' +
                    '</PathNode>' +
                '</Path>' +
            '</Result>' +
        '</Query>' +
    '</CxXMLResults>';

    @TestSetup
    static void setupTestData() {
        copado__User_Story__c userStory = new copado__User_Story__c();
        insert userStory;

        copado__Test__c checkmarxTest = new copado__Test__c(
            Name = 'Checkmarx - Test',
            copado__User_Story__c = userStory.Id
        );
        insert checkmarxTest;

        copado__Result__c result = new copado__Result__c(
            copado__Test__c = checkmarxTest.Id,
            copado__Status__c = 'In Progress',
            copado__Job_Type__c = 'Integration'
        );
        insert result;

        ContentVersion cv = new ContentVersion(
            Title = 'cx_output_report.xml',
            PathOnClient = 'cx_output_report.xml',
            VersionData = Blob.valueOf(TEST_XML_CONTENT),
            IsMajorVersion = true
        );
        insert cv;

        ContentDocumentLink cdl = new ContentDocumentLink(
            ContentDocumentId = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id].ContentDocumentId,
            LinkedEntityId = result.Id,
            ShareType = 'V'
        );
        insert cdl;
    }

@isTest
static void testSuccessfulResultUpdate() {
    // Get the test result record
    copado__Result__c result = [SELECT Id, copado__Status__c, copado__Job_Type__c, copado__Test__c 
                               FROM copado__Result__c 
                               WHERE copado__Status__c = 'In Progress' LIMIT 1];
    
    // Ensure we have the correct XML content linked
    ContentVersion cv = [SELECT Id, VersionData 
                        FROM ContentVersion 
                        WHERE Title = 'cx_output_report.xml' LIMIT 1];
    
    // Verify the XML content is correctly set
    System.assertEquals(true, cv.VersionData.toString().contains('CxXMLResults'), 
                       'XML content should contain CxXMLResults tag');

    Test.startTest();
    try {
        // Update the result status to trigger the processing
        result.copado__Status__c = 'Success';
        update result;
    } catch(Exception e) {
        System.debug('Error updating result: ' + e.getMessage());
        throw e;
    }
    Test.stopTest();

    // Query for violations with all fields to debug
    List<copado__Static_Code_Analysis_Violation__c> violations = [
        SELECT Id, copado__File__c, copado__Line__c, copado__Message__c,
               copado__Status__c, copado__Severity__c
        FROM copado__Static_Code_Analysis_Violation__c
    ];

    // Debug output
    System.debug('Number of violations found: ' + violations.size());
    for(copado__Static_Code_Analysis_Violation__c violation : violations) {
        System.debug('Violation: ' + violation);
    }

    // Assert violations were created
    System.assertNotEquals(0, violations.size(), 'Violations should have been created');
    System.assertEquals(6, violations.size(), 'Six Static Code Analysis Violations should be created');

    
}

@isTest
static void testMultipleResultsUpdate() {
    // Query existing data from setup
    copado__User_Story__c userStory = [SELECT Id FROM copado__User_Story__c LIMIT 1];
    copado__Test__c checkmarxTest = [SELECT Id FROM copado__Test__c LIMIT 1];
    
    // Create new results
    List<copado__Result__c> results = new List<copado__Result__c>();
    for(Integer i = 0; i < 3; i++) {
        copado__Result__c result = new copado__Result__c(
            copado__Test__c = checkmarxTest.Id,
            copado__Status__c = 'In Progress',
            copado__Job_Type__c = 'Integration'
        );
        results.add(result);
    }
    insert results;

    // Create ContentVersion and ContentDocumentLink for each result
    List<ContentVersion> contentVersions = new List<ContentVersion>();
    List<ContentDocumentLink> contentDocumentLinks = new List<ContentDocumentLink>();
    
    for(copado__Result__c result : results) {
        ContentVersion cv = new ContentVersion(
            Title = 'cx_output_report.xml',
            PathOnClient = 'cx_output_report.xml',
            VersionData = Blob.valueOf(TEST_XML_CONTENT),
            IsMajorVersion = true
        );
        contentVersions.add(cv);
    }
    insert contentVersions;

    // Create ContentDocumentLinks
    for(Integer i = 0; i < results.size(); i++) {
        ContentDocumentLink cdl = new ContentDocumentLink(
            ContentDocumentId = [SELECT ContentDocumentId 
                               FROM ContentVersion 
                               WHERE Id = :contentVersions[i].Id].ContentDocumentId,
            LinkedEntityId = results[i].Id,
            ShareType = 'V',
            Visibility = 'AllUsers'
        );
        contentDocumentLinks.add(cdl);
    }
    insert contentDocumentLinks;

    Test.startTest();
    for(copado__Result__c result : results) {
        result.copado__Status__c = 'Success';
    }
    update results;
    Test.stopTest();

    // Query all SCA results
    List<copado__Static_Code_Analysis_Result__c> scaResults = [
        SELECT Id, copado__User_Story__c 
        FROM copado__Static_Code_Analysis_Result__c 
        WHERE copado__User_Story__c = :userStory.Id
    ];

    // Debug output
    System.debug('Number of SCA Results found: ' + scaResults.size());
    for(copado__Static_Code_Analysis_Result__c sca : scaResults) {
        System.debug('SCA Result: ' + sca);
    }

    // The expected count should be 3 (one for each new result)
    System.assertEquals(3, scaResults.size(), 
                       'Three Static Code Analysis Results should be created');
}
}