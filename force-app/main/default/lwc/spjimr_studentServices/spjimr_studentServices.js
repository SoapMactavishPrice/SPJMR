import { LightningElement } from 'lwc';

const TAB_WITHDRAWAL = 'withdrawal';
const TAB_DEFERMENT = 'deferment';

export default class Spjimr_studentServices extends LightningElement {
    activeTab = TAB_DEFERMENT;

    get isWithdrawalActive() {
        return this.activeTab === TAB_WITHDRAWAL;
    }

    get isDefermentActive() {
        return this.activeTab === TAB_DEFERMENT;
    }

    get withdrawalTabClass() {
        return this.isWithdrawalActive
            ? 'ss-tab ss-tab_active'
            : 'ss-tab';
    }

    get defermentTabClass() {
        return this.isDefermentActive
            ? 'ss-tab ss-tab_active'
            : 'ss-tab';
    }

    handleWithdrawalClick() {
        this.activeTab = TAB_WITHDRAWAL;
    }

    handleDefermentClick() {
        this.activeTab = TAB_DEFERMENT;
    }
}