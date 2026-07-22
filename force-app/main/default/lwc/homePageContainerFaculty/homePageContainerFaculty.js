import { LightningElement, track,wire } from 'lwc';
import { CurrentPageReference } from 'lightning/navigation';
import { getRecord } from 'lightning/uiRecordApi';
import USER_ID from '@salesforce/user/Id';
import NAME_FIELD from '@salesforce/schema/User.Name';
import LOGO from '@salesforce/resourceUrl/SPJIMR_RGB';
// import c_dashboard from 'c/apAccountPrograms';
// import c_applications from 'c/allApplicationsGrid';
// import c_profile from 'c/apMyProfileContainer';
// import c_queries from 'c/apMyQueriesContainer';
// import c_communication from 'c/apMyCommunicationContainer';
// import c_payments from 'c/apMyPaymentsContainer';
// import c_faq from 'c/apFaqContainer';

export default class HomePageContainer extends LightningElement {

    @track userName = '';
    logoUrl = LOGO;
    @track isCollapsed = false;
    @track selectedMenu = 'dashboard';
    @track menuItems = [
        { name: 'dashboard', label: 'Dashboard', icon: 'utility:home' },
        { name: 'slot', label: 'Slot Assignment', icon: 'utility:form'  },
        { name: 'logout', label: 'Logout', icon: 'utility:logout' }
    ];

    // getter for sidebar class
    get sidebarClass() {
        return this.isCollapsed ? 'sidebar collapsed' : 'sidebar';
    }

    // getter for content class
    get contentClass() {
        return this.isCollapsed ? 'content expanded' : 'content';
    }

    get isDashboard() { return this.selectedMenu === 'dashboard'; }
    get isApplications() { return this.selectedMenu === 'applications'; }
    get isProfile() { return this.selectedMenu === 'profile'; }
    get isQueries() { return this.selectedMenu === 'queries'; }
    get isCommunication() { return this.selectedMenu === 'communication'; }
    get isPayments() { return this.selectedMenu === 'payments'; }
    get isFaq() { return this.selectedMenu === 'faq'; }
    get isLogout() { return this.selectedMenu === 'logout'; }

    @wire(getRecord, { recordId: USER_ID, fields: [NAME_FIELD] })
    wireUser({ error, data }) {
        if (data) {
            this.userName = data.fields.Name.value;
        } else if (error) {
            this.userName = 'Guest User';
            console.error('Error fetching user:', error);
        }
    }

    // toggle method
    toggleMenu() {
        this.isCollapsed = !this.isCollapsed;
    }

    // handleMenuClick(event) {
    //     this.selectedMenu = event.currentTarget.dataset.name;
    //     const selected = event.currentTarget.dataset.name;
    //     this.setActiveMenu(selected);
    // }

    connectedCallback() {
        this.setActiveMenu('dashboard');
    }

    handleMenuClick(event) {
        
        const selected = event.currentTarget.dataset.name;
        const selectedItem = this.menuItems.find(item => item.name === selected);
        if (selectedItem) {
            if (selected != 'logout') {
               // this.currentComponent = selectedItem.component;
               this.selectedMenu = event.currentTarget.dataset.name;
                this.setActiveMenu(selected);
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

    logoutUser() {
        // Clear browser cache/sessionStorage
        sessionStorage.clear();
        localStorage.clear();

        // Invalidate session in Salesforce
        window.location.replace('/applicationportal/secur/logout.jsp');
    }
}