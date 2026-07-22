({
    handleSuccess : function(component, event, helper) {
        var detail = event.getParam('detail') || {};
        var recordId = detail.recordId;
        if (recordId) {
            var navService = component.find('navService');
            if (navService) {
                navService.navigate({
                    type: 'standard__recordPage',
                    attributes: {
                        recordId: recordId,
                        objectApiName: 'LearningCourse',
                        actionName: 'view'
                    }
                });
            }
        }
    },

    handleCancel : function(component, event, helper) {
        var navService = component.find('navService');
        if (navService) {
            navService.navigate({
                type: 'standard__objectPage',
                attributes: {
                    objectApiName: 'LearningCourse',
                    actionName: 'home'
                }
            });
        }
    }
})