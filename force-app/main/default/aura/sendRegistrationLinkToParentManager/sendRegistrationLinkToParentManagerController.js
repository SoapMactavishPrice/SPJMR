({
    doInit: function (component, event, helper) {
        console.log('doInit');
        var action = component.get("c.getParentInfo");
        action.setParams({ accountId: component.get("v.recordId") });
        console.log('doInit');
        // Create a callback that is executed after 
        // the server-side action returns
        action.setCallback(this, function (response) {
            var state = response.getState();
            console.log('doInit',response.getState());
            if (state === "SUCCESS") {
                // Alert the user with the value returned 
                // from the server
                console.log('ReturnValue :->',response.getReturnValue());
                var result = response.getReturnValue();
                for (let index = 0; index < result.length; index++) {
                    result['checked'] = false;
                    
                }
                component.set("v.Account_Parent_List",result);
                console.log('ReturnValue :->',result);
                // You would typically fire a event here to trigger 
                // client-side notification that the server-side 
                // action is complete
            }
            else if (state === "INCOMPLETE") {
                // do something
                console.log('doInit else');
            }
            else if (state === "ERROR") {
                var errors = response.getError();
                if (errors) {
                    if (errors[0] && errors[0].message) {
                        console.log("Error message: " +
                            errors[0].message);
                    }
                } else {
                    console.log("Unknown error");
                }
            }
        });

        // optionally set storable, abortable, background flag here

        // A client-side action could cause multiple events, 
        // which could trigger other events and 
        // other server-side action calls.
        // $A.enqueueAction adds the server-side action to the queue.
        $A.enqueueAction(action);
    },

    onchnageCheckbox: function (component, event, helper) {
        console.log(component.get("v.Account_Parent_List"));
        
    },

    saveClick: function (component, event, helper) {
        console.log('doInit');
        var resultData = JSON.parse(JSON.stringify(component.get("v.Account_Parent_List")));
        console.log('doInit',JSON.parse(JSON.stringify(resultData)));
        console.log('doInit',resultData);
        var ids = [];
        for (let index = 0; index < resultData.length; index++) {
            if(resultData[index].checked == true){
                ids.push(resultData[index].Id);
            }
            
        }
        console.log('doInit',ids);
        var action = component.get("c.sendEmail");
        action.setParams({ ids: ids});
        console.log('doInit');
        // Create a callback that is executed after 
        // the server-side action returns
        action.setCallback(this, function (response) {
            var state = response.getState();
            console.log('doInit',response.getState());
            if (state === "SUCCESS") {
                // Alert the user with the value returned 
                // from the server
                console.log('ReturnValue :->',response.getReturnValue());
                if(response.getReturnValue() == 'success'){
                    var toastEvent = $A.get("e.force:showToast");
                    toastEvent.setParams({
                        "type" : 'success',
                        "title": "Success!",
                        "message": "Email has been sent."
                    });
                    toastEvent.fire();
                    var dismissActionPanel = $A.get("e.force:closeQuickAction");
                    dismissActionPanel.fire();
                }
            }
            else if (state === "INCOMPLETE") {
                // do something
                console.log('doInit else');
            }
            else if (state === "ERROR") {
                var errors = response.getError();
                if (errors) {
                    if (errors[0] && errors[0].message) {
                        console.log("Error message: " +
                            errors[0].message);
                    }
                } else {
                    console.log("Unknown error");
                }
            }
        });
        $A.enqueueAction(action);
    },

})