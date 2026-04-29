@SuppressWarnings('PMD.AvoidGlobalModifier')

global class RevenueCloudParameters implements copado.ParameterExpressionCallable {

    global RevenueCloudParameters(){}
    
    global String execute(Id contextId) {
        copado__JobStep__c jobStep = [SELECT Id, copado__JobExecution__c FROM copado__JobStep__c WHERE Id = :contextId];
        copado__JobExecution__c jobExecution = [SELECT Id, copado__DataJson__c FROM copado__JobExecution__c WHERE Id = :jobStep.copado__JobExecution__c];
        Map<String, Object> dataJson = (Map<String, Object>) JSON.deserializeUntyped(jobExecution.copado__DataJson__c);
        String fileWithSelectedChangesId = (String) dataJson.get('fileWithSelectedChanges');
        ContentVersion fileWithSelectedChanges = [SELECT Id, VersionData FROM ContentVersion WHERE Id = :fileWithSelectedChangesId];
        String fileWithSelectedChangesContent = fileWithSelectedChanges.VersionData.toString();
        System.debug(fileWithSelectedChangesContent);
        if(fileWithSelectedChangesContent.contains('ExpressionSetDefinition') || fileWithSelectedChangesContent.contains('ExpressionSetDefinitionVersion') ) {
            return 'true';
        } else {
            return 'false';
        }
    }

}