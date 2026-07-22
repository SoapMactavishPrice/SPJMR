import { LightningElement, api, track, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { refreshApex } from '@salesforce/apex';
import { CloseActionScreenEvent } from 'lightning/actions';
import getOpportunityLineItems from '@salesforce/apex/OpportunitySlabPricingController.getOpportunityLineItems';
import applySlabDiscounts from '@salesforce/apex/OpportunitySlabPricingController.applySlabDiscounts';

function extractDiscountPercent(option) {
    if (!option) {
        return null;
    }
    if (option.discountPercent != null && option.discountPercent !== '') {
        return Number(option.discountPercent);
    }
    if (option.discountIn != null && option.discountIn !== '') {
        const parsed = Number(String(option.discountIn).replace('%', '').trim());
        return Number.isNaN(parsed) ? null : parsed;
    }
    return null;
}

export default class OpportunitySlabPricing extends LightningElement {
    @api recordId;

    @track rows = [];
    @track isLoading = true;
    @track isSaving = false;
    @track currencyCode = 'INR';
    /** Section `name` values (line item Ids) kept open in the accordion. */
    @track activeAccordionSectionNames = [];

    wiredLinesResult;

    /** Keeps accordion controlled so all sections open on load; user toggles still persist. */
    handleAccordionSectionToggle(event) {
        const open = event.detail && event.detail.openSections;
        if (Array.isArray(open)) {
            this.activeAccordionSectionNames = [...open];
        } else if (open != null && open !== '') {
            this.activeAccordionSectionNames = [String(open)];
        }
    }

    getSelectedSlabRow(lineRow) {
        if (!lineRow || !lineRow.selectedSlabId || !lineRow.slabRows) {
            return null;
        }
        return (
            lineRow.slabRows.find((slab) => String(slab.slabId) === String(lineRow.selectedSlabId)) || null
        );
    }

    computeLineTotalForRow(lineRow) {
        const slabRow = this.getSelectedSlabRow(lineRow);
        const sale = slabRow != null ? Number(slabRow.salePricePerPerson) : NaN;
        const qty = Number(lineRow.quantity) || 0;
        if (!Number.isNaN(sale) && sale >= 0) {
            return qty * sale;
        }
        return lineRow.totalPrice != null ? Number(lineRow.totalPrice) : 0;
    }

    /**
     * Each slab row: list price defaults from the opportunity line ({@code ListPrice} / {@code UnitPrice}
     * from Apex as {@code line.listPrice}), same value for every slab until the user edits a row.
     *
     * @param {object[]} discountOptions Apex slab options
     * @param {string} lineItemId Line id for keys
     * @param {string|null} selectedSlabId Selected slab id
     * @param {number} lineListFallback Opportunity line list (or unit) price
     * @param {Record<string, number>} prevSlabListPrices Slab id → list price from prior UI state
     */
    decorateSlabRows(discountOptions, lineItemId, selectedSlabId, lineListFallback, prevSlabListPrices) {
        const key = lineItemId || '';
        const lineDefault = Number(lineListFallback);
        const defaultList =
            !Number.isNaN(lineDefault) && lineDefault > 0 ? lineDefault : 0;
        const prevMap = prevSlabListPrices || {};
        return (discountOptions || []).map((opt) => {
            const d = extractDiscountPercent(opt);
            const sk = String(opt.slabId);
            let rowList =
                prevMap[sk] != null && prevMap[sk] !== '' && !Number.isNaN(Number(prevMap[sk]))
                    ? Number(prevMap[sk])
                    : defaultList;
            if (Number.isNaN(rowList) || rowList < 0) {
                rowList = defaultList;
            }
            const sale =
                rowList > 0 && d != null && !Number.isNaN(d) ? rowList * (1 - d / 100) : null;
            const minN = opt.minStudents != null && opt.minStudents !== '' ? Number(opt.minStudents) : null;
            const maxN = opt.maxStudents != null && opt.maxStudents !== '' ? Number(opt.maxStudents) : null;
            return {
                slabRowKey: `${key}-${opt.slabId}`,
                slabId: opt.slabId,
                slabName: opt.slabName || 'Slab',
                discountPercent: d,
                hasMinStudents: minN != null && !Number.isNaN(minN),
                hasMaxStudents: maxN != null && !Number.isNaN(maxN),
                minStudentsValue: minN != null && !Number.isNaN(minN) ? minN : null,
                maxStudentsValue: maxN != null && !Number.isNaN(maxN) ? maxN : null,
                discountLabel: d != null && !Number.isNaN(d) ? `${d}%` : opt.discountIn || '—',
                isSelected: String(selectedSlabId || '') === String(opt.slabId || ''),
                listPrice: rowList,
                salePricePerPerson: sale
            };
        });
    }

    buildRowFromLine(line, prevState) {
        const rowKey = line.lineItemId || line.id;
        const discountOptions = line.discountOptions || [];
        let selectedSlabId = line.selectedSlabId || null;

        if (prevState && prevState.selectedSlabId) {
            selectedSlabId = prevState.selectedSlabId;
        }

        if (!selectedSlabId && discountOptions.length === 1) {
            selectedSlabId = discountOptions[0].slabId;
        }

        const lineListFallback = Number(line.listPrice) || Number(line.unitPrice) || 0;
        const prevSlabListPrices = {};
        if (prevState && Array.isArray(prevState.slabRows)) {
            for (let i = 0; i < prevState.slabRows.length; i++) {
                const sr = prevState.slabRows[i];
                if (
                    sr &&
                    sr.slabId != null &&
                    sr.listPrice != null &&
                    sr.listPrice !== '' &&
                    !Number.isNaN(Number(sr.listPrice))
                ) {
                    prevSlabListPrices[String(sr.slabId)] = Number(sr.listPrice);
                }
            }
        }

        const hasSlabs = discountOptions.length > 0;
        const name = line.productName || 'Product';
        const codePart = line.productCode ? ` (${line.productCode})` : '';

        const builtRow = {
            ...line,
            lineItemId: line.lineItemId || line.id,
            hasSlabs,
            accordionLabel: `${name}${codePart}`.trim(),
            radioGroupName: `slab-${rowKey}`,
            slabRows: this.decorateSlabRows(
                discountOptions,
                rowKey,
                selectedSlabId,
                lineListFallback,
                prevSlabListPrices
            ),
            selectedSlabId
        };
        builtRow.computedLineTotal = this.computeLineTotalForRow(builtRow);
        return builtRow;
    }

    /**
     * @param {object[]} previousRows Snapshot before wire assigns new server data
     */
    buildPrevStateByLineId(previousRows) {
        const prevById = new Map();
        const safeRows = Array.isArray(previousRows) ? previousRows : [];
        for (let i = 0; i < safeRows.length; i++) {
            const rowItem = safeRows[i];
            if (!rowItem) {
                continue;
            }
            const key = rowItem.lineItemId || rowItem.id;
            if (!key) {
                continue;
            }
            prevById.set(key, {
                selectedSlabId: rowItem.selectedSlabId,
                slabRows: rowItem.slabRows
            });
        }
        return prevById;
    }

    @wire(getOpportunityLineItems, { opportunityId: '$recordId' })
    wiredLines(result) {
        this.wiredLinesResult = result;
        if (result.error) {
            this.isLoading = false;
            this.activeAccordionSectionNames = [];
            this.showToast('Error', this.reduceError(result.error), 'error');
            return;
        }
        if (!result.data) {
            return;
        }

        try {
            const previousRows = Array.isArray(this.rows) ? this.rows.slice() : [];
            const prevById = this.buildPrevStateByLineId(previousRows);
            this.currencyCode = result.data.currencyCode || 'INR';
            const lines = Array.isArray(result.data.lines) ? result.data.lines : [];
            const nextRows = [];
            for (let j = 0; j < lines.length; j++) {
                const line = lines[j];
                const rowKey = line.lineItemId || line.id;
                const prevState = prevById.get(rowKey);
                nextRows.push(this.buildRowFromLine(line, prevState));
            }
            this.rows = nextRows;
            const sectionNames = [];
            for (let k = 0; k < nextRows.length; k++) {
                const id = nextRows[k].lineItemId || nextRows[k].id;
                if (id) {
                    sectionNames.push(String(id));
                }
            }
            this.activeAccordionSectionNames = sectionNames;
        } catch (err) {
            this.showToast('Error', err && err.message ? err.message : String(err), 'error');
            this.activeAccordionSectionNames = [];
        } finally {
            this.isLoading = false;
        }
    }

    get hasRows() {
        return this.rows && this.rows.length > 0;
    }

    get grandTotal() {
        if (!this.hasRows) {
            return 0;
        }
        let sum = 0;
        for (let i = 0; i < this.rows.length; i++) {
            const lineRow = this.rows[i];
            sum += Number(lineRow.computedLineTotal) || 0;
        }
        return sum;
    }

    handleSlabChange(event) {
        const host = event.currentTarget;
        if (!host) {
            return;
        }
        const lineId = host.dataset.lineId;
        const slabId = host.dataset.slabId;
        if (!lineId || !slabId) {
            return;
        }
        const updated = [];
        for (let i = 0; i < this.rows.length; i++) {
            const lineRow = this.rows[i];
            const id = lineRow.lineItemId || lineRow.id;
            if (String(id) !== String(lineId)) {
                updated.push(lineRow);
                continue;
            }
            const slabRows = (lineRow.slabRows || []).map((slab) => ({
                ...slab,
                isSelected: String(slab.slabId) === String(slabId)
            }));
            const next = { ...lineRow, selectedSlabId: slabId, slabRows };
            next.computedLineTotal = this.computeLineTotalForRow(next);
            updated.push(next);
        }
        this.rows = updated;
    }

    handleListPriceChange(event) {
        const host = event.currentTarget;
        if (!host) {
            return;
        }
        const lineId = host.dataset.lineId;
        const slabId = host.dataset.slabId;
        const raw = host.value;
        const val = raw === '' || raw == null ? null : Number(raw);
        if (!lineId || !slabId) {
            return;
        }
        const listVal = val != null && !Number.isNaN(val) ? val : 0;
        const updated = [];
        for (let i = 0; i < this.rows.length; i++) {
            const lineRow = this.rows[i];
            if (String(lineRow.lineItemId || lineRow.id) !== String(lineId)) {
                updated.push(lineRow);
                continue;
            }
            const slabRows = (lineRow.slabRows || []).map((slab) => {
                if (String(slab.slabId) !== String(slabId)) {
                    return slab;
                }
                const d = slab.discountPercent;
                const sale =
                    listVal > 0 && d != null && !Number.isNaN(Number(d))
                        ? listVal * (1 - Number(d) / 100)
                        : null;
                return { ...slab, listPrice: listVal, salePricePerPerson: sale };
            });
            const next = { ...lineRow, slabRows };
            next.computedLineTotal = this.computeLineTotalForRow(next);
            updated.push(next);
        }
        this.rows = updated;
    }

    validateBeforeApply() {
        const withSlabs = this.rows.filter((lineRow) => lineRow.hasSlabs);
        if (withSlabs.length === 0) {
            return { ok: false, message: 'No slab records are configured for these programme lines.' };
        }
        const missing = withSlabs.filter((lineRow) => {
            if (!lineRow.selectedSlabId) {
                return true;
            }
            const sr = this.getSelectedSlabRow(lineRow);
            const list = Number(sr != null ? sr.listPrice : NaN);
            if (sr == null || list == null || Number.isNaN(list) || list <= 0) {
                return true;
            }
            const sale = Number(sr.salePricePerPerson);
            return sale == null || Number.isNaN(sale);
        });
        if (missing.length > 0) {
            return {
                ok: false,
                message:
                    'For each programme with slabs, select a slab and enter a positive list price on that slab row. Sale price follows the slab discount.'
            };
        }
        return { ok: true };
    }

    async handleApply() {
        let check;
        try {
            check = this.validateBeforeApply();
        } catch (err) {
            this.showToast('Error', err && err.message ? err.message : String(err), 'error');
            return;
        }
        if (!check.ok) {
            this.showToast('Validation', check.message, 'warning');
            return;
        }

        const inputs = [];
        for (let i = 0; i < this.rows.length; i++) {
            const lineRow = this.rows[i];
            if (!lineRow.hasSlabs) {
                continue;
            }
            const sr = this.getSelectedSlabRow(lineRow);
            inputs.push({
                lineItemId: lineRow.lineItemId || lineRow.id,
                selectedSlabId: lineRow.selectedSlabId,
                listPrice: Number(sr.listPrice),
                salePricePerPerson: Number(sr.salePricePerPerson)
            });
        }

        this.isSaving = true;
        try {
            const inputsJson = JSON.stringify(inputs);
            const result = await applySlabDiscounts({
                opportunityId: this.recordId,
                inputsJson
            });

            if (result.warnings && result.warnings.length) {
                result.warnings.forEach((w) => this.showToast('Notice', w, 'warning'));
            }

            if (result.success) {
                this.showToast('Success', result.message, 'success');
                await refreshApex(this.wiredLinesResult);
                this.handleClose();
            } else if (result.message) {
                this.showToast(
                    result.success ? 'Success' : 'Could not apply',
                    result.message,
                    result.success ? 'success' : 'error'
                );
            }
        } catch (error) {
            this.showToast('Error', this.reduceError(error), 'error');
        } finally {
            this.isSaving = false;
        }
    }

    handleClose() {
        this.dispatchEvent(new CloseActionScreenEvent());
    }

    showToast(title, message, variant) {
        this.dispatchEvent(
            new ShowToastEvent({
                title,
                message,
                variant,
                mode: variant === 'warning' ? 'sticky' : 'dismissable'
            })
        );
    }

    reduceError(error) {
        if (Array.isArray(error.body)) {
            return error.body.map((e) => e.message).join(', ');
        }
        if (error.body && error.body.message) {
            return error.body.message;
        }
        if (error.message) {
            return error.message;
        }
        return 'Unknown error';
    }
}