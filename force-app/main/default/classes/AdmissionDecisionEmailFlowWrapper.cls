@JsonAccess(serializable='always' deserializable='always')
global class AdmissionDecisionEmailFlowWrapper {
    @AuraEnabled
    global String admissionDecisionEmailId;

    @AuraEnabled
    global String contentDocumentId;

    @AuraEnabled
    global String attachmentVersionId;

    @AuraEnabled
    global String admissionDecisionRecordId;

    @AuraEnabled
    global String recipientId;

    global AdmissionDecisionEmailFlowWrapper() {
    }
}