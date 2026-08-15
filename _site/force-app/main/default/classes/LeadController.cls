public with sharing class LeadController {
    @AuraEnabled(cacheable=true)
    public static Boolean doesLeadExist(String leadName) {
        // Query to check if any lead with the given name exists
        Integer count = [SELECT COUNT() FROM Lead WHERE Name = :leadName];
        return count > 0;
    }
}