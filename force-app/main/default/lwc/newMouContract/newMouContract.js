import { LightningElement, api, track, wire } from "lwc";

import getProgramOptions from "@salesforce/apex/MOUContractController.getProgramOptions";
import resolveSlab from "@salesforce/apex/MOUContractController.resolveSlab";
import saveMOUContract from "@salesforce/apex/MOUContractController.saveMOUContract";
import getPrimaryContacts from "@salesforce/apex/MOUContractController.getPrimaryContacts";

import { ShowToastEvent } from "lightning/platformShowToastEvent";
import { CloseActionScreenEvent } from "lightning/actions";

export default class NewMouContract extends LightningElement {

    @api recordId;

    @track programOptions = [];
    @track rows = [];
    @track mou = {};

    /* ===============================
       PRIMARY CONTACTS VARIABLES
    =============================== */
    @track contacts = [];
    @track selectedContacts = [];

    pageSize = 5;
    pageNumber = 1;
    totalContacts = 0;

    isLoadingContacts = false;
    contactsLoadedOnce = false;

    key = 1;

    statusOptions = [
        { label: "Draft", value: "Draft" },
        { label: "Negotiation", value: "Negotiation" },
        { label: "Renewed", value: "Renewed" }
    ];

    /* ===============================
       LOAD PROGRAM PICKLIST
    =============================== */
    @wire(getProgramOptions)
    wiredPrograms({ data, error }) {
        if (data) {
            this.programOptions = data;
        } else if (error) {
            this.showToast("Error", "Unable to load Programs", "error");
            // helpful debug
            // eslint-disable-next-line no-console
            console.log("Program Options Error:", JSON.stringify(error));
        }
    }

    /* ===============================
       LOAD CONTACTS WHEN recordId READY
       (Quick Action timing safe)
    =============================== */
    renderedCallback() {
        if (this.recordId && !this.contactsLoadedOnce) {
            this.contactsLoadedOnce = true;
            this.loadContacts();
        }
    }

    get selectedContactsCount() {
        return this.selectedContacts?.length || 0;
    }

    async loadContacts() {
        if (!this.recordId) return;

        this.isLoadingContacts = true;

        try {
            const res = await getPrimaryContacts({
                leadId: this.recordId,
                pageSize: this.pageSize,
                pageNumber: this.pageNumber
            });

            const records = res?.records || [];
            this.totalContacts = res?.total || 0;

            // Preserve checked status across pages
            const selectedSet = new Set(this.selectedContacts);
            this.contacts = records.map(r => ({
                ...r,
                _checked: selectedSet.has(r.Id)
            }));

        } catch (e) {
            // eslint-disable-next-line no-console
            console.log("Primary Contacts Error:", JSON.stringify(e));
            this.showToast(
                "Error",
                e?.body?.message || "Unable to load Primary Contacts",
                "error"
            );
            this.contacts = [];
            this.totalContacts = 0;
        } finally {
            this.isLoadingContacts = false;
        }
    }

    /* ===============================
       CHECKBOX SELECT CONTACT
    =============================== */
    handleContactSelect(event) {
        const contactId = event.target.dataset.id;
        const checked = event.target.checked;

        const selectedSet = new Set(this.selectedContacts);

        if (checked) {
            selectedSet.add(contactId);
        } else {
            selectedSet.delete(contactId);
        }

        this.selectedContacts = Array.from(selectedSet);

        // update UI state for current page
        this.contacts = this.contacts.map(c => ({
            ...c,
            _checked: c.Id === contactId ? checked : c._checked
        }));
    }

    get disablePrev() {
        return this.pageNumber === 1;
    }

    get disableNext() {
        return this.pageNumber * this.pageSize >= this.totalContacts;
    }

    nextPage() {
        this.pageNumber++;
        this.loadContacts();
    }

    prevPage() {
        this.pageNumber--;
        this.loadContacts();
    }

    /* ===============================
       UNIVERSAL PARENT FIELD HANDLER
    =============================== */
    handleParentFieldChange(event) {
        const fieldName = event.target.dataset.field;
        const value = event.target.value;

        this.mou = {
            ...this.mou,
            [fieldName]: value
        };
    }

    /* ===============================
       ADD PROGRAM ROW
    =============================== */
    addRow() {
        this.rows = [
            ...this.rows,
            {
                key: this.key++,
                programId: null,
                participants: null,
                slabId: null,
                slabLabel: ""
            }
        ];
    }

    removeRow(event) {
        const index = parseInt(event.target.dataset.index, 10);
        this.rows.splice(index, 1);
        this.rows = [...this.rows];
    }

    handleProgramChange(event) {
        const index = parseInt(event.target.dataset.index, 10);

        this.rows[index] = {
            ...this.rows[index],
            programId: event.detail.value,
            slabId: null,
            slabLabel: ""
        };

        this.rows = [...this.rows];
        this.findSlab(index);
    }

    handleParticipantsChange(event) {
        const index = parseInt(event.target.dataset.index, 10);

        this.rows[index] = {
            ...this.rows[index],
            participants: parseInt(event.target.value, 10),
            slabId: null,
            slabLabel: ""
        };

        this.rows = [...this.rows];
        this.findSlab(index);
    }

    async findSlab(index) {
        const row = this.rows[index];
        if (!row.programId || !row.participants) return;

        try {
            const slab = await resolveSlab({
                programId: row.programId,
                participants: row.participants
            });

            if (slab) {
                row.slabId = slab.id;
                row.slabLabel = slab.name;
            } else {
                row.slabId = null;
                row.slabLabel = "❌ No Slab Found";
            }

            this.rows = [...this.rows];
        } catch (error) {
            row.slabId = null;
            row.slabLabel = "❌ Error Resolving Slab";
            this.rows = [...this.rows];
        }
    }

    /* ===============================
       SAVE CONTRACT + PROGRAMS + CONTACTS
    =============================== */
    async save() {

        if (!this.recordId) {
            this.showToast("Error", "Lead Id missing", "error");
            return;
        }

        if (this.rows.length === 0) {
            this.showToast("Error", "Please add at least one Program row", "error");
            return;
        }

        const payload = this.rows.map(r => ({
            programId: r.programId,
            participants: r.participants,
            slabId: r.slabId
        }));

        try {
            const msg = await saveMOUContract({
                mou: this.mou,
                programRows: payload,
                selectedContactIds: this.selectedContacts,
                leadId: this.recordId
            });

            this.showToast("Success", msg, "success");
            this.dispatchEvent(new CloseActionScreenEvent());

        } catch (e) {
            // eslint-disable-next-line no-console
            console.log("Save Error:", JSON.stringify(e));
            this.showToast(
                "Error",
                e?.body?.message || "Save Failed",
                "error"
            );
        }
    }

    close() {
        this.dispatchEvent(new CloseActionScreenEvent());
    }

    showToast(title, message, variant) {
        this.dispatchEvent(
            new ShowToastEvent({
                title,
                message,
                variant
            })
        );
    }
}