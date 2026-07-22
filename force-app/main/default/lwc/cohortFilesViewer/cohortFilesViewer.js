import { LightningElement, track } from 'lwc';
import searchProgramCohorts from '@salesforce/apex/CohortFilesController.searchProgramCohorts';
import getCohortFiles from '@salesforce/apex/CohortFilesController.getCohortFiles';
import getContentDocumentBodyForZip from '@salesforce/apex/CohortFilesController.getContentDocumentBodyForZip';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { loadScript } from 'lightning/platformResourceLoader';
import JSZIP_RESOURCE from '@salesforce/resourceUrl/cohortJsZip';

const FILE_TYPE_OPTIONS = [
    { label: 'All', value: '' },
    { label: 'PNG', value: 'png' },
    { label: 'JPG / JPEG', value: 'jpeg' },
    { label: 'PDF', value: 'pdf' }
];

const SEARCH_DEBOUNCE_MS = 300;

export default class CohortFilesViewer extends LightningElement {
    @track cohortOptions = [];
    @track cohortSearchTerm = '';
    @track selectedCohortId = null;
    @track selectedCohortLabel = '';
    @track showCohortDropdown = false;
    @track fileTypeOptions = FILE_TYPE_OPTIONS;
    @track selectedFileType = '';
    @track files = [];
    @track isLoadingCohorts = false;
    @track isLoadingFiles = false;
    @track isDownloadingAll = false;
    @track downloadProgress = 0;
    _searchTimeout = null;
    _jsZipLoaded = false;

    get fileTypeOptionsList() {
        return this.fileTypeOptions;
    }

    get hasSelectedCohort() {
        return this.selectedCohortId != null && this.selectedCohortId !== '';
    }

    get cohortDropdownClass() {
        return this.showCohortDropdown ? 'slds-is-open' : '';
    }

    get cohortDropdownTriggerClass() {
        const base = 'cohort-dropdown-trigger slds-dropdown-trigger slds-dropdown-trigger_click';
        return this.showCohortDropdown ? base + ' slds-is-open' : base;
    }

    get hasFiles() {
        return this.files && this.files.length > 0;
    }

    get fileCount() {
        return this.files ? this.files.length : 0;
    }

    get noCohortResults() {
        return this.cohortSearchTerm && this.cohortOptions.length === 0 && !this.isLoadingCohorts;
    }

    get downloadAllDisabled() {
        return !this.hasFiles || this.isDownloadingAll || this.isLoadingFiles;
    }

    get downloadProgressLabel() {
        return `Preparing ZIP... ${this.downloadProgress} / ${this.fileCount}`;
    }

    get downloadProgressPercent() {
        if (!this.fileCount) return 0;
        return Math.floor((this.downloadProgress / this.fileCount) * 100);
    }

    renderedCallback() {
        if (this._jsZipLoaded) return;
        loadScript(this, JSZIP_RESOURCE)
            .then(() => {
                this._jsZipLoaded = true;
            })
            .catch(() => {
                // Surfaced if user clicks Download All before retry succeeds
            });
    }

    handleFileTypeChange(event) {
        this.selectedFileType = event.detail.value || '';
        if (this.hasSelectedCohort) {
            this.loadFiles();
        }
    }

    handleCohortSearchInput(event) {
        const term = (event.target.value || '').trim();
        this.cohortSearchTerm = term;
        this.selectedCohortId = null;
        this.selectedCohortLabel = '';
        this.files = [];
        clearTimeout(this._searchTimeout);
        if (term.length === 0) {
            this.cohortOptions = [];
            this.showCohortDropdown = false;
            return;
        }
        this._searchTimeout = setTimeout(() => {
            this.searchCohorts(term);
        }, SEARCH_DEBOUNCE_MS);
    }

    searchCohorts(term) {
        this.isLoadingCohorts = true;
        this.showCohortDropdown = true;
        searchProgramCohorts({ searchTerm: term || '%' })
            .then((options) => {
                this.cohortOptions = options || [];
            })
            .catch((err) => {
                this.cohortOptions = [];
                this.showToast('Error', (err.body && err.body.message) || err.message || 'Search failed', 'error');
            })
            .finally(() => {
                this.isLoadingCohorts = false;
            });
    }

