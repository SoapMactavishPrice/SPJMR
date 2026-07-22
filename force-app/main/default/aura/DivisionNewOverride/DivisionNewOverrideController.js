({
    onInit : function(component, event, helper) {
        var pageRef = component.get('v.pageReference');
        if (pageRef && pageRef.state && pageRef.state.inContextOfRef) {
            var parentId = helper.decodeInContextOfRef(pageRef.state.inContextOfRef);
            if (parentId) component.set('v.parentContextRecordId', parentId);
        }
    },

    onPageReferenceChange : function(component, event, helper) {
        var pageRef = component.get('v.pageReference');
        if (pageRef && pageRef.state && pageRef.state.inContextOfRef) {
            var parentId = helper.decodeInContextOfRef(pageRef.state.inContextOfRef);
            if (parentId) component.set('v.parentContextRecordId', parentId);
        }
    },

    handleCancel : function(component, event, helper) {
        var navService = component.find('navService');
        if (!navService) return;
        var detail = event.getParam('detail') || {};
        var returnToRecordId = detail.returnToRecordId || component.get('v.parentContextRecordId') || component.get('v.recordId');
        if (returnToRecordId) {
            navService.navigate({
                type: 'standard__recordPage',
                attributes: {
                    recordId: returnToRecordId,
                    actionName: 'view'
                }
            });
        } else {
            navService.navigate({
                type: 'standard__objectPage',
                attributes: {
                    objectApiName: 'Division__c',
                    actionName: 'home'
                }
            });
        }
    }
})