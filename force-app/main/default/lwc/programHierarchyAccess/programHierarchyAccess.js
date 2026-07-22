import { LightningElement, api, wire } from 'lwc';
import { CurrentPageReference } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { CloseActionScreenEvent } from 'lightning/actions';
import { getRecordNotifyChange } from 'lightning/uiRecordApi';
import getAccessRows from '@salesforce/apex/ProgramHierarchyAccessController.getAccessRows';
import applyChanges from '@salesforce/apex/ProgramHierarchyAccessController.applyChanges';

const ACCESS_LEVEL_OPTIONS = [{ label: 'Edit', value: 'Edit' }];

const USER_DISPLAY_INFO = {
    primaryField: 'Name',
    additionalFields: ['Username']
};

const USER_MATCHING_INFO = {
    primaryField: { fieldPath: 'Name' },
    additionalFields: [{ fieldPath: 'Username' }]
};

const USER_SEARCH_FILTER = {
    criteria: [
        {
            fieldPath: 'IsActive',
            operator: 'eq',
            value: true
        }
    ]
};

/**
 * Maps Apex / platform errors to short user-facing text.
 *
 * @param {object|string} error Error from Apex or LWC wire.
 * @returns {string} Friendly message.
 */
function friendlyError(error) {
    const raw =
        (error && error.body && error.body.message) ||
        (error && error.message) ||
        (typeof error === 'string' ? error : '') ||
        'Something went wrong. Try again or contact your administrator.';
    if (raw.includes('SPJIMR_Program_Access_Group__c')) {
        return 'Program access group is not set up in this org. Deploy the Program Access Group field on Program, then try again.';
    }
    if (raw.includes('public group')) {
        return 'Could not create the program access group. Your administrator may need to grant Manage Public Groups permission.';
    }
    if (raw.includes('Program Id is required')) {
        return 'Open this action from a Program record page.';
    }
    return raw;
}

export default class ProgramHierarchyAccess extends LightningElement {
    @api recordId;

    users = [];
    initialAccessByUserId = new Map();

    accessLevel = 'Edit';
    accessLevelOptions = ACCESS_LEVEL_OPTIONS;
    userDisplayInfo = USER_DISPLAY_INFO;
    userMatchingInfo = USER_MATCHING_INFO;
    userSearchFilter = USER_SEARCH_FILTER;

    isLoading = true;
    isSaving = false;
    showManageList = false;
    loadError;
    saveError;
    pendingChangeCount = 0;

    @wire(CurrentPageReference)
    setPageReference(pageRef) {
        if (!this.recordId && pageRef?.state?.recordId) {
            this.recordId = pageRef.state.recordId;
        }
    }

    @wire(getAccessRows, { programId: '$effectiveProgramId' })
    wiredRows({ data, error }) {
        this.isLoading = false;
        if (data) {
            this.initialAccessByUserId = new Map();
            this.users = data.map((row) => this.toUserRow(row));
            this.loadError = undefined;
            this.showManageList = this.sharedUserCount > 0;
            this.refreshPendingCount();
        } else if (error) {
            this.users = [];
            this.loadError = friendlyError(error);
        }
    }

    get effectiveProgramId() {
        return this.recordId;
    }

    get hasUsers() {
        return this.users.length > 0;
    }

    get sharedUserCount() {
        return this.users.filter((u) => u.draftAccess).length;
    }

    get sharedSummaryText() {
        const n = this.sharedUserCount;
        if (n === 0) {
            return 'Not shared with any users yet.';
        }
        if (n === 1) {
            return 'Shared with 1 user.';
        }
        return `Shared with ${n} users.`;
    }

    get manageLinkLabel() {
        return this.showManageList ? 'Hide' : 'Edit';
    }

    get showEmpty() {
        return !this.isLoading && !this.loadError && this.users.length === 0;
    }

    get saveDisabled() {
        return this.isSaving || !this.recordId || this.isLoading || this.pendingChangeCount === 0;
    }

    /**
     * Builds a UI row from an Apex access row.
     *
     * @param {object} row Apex ProgramAccessUserRow.
     * @returns {object} UI user row.
     */
    toUserRow(row) {
        const userId = row.userId;
        const displayName = row.userName || row.username || 'Unknown user';
        this.initialAccessByUserId.set(userId, row.hasAccess === true);
        return {
            userId,
            displayName,
            username: row.username || '',
            photoUrl: row.photoUrl,
            userUrl: `/lightning/r/User/${userId}/view`,
            draftAccess: row.hasAccess === true
        };
    }

    refreshPendingCount() {
        let count = 0;
        this.users.forEach((row) => {
            const initial = this.initialAccessByUserId.get(row.userId) === true;
            if (row.draftAccess !== initial) {
                count += 1;
            }
        });
        this.pendingChangeCount = count;
    }

    handleToggleManage() {
        this.showManageList = !this.showManageList;
    }

    handleUserSearch(event) {
        const userId = event.detail.recordId;
        if (!userId) {
            return;
        }
        const existing = this.users.find((u) => u.userId === userId);
        if (existing) {
            if (!existing.draftAccess) {
                this.users = this.users.map((u) =>
                    u.userId === userId ? { ...u, draftAccess: true } : u
                );
                this.refreshPendingCount();
            }
            this.showManageList = true;
            return;
        }

        const displayName =
            event.detail.displayValue ||
            (event.detail.record && event.detail.record.fields?.Name?.value) ||
            'User';
        const username =
            event.detail.record && event.detail.record.fields?.Username
                ? event.detail.record.fields.Username.value
                : '';

        const newRow = {
            userId,
            displayName,
            username,
            photoUrl: null,
            userUrl: `/lightning/r/User/${userId}/view`,
            draftAccess: true
        };
        this.initialAccessByUserId.set(userId, false);
        this.users = [...this.users, newRow].sort((a, b) =>
            a.displayName.localeCompare(b.displayName)
        );
        this.showManageList = true;
        this.saveError = undefined;
        this.refreshPendingCount();

        // Clear picker selection for the next search
        const picker = this.template.querySelector('lightning-record-picker');
        if (picker) {
            picker.clearSelection();
        }
    }

    handleAccessToggle(event) {
        const userId = event.currentTarget.dataset.id;
        const checked = event.detail.checked;
        this.users = this.users.map((u) =>
            u.userId === userId ? { ...u, draftAccess: checked } : u
        );
        this.saveError = undefined;
        this.refreshPendingCount();
    }

    async handleSave() {
        if (!this.recordId) {
            this.saveError = friendlyError('Program Id is required.');
            return;
        }

        const grant = [];
        const revoke = [];
        this.users.forEach((row) => {
            const initial = this.initialAccessByUserId.get(row.userId) === true;
            if (row.draftAccess && !initial) {
                grant.push(row.userId);
            }
            if (!row.draftAccess && initial) {
                revoke.push(row.userId);
            }
        });

        if (grant.length === 0 && revoke.length === 0) {
            return;
        }

        this.isSaving = true;
        this.saveError = undefined;
        try {
            await applyChanges({
                programId: this.recordId,
                grantUserIds: grant,
                revokeUserIds: revoke
            });
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Sharing updated',
                    message: 'Program access was saved.',
                    variant: 'success'
                })
            );
            getRecordNotifyChange([{ recordId: this.recordId }]);
            this.dispatchEvent(new CloseActionScreenEvent());
        } catch (e) {
            this.saveError = friendlyError(e);
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Could not save',
                    message: this.saveError,
                    variant: 'error'
                })
            );
        } finally {
            this.isSaving = false;
        }
    }

    handleCancel() {
        this.dispatchEvent(new CloseActionScreenEvent());
    }
}