({
    doInit: function (component, event, helper) {
        const isMobile = window.innerWidth <= 600;

        // Desktop/tablet: open by default
        // Mobile: closed by default
        component.set("v.isSidebarOpen", !isMobile);
    },

    handleHamburgerToggle: function (component, event, helper) {
        const current = component.get("v.isSidebarOpen");
        component.set("v.isSidebarOpen", !current);
    }
});