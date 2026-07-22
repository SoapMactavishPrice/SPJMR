import { LightningElement, api, track } from 'lwc';
import search from '@salesforce/apex/GenericLookupController.search';

export default class FineRecordPicker extends LightningElement {

    /* ============================================================
       Public API (LRP-compatible)
       ============================================================ */
    @api objectApiName;
    @api displayInfo;       // { primaryField, additionalFields }
    @api sortInfo;          
    @api matchingInfo;      // { primaryField, additionalFields }
    @api value;
    @api label;
    @api variant;
    @api placeholder;
    @api allowOther = false;

    @api
    set filter(value) {
        const changed = JSON.stringify(value) !== JSON.stringify(this._filter);
        this._filter = value;

        if (changed) {
            this.records = [];
            this.pageState = null;
        }
    }

    get filter() {
        return this._filter;
    }

    /* Public booleans must default to false */
    @api disabled = false;
    @api showPill = false;

    /* Extensions */
    @api pageSize = 50;
    @api paginationMode = 'offset'; // 'offset' | 'keyset'

    /* ============================================================
       Internal state
       ============================================================ */
    @track records = [];
    @track decorated = [];
    @track open = false;
    @track loading = false;
    @track noResults = false;

    searchTerm = '';
    pageState = null;
    activeIndex = -1;

    // Guards
    resolvingSelected = false;
    suppressNextFocusLoad = false;

    /* ============================================================
       Getters
       ============================================================ */

    get hasValue() {
        return this.showPill && !!this.value;
    }

    get hasAdditionalFields() {
        return !!this.displayInfo?.additionalFields?.length;
    }

    showSecondaryLabel = false;

    get showNoResults() {
        return this.open && !this.loading && this.decorated.length === 0 && this.noResults;
    }

    get selectedLabel() {
        const rec = this.decorated.find(r => r.Id === this.value);
        return rec ? rec._primaryLabel : '';
    }

    /**
     * Field API path for label resolution.
     * Fallback is Name.
     */
    get primaryFieldPath() {
        return this.displayInfo?.primaryField || 'Name';
    }

    /* ============================================================
       Lifecycle
       ============================================================ */

    connectedCallback() {
        this._onDocumentClick = this.handleDocumentClick.bind(this);
        document.addEventListener('click', this._onDocumentClick);
    }

    handleDocumentClick(e) {
        this.closeDropdown();
    }

    stopPropagation(e) {
        e.stopPropagation();
    }

    disconnectedCallback() {
        document.removeEventListener('click', this._onDocumentClick);
    }


    renderedCallback() {
        this.loadSelectedRecordIfNeeded();
    }

    /* ============================================================
       Helpers
       ============================================================ */

    resolvePath(obj, path) {
        if (!obj || !path) return '';
        return path.split('.').reduce((o, k) => o?.[k], obj);
    }

    decorateRecords() {
        this.decorated = this.records.map((rec, index) => {
            const primary =
                this.resolvePath(rec, this.primaryFieldPath);

            const secondary =
                (this.displayInfo?.additionalFields || [])
                    .map(f => this.resolvePath(rec, f))
                    .filter(Boolean)
                    .join(' • ');

            return {
                ...rec,
                _index: index,
                _rowClass: index === this.activeIndex ? 'row active' : 'row',
                _primaryLabel: primary,
                _secondaryLabel: secondary,
                _additionalFields:
                    (this.displayInfo?.additionalFields || [])
                        .reduce((acc, f) => {
                            acc[f] = this.resolvePath(rec, f);
                            return acc;
                        }, {})
            };
        });
    }

    /* ============================================================
       Selected value resolution (EDIT MODE)
       ============================================================ */

