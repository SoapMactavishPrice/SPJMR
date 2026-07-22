({
    handleHamburgerToggle: function (component, event, helper) {
        const current = component.get("v.isSidebarOpen");
        component.set("v.isSidebarOpen", !current);
    }
});