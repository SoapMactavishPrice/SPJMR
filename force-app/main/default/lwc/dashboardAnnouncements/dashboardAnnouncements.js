import { LightningElement, api, wire } from 'lwc';
import getAnnouncements from '@salesforce/apex/ApAccountProgramController.getDashboardAnnouncementsForApplication';

export default class DashboardAnnouncements extends LightningElement {
    @api applicationId;
    @api programName;
    announcements = [];

    @wire(getAnnouncements, { applicationId: '$applicationId' })
    wiredAnnouncements({ data, error }) {
        if (data) {
            this.announcements = [...data].sort(
                (a, b) => (a.priority || 0) - (b.priority || 0)
            );
        } else if (error) {
            this.announcements = [];
            console.error(error);
        }
    }

    get hasAnnouncements() {
        return this.announcements.length > 0;
    }

    get sectionLabel() {
        return this.programName
            ? `${this.programName} Updates`
            : 'Application Updates';
    }
}