    async loadSelectedRecordIfNeeded() {
        if (!this.value || !this.showPill) return;
        if (this.resolvingSelected) return;

        // Already resolved
        if (this.decorated.some(r => r.Id === this.value)) return;

        this.resolvingSelected = true;

        try {
            const result = await search({
                objectApiName: this.objectApiName,
                displayInfo: {
                    primaryField: this.primaryFieldPath,
                    additionalFields: this.displayInfo?.additionalFields || []
                },
                sortInfo: this.sortInfo,
                matchingInfo: null, 
                filter: {
                    criteria: [
                        {
                            fieldPath: 'Id',
                            operator: 'eq',
                            value: this.value
                        }
                    ]
                },
                searchTerm: null,
                allowOther: this.allowOther,
                pageState: null,
                pageSize: 2,
                paginationMode: 'offset'
            });

            if (result?.records?.length) {
                this.records = [...result.records];
                this.decorateRecords();

                const rec = this.decorated.find(r => r.Id === this.value);
                if (rec && this.lastResolvedId !== rec.Id) {
                    this.lastResolvedId = rec.Id;
                    this.dispatchEvent(
                        new CustomEvent('lookupset', {
                            detail: { 
                                recordId:rec.Id,
                                primaryLabel:rec._primaryLabel,
                                secondaryLabel:rec._secondaryLabel,
                                additionalFields:rec._additionalFields
                            },
                            bubbles: true,
                            composed: true
                        })
                    );
                }
            }
        } catch (e) {
            console.error(e);
        }
         finally {
            this.resolvingSelected = false;
        }
    }

    lastResolvedId = null;

    /* ============================================================
       Data loading (search / lazy load)
       ============================================================ */

    @track requestSnapshot = {};


    async load(reset = false) {
        if (this.loading) return;

        if (reset) {
            this.records = [];
            this.decorated = [];
            this.pageState = null;
            this.activeIndex = -1;
            this.noResults = false;

            this.hasOtherInResults = false;
            this.waitingForSecondScroll = false;
            this.atBottomLocked = false;
        }

        const currentRequest = {
            objectApiName: this.objectApiName,
            displayInfo: this.displayInfo,
            sortInfo: this.sortInfo,
            matchingInfo: this.matchingInfo,
            filter: this.filter,
            searchTerm: this.searchTerm,
            allowOther: this.allowOther,
            pageState: this.pageState,
            pageSize: this.pageSize,
            paginationMode: this.paginationMode
        };

        if (
            !reset && (
            this.requestSnapshot &&
            JSON.stringify(this.requestSnapshot) === JSON.stringify(currentRequest))
        ) {
            this.loading = false;
            return;
        }

        this.requestSnapshot = currentRequest;


        this.loading = true;

        try {
            const result = await search({
                objectApiName: this.objectApiName,
                displayInfo: this.displayInfo,
                sortInfo: this.sortInfo,
                matchingInfo: this.matchingInfo,
                filter: this.filter,
                searchTerm: this.searchTerm,
                allowOther: this.allowOther,
                pageState: this.pageState,
                pageSize: this.pageSize,
                paginationMode: this.paginationMode
            });

            if (!result || Object.keys(result) == 0) {
                this.loading = false;
                this.noResults = true;
                return;
            }

            const incoming = result.records || [];

            // Append first
            this.records = [...this.records, ...incoming];
            this.dedupeRecordsById();

            // 🔥 THEN normalize the FULL list
            this.normalizeOtherAtEnd();

            this.pageState = result.pageState;
            this.decorateRecords();

            // Mark empty state when there are no records overall for current criteria
            if (this.records.length === 0 && (!this.pageState || incoming.length === 0)) {
                this.noResults = true;
            } else {
                this.noResults = false;
            }
        } catch (error) {
            console.error('fineRecordPicker load', error);
        } finally {
            this.loading = false;
        }
    }

    /* ============================================================
       Event handlers
       ============================================================ */

    handleFocus(event) {
        if (this.disabled) return;

        this.open = true;

        if (!this.suppressNextFocusLoad && !this.records.length) {
            this.load(true);
        }

        this.suppressNextFocusLoad = false;
    }
    
    delayTimeout;

    handleInput(event) {
        this.searchTerm = event.target.value;

        if (this.delayTimeout) {
            clearTimeout(this.delayTimeout);
        }

        this.delayTimeout = setTimeout(() => {
            this.noResults = false;
            this.load(true);
        }, 500);
        
    }

    
    atBottomLocked = false;
    waitingForSecondScroll = false;

    lastBottomHitTs = 0;


