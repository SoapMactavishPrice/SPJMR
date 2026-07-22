import { LightningElement, api, wire, track } from 'lwc';
import { CurrentPageReference } from 'lightning/navigation';
import getMenuItems from '@salesforce/apex/StudentProfileDashboardController.getMenuItems';

export default class BaseNavigation extends LightningElement {
    @api menuName;
    @api headerText;

    publishedState;
    @track menuItems = [];
    error;
    isLoaded;
    @track expandedItems = new Set();
    @track activeItemId = null;
    @track isUserInteraction = false;

    get hasMenuItems() {
        return this.menuItems && this.menuItems.length > 0;
    }

    get processedMenuItems() {
        return this.menuItems.map(item => ({
            ...item,
            isExpanded: this.expandedItems.has(item.id),
            hasChildren: item.hasChildren || false
        }));
    }
    //@track menuItems = [];
    decodeHtmlLabel(value) {
        if (!value) {
            return value;
        }

        const txt = document.createElement('textarea');
        txt.innerHTML = value;
        return txt.value;
    }
    @wire(getMenuItems, {
        menuName: '$menuName',
    })
    wiredMenuItems({ error, data }) {
        if (data) {
            this.menuItems = this.transformMenuItems(data);
            if (!this.activeItemId && this.menuItems.length > 0) {
                const homeItem = this.menuItems.find(i =>
                    (i.label || '').toLowerCase().includes('home')
                );
                this.activeItemId = homeItem?.id || this.menuItems[0].id;
            }
            this.expandActiveItems();

        } else if (error) {
            console.log('error::', error);
            this.error = error;
        }
    }
    transformMenuItems(items, parentPath = '') {
        if (!items || !Array.isArray(items)) {
            return [];
        }

        return items.map((item, index) => {

            const itemPath = parentPath ? `${parentPath}-${index}` : `${index}`;
            const uniqueId = item.id || `item-${itemPath}`;


            const decodedLabel = this.decodeHtmlLabel(item.label || '');

            const transformedItem = {
                id: uniqueId,
                label: decodedLabel,
                publicLabel: decodedLabel,
                type: item.actionType || item.type || 'InternalLink',
                target: item.actionValue || item.target || null,
                defaultListViewId: item.defaultListViewId,
                index: index,
                children: null,
                hasChildren: false
            };


            if (item.subMenu && Array.isArray(item.subMenu) && item.subMenu.length > 0) {
                transformedItem.children = this.transformMenuItems(item.subMenu, itemPath);
                transformedItem.hasChildren = true;
            } else if (item.children && Array.isArray(item.children) && item.children.length > 0) {
                transformedItem.children = this.transformMenuItems(item.children, itemPath);
                transformedItem.hasChildren = true;
            }

            return transformedItem;
        });
    }


    processMenuItems(items) {
        return items.map((item, index) => {
            const processedItem = {
                target: item.target,
                id: item.id,
                label: item.label,
                publicLabel: item.publicLabel || item.label,
                index: item.index !== undefined ? item.index : index,
                defaultListViewId: item.defaultListViewId,
                type: item.type,
                children: null,
                hasChildren: false
            };

            // Process children recursively
            if (item.children && item.children.length > 0) {
                processedItem.children = this.processMenuItems(item.children);
                processedItem.hasChildren = true;
            }

            return processedItem;
        });
    }

    filterMenuItems(items) {
        return items
            .map(item => {
                // Filter children recursively
                if (item.children && item.children.length > 0) {
                    const filteredChildren = this.filterMenuItems(item.children);
                    return {
                        ...item,
                        children: filteredChildren.length > 0 ? filteredChildren : null
                    };
                }

                return item;
            })
            .filter(item => item !== null);
    }

    @wire(CurrentPageReference)
    setCurrentPageReference(currentPageReference) {
        if (this.isUserInteraction) {
            return;
        }
        const app =
            currentPageReference &&
            currentPageReference.state &&
            currentPageReference.state.app;
        if (app === 'commeditor') {
            this.publishedState = 'Draft';
        } else {
            this.publishedState = 'Live';
        }
    }

    get isNavReady() {
        return this.menuItems.length > 0 && this.activeItemId;
    }

    handleItemSelected(event) {
        const selectedItem = event.detail.item;

        if (!selectedItem || !selectedItem.id) return;

        // 🔒 user has manually selected
        this.isUserInteraction = true;
        this.activeItemId = selectedItem.id;

        // keep your expand logic
        this.ensureParentExpanded(selectedItem.id, this.menuItems);
    }


   

    handleEnsureParentExpanded(event) {
        // Immediately expand parent when child is about to navigate
        const itemId = event.detail.itemId;
        const wasExpanded = this.ensureParentExpanded(itemId, this.menuItems);

        // If we expanded something, trigger multiple re-checks to ensure state persists
        if (wasExpanded) {
            // Immediate re-check
            setTimeout(() => {
                this.expandActiveItems();
            }, 50);

            // Re-check after navigation likely completes
            setTimeout(() => {
                this.expandActiveItems();
            }, 300);

            setTimeout(() => {
                this.expandActiveItems();
            }, 600);
        }
    }

