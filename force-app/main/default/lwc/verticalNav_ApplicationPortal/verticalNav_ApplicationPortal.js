import { LightningElement } from 'lwc';
import customIcons from '@salesforce/resourceUrl/customNavIcons'; 

export default class VerticalNav_ApplicationPortal extends LightningElement {
    customIconsUrl = customIcons;
    selectedItem = 'dashboard';
    
    get menuItems() {
        return [
            {
                label: 'Dashboard',
                name: 'dashboard',
                iconUrl: `${this.customIconsUrl}/dashboard.svg`
            },
            {
                label: 'My Profile',
                name: 'profile',
                iconUrl: `${this.customIconsUrl}/profile.svg`
            },
            {
                label: 'My Queries',
                name: 'queries',
                iconUrl: `${this.customIconsUrl}/query.svg`
            },
            {
                label: 'My Communication',
                name: 'communication',
                iconUrl: `${this.customIconsUrl}/communication.svg`
            },
            {
                label: 'My Payments',
                name: 'payments',
                iconUrl: `${this.customIconsUrl}/payment.svg`
            },
            {
                label: 'FAQ',
                name: 'faq',
                iconUrl: `${this.customIconsUrl}/faq.svg`
            },
            {
                label: 'Logout',
                name: 'logout',
                iconUrl: `${this.customIconsUrl}/logout.svg`
            }
        ];
    }

    handleItemClick(event) {
        const itemName = event.currentTarget.dataset.name;
        this.selectedItem = itemName;
        
        // Dispatch custom event for parent component
        this.dispatchEvent(new CustomEvent('navigate', {
            detail: { name: itemName }
        }));
    }

    handleIconError(event) {
        console.error('Failed to load icon:', event.target.src);
    }
}