    handleScroll(event) {
        const el = event.target;
        const atBottom =
            el.scrollTop + el.clientHeight >= el.scrollHeight - 5;

        if (!atBottom || this.loading) return;

        const now = Date.now();
        const SAME_GESTURE_WINDOW = 250; // ms

        // Ignore repeated bottom hits from same scroll gesture
        if (now - this.lastBottomHitTs < SAME_GESTURE_WINDOW) {
            return;
        }

        this.lastBottomHitTs = now;

        // 🔥 FIRST bottom hit → PAUSE
        if (
            this.hasOtherInResults &&
            !this.waitingForSecondScroll &&
            !!this.pageState
        ) {
            this.waitingForSecondScroll = true;
            return;
        }

        // 🔥 SECOND bottom hit → LOAD
        this.waitingForSecondScroll = false;
        this.load();
    }


    get showScrollAgainHint() {
        return (
            this.open &&
            this.waitingForSecondScroll &&
            !!this.pageState &&        // no hint if no more data
            !this.loading
        );
    }


    hasOtherInResults = false;

    normalizeOtherAtEnd() {
        if (!this.records || !this.records.length) return;

        const others = [];
        const normal = [];

        // Determine which field represents "Other"
        // Priority:
        // 1) filter.otherField if provided
        // 2) displayInfo.primaryField if provided
        // 3) fallback to 'Name'
        const otherFieldPath =
            this.filter?.otherField ||
            this.primaryFieldPath ||
            'Name';

        this.records.forEach(r => {
            const otherFieldValue = this.resolvePath(r, otherFieldPath);
            if (otherFieldValue === 'Other') {
                others.push(r);
            } else {
                normal.push(r);
            }
        });

        this.hasOtherInResults = others.length > 0;

        // 🔥 overwrite records — Other ALWAYS last
        this.records = [...normal, ...others];
    }

    dedupeRecordsById() {
        if (!this.records || !this.records.length) return;

        const seen = new Set();
        this.records = this.records.filter(rec => {
            const id = rec?.Id;

            if (!id) {
                return true;
            }

            if (seen.has(id)) {
                return false;
            }

            seen.add(id);
            return true;
        });
    }



    handleKeyDown(event) {
        if (!this.open) return;

        switch (event.key) {
            case 'ArrowDown':
                event.preventDefault();
                this.activeIndex = Math.min(
                    this.activeIndex + 1,
                    this.records.length - 1
                );
                break;

            case 'ArrowUp':
                event.preventDefault();
                this.activeIndex = Math.max(this.activeIndex - 1, 0);
                break;

            case 'Enter':
                event.preventDefault();
                if (this.activeIndex >= 0) {
                    this.selectByIndex(this.activeIndex);
                }
                break;

            case 'Escape':
                this.closeDropdown();
                break;
        }

        this.decorateRecords();
    }

    /* ============================================================
       Selection
       ============================================================ */

    select(event) {
        const index = Number(event.currentTarget.dataset.index);
        const rec = this.decorated[index];
        if (!rec) return;
        this.selectById(
            rec.Id,
            rec._primaryLabel,
            rec._secondaryLabel,
            rec._additionalFields
        );
    }

    selectByIndex(index) {
        const rec = this.decorated[index];
        if (rec) this.selectById(
            rec.Id,
            rec._primaryLabel,
            rec._secondaryLabel,
            rec._additionalFields
        );
    }

    selectById(recordId, primaryLabel, secondaryLabel, additionalFields) {
        this.value = recordId;
        this.searchTerm = '';
        this.suppressNextFocusLoad = true;
        this.closeDropdown();

        this.dispatchEvent(
            new CustomEvent('lookupchange', {
                detail: { 
                    recordId,
                    primaryLabel,
                    secondaryLabel,
                    additionalFields
                 }
            })
        );
    }

    clear() {
        if (this.disabled) return;

        this.value = null;
        this.searchTerm = '';
        this.records = [];
        this.decorated = [];
        this.pageState = null;
        this.activeIndex = -1;

        this.dispatchEvent(
            new CustomEvent('lookupchange', {
                detail: { 
                    recordId: null,
                    primaryLabel: null,
                    secondaryLabel: null,
                    additionalFields: null
                }
            })
        );

        this.open = true;
        this.load(true);
    }

    /* ============================================================
       Utilities
       ============================================================ */

    closeDropdown(clear = false) {
        this.open = false;

        if (clear) {
            this.searchTerm = '';
            this.records = [];
            this.decorated = [];
            this.pageState = null;
            this.activeIndex = -1;
            this.noResults = false;
        }
    }


}