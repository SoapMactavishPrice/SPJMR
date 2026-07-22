trigger CDLTrigger on ContentDocumentLink (after insert) {
    ContentDocumentLinkHelper.cleanFiles(Trigger.new);
}