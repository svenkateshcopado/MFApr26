public with sharing class RevenueCloudConfiguratorController {

    private static Map<String, String> fileNamesByType = new Map<String, String>{
        'standard' => 'configuration_rules.json',
        'advanced' => 'advanced_rules.json',
        'automation' => 'automations.json'
    };

    @AuraEnabled
    public static String getTargetEnvironmentName(String recordId){
        copado__User_Story__c userStory = [SELECT Id, copado__Environment__c, copado__Project__r.copado__Deployment_Flow__c, 
        copado__Release__r.copado__Project__r.copado__Deployment_Flow__c 
        FROM copado__User_Story__c WHERE Id = :recordId LIMIT 1];
        String pipelineId = userStory.copado__Project__r.copado__Deployment_Flow__c != null ? userStory.copado__Project__r.copado__Deployment_Flow__c : userStory.copado__Release__r.copado__Project__r.copado__Deployment_Flow__c;
        String targetEnvironmentName = '';
        if(String.isNotBlank(pipelineId)) {
            List<copado__Deployment_Flow_Step__c> pipelineConnections = [SELECT Id, copado__Destination_Environment__r.Name 
            FROM copado__Deployment_Flow_Step__c 
            WHERE copado__Source_Environment__c = :userStory.copado__Environment__c AND copado__Deployment_Flow__c = :pipelineId];
            if(pipelineConnections.isEmpty() == false) {
                targetEnvironmentName = pipelineConnections[0].copado__Destination_Environment__r.Name;
            }
        }
        return targetEnvironmentName;
    }

    @AuraEnabled
    public static RevenueCloudTabDTO retrieveItemsFromCacheByType(String recordId, String type) {
        RevenueCloudTabDTO tab = new RevenueCloudTabDTO();
        tab.type = type;
        tab.items = new List<RevenueCloudItemDTO>();
        tab.itemCount = 0;
        try {
            copado__User_Story__c userStory = [SELECT Id, copado__Environment__c FROM copado__User_Story__c WHERE Id = :recordId LIMIT 1];
            List<ContentDocumentLink> cdl = [SELECT ContentDocumentId 
                                            FROM ContentDocumentLink 
                                            WHERE LinkedEntityId = :userStory.copado__Environment__c AND ContentDocument.Title = :fileNamesByType.get(type) 
                                            ORDER BY SystemModstamp DESC LIMIT 1];

            if(cdl.isEmpty()) {
                return tab;
            }
        
            ContentVersion cv = [SELECT Id, VersionData, CreatedDate FROM ContentVersion WHERE ContentDocumentId = :cdl[0].ContentDocumentId ORDER BY CreatedDate DESC LIMIT 1];
            tab.lastRefreshDate = cv.CreatedDate;
            String jsonString = cv.VersionData.toString();
            List<copado__JobStep__c> existingSteps = [
                SELECT Id,
                        copado__UserStory__r.Name, copado__ConfigJson__c 
                       FROM
                       copado__JobStep__c
                       WHERE 
                       copado__UserStory__c = :recordId AND copado__Type__c = 'Function'
            ];
            String configurationRulesJson = '';
            String advancedRulesJson = '';
            String automationsJson = '';
            for(copado__JobStep__c step : existingSteps) {
                if(step.copado__ConfigJson__c != null) {
                    if(step.copado__ConfigJson__c.contains('"functionName":"RCA_Deploy_Configuration_Rules"')) {
                        configurationRulesJson = getParameterValue(step.copado__ConfigJson__c, 'recordList');
                    } else if(step.copado__ConfigJson__c.contains('"functionName":"RCA_Constraint_Deployer"')) {
                        advancedRulesJson = getParameterValue(step.copado__ConfigJson__c, 'recordList');
                    } else if(step.copado__ConfigJson__c.contains('"functionName":"RCA_Refresh_Decision_Table"')) {
                        automationsJson = getParameterValue(step.copado__ConfigJson__c, 'recordList');
                    }
                }
            }
            Map<String, Object> parsedData = (Map<String, Object>) JSON.deserializeUntyped(jsonString);
            Map<String, Object> result = (Map<String, Object>) parsedData.get('result');
            String nameField = type == 'automation' ? 'SetupName' : 'Name';
            String valueField = type == 'automation' ? 'DeveloperName' : 'ApiName';
            List<Object> records = (List<Object>) result.get('records');
            for(Object recordObj : records) {
                Map<String, Object> record = (Map<String, Object>) recordObj;
                RevenueCloudItemDTO item = new RevenueCloudItemDTO();
                item.label = (String) record.get(nameField);
                item.value = (String) record.get(valueField);
                item.type = type;
                item.lastModifiedDate = (String) record.get('LastModifiedDate');
                item.status = (String) record.get('Status');
                if(item.status == 'Active') {
                    //item.statusIcon = 'utility:check';
                    item.statusColor = 'status-indicator-active';
                } else if(item.status == 'Draft') {
                    //item.statusIcon = 'utility:close';
                    item.statusColor = 'status-indicator-inactive';
                } else {
                    //item.statusIcon = 'utility:question';
                    item.statusColor = 'status-indicator-base';
                }
                item.lastModifiedBy = record.containsKey('LastModifiedBy') ? ((Map<String, Object>)record.get('LastModifiedBy')).get('Name').toString() : '';
                if(type == 'standard' && configurationRulesJson != null && configurationRulesJson.contains(item.value)) {
                    item.selected = true;
                } else if(type == 'advanced' && advancedRulesJson != null && advancedRulesJson.contains(item.value)) {
                    item.selected = true;
                } else if(type == 'automation' && automationsJson != null && automationsJson.contains(item.value)) {
                    item.selected = true;
                } else {
                    item.selected = false;
                }
                tab.items.add(item);
            }
            tab.itemCount = tab.items.size();
            return tab;
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    @AuraEnabled
    public static String retrieveItemsFromSource(String recordId) {
        copado__User_Story__c userStory = [SELECT Id, copado__Environment__c FROM copado__User_Story__c WHERE Id = :recordId];
        copado.RunCopadoFunction.InvocableVariables request = new copado.RunCopadoFunction.InvocableVariables();
        request.functionApiName = 'RCA_Refresh_Index';
        request.contextId = userStory.copado__Environment__c;
        List<String> result = copado.RunCopadoFunction.execute(new List<copado.RunCopadoFunction.InvocableVariables> { request });
        String resultId = result[0];
        return resultId;
    }

    @AuraEnabled(cacheable=false)
    public static String pollRetrievalStatus(String recordId, String resultId) {
        List<copado__Result__c> results = [SELECT Id, copado__Status__c, copado__ParentId__c, copado__Progress_Status__c FROM copado__Result__c WHERE Id = :resultId WITH SECURITY_ENFORCED];
        if(results.isEmpty() == false) {
            String resultStatus = results[0].copado__Status__c;
            if(resultStatus == 'Success') {
                deletePreviousIndexFiles(recordId);
                return 'success';
            } else if(resultStatus == 'Failed' || resultStatus == 'Cancelled') {
                return 'error';
            }
        } else {
            return 'error';
        }
        return 'In Progress: ' + (String.isNotBlank(results[0].copado__Progress_Status__c) ? results[0].copado__Progress_Status__c : 'Starting...');
    }

    @AuraEnabled
    public static void processSelectedConfigurationRules(List<String> selectedItems, Id recordId) {
        System.debug('userStoryId' + recordId);
        System.debug('Selected Component IDs: ' + selectedItems);
        
        List <copado__JobStep__c> steps = [
            SELECT Id,
                    copado__UserStory__r.Name, copado__ConfigJson__c 
                   FROM
                   copado__JobStep__c
                   WHERE 
                   copado__UserStory__c = :recordId
        ];
        copado__User_Story__c story = [
            SELECT Id, Name,
                   copado__Environment__c
            FROM copado__User_Story__c 
            WHERE Id = :recordId LIMIT 1

        ];
        System.debug('steps.size()' + steps.size());

        if(steps.isEmpty() == false) {
            deletePreExistingSteps(steps, 'RCA_Deploy_Configuration_Rules');
        }
        copado__JobStep__c jobStep = new copado__JobStep__c();
        String joinedIds = String.join(selectedItems, ',');
        jobStep.copado__ConfigJson__c = '{"functionName":"RCA_Deploy_Configuration_Rules","parameters":[' +
            '{"name":"target","value":"{$Destination.Credential.SessionId}"},' +
            '{"name":"source","value":"{$Source.Credential.SessionId}"},' +
            '{"name":"targetUrl","value":"{$Destination.Credential.EndpointURL}"},' +
            '{"name":"sourceUrl","value":"{$Source.Credential.EndpointURL}"},' +
            '{"name":"recordList","value":"' + joinedIds + '"},' +
            '{"name":"userStoryId","value":"' + recordId + '"}' +
            '],"runOnValidationDeployment":null}';
        jobStep.copado__ExecutionSequence__c = 'after';
        jobStep.copado__IsSkipped__c = false;
        jobStep.copado__Type__c = 'Function';
        jobStep.copado__UserStory__c = story.Id;
        jobStep.copado__CustomType__c = 'Function';
        jobStep.Name = 'Deploy Product Configuration Rules '+ String.valueOf(steps.size() + 1);
        System.debug('Before insert');
        insert jobStep;
        System.debug('After insert');
        List<Product_Configuration_Commits__c> pcrList = new List<Product_Configuration_Commits__c>();
        for (String apiName : selectedItems) {
            System.debug('Selected Component ID: ' + apiName);
            Product_Configuration_Commits__c pcr = new Product_Configuration_Commits__c();
            pcr.Name = apiName;
            pcr.API_Name__c = apiName;
            pcr.User_Story__c = recordId;
            pcrList.add(pcr);
        }
        try {
            insert pcrList;
        } catch (DmlException e) {
            System.debug('Error inserting Product_Configuration_Commits__c records: ' + e.getMessage());
        }  
    }

    @AuraEnabled
    public static void processSelectedAdvancedConfigurationRules(List<String> selectedItems, Id recordId) {
        System.debug('userStoryId' + recordId);
        System.debug('Selected Component IDs: ' + selectedItems);
        
        List <copado__JobStep__c> steps = [
            SELECT Id,
                    copado__UserStory__r.Name, copado__ConfigJson__c 
                   FROM
                   copado__JobStep__c
                   WHERE 
                   copado__UserStory__c = :recordId
        ];
        copado__User_Story__c story = [
            SELECT Id, Name,
                   copado__Environment__c
            FROM copado__User_Story__c 
            WHERE Id = :recordId LIMIT 1

        ];
        System.debug('steps.size()' + steps.size());

        if(steps.isEmpty() == false) {
            deletePreExistingSteps(steps, 'RCA_Constraint_Deployer');
        }
        copado__JobStep__c jobStep = new copado__JobStep__c();
        String joinedIds = String.join(selectedItems, ',');
        jobStep.copado__ConfigJson__c = '{"functionName":"RCA_Constraint_Deployer","parameters":[' +
            '{"name":"target","value":"{$Destination.Credential.SessionId}"},' +
            '{"name":"source","value":"{$Source.Credential.SessionId}"},' +
            '{"name":"targetUrl","value":"{$Destination.Credential.EndpointURL}"},' +
            '{"name":"sourceUrl","value":"{$Source.Credential.EndpointURL}"},' +
            '{"name":"recordList","value":"' + joinedIds + '"},' +
            '{"name":"environmentId","value":"' + story.copado__Environment__c + '"}' +
            '],"runOnValidationDeployment":null}';
        jobStep.copado__ExecutionSequence__c = 'after';
        jobStep.copado__IsSkipped__c = false;
        jobStep.copado__Type__c = 'Function';
        jobStep.copado__UserStory__c = story.Id;
        jobStep.copado__CustomType__c = 'Function';
        jobStep.Name = 'Deploy Advanced Configuration Rules '+ String.valueOf(steps.size() + 1);
        System.debug('Before insert');
        insert jobStep;
        System.debug('After insert');
        List<Product_Configuration_Commits__c> pcrList = new List<Product_Configuration_Commits__c>();
        for (String apiName : selectedItems) {
            System.debug('Selected Component ID: ' + apiName);
            Product_Configuration_Commits__c pcr = new Product_Configuration_Commits__c();
            pcr.Name = apiName;
            pcr.API_Name__c = apiName;
            pcr.User_Story__c = recordId;
            pcrList.add(pcr);
        }
        try {
            insert pcrList;
        } catch (DmlException e) {
            System.debug('Error inserting Product_Configuration_Commits__c records: ' + e.getMessage());
        }  
    }

    @AuraEnabled
    public static void processSelectedAutomations(List<String> selectedItems, Id recordId) {
        System.debug('userStoryId' + recordId);
        System.debug('Selected Component IDs: ' + selectedItems);
        
        List <copado__JobStep__c> steps = [
            SELECT Id,
                    copado__UserStory__r.Name, copado__ConfigJson__c 
                   FROM
                   copado__JobStep__c
                   WHERE 
                   copado__UserStory__c = :recordId
        ];
        copado__User_Story__c story = [
            SELECT Id, Name,
                   copado__Environment__c
            FROM copado__User_Story__c 
            WHERE Id = :recordId LIMIT 1

        ];
        System.debug('steps.size()' + steps.size());

        if(steps.isEmpty() == false) {
            deletePreExistingSteps(steps, 'RCA_Refresh_Decision_Table');
        }
        copado__JobStep__c jobStep = new copado__JobStep__c();
        String joinedIds = String.join(selectedItems, ',');
        jobStep.copado__ConfigJson__c = '{"functionName":"RCA_Refresh_Decision_Table","parameters":[' +
            '{"name":"sessionId","value":"{$Context.Credential.SessionId}"},' +
            '{"name":"environmentUrl","value":"{$Context.Credential.EndpointURL}"},' +
            '{"name":"recordList","value":"' + joinedIds + '"},' +
            '{"name":"userStoryId","value":"' + recordId + '"}' +
            '],"runOnValidationDeployment":null}';
        jobStep.copado__ExecutionSequence__c = 'after';
        jobStep.copado__IsSkipped__c = false;
        jobStep.copado__Type__c = 'Function';
        jobStep.copado__UserStory__c = story.Id;
        jobStep.copado__CustomType__c = 'Function';
        jobStep.Name = 'Refresh Decision Tables '+ String.valueOf(steps.size() + 1);
        System.debug('Before insert');
        insert jobStep;
        System.debug('After insert');
        
    }

    private static void deletePreExistingSteps(List<copado__JobStep__c> existingSteps, String functionName) {
        List<copado__JobStep__c> stepsToDelete = new List<copado__JobStep__c>();
        for(copado__JobStep__c step : existingSteps) {
            if(step.copado__ConfigJson__c != null && step.copado__ConfigJson__c.contains('"functionName":"' + functionName + '"')) {
                stepsToDelete.add(step);
            }
        }
        if(stepsToDelete.isEmpty() == false) {
            try {
                delete stepsToDelete;
            } catch (DmlException e) {
                System.debug('Error deleting old job steps: ' + e.getMessage());
            }
        }
    }

    private static void deletePreviousIndexFiles(Id recordId) {
        copado__User_Story__c userStory = [SELECT Id, copado__Environment__c FROM copado__User_Story__c WHERE Id = :recordId LIMIT 1];

        // Get the latest ContentDocumentId for each file type
        Set<Id> latestDocIds = new Set<Id>();
        for(String fileName : fileNamesByType.values()) {
            List<ContentDocumentLink> latestCdl = [SELECT ContentDocumentId
                                                    FROM ContentDocumentLink
                                                    WHERE LinkedEntityId = :userStory.copado__Environment__c
                                                    AND ContentDocument.Title = :fileName
                                                    ORDER BY SystemModstamp DESC
                                                    LIMIT 1];
            if(!latestCdl.isEmpty()) {
                latestDocIds.add(latestCdl[0].ContentDocumentId);
            }
        }

        // Get all documents except the latest ones
        List<ContentDocumentLink> cdlToDelete = [SELECT ContentDocumentId
                                                FROM ContentDocumentLink
                                                WHERE LinkedEntityId = :userStory.copado__Environment__c
                                                AND ContentDocument.Title IN :fileNamesByType.values()
                                                AND ContentDocumentId NOT IN :latestDocIds];

        if(cdlToDelete.isEmpty() == false) {
            Set<Id> contentDocIds = new Set<Id>();
            for(ContentDocumentLink cdl : cdlToDelete) {
                contentDocIds.add(cdl.ContentDocumentId);
            }
            List<ContentDocument> docsToDelete = [SELECT Id FROM ContentDocument WHERE Id IN :contentDocIds];
            try {
                delete docsToDelete;
            } catch (DmlException e) {
                System.debug('Error deleting old ContentDocuments: ' + e.getMessage());
            }
        }
    }

    public static String getParameterValue(String jsonString, String parameterName) {
        Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(jsonString);
        List<Object> parameters = (List<Object>) parsed.get('parameters');
        
        for (Object param : parameters) {
            Map<String, Object> paramMap = (Map<String, Object>) param;
            if (paramMap.get('name') == parameterName) {
                return (String) paramMap.get('value');
            }
        }
        return null;
    }

    public class RevenueCloudTabDTO {
        @AuraEnabled public List<RevenueCloudItemDTO> items {get; set;}
        @AuraEnabled public String type {get; set;}
        @AuraEnabled public Integer itemCount {get; set;}
        @AuraEnabled public Datetime lastRefreshDate {get; set;}
    }

    public class RevenueCloudItemDTO {
        @AuraEnabled public String label {get; set;}
        @AuraEnabled public String value {get; set;}
        @AuraEnabled public String type {get; set;}
        @AuraEnabled public String description {get; set;}
        @AuraEnabled public String lastModifiedDate {get; set;}
        @AuraEnabled public String lastModifiedBy {get; set;}
        @AuraEnabled public Boolean selected {get; set;}
        @AuraEnabled public String status {get; set;}
        @AuraEnabled public String statusIcon {get; set;}
        @AuraEnabled public String statusColor {get; set;}
    }
}