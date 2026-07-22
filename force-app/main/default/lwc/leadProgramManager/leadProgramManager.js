import { LightningElement, api, track } from 'lwc';
import getLeadSources from '@salesforce/apex/LeadProgramManagerController.getLeadSources';
import getPrograms from '@salesforce/apex/LeadProgramManagerController.getPrograms';
import saveLeadSources from '@salesforce/apex/LeadProgramManagerController.saveLeadSources';

export default class LeadProgramManager extends LightningElement {
    @api recordId;
    @track rows = [];
    @track programOptions = [];

    connectedCallback() {
        this.loadPrograms();
        this.loadRows();
    }

    loadPrograms() {
        getPrograms().then(data => {
            this.programOptions = data.map(p => ({
                label: p.Name,
                value: p.Id
            }));
        });
    }

    loadRows() {
        getLeadSources({ leadId: this.recordId })
            .then(data => {

                if (!data || data.length === 0) {
                    // First time → default single row
                    this.rows = [
                        {
                            id: Date.now(),
                            programId: null,
                            primary: true
                        }
                    ];
                } else {
                    // Show existing record (always 1 because LIMIT 1)
                    const row = data[0];
                    this.rows = [
                        {
                            id: row.Id,
                            programId: row.Program__c,
                            primary: row.Primary__c
                        }
                    ];
                }
            });
    }

    get canRemoveRows() {
        return this.rows.length > 1;
    }

    addRow() {
        this.rows = [
            ...this.rows,
            {
                id: Date.now(),
                programId: null,
                primary: false
            }
        ];
    }

    removeRow(event) {
        const id = event.target.dataset.id;

        if (this.rows.length === 1) return;

        this.rows = this.rows.filter(r => String(r.id) !== String(id));

        // Ensure one primary exists
        if (!this.rows.some(r => r.primary)) {
            this.rows[0].primary = true;
        }
    }

    handleProgramChange(event) {
        const id = event.target.dataset.id;
        const value = event.detail.value;

        this.rows = this.rows.map(r => {
            if (String(r.id) === String(id)) {
                return { ...r, programId: value };
            }
            return r;
        });
    }

    handlePrimaryChange(event) {
        const id = event.target.dataset.id;

        this.rows = this.rows.map(r => ({
            ...r,
            primary: String(r.id) === String(id)
        }));
    }

    saveRecords() {

        const payload = this.rows.map(r => {
            let obj = {
                sobjectType: 'Lead_Sources__c',
                Lead__c: this.recordId,
                Program__c: r.programId,
                Primary__c: r.primary
            };

            // Existing Salesforce Id
            if (String(r.id).length === 18) {
                obj.Id = r.id;
            }

            return obj;
        });

        console.log('🚀 Sending to Apex: ', JSON.stringify(payload));

        saveLeadSources({ leadId: this.recordId, rows: payload })
            .then(() => {
                console.log('💾 SAVE SUCCESS');
                this.loadRows();
            })
            .catch(error => {
                console.error('❌ SAVE ERROR: ', JSON.stringify(error));
            });
    }
}