    handleCohortFocus() {
        if (this.cohortSearchTerm && this.cohortOptions.length > 0) {
            this.showCohortDropdown = true;
        } else if (this.cohortSearchTerm.trim().length > 0) {
            this.searchCohorts(this.cohortSearchTerm);
        }
    }

    handleCohortSelect(event) {
        event.preventDefault();
        event.stopPropagation();
        const id = event.currentTarget.dataset.id;
        const label = event.currentTarget.dataset.label;
        this.selectedCohortId = id;
        this.selectedCohortLabel = label;
        this.showCohortDropdown = false;
        this.cohortOptions = [];
        this.loadFiles();
    }

    handleCohortBlur() {
        // Delay so mousedown on dropdown option can fire first
        setTimeout(() => {
            this.showCohortDropdown = false;
        }, 250);
    }

    loadFiles() {
        if (!this.selectedCohortId) return;
        this.isLoadingFiles = true;
        getCohortFiles({
            programCohortId: this.selectedCohortId,
            fileTypeFilter: this.selectedFileType || null
        })
            .then((data) => {
                const list = data || [];
                this.files = list.map((row, idx) => ({
                    ...row,
                    rowNumber: idx + 1,
                    downloadUrl: row.fileId ? `/sfc/servlet.shepherd/document/download/${row.fileId}` : null
                }));
            })
            .catch((err) => {
                this.files = [];
                this.showToast('Error', (err.body && err.body.message) || err.message || 'Failed to load files', 'error');
            })
            .finally(() => {
                this.isLoadingFiles = false;
            });
    }

    handleClearCohort() {
        this.selectedCohortId = null;
        this.selectedCohortLabel = '';
        this.cohortSearchTerm = '';
        this.files = [];
        this.showCohortDropdown = false;
        this.cohortOptions = [];
        const input = this.template.querySelector('.cohort-search-input');
        if (input) input.value = '';
    }

    async handleDownloadAll() {
        if (!this.hasFiles) return;
        if (!this._jsZipLoaded || typeof JSZip === 'undefined') {
            this.showToast('Error', 'ZIP library not ready yet. Please try again in a moment.', 'error');
            return;
        }
        this.isDownloadingAll = true;
        this.downloadProgress = 0;
        const zip = new JSZip();
        const usedNames = new Set();
        try {
            for (const f of this.files) {
                const payload = await getContentDocumentBodyForZip({ contentDocumentId: f.fileId });
                if (payload && payload.base64Data) {
                    const name = this.uniqueName(payload.fileName || f.fileName || `file_${this.downloadProgress + 1}`, usedNames);
                    zip.file(name, payload.base64Data, { base64: true });
                }
                this.downloadProgress++;
            }
            const blob = await zip.generateAsync({ type: 'blob' });
            const url = URL.createObjectURL(blob);
            const a = document.createElement('a');
            a.href = url;
            const safeLabel = (this.selectedCohortLabel || 'cohort').replace(/[^a-z0-9_-]/gi, '_');
            a.download = `${safeLabel}_${this.timestampSuffix()}.zip`;
            document.body.appendChild(a);
            a.click();
            document.body.removeChild(a);
            URL.revokeObjectURL(url);
            this.showToast('Success', `Downloaded ${this.files.length} file(s) as ZIP.`, 'success');
        } catch (err) {
            this.showToast('Error', (err && err.body && err.body.message) || (err && err.message) || 'Failed to build ZIP.', 'error');
        } finally {
            this.isDownloadingAll = false;
            this.downloadProgress = 0;
        }
    }

    timestampSuffix() {
        const d = new Date();
        const pad = (n) => String(n).padStart(2, '0');
        return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}_${pad(d.getHours())}-${pad(d.getMinutes())}-${pad(d.getSeconds())}`;
    }

    uniqueName(name, used) {
        if (!used.has(name)) {
            used.add(name);
            return name;
        }
        const dot = name.lastIndexOf('.');
        const base = dot > 0 ? name.substring(0, dot) : name;
        const ext = dot > 0 ? name.substring(dot) : '';
        let i = 2;
        let candidate = `${base} (${i})${ext}`;
        while (used.has(candidate)) {
            i++;
            candidate = `${base} (${i})${ext}`;
        }
        used.add(candidate);
        return candidate;
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}