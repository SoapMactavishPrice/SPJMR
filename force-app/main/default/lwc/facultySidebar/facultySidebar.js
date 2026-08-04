import { LightningElement, api, track, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { CurrentPageReference } from 'lightning/navigation';
import getObjectApiName from '@salesforce/apex/ApAccountProgramController.getObjectApiName';

export default class facultySidebar extends NavigationMixin(LightningElement) {
    @api isSidebarOpen = false;

    recordId = '';
    selectedMenu = '';

    @track menuItems = [
        { name: 'dashboard', label: 'Dashboard', icon: 'utility:home', page: 'Home' },
        { name: 'slots', label: 'Slot Assignment', icon: 'utility:form', page: 'Slot_Assignment__c' },
        { name: 'logout', label: 'Logout', icon: 'utility:logout' }
    ];

    @track menuSubItems = [
        { name: 'profile', label: 'My Profile', icon: 'utility:user', page: 'User' }
    ];

    @wire(CurrentPageReference)
    getPageRef(pageRef) {
        if (pageRef) {
            let pageName = '';
            if (pageRef.attributes && pageRef.attributes.name) {
                pageName = pageRef.attributes.name;
            } else if (pageRef.attributes && pageRef.attributes.objectApiName) {
                pageName = pageRef.attributes.objectApiName;
            }

            if (pageName) {
                const matchedItem = this.menuItems.find(item => item.page === pageName);
                if (matchedItem) {
                    this.selectedMenu = matchedItem.name;
                } else {
                    const matchedSub = this.menuSubItems.find(item => item.page === pageName);
                    if (matchedSub) {
                        this.selectedMenu = matchedSub.name;
                    }
                }
            }

            if (pageRef.attributes && pageRef.attributes.recordId) {
                this.recordId = pageRef.attributes.recordId;
            } else {
                this.recordId = '';
            }

            this.setActiveMenu(this.selectedMenu);
        }
    }

    @wire(getObjectApiName, { recordId: '$recordId' })
    wiredObjectApiName({ error, data }) {
        if (data) {
            const matchedItem = this.menuItems.find(item => item.page === data);
            if (matchedItem) {
                this.selectedMenu = matchedItem.name;
                this.setActiveMenu(this.selectedMenu);
            } else {
                const matchedSub = this.menuSubItems.find(item => item.page === data);
                if (matchedSub) {
                    this.selectedMenu = matchedSub.name;
                    this.setActiveMenu(this.selectedMenu);
                }
            }
        }
    }

    // getter for sidebar class
    get sidebarClass() {
        return this.isSidebarOpen ? 'sidebar' : 'sidebar collapsed';
    }

    // getter for content class
    get contentClass() {
        return this.isSidebarOpen ? 'content' : 'content expanded';
    }

    connectedCallback() {
        this.setActiveMenu(this.selectedMenu);
    }

    handleMenuClick(event) {        
        const selected = event.currentTarget.dataset.name;
        const selectedItem = this.menuItems.find(item => item.name === selected);
        if (selectedItem) {
            if (selected !== 'logout') {
                this.setActiveMenu(selected);
                this.navigateToPage(event.currentTarget.dataset.page, {}); 
            } else {
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

    navigateToPage(pageApi, state) {
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