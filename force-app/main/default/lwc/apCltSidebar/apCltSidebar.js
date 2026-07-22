import { LightningElement, api, track, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { CurrentPageReference } from 'lightning/navigation';
import getObjectApiName from '@salesforce/apex/ApAccountProgramController.getObjectApiName';
import isDecisionPresent from '@salesforce/apex/ApAccountProgramController.isDecisionPresent';
import getNotificationsUnread from '@salesforce/apex/CommunicationsController.getNotificationsUnread';
import USER_ID from '@salesforce/user/Id';

export default class ApCltSidebar extends NavigationMixin(LightningElement) {
    @api isSidebarOpen = false;
    offerPresent = false;
    recordId = '';

    /* -------------------------
       Track Page Reference
    -------------------------- */
    @wire(CurrentPageReference)
    getPageRef(pageRef) {
        if (pageRef && pageRef.attributes && pageRef.attributes.name) {
            this.selectedMenu =
                this.menuItems.find(i => i.page === pageRef.attributes.name)?.name ??
                this.menuSubItems.find(s => s.page === pageRef.attributes.name)?.name ??
                this.selectedMenu;
        } else if (pageRef?.attributes?.recordId) {
            this.recordId = pageRef.attributes.recordId;
        }
    }

    /* -------------------------
       Object API Name Wire
    -------------------------- */
    @wire(getObjectApiName, { recordId: '$recordId' })
    wiredObjectApiName({ data }) {
        if (data) {
            this.objectApiName = data;
        }
    }

    /* -------------------------
       Default Menu
    -------------------------- */
    selectedMenu = 'dashboard';

    @track menuItems = [
        { name: 'dashboard', label: 'Dashboard', icon: 'utility:home', page: 'Home', isVisible: true },
        // { name: 'applicationlist', label: 'All Applications Form', icon: 'utility:form', page: 'ApplicationList__c', isVisible: true },
        { name:'application-form',label:'Application Form',icon:'utility:form',page:'ApplicationForm_1__c',isVisible:true},
        { name: 'profile', label: 'My Profile', icon: 'utility:user', page: '', isVisible: false },
        { name: 'queries', label: 'My Queries', icon: 'utility:question', page: 'Home', isVisible: false },
        { name: 'my-communications', label: 'My Communication', icon: 'utility:email', page: 'my_communications__c', isVisible: true,isVisible: true,badgeCount: 0,badge: false },
        { name: 'paymenthistory', label: 'My Payments', icon: 'utility:money', page: 'paymenthistory__c', isVisible: true },
        { name: 'faq', label: 'FAQ', icon: 'utility:info', page: 'Home', isVisible: false },
        
        // OFFER ITEM (HIDDEN BY DEFAULT – second last position)
        { name: 'offer', label: 'Offer and Acceptance', icon: 'utility:contract_doc', page: 'OfferAndAcceptance__c', isVisible: false },

        { name: 'logout', label: 'Logout', icon: 'utility:logout', isVisible: true }
    ];

    menuSubItems = [
        { name: 'queries', label: 'My Queries', icon: 'utility:question', page: 'Case' },
        { name: 'profile', label: 'My Profile', icon: 'utility:user', page: 'Account' },
        { name: 'profile', label: 'My Profile', icon: 'utility:user', page: 'User' },
        { name: 'applicationlist', label: 'All Applications Form', icon: 'utility:form', page: 'Application__c' },
        { name: 'application-form', label: 'Application Form', icon: 'utility:form', page: 'ApplicationForm_1__c' }

    ];

    /* -------------------------
       Sidebar CSS Getters
    -------------------------- */
    get sidebarClass() {
        return this.isSidebarOpen ? 'sidebar' : 'sidebar collapsed';
    }

    get contentClass() {
        return this.isSidebarOpen ? 'content' : 'content expanded';
    }

    /* -------------------------
       Connected Callback
    -------------------------- */
    async connectedCallback() {
        console.log('connectedCallback: sidebar');
        getNotificationsUnread()
                .then((result)=>{
                    console.log('Count is ',result)
                    this.notificationCount = result;
                    this.menuItems = this.menuItems.map(item=>{
                        if(item.name == 'my-communications' && result > 0){
                            return{
                                ...item,badgeCount:result,badge:true
                            }
                            
                        }
                        return item;
                    })
                })
                .catch((error)=>{
                    console.log('Error retrieving unread notifications:', error )
                })
            

        // 1️⃣ Check if offer exists from Apex
        isDecisionPresent()
        .then(result => {
            console.log('isDecisionPresent:', result);

            if (result === 'Yes') {
                this.offerPresent = true;

                // Update isVisible for OFFER
                this.menuItems = this.menuItems.map(item => {
                    if (item.name === 'offer') {
                        return { ...item, isVisible: true };
                    }
                    return item;
                });

                console.log('Updated offer menu:', JSON.stringify(this.menuItems));
            }
        })
        .catch(error => {
            console.error('Error retrieving offer decision:', error);
        });

        // 2️⃣ Resolve current page for active highlight
        if (this.recordId) {
            await getObjectApiName({ recordId: this.recordId }).then(result => {
                this.selectedMenu =
                    this.menuItems.find(i => i.page === result)?.name ??
                    this.menuSubItems.find(s => s.page === result)?.name ??
                    this.selectedMenu;
            });
        }

        // 3️⃣ Set active menu
        this.setActiveMenu(this.selectedMenu);
    }

    /* -------------------------
       Menu Click Handler
    -------------------------- */
    handleMenuClick(event) {
        const selected = event.currentTarget.dataset.name;
        const selectedItem = this.menuItems.find(item => item.name === selected);

        if (selectedItem) {
            
            if (selected !== 'logout' && selected !== 'profile') {
                this.setActiveMenu(selected);
                this.navigateToPage(event.currentTarget.dataset.page, {});
            } else if(selected === 'profile') {
                this.setActiveMenu(selected);
                this.navigateToRecordPage(USER_ID, 'User');
            
            } else if(selected == 'application-form'){
                return;
            } 
            else {
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
            attributes: { name: pageApi },
            state: state
        });
    }

    navigateToRecordPage(recordId, objectApiName) {
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId: recordId,
                objectApiName: objectApiName,
                actionName: 'view'
            }
        });
    }

    logoutUser() {
        sessionStorage.clear();
        localStorage.clear();
        window.location.replace('/applicationportal/secur/logout.jsp');
    }
}