    handleToggleExpand(event) {
        const itemId = event.detail.itemId;
        const forceExpand = event.detail.forceExpand;

        // If forceExpand is true, just add it (don't toggle)
        if (forceExpand) {
            if (!this.expandedItems.has(itemId)) {
                this.expandedItems.add(itemId);
                // Force reactivity by creating new Set - this will trigger getter recalculation
                this.expandedItems = new Set(this.expandedItems);
            }
        } else {
            // Normal toggle behavior
            if (this.expandedItems.has(itemId)) {
                this.expandedItems.delete(itemId);
            } else {
                this.expandedItems.add(itemId);
            }
            // Force reactivity by creating new Set - this will trigger getter recalculation
            this.expandedItems = new Set(this.expandedItems);
        }
    }

    connectedCallback() {
        this.restoreExpandedState();
    }

    restoreExpandedState() {
        // Restore expanded items from sessionStorage
        try {
            const currentUrl = window.location.pathname + window.location.search;
            const storedActiveUrl = sessionStorage.getItem('nav_active_url');

            // If current URL matches stored active URL, restore expanded state
            if (storedActiveUrl && currentUrl.includes(storedActiveUrl)) {
                // Find the item and expand its parents
                this.expandActiveItems();
            }
        } catch (e) {
            console.warn('Could not restore navigation state:', e);
        }
    }

    // expandActiveItems() {

    //     const currentUrl = window.location.pathname + window.location.search;
    //     if (this.menuItems && this.menuItems.length > 0) {
    //         this.checkAndExpandActive(this.menuItems, currentUrl);
    //     }
    // }
    expandActiveItems() {

        if (this.isUserInteraction) {
            return;
        }

        const currentUrl = window.location.pathname + window.location.search;
        if (this.menuItems && this.menuItems.length > 0) {
            this.checkAndExpandActive(this.menuItems, currentUrl);
        }
    }

    checkAndExpandActive(items, currentUrl, parentId = null) {
        if (!items || items.length === 0) return false;

        let foundActive = false;

        // Normalize current URL - check if it's exactly /demo or /demo/
        const normalizedCurrentUrl = currentUrl.toLowerCase().split('?')[0].replace(/\/$/, '');
        const isBaseDemoPage = normalizedCurrentUrl === '/demo' || normalizedCurrentUrl.endsWith('/demo');

        for (const item of items) {
            // Check if this item matches current URL
            if (item.target) {
                const itemUrl = item.target.toLowerCase();
                const url = currentUrl.toLowerCase();

                // Normalize URLs for comparison
                const normalizedItemUrl = itemUrl.split('?')[0].replace(/\/$/, '');

                // If we're on the base /demo page, only match Dashboard
                if (isBaseDemoPage) {
                    const label = (item.label || item.publicLabel || '').toLowerCase();
                    if (label.includes('dashboard')) {
                        // Found Dashboard, expand all its parents
                        this.ensureParentExpanded(item.id, this.menuItems);

                        // 🔑 SET ACTIVE ITEM FROM URL (ONLY IF USER DID NOT CLICK)
                        if (!this.isUserInteraction) {
                            this.activeItemId = item.id;
                        }

                        foundActive = true;
                        // Continue to check children
                    }
                } else {
                    // For other pages, use strict URL matching
                    // Only match if URLs are exactly the same or current URL starts with item URL
                    if (normalizedCurrentUrl === normalizedItemUrl ||
                        (normalizedItemUrl && normalizedCurrentUrl.startsWith(normalizedItemUrl + '/'))) {
                        // Found active item, expand all its parents
                        this.ensureParentExpanded(item.id, this.menuItems);

                        // 🔑 SET ACTIVE ITEM FROM URL (ONLY IF USER DID NOT CLICK)
                        if (!this.isUserInteraction) {
                            this.activeItemId = item.id;
                        }

                        foundActive = true;
                    }
                }
            }

            // Recursively check children
            if (item.children && item.children.length > 0) {
                const childFound = this.checkAndExpandActive(item.children, currentUrl, item.id);
                if (childFound) {
                    // If a child is active, expand this parent
                    this.expandedItems.add(item.id);
                    this.expandedItems = new Set(this.expandedItems);
                    foundActive = true;
                }
            }
        }

        return foundActive;
    }

    ensureParentExpanded(itemId, items, parentId = null) {
        let expanded = false;
        const itemsToExpand = [];

        for (const item of items) {
            if (item.id === itemId && parentId) {
                // Found the item, expand its parent
                if (!this.expandedItems.has(parentId)) {
                    itemsToExpand.push(parentId);
                    expanded = true;
                }
            }
            if (item.children && item.children.length > 0) {
                if (this.ensureParentExpanded(itemId, item.children, item.id)) {
                    // If found in children, expand this parent too
                    if (!this.expandedItems.has(item.id)) {
                        itemsToExpand.push(item.id);
                        expanded = true;
                    }
                }
            }
        }

        // Add all items to expand at once
        if (itemsToExpand.length > 0) {
            itemsToExpand.forEach(id => this.expandedItems.add(id));
            // Force reactivity by creating new Set - this will trigger getter recalculation
            this.expandedItems = new Set(this.expandedItems);
        }

        return expanded;
    }
}