import { LightningElement, api, track, wire } from 'lwc';
import { NavigationMixin, CurrentPageReference } from 'lightning/navigation';
import basePath from '@salesforce/community/basePath';

export default class MainNavigation extends NavigationMixin(
    LightningElement
) {
    @api item = {};
    @api isExpanded = false;

    @track href = '#';
    @track expandedChildren = new Set();
    @track currentPageUrl = '';
    pageReference;

normalizeLabel(label) {
    return (label || '')
        .toLowerCase()
        .replace(/&/g, 'and')     // & → and
        .replace(/\s+/g, ' ')    // collapse spaces
        .trim()
        .replace(/\s/g, '_');    // spaces → _
}
    get menuIcon() {
    // If icon is explicitly provided from backend, use it
    if (this.item?.iconName) {
        return this.item.iconName;
    }

    const label = this.normalizeLabel(
        this.item?.publicLabel || this.item?.label
    );

    const ICON_MAP = {
        student_details: 'utility:user',
        programme_details: 'utility:apps',
        term_deatil:'utility:chevronright',
        academic_scheduler: 'utility:checkin',
        leave_and_attendance: 'utility:event',
        attendance: 'utility:event',
        logout: 'utility:logout'
        // exams_and_evaluation: 'utility:note',
        // academics_and_learning: 'utility:education',
        // finance_and_ledger: 'utility:money',
        // mentorship_and_mqr: 'utility:groups',
        // hostel_and_campus_logistics: 'utility:company',
        // reports_and_certificates: 'utility:chart',
        // project_and_capstone: 'utility:kanban',
        // ticker_management: 'utility:case',
    };

    return ICON_MAP[label] || 'utility:chevronright';
}

    get hasChildren() {
        return this.item.children && this.item.children.length > 0;
    }

    get children() {
        return this.item.children || [];
    }

    get expandIcon() {
        return this.isExpanded ? 'utility:chevrondown' : 'utility:chevronright';
    }

    get displayIndex() {
        return this.item.index !== undefined && this.item.index !== null 
            ? this.item.index + 1 
            : '';
    }

    get processedChildren() {
        if (!this.hasChildren) {
            return [];
        }
        return this.children.map(child => ({
            ...child,
            hasChildren: (child.children && child.children.length > 0) || false,
            isExpanded: this.expandedChildren.has(child.id)
        }));
    }


    get hasActiveChild() {
        // Check if any child is active (recursively)
        if (!this.hasChildren || !this.children) {
            return false;
        }
        
        // Check each child
        for (const child of this.children) {
            // Create a temporary component-like check
            // We'll use the child's target/href to check
            if (child.target) {
                const currentUrl = this.currentPageUrl || window.location.pathname;
                const childUrl = child.target;
                
                // Simple check - if current URL contains child target or vice versa
                if (currentUrl.toLowerCase().includes(childUrl.toLowerCase()) || 
                    childUrl.toLowerCase().includes(currentUrl.toLowerCase())) {
                    return true;
                }
            }
        }
        
        return false;
    }

    get shouldStayExpanded() {
        // Keep expanded if it's currently expanded OR if it has an active child
        return this.isExpanded || this.hasActiveChild;
    }

    @wire(CurrentPageReference)
    setCurrentPageReference(currentPageReference) {
        if (currentPageReference) {
            // Get the current page URL from various possible locations
            let url = '';
            
            if (currentPageReference.attributes && currentPageReference.attributes.url) {
                url = currentPageReference.attributes.url;
            } else if (currentPageReference.state) {
                // Check various state properties
                if (currentPageReference.state.c__url) {
                    url = currentPageReference.state.c__url;
                } else if (currentPageReference.state.url) {
                    url = currentPageReference.state.url;
                }
            }
            
            // Fallback to window location
            if (!url) {
                url = window.location.pathname + window.location.search;
            }
            
            this.currentPageUrl = url;
            
            // If this item or any child is active, ensure parent is expanded
            if (this.isActive || this.hasActiveChild) {
                this.dispatchEvent(new CustomEvent('ensureexpanded', {
                    detail: { itemId: this.item.id },
                    bubbles: true,
                    composed: true
                }));
            }
        } else {
            // Fallback to window location if no page reference
            this.currentPageUrl = window.location.pathname + window.location.search;
        }
    }

   
    @api activeItemId;

get isActive() {
    return this.activeItemId === this.item.id;
}

    get ariaHidden() {
        return !this.isExpanded;
    }

    connectedCallback() {
        const { type, target, defaultListViewId } = this.item;

        // Only create page reference if target exists (skip parent items with only submenus)
        if (target) {
            // Get the correct PageReference object for the menu item type
            if (type === 'SalesforceObject') {
                this.pageReference = {
                    type: 'standard__objectPage',
                    attributes: {
                        objectApiName: target
                    },
                    state: {
                        filterName: defaultListViewId
                    }
                };
            } else if (type === 'InternalLink') {
                // Ensure target starts with / for internal links
                const url = target.startsWith('/') ?  target : basePath + '/' + target;
                this.pageReference = {
                    type: 'standard__webPage',
                    attributes: {
                        url: url
                    }
                };
            } else if (type === 'ExternalLink') {
                this.pageReference = {
                    type: 'standard__webPage',
                    attributes: {
                        url: target
                    }
                };
            }

            // Generate URL for navigation
            if (this.pageReference) {
                this[NavigationMixin.GenerateUrl](this.pageReference).then(
                    (url) => {
                        this.href = url;
                    }
                ).catch((error) => {
                    console.error('Error generating URL:', error);
                    this.href = '#';
                });
            }
        } else {
            // For items without target (parent items with submenus), set href to #
            this.href = '#';
        }
    }

    handleClick(evt) {
        evt.stopPropagation();
        evt.preventDefault();

        // If item has children, ALWAYS toggle expansion (don't navigate)
        if (this.hasChildren) {
            // Parent items with children should only toggle, never navigate
            this.dispatchEvent(new CustomEvent('toggleexpand', {
                detail: {
                    itemId: this.item.id
                },
                bubbles: true,
                composed: true
            }));
        } else if (this.pageReference && this.item.target) {
            // For leaf items, ensure parent is expanded BEFORE navigation
            // Fire the event immediately and synchronously
            const ensureEvent = new CustomEvent('ensureparentexpanded', {
                detail: {
                    itemId: this.item.id
                },
                bubbles: true,
                composed: true
            });
            this.dispatchEvent(ensureEvent);
            
            // Also fire itemselected to trigger parent expansion
            this.dispatchEvent(new CustomEvent('itemselected', {
                detail: {
                    item: {
                        ...this.item,
                        hasChildren: this.hasChildren
                    }
                },
                bubbles: true,
                composed: true
            }));
            
            // Use a small delay to ensure parent expansion is processed before navigation
            setTimeout(() => {
                // Then navigate
                if (this.pageReference) {
                    this[NavigationMixin.Navigate](this.pageReference);
                }
            }, 100);
            
            return;
        }

        // Emit itemselected event
        this.dispatchEvent(new CustomEvent('itemselected', {
            detail: {
                item: {
                    ...this.item,
                    hasChildren: this.hasChildren
                }
            },
            bubbles: true,
            composed: true
        }));
    }

    handleChildItemSelected(event) {
        // When a child is selected, ALWAYS ensure this parent stays expanded
        // The event.detail.item contains the child item that was selected
        const selectedChildItem = event.detail.item;
        
        // 1. First, ensure this parent is expanded (force expand, don't toggle)
        this.dispatchEvent(new CustomEvent('toggleexpand', {
            detail: {
                itemId: this.item.id,
                forceExpand: true  // Signal to force expand, don't toggle
            },
            bubbles: true,
            composed: true
        }));
        
        // 2. Also fire ensureparentexpanded with the child's ID so it can find this parent
        if (selectedChildItem && selectedChildItem.id) {
            this.dispatchEvent(new CustomEvent('ensureparentexpanded', {
                detail: {
                    itemId: selectedChildItem.id  // Use child's ID to find its parent
                },
                bubbles: true,
                composed: true
            }));
        }
        
        // 3. Bubble up the itemselected event (which also triggers parent expansion)
        this.dispatchEvent(new CustomEvent('itemselected', {
            detail: event.detail,
            bubbles: true,
            composed: true
        }));
    }

    handleChildToggleExpand(event) {
        // Handle expanded state for nested children locally
        const itemId = event.detail.itemId;
        if (this.expandedChildren.has(itemId)) {
            this.expandedChildren.delete(itemId);
        } else {
            this.expandedChildren.add(itemId);
        }
        // Force reactivity by creating new Set
        this.expandedChildren = new Set(this.expandedChildren);
        
        // Also bubble up the event to parent
        this.dispatchEvent(new CustomEvent('toggleexpand', {
            detail: event.detail,
            bubbles: true,
            composed: true
        }));
    }

    handleChildEnsureParentExpanded(event) {
        // When a grandchild is selected, ensure this parent and its parent stay expanded
        if (!this.isExpanded) {
            this.dispatchEvent(new CustomEvent('toggleexpand', {
                detail: {
                    itemId: this.item.id
                },
                bubbles: true,
                composed: true
            }));
        }
        
        // Bubble up the event
        this.dispatchEvent(new CustomEvent('ensureparentexpanded', {
            detail: event.detail,
            bubbles: true,
            composed: true
        }));
    }
}