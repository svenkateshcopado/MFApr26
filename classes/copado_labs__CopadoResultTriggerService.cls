public class CopadoResultTriggerService {
    @TestVisible
    private static final String CHECKMARX_TEST_NAME_PREFIX = 'Checkmarx - ';
    private static final String XML_FILE_NAME = 'cx_output_report.xml';

    public static void beforeUpdate(List<copado__Result__c> newResults, Map<Id, copado__Result__c> oldMap) {
    try {
        Set<Id> checkmarxTestIds = new Set<Id>();
        Map<Id, Id> resultIdToTestId = new Map<Id, Id>();
        Map<Id, copado__Result__c> resultIdToResult = new Map<Id, copado__Result__c>();

        system.debug('Number of results: ' + newResults.size());

        // Identify Checkmarx test results
        for (copado__Result__c result : newResults) {
            system.debug('Processing result: ' + result.Id);
            system.debug('result Test record: '+ result.copado__Test__c);
            system.debug('result Status record: '+ result.copado__Status__c);
            system.debug('result oldMap Status record: '+ oldMap.get(result.Id).copado__Status__c);
            system.debug('result oldmap record: '+ oldMap);
            if (result.copado__Test__c != null && 
                (result.copado__Status__c == 'Success' || result.copado__Status__c == 'Failed') &&
                (oldMap == null || result.copado__Status__c != oldMap.get(result.Id).copado__Status__c)) {
                system.debug('Adding to checkmarxTestIds: ' + result.copado__Test__c);
                checkmarxTestIds.add(result.copado__Test__c);
                resultIdToTestId.put(result.Id, result.copado__Test__c);
                resultIdToResult.put(result.Id, result);
            }
        }

        //system.debug('Number of checkmarxTestIds: ' + checkmarxTestIds.size());
        if (!checkmarxTestIds.isEmpty()) {
            processCheckmarxTests(checkmarxTestIds, resultIdToTestId, resultIdToResult);
        }
    } catch (Exception e) {
        system.debug('Error in beforeUpdate: ' + e.getMessage() + ' at line ' + e.getLineNumber());
        // Consider how you want to handle this exception. You might want to add custom error handling here.
    }
}
    private static void processCheckmarxTests(Set<Id> testIds, Map<Id, Id> resultIdToTestId, Map<Id, copado__Result__c> resultIdToResult) {
    try {
        // Query for Checkmarx tests and related user stories
        Map<Id, copado__Test__c> checkmarxTests = new Map<Id, copado__Test__c>(
            [SELECT Id, Name, copado__User_Story__c 
             FROM copado__Test__c 
             WHERE Id IN :testIds AND Name LIKE :(CHECKMARX_TEST_NAME_PREFIX + '%')]
        );
        system.debug('Number of checkmarxTests: ' + checkmarxTests.size());

        if (!checkmarxTests.isEmpty()) {
            processCheckMarxXMLFiles(checkmarxTests, resultIdToTestId, resultIdToResult);
        }
    } catch (Exception e) {
        system.debug('Error in processCheckmarxTests: ' + e.getMessage() + ' at line ' + e.getLineNumber());
    }
}

    private static void processCheckMarxXMLFiles(Map<Id, copado__Test__c> checkmarxTests, Map<Id, Id> resultIdToTestId, Map<Id, copado__Result__c> resultIdToResult) {
        // Query for ContentDocumentLinks related to the result records
        List<ContentDocumentLink> documentLinks = [
            SELECT ContentDocumentId, LinkedEntityId 
            FROM ContentDocumentLink 
            WHERE LinkedEntityId IN :resultIdToTestId.keySet()
        ];
        system.debug('************* List documentLinks ******************');

        Set<Id> contentDocumentIds = new Set<Id>();
        for (ContentDocumentLink link : documentLinks) {
            contentDocumentIds.add(link.ContentDocumentId);
        }

        // Query for the latest version of the XML files
        List<ContentVersion> contentVersions = [
            SELECT ContentDocumentId, VersionData, Title
            FROM ContentVersion 
            WHERE ContentDocumentId IN :contentDocumentIds 
            AND IsLatest = true
            AND Title = :XML_FILE_NAME
        ];
        system.debug('************* Cx Content Version: '+ contentVersions);

        Map<Id, ContentVersion> xmlFilesByResultId = new Map<Id, ContentVersion>();
        for (ContentDocumentLink link : documentLinks) {
            for (ContentVersion version : contentVersions) {
                if (link.ContentDocumentId == version.ContentDocumentId) {
                    system.debug('*************** Inside If link Content Document Id = version .Content Document Id');
                    xmlFilesByResultId.put(link.LinkedEntityId, version);
                    break;
                }

            }
        }
        system.debug('****************** xmlFilesByResultId: ' + xmlFilesByResultId);
        List<copado__Static_Code_Analysis_Result__c> scaResults = new List<copado__Static_Code_Analysis_Result__c>();
        List<copado__Static_Code_Analysis_Violation__c> scaViolations = new List<copado__Static_Code_Analysis_Violation__c>();

        for (Id resultId : xmlFilesByResultId.keySet()) {
            system.debug('**************** loop inside xmlFilesByResultId ***************** ');
            ContentVersion xmlFile = xmlFilesByResultId.get(resultId);
            Id testId = resultIdToTestId.get(resultId);
            copado__Test__c checkmarxTest = checkmarxTests.get(testId);

            if (checkmarxTest != null && checkmarxTest.copado__User_Story__c != null) {
                system.debug('**************** inside if CxXMLResults ***************** ');
                CxXMLResults cxResults = parseCheckMarxLogFile(xmlFile);

                copado__Static_Code_Analysis_Result__c scaResult = new copado__Static_Code_Analysis_Result__c(
                    copado__User_Story__c = checkmarxTest.copado__User_Story__c
                );
                scaResults.add(scaResult);
                system.debug('***************** Sca result added to the list: '+ scaResult.Name);

                if(cxResults.deepLink != null || cxResults.deepLink != ''){
                     resultIdToResult.get(resultId).copado__Link__c = cxResults.deepLink;
                    }

                for (Query query : cxResults.querys) {
                    system.debug('***************** inside for query **************');
                    for (Result result : query.result) {
                        
                        system.debug('***************** inside for result query **************');


                        for (PathNode pathNode : result.pathNodes) {
                            copado__Static_Code_Analysis_Violation__c violation = new copado__Static_Code_Analysis_Violation__c(
                                copado__File__c = pathNode.fileName,
                                copado__Line__c = Integer.valueOf(pathNode.line),
                                copado__Rule__c = query.name,
                                copado__Severity__c = result.severity,
                                copado_labs__Checkmarx_score__c = Integer.valueOf(result.severityIndex) + 1,
                                copado__Priority__c = 5 - Integer.valueOf(result.severityIndex),
                                copado__Message__c = query.categories,
                                copado__Info_URL__c = result.resultDeepLink
                            );
                            scaViolations.add(violation);
                            system.debug('***************** add violation: '+ violation);
                        }
                    }
                }
            }
        }
        system.debug('****************** scaViolations size: '+scaViolations.size());
        if (!scaResults.isEmpty()) {

            insert scaResults;
            system.debug('****************** after scaResults insert **********');
            for (Integer i = 0; i < scaViolations.size(); i++) {
                system.debug('*************************** loop scaViolations '+ scaViolations[i]);
                scaViolations[i].copado__Static_Code_Analysis_Result__c = scaResults[0].Id;
            }
            system.debug('****************** before scaViolations insert **********');
            insert scaViolations;
        }
    }

    private static CxXMLResults parseCheckMarxLogFile(ContentVersion version) {
        System.debug('*******************  parseCheckMarxLogFile: '+ version);
        DOM.Document doc = new DOM.Document();
        CxXMLResults cxXMLResults = new CxXMLResults();
        try {
            doc.load(version.VersionData.toString());
            String xmlString = doc.toXmlString();
            System.debug('xmlString =' + xmlString);
            
            
            Dom.XMLNode cxXMLResult = doc.getRootElement();
            cxXMLResults.deepLink = cxXMLResult.getAttribute('DeepLink', null);
            cxXMLResults.querys = new List<Query>();
            for (Dom.XMLNode query : cxXMLResult.getChildElements()) {
                Query queryObj = new Query();
                queryObj.name = query.getAttribute('name', null);
                

                String categories = query.getAttribute('categories', null);
                queryObj.categories = categories?.length() > 255 ? categories.substring(0, 255) : categories;
                for (Dom.XMLNode result : query.getChildElements()) {
                    Result resultObj = new Result();
                    resultObj.severityIndex = result.getAttribute('SeverityIndex', null);
                    resultObj.resultDeepLink = result.getAttribute('DeepLink', null);
                    Dom.XmlNode[] path = result.getChildren();
                    Dom.XmlNode[] path1 = result.getChildElements();
                    String fileName1 = path[0].getChildElement('FileName', null)?.getText();
                    PathNode pathNodeObj1 = new PathNode();
                    String fileName2 = result.getAttribute('FileName', null);
                    pathNodeObj1.fileName = fileName2?.substringAfterLast('/');
                    pathNodeObj1.line = result.getAttribute('Line', null);
                    resultObj.pathNodes.add(pathNodeObj1);
                    
                    for (Dom.XMLNode pathNode : path[0].getChildElements()) {
                        System.debug('manu1 =' + resultObj.resultDeepLink);
                        PathNode pathNodeObj = new PathNode();
                        String fileName = pathNode.getChildElement('FileName', null)?.getText();
                        pathNodeObj.fileName = fileName?.substringAfterLast('/');
                        pathNodeObj.line = pathNode.getChildElement('Line', null)?.getText();
                        System.debug('manu2 =' + pathNodeObj.line);

                        resultObj.pathNodes.add(pathNodeObj);
                    }
                    queryObj.result.add(resultObj);
                }
                cxXMLResults.querys.add(queryObj);
                System.debug('manu3 =' + cxXMLResults.querys);

            }
        } catch (Exception exp) {
            System.debug('Exception in method parseCheckMarxLogFile with ' + exp.getMessage());
        }
        return cxXMLResults;
    }

    private static String getSeverity(Integer severityIndex) {
        switch on severityIndex {
            when 5 { return 'Info'; }
            when 4 { return 'Low'; }
            when 3 { return 'Medium'; }
            when 2 { return 'High'; }
            when 1 { return 'Critical'; }
            when else { return 'Unknown'; }
            
        }
    }

    // Inner classes
    private class CxXMLResults {
        String deepLink;
        List<Query> querys = new List<Query>();
    }

    private class Query {
        String name;
        String categories;
        List<Result> result = new List<Result>();
    }

    private class Result {
        String severityIndex;
        String resultDeepLink;
        String severity;
        List<PathNode> pathNodes = new List<PathNode>();
    }

    private class PathNode {
        String fileName;
        String line;
    }
}