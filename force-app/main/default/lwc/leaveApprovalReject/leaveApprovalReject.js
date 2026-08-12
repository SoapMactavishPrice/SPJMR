import { LightningElement, api } from 'lwc';
import { CloseActionScreenEvent } from 'lightning/actions';

/**
 * Quick action entry point for "Reject".
 *
 * Exists purely so the action type is known at design time. A screen quick
 * action LWC cannot discover which action launched it, so each action gets its
 * own thin component that hands a fixed mode to the shared form.sdf
 */
export default class LeaveApprovalReject extends LightningElement {
    @api recordId;

    handleClose() {
        this.dispatchEvent(new CloseActionScreenEvent());
    }
}