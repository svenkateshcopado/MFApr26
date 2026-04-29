@IsTest
private class RevenueCloudParametersTest {
    
    @IsTest static void testRevenueCloudParameters() {
        ContentVersion cv = new ContentVersion();
        cv.Title = 'Copado Promotion changes';
        cv.VersionData = Blob.valueOf('ExpressionSetDefinition');
        cv.PathOnClient = 'test.json';
        insert cv;
        
        copado__JobExecution__c je = new copado__JobExecution__c(
            copado__DataJson__c = '{ "userStoryIds" : [ "a1vam000000nkRVAAY" ], "userStoryBranches" : [ "feature/US-0000142" ], "sourceCredentialId" : "a11am000004T1WTAA0", "promotionId" : "a17am000084GPkcAAG", "promotionBranchName" : "promotion/P00180", "isBackPromotion" : false, "fileWithSelectedChanges" : "' + cv.Id + '", "executePromotion" : true, "executeDeployment" : true, "destinationCredentialId" : "a11am000004grqPAAQ", "destinationBranchName" : "main", "deploymentDryRun" : false, "blockQueueForTransaction" : true, "action" : "Promotion" }'
        );
        insert je;
        
        copado__JobStep__c js = new copado__JobStep__c(copado__JobExecution__c = je.Id, copado__Type__c = 'Function');
        insert js;
        
        RevenueCloudParameters rcp = new RevenueCloudParameters();
        String result = rcp.execute(js.Id);
        
        Assert.areEqual('true', result, 'Result is true for ExpressionSetDefinition');
    }

}