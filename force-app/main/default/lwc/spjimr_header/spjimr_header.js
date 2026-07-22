import { LightningElement, api, track } from 'lwc';
import logo from '@salesforce/resourceUrl/Site_Logo';
import getUserInfo from '@salesforce/apex/StudentProfileDashboardController.getUserInfo';
import getProfilePhotoBase64 from '@salesforce/apex/StudentProfileDashboardController.getProfilePhotoBase64';
import getPortalNotifications from '@salesforce/apex/PortalNotificationController.getPortalNotifications';
import markNotificationsRead from '@salesforce/apex/PortalNotificationController.markNotificationsRead';
import navbarIcon from '@salesforce/resourceUrl/Navbar_Icon';

const NOTIF_POLL_MS = 60 * 1000;

export default class Spjimr_header extends LightningElement {
    logoImage = logo;
    navbarIcon = navbarIcon;
    studentName = '';
    @track profilePhotoUrl = null;
    accountId = null;

    @api userRole = 'Salesforce Developer';

    // --- Portal notifications state ---
    @track notifications = [];
    @track unreadCount = 0;
    @track notifPanelOpen = false;
    _notifIntervalId = null;
    _boundHandleDocumentClick = null;

    get hasUnread() {
        return this.unreadCount > 0;
    }

    get unreadCountDisplay() {
        return this.unreadCount > 9 ? '9+' : String(this.unreadCount);
    }

    get hasNotifications() {
        return this.notifications && this.notifications.length > 0;
    }

    get isEmpty() {
        return !this.hasNotifications;
    }

    get notifBellBtnClass() {
        return 'notif-bell-btn' + (this.notifPanelOpen ? ' notif-bell-btn--active' : '');
    }

    get hasProfilePhoto() {
        return !!(this.profilePhotoUrl && String(this.profilePhotoUrl).trim());
    }

    handleMenuClick() {
        this.dispatchEvent(new CustomEvent('menuclick'));
    }

    handleUserProfileClick() {
        this.dispatchEvent(new CustomEvent('profileclick'));
    }

    connectedCallback() {
        this._boundHandleDocumentClick = this.handleDocumentClick.bind(this);
        // Capture phase: fires before any handler in the click path can stop
        // propagation or trigger navigation, so the panel always gets a chance to close.
        document.addEventListener('click', this._boundHandleDocumentClick, true);
        this.loadUserName();
        this.loadNotifications();
        this._notifIntervalId = setInterval(() => {
            this.loadNotifications();
        }, NOTIF_POLL_MS);

    }

    disconnectedCallback() {
        if (this._boundHandleDocumentClick) {
            document.removeEventListener('click', this._boundHandleDocumentClick, true);
            this._boundHandleDocumentClick = null;
        }
        if (this._notifIntervalId != null) {
            clearInterval(this._notifIntervalId);
            this._notifIntervalId = null;
        }

    }

    loadUserName() {
        getUserInfo()
            .then((result) => {
                if (result) {
                    this.studentName = result.fullName ? result.fullName : null;
                    this.accountId = result.accountId || null;
                    if (this.accountId) {
                        this.loadHeaderProfilePhoto();
                    } else {
                        this.profilePhotoUrl = null;
                    }
                } else {
                    this.profilePhotoUrl = null;
                }
            })
            .catch((error) => {
                console.error('Error fetching user info:', error);
            });
    }

    loadHeaderProfilePhoto() {
        if (!this.accountId) {
            this.profilePhotoUrl = null;
            return;
        }
        getProfilePhotoBase64({ accountId: this.accountId })
            .then((dataUrl) => {
                if (dataUrl && typeof dataUrl === 'string' && dataUrl.startsWith('data:image')) {
                    this.profilePhotoUrl = dataUrl;
                } else {
                    this.profilePhotoUrl = null;
                }
            })
            .catch(() => {
                this.profilePhotoUrl = null;
            });
    }

    handleHeaderProfilePhotoError() {
        this.profilePhotoUrl = null;
    }

    // --- Portal notifications handlers ---
    loadNotifications() {
        getPortalNotifications()
            .then((result) => {
                console.log('notifcation result::',result);
                if (!result) return;
                this.unreadCount = result.unreadCount || 0;
                this.notifications = (result.notifications || []).map((n) => ({
                    ...n,
                    itemClass: 'notif-item' + (n.isRead ? '' : ' notif-item--unread')
                }));
            })
            .catch((error) => {
                console.error('Error fetching portal notifications:', error);
            });
    }

    handleNotifBellClick() {
        this.notifPanelOpen = !this.notifPanelOpen;
    }

    handleDocumentClick(event) {
        if (!this.notifPanelOpen) return;
        const host = this.template.host;
        const clickPath = event.composedPath ? event.composedPath() : [];
        const clickedInsideComponent = host && (
            (clickPath.length ? clickPath.includes(host) : false) ||
            host.contains(event.target)
        );
        if (!clickedInsideComponent) {
            this.notifPanelOpen = false;
        }
    }

    handleNotifItemClick(event) {
        const notifId = event.currentTarget.dataset.id;
        if (!notifId) return;

        // Optimistically mark as read in the UI
        this.notifications = this.notifications.map((n) => {
            if (n.id === notifId && !n.isRead) {
                this.unreadCount = Math.max(0, this.unreadCount - 1);
                return { ...n, isRead: true, itemClass: 'notif-item' };
            }
            return n;
        });

        markNotificationsRead({ notificationIds: [notifId] }).catch((error) => {
            console.error('Error marking notification as read:', error);
        });
    }

    handleMarkAllRead() {
        const unreadIds = this.notifications.filter((n) => !n.isRead).map((n) => n.id);
        if (unreadIds.length === 0) return;

        this.notifications = this.notifications.map((n) => ({
            ...n,
            isRead: true,
            itemClass: 'notif-item'
        }));
        this.unreadCount = 0;

        markNotificationsRead({ notificationIds: unreadIds }).catch((error) => {
            console.error('Error marking all notifications as read:', error);
        });
    }
   
}