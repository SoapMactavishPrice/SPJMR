import { LightningElement, api, wire } from 'lwc';
import getAnnouncements from '@salesforce/apex/ApAccountProgramController.getDashboardAnnouncementsForApplication';

export default class DashboardAnnouncements extends LightningElement {
    @api applicationId;
    @api programName;
    announcements = []; 
    _rendered = false;

    @wire(getAnnouncements, { applicationId: '$applicationId' }) 
    wired({ data, error }) { 
        if (data) { 
            this.announcements = [...data].sort((a, b) => (a.priority || 0) - (b.priority || 0));
            this._rendered = false; 
        } else if (error) { 
            this.announcements = []; 
        }
    }

    renderedCallback() { 
        if (this._rendered) return; 
        const els = this.template.querySelectorAll('.announcement-body'); 
        els.forEach((e, i) => e.innerHTML = this.announcements[i]?.htmlContent || '');
        this._rendered = true; 
    }

    get hasAnnouncements() {
        return this.announcements.length > 0; 
    }

    get sectionLabel() { 
        return this.programName ? `${this.programName} Updates` : 'Application Updates'; 
    }

    get updateLabel() { 
        const n = this.announcements.length; 
        return `${n} update${n === 1 ? '' : 's'}`; 
    }
}