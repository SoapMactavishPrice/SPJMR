import { LightningElement, api, track, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { CurrentPageReference } from 'lightning/navigation';
import getObjectApiName from '@salesforce/apex/ApAccountProgramController.getObjectApiName';

export default class facultySidebar extends NavigationMixin(LightningElement) {
    @api isSidebarOpen = false;

    recordId = '';

    

   


    selectedMenu = 'dashboard';
    menuItems = [
        { name: 'dashboard', label: 'Dashboard', icon: 'utility:home', page: 'Home' },
        { name: 'slots', label: 'Slot Assignment', icon: 'utility:form', page: 'Slot_Assignment__c' },
       { name: 'logout', label: 'Logout', icon: 'utility:logout' }
    ];

    menuSubItems = [
        
        { name: 'profile', label: 'My Profile', icon: 'utility:user', page: 'User' },
        
    ];

    // getter for sidebar class
    get sidebarClass() {
        return this.isSidebarOpen ? 'sidebar' : 'sidebar collapsed';
    }

    // getter for content class
    get contentClass() {
        return this.isSidebarOpen ? 'content' : 'content expanded';
    }

   

    handleMenuClick(event) {        
        const selected = event.currentTarget.dataset.name;
        const selectedItem = this.menuItems.find(item => item.name === selected);
        if (selectedItem) {
            if (selected != 'logout') {
                this.setActiveMenu(selected);
                this.navigateToPage(event.currentTarget.dataset.page,{}); 
            }else{
                console.log('logout');
                this.logoutUser();
            }
        }
    }

    setActiveMenu(activeName) {
        this.menuItems = this.menuItems.map(item => ({
            ...item,
            class: `menu-item ${item.name === activeName ? 'active' : ''}`
        }));
    }

    navigateToPage(pageApi,state) {
        this[NavigationMixin.Navigate]({
            type: 'comm__namedPage',
            attributes: {
                name: pageApi   // developer name of the page
            },
            state: state
        });
    }

    logoutUser() {
        // Clear browser cache/sessionStorage
        sessionStorage.clear();
        localStorage.clear();

        // Invalidate session in Salesforce
        window.location.replace('/facultyportal/secur/logout.jsp');
    }
}