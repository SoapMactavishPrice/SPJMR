/**
 * Opportunity line programme slabs: load all slabs per programme, apply slab cohort and set line
 * {@link OpportunityLineItem#UnitPrice} to the list amount entered in the LWC for the selected slab row,
 * with {@link OpportunityLineItem#Discount} taken from the selected slab’s {@code Discount_in__c}.
 * Price book List Price is not updated.
 */
public with sharing class OpportunitySlabPricingController {

    public class LineItemRow {
        /** Use lineItemId (not id) so LWC/Apex JSON round-trips reliably. */
        @AuraEnabled public Id lineItemId;
        @AuraEnabled public String productName;
        @AuraEnabled public String productCode;
        @AuraEnabled public Decimal quantity;
        @AuraEnabled public Decimal unitPrice;
        @AuraEnabled public Decimal listPrice;
        @AuraEnabled public Decimal discount;
        @AuraEnabled public Decimal totalPrice;
        @AuraEnabled public Decimal salePricePerPerson;
        /** From the line item; read-only in the UI. */
        @AuraEnabled public Decimal minStudents;
        @AuraEnabled public Decimal maxStudents;
        /** All slabs for this product’s programme (Programme Code match); no student-band filter. */
        @AuraEnabled public List<SlabDiscountOption> discountOptions;
    }

    public class LineApplyInput {
        @AuraEnabled public Id lineItemId;
        @AuraEnabled public Id selectedSlabId;
        /** Net per person from the LWC (optional; informational). */
        @AuraEnabled public Decimal salePricePerPerson;
        /** Per-row list value for the selected slab; persisted as {@link OpportunityLineItem#UnitPrice}. */
        @AuraEnabled public Decimal listPrice;
    }

    public class SlabDiscountOption {
        @AuraEnabled public Id slabId;
        @AuraEnabled public String slabName;
        @AuraEnabled public String discountIn;
        @AuraEnabled public Decimal discountPercent;
        /** From {@code Slab__c.Start_Range__c}; shown as Min Students in the LWC. */
        @AuraEnabled public Decimal minStudents;
        /** From {@code Slab__c.End_Range__c}; shown as Max Students in the LWC. */
        @AuraEnabled public Decimal maxStudents;
    }

    public class LineSlabQueryInput {
        @AuraEnabled public Id lineItemId;
        @AuraEnabled public String productCode;
        @AuraEnabled public String productName;
        @AuraEnabled public Decimal minStudents;
        @AuraEnabled public Decimal maxStudents;
    }

    public class LineSlabOptionsResult {
        @AuraEnabled public Id lineItemId;
        @AuraEnabled public List<SlabDiscountOption> options;
    }

    public class ApplyResult {
        @AuraEnabled public Boolean success;
        @AuraEnabled public String message;
        @AuraEnabled public List<String> warnings;
    }

    public class LineItemsPayload {
        @AuraEnabled public String currencyCode;
        @AuraEnabled public List<LineItemRow> lines;
    }

    /**
     * Loads opportunity line items with currency, cohort min/max from the line, and all matching slabs per programme.
     *
     * @param opportunityId Opportunity whose line items are loaded.
     * @return Payload including slab picklists per line (no range filtering).
     */
    @AuraEnabled(cacheable=true)
    public static LineItemsPayload getOpportunityLineItems(Id opportunityId) {
        LineItemsPayload payload = new LineItemsPayload();
        payload.lines = new List<LineItemRow>();
        payload.currencyCode = UserInfo.getDefaultCurrency();

        if (opportunityId == null) {
            return payload;
        }

        List<Opportunity> opps = [
            SELECT CurrencyIsoCode
            FROM Opportunity
            WHERE Id = :opportunityId
            LIMIT 1
        ];
        if (!opps.isEmpty() && String.isNotBlank(opps[0].CurrencyIsoCode)) {
            payload.currencyCode = opps[0].CurrencyIsoCode;
        }

        List<OpportunityLineItem> olis = [
            SELECT
                Id,
                Quantity,
                UnitPrice,
                ListPrice,
                Discount,
                TotalPrice,
                Min_Students__c,
                Max_Students__c,
                Product2.Name,
                Product2.ProductCode
            FROM OpportunityLineItem
            WHERE OpportunityId = :opportunityId
            ORDER BY CreatedDate
        ];

        Set<String> codes = new Set<String>();
        for (OpportunityLineItem oli : olis) {
            if (oli.Product2 != null && String.isNotBlank(oli.Product2.ProductCode)) {
                String t = oli.Product2.ProductCode.trim();
                codes.add(t);
                codes.add(t.toUpperCase());
                codes.add(t.toLowerCase());
            }
        }

        List<Slab__c> candidateSlabs = codes.isEmpty()
            ? new List<Slab__c>()
            : [
                  SELECT
                      Id,
                      Name,
                      Discount_in__c,
                      Start_Range__c,
                      End_Range__c,
                      Program_Master__r.Program_Code__c,
                      Program_Master__r.Name
                  FROM Slab__c
                  WHERE Program_Master__r.Program_Code__c IN :codes
                  ORDER BY Start_Range__c ASC NULLS LAST
              ];

        for (OpportunityLineItem oli : olis) {
            LineItemRow row = new LineItemRow();
            row.lineItemId = oli.Id;
            row.productName = oli.Product2 != null ? oli.Product2.Name : null;
            row.productCode = oli.Product2 != null ? oli.Product2.ProductCode : null;
            row.quantity = oli.Quantity;
            row.unitPrice = oli.UnitPrice;
            row.listPrice = oli.ListPrice != null ? oli.ListPrice : oli.UnitPrice;
            row.discount = oli.Discount;
            row.totalPrice = oli.TotalPrice;
            row.minStudents = oli.Min_Students__c;
            row.maxStudents = oli.Max_Students__c;
            row.salePricePerPerson = computeSalePricePerPerson(row.listPrice, oli.Discount);
            row.discountOptions = new List<SlabDiscountOption>();

            if (oli.Product2 != null && String.isNotBlank(oli.Product2.ProductCode)) {
                String code = oli.Product2.ProductCode.trim();
                for (Slab__c slab : candidateSlabs) {
                    if (
                        slab.Program_Master__r == null ||
                        String.isBlank(slab.Program_Master__r.Program_Code__c)
                    ) {
                        continue;
                    }
                    if (!code.equalsIgnoreCase(slab.Program_Master__r.Program_Code__c.trim())) {
                        continue;
                    }
                    row.discountOptions.add(toSlabDiscountOption(slab));
                }
            }

            payload.lines.add(row);
            System.debug('row: ' + payload);
        }
        return payload;
    }

    /**
     * Returns all slab discount options per line for the product’s programme (Programme Code only).
     * Min/max on the request are ignored for filtering; kept for API compatibility with older LWCs.
     *
     * @param inputsJson JSON array of {@link LineSlabQueryInput}.
     * @return One result row per input line with all matching slabs.
     */
    @AuraEnabled
    public static List<LineSlabOptionsResult> getSlabDiscountOptionsForLines(String inputsJson) {
        List<LineSlabOptionsResult> results = new List<LineSlabOptionsResult>();
        if (String.isBlank(inputsJson)) {
            return results;
        }

        List<LineSlabQueryInput> inputs;
        try {
            inputs = deserializeLineSlabQueryInputs(inputsJson);
        } catch (Exception ex) {
            throw new AuraHandledException('Could not read line inputs: ' + ex.getMessage());
        }

        if (inputs == null || inputs.isEmpty()) {
            return results;
        }

        Set<String> codes = new Set<String>();
        for (LineSlabQueryInput q : inputs) {
            if (q != null && String.isNotBlank(q.productCode)) {
                String t = q.productCode.trim();
                codes.add(t);
                codes.add(t.toUpperCase());
                codes.add(t.toLowerCase());
            }
        }

        List<Slab__c> candidateSlabs = codes.isEmpty()
            ? new List<Slab__c>()
            : [
                  SELECT
                      Id,
                      Name,
                      Discount_in__c,
                      Start_Range__c,
                      End_Range__c,
                      Program_Master__r.Program_Code__c,
                      Program_Master__r.Name
                  FROM Slab__c
                  WHERE Program_Master__r.Program_Code__c IN :codes
                  ORDER BY Start_Range__c ASC NULLS LAST
              ];

        for (LineSlabQueryInput q : inputs) {
            LineSlabOptionsResult one = new LineSlabOptionsResult();
            one.lineItemId = q != null ? q.lineItemId : null;
            one.options = new List<SlabDiscountOption>();

            if (q == null || q.lineItemId == null) {
                results.add(one);
                continue;
            }

            if (String.isBlank(q.productCode)) {
                results.add(one);
                continue;
            }

            String code = q.productCode.trim();

            for (Slab__c slab : candidateSlabs) {
                if (
                    slab.Program_Master__r == null ||
                    String.isBlank(slab.Program_Master__r.Program_Code__c)
                ) {
                    continue;
                }
                if (!code.equalsIgnoreCase(slab.Program_Master__r.Program_Code__c.trim())) {
                    continue;
                }
                one.options.add(toSlabDiscountOption(slab));
            }

            results.add(one);
        }

        return results;
    }

    /**
     * Applies selected slab: sets {@link OpportunityLineItem#UnitPrice} from {@code listPrice} (per-slab list
     * entered for the selected row) and {@link OpportunityLineItem#Discount} from the slab’s {@code Discount_in__c},
     * and copies cohort min/max from the slab.
     *
     * @param opportunityId Parent opportunity.
     * @param inputsJson JSON array: {@code [{"lineItemId":"...","selectedSlabId":"...","listPrice":1400,"salePricePerPerson":1232}]}
     *     {@code listPrice} is required (positive) and written to Unit Price. {@code salePricePerPerson} is optional.
     * @return Apply outcome with warnings for skipped rows.
     */
    @AuraEnabled
    public static ApplyResult applySlabDiscounts(Id opportunityId, String inputsJson) {
        ApplyResult result = new ApplyResult();
        result.success = false;
        result.warnings = new List<String>();

        if (opportunityId == null || String.isBlank(inputsJson)) {
            result.message = 'Opportunity and line inputs are required.';
            return result;
        }

        List<LineApplyInput> inputs;
        try {
            inputs = deserializeApplyInputs(inputsJson);
        } catch (Exception ex) {
            result.message = 'Could not read line inputs: ' + ex.getMessage();
            return result;
        }

        if (inputs == null || inputs.isEmpty()) {
            result.message = 'Opportunity and line inputs are required.';
            return result;
        }

        Map<Id, LineApplyInput> inputByLineId = new Map<Id, LineApplyInput>();
        for (LineApplyInput inp : inputs) {
            if (inp == null || inp.lineItemId == null || inp.selectedSlabId == null) {
                result.warnings.add('Skipped a row: line and slab selection are required.');
                continue;
            }
            if (inp.listPrice == null || inp.listPrice <= 0) {
                result.warnings.add('Skipped a row: list price for sales price (Unit Price) is required.');
                continue;
            }
            inputByLineId.put(inp.lineItemId, inp);
        }

        if (inputByLineId.isEmpty()) {
            result.message = result.warnings.isEmpty()
                ? 'No valid line items to update.'
                : 'No line items to update. Review the notices below.';
            return result;
        }

        List<OpportunityLineItem> olis = [
            SELECT Id, UnitPrice, ListPrice, Discount, Product2.ProductCode, Product2.Name
            FROM OpportunityLineItem
            WHERE OpportunityId = :opportunityId AND Id IN :inputByLineId.keySet()
        ];

        Set<Id> slabIds = new Set<Id>();
        for (LineApplyInput inp : inputByLineId.values()) {
            slabIds.add(inp.selectedSlabId);
        }

        Map<Id, Slab__c> slabById = new Map<Id, Slab__c>(
            [
                SELECT
                    Id,
                    Discount_in__c,
                    Start_Range__c,
                    End_Range__c,
                    Program_Master__r.Program_Code__c,
                    Program_Master__r.Name
                FROM Slab__c
                WHERE Id IN :slabIds
            ]
        );

        List<OpportunityLineItem> toUpdate = new List<OpportunityLineItem>();

        for (OpportunityLineItem oli : olis) {
            LineApplyInput inp = inputByLineId.get(oli.Id);
            if (inp == null) {
                continue;
            }

            String code =
                (oli.Product2 != null && oli.Product2.ProductCode != null)
                    ? oli.Product2.ProductCode.trim()
                    : null;
            if (String.isBlank(code)) {
                result.warnings.add('Line item ' + oli.Id + ': Product has no Product Code.');
                continue;
            }

            Slab__c slab = slabById.get(inp.selectedSlabId);
            if (slab == null) {
                result.warnings.add('Line item ' + oli.Id + ': Selected slab was not found.');
                continue;
            }
            if (slab.Program_Master__r == null || String.isBlank(slab.Program_Master__r.Program_Code__c)) {
                result.warnings.add('Line item ' + oli.Id + ': Slab has no Program Master code.');
                continue;
            }
            if (!code.equalsIgnoreCase(slab.Program_Master__r.Program_Code__c.trim())) {
                result.warnings.add(
                    'Line item ' + oli.Id + ': Selected slab does not match this product Programme Code.'
                );
                continue;
            }

            Decimal discountFromSlab = clampSlabDiscountPercent(slab.Discount_in__c);

            OpportunityLineItem upd = new OpportunityLineItem(
                Id = oli.Id,
                UnitPrice = inp.listPrice,
                Discount = discountFromSlab
            );
            putCohortFromSlabOnLineItem(slab, upd, result, oli.Id);
            toUpdate.add(upd);
        }

        if (toUpdate.isEmpty()) {
            result.message = 'No line items were updated. See warnings for details.';
            result.success = result.warnings.isEmpty();
            return result;
        }

        try {
            update toUpdate;
            result.success = true;
            result.message = toUpdate.size() + ' line item(s) updated.';
        } catch (DmlException e) {
            result.message = e.getDmlMessage(0);
            return result;
        }

        return result;
    }

    /**
     * Sets {@link OpportunityLineItem#Min_Students__c} and {@link OpportunityLineItem#Max_Students__c} from
     * {@code Slab__c.Start_Range__c} and {@code End_Range__c} when both are present and start is not greater than end.
     *
     * @param slab Selected slab record.
     * @param upd Line item row being built for update (discount already set by caller).
     * @param result Collects warnings when cohort cannot be derived.
     * @param oliId Line item Id for warning text.
     */
    private static void putCohortFromSlabOnLineItem(
        Slab__c slab,
        OpportunityLineItem upd,
        ApplyResult result,
        Id oliId
    ) {
        if (slab == null || upd == null) {
            return;
        }

        if (
            slab.Start_Range__c != null &&
            slab.End_Range__c != null &&
            slab.Start_Range__c <= slab.End_Range__c
        ) {
            upd.Min_Students__c = slab.Start_Range__c;
            upd.Max_Students__c = slab.End_Range__c;
            return;
        }

        if (slab.Start_Range__c != null && slab.End_Range__c != null && slab.Start_Range__c > slab.End_Range__c) {
            result.warnings.add(
                'Line item ' + oliId + ': Slab start range is greater than end; cohort not updated.'
            );
            return;
        }
        result.warnings.add(
            'Line item ' + oliId + ': Selected slab needs Start Range and End Range; min/max not updated on the line.'
        );
    }

    /**
     * Normalizes slab {@code Discount_in__c} to a line-item Discount value between 0 and 100.
     *
     * @param raw Slab discount percent, or null.
     * @return Clamped percent, or 0 when {@code raw} is null.
     */
    private static Decimal clampSlabDiscountPercent(Decimal raw) {
        if (raw == null) {
            return 0;
        }
        if (raw < 0) {
            return 0;
        }
        if (raw > 100) {
            return 100;
        }
        return raw;
    }

    /**
     * Discount % off list anchor so that {@code anchor * (1 - discount/100) = salePrice}.
     *
     * @param anchorPrice List price, else unit price.
     * @param salePricePerPerson Target net unit amount after discount.
     * @return Discount 0–100, or null if anchor is missing or not positive.
     */
    private static Decimal deriveDiscountPercent(Decimal anchorPrice, Decimal salePricePerPerson) {
        if (anchorPrice == null || anchorPrice <= 0 || salePricePerPerson == null) {
            return null;
        }
        Decimal raw = ((anchorPrice - salePricePerPerson) / anchorPrice) * 100;
        if (raw < 0) {
            return 0;
        }
        if (raw > 100) {
            return 100;
        }
        return raw;
    }

    private static SlabDiscountOption toSlabDiscountOption(Slab__c slab) {
        SlabDiscountOption opt = new SlabDiscountOption();
        opt.slabId = slab.Id;
        opt.slabName = slab.Name;
        opt.discountIn = slab.Discount_in__c != null ? String.valueOf(slab.Discount_in__c) : null;
        opt.discountPercent = slab.Discount_in__c;
        opt.minStudents = slab.Start_Range__c;
        opt.maxStudents = slab.End_Range__c;
        return opt;
    }

    private static Decimal computeSalePricePerPerson(Decimal listAnchor, Decimal discountPercent) {
        if (listAnchor == null) {
            return null;
        }
        Decimal d = discountPercent != null ? discountPercent : 0;
        return listAnchor * (1 - (d / 100));
    }

    private static List<LineApplyInput> deserializeApplyInputs(String inputsJson) {
        List<LineApplyInput> inputs = new List<LineApplyInput>();
        List<Object> rows;
        try {
            rows = (List<Object>) JSON.deserializeUntyped(inputsJson);
        } catch (Exception ex) {
            throw new AuraHandledException('Expected a JSON array of line inputs.');
        }
        for (Object row : rows) {
            if (!(row instanceof Map<String, Object>)) {
                continue;
            }
            Map<String, Object> m = (Map<String, Object>) row;
            LineApplyInput inp = new LineApplyInput();
            Object lineItemIdObj = m.get('lineItemId');
            if (lineItemIdObj != null) {
                inp.lineItemId = String.valueOf(lineItemIdObj);
            }
            Object slabIdObj = m.get('selectedSlabId');
            if (slabIdObj != null && String.isNotBlank(String.valueOf(slabIdObj))) {
                inp.selectedSlabId = String.valueOf(slabIdObj);
            }
            inp.salePricePerPerson = toDecimal(m.get('salePricePerPerson'));
            inp.listPrice = toDecimal(m.get('listPrice'));
            inputs.add(inp);
        }
        return inputs;
    }

    private static List<LineSlabQueryInput> deserializeLineSlabQueryInputs(String inputsJson) {
        List<LineSlabQueryInput> inputs = new List<LineSlabQueryInput>();
        List<Object> rows;
        try {
            rows = (List<Object>) JSON.deserializeUntyped(inputsJson);
        } catch (Exception ex) {
            throw new AuraHandledException('Expected a JSON array of line inputs.');
        }
        for (Object row : rows) {
            if (!(row instanceof Map<String, Object>)) {
                continue;
            }
            Map<String, Object> m = (Map<String, Object>) row;
            LineSlabQueryInput q = new LineSlabQueryInput();
            Object lineItemIdObj = m.get('lineItemId');
            if (lineItemIdObj != null) {
                q.lineItemId = String.valueOf(lineItemIdObj);
            }
            Object pc = m.get('productCode');
            q.productCode = pc != null ? String.valueOf(pc) : null;
            Object pn = m.get('productName');
            q.productName = pn != null ? String.valueOf(pn) : null;
            q.minStudents = toDecimal(m.get('minStudents'));
            q.maxStudents = toDecimal(m.get('maxStudents'));
            inputs.add(q);
        }
        return inputs;
    }

    private static Decimal toDecimal(Object o) {
        if (o == null) {
            return null;
        }
        if (o instanceof Decimal) {
            return (Decimal) o;
        }
        if (o instanceof Integer || o instanceof Long || o instanceof Double) {
            return Decimal.valueOf(String.valueOf(o));
        }
        return Decimal.valueOf(String.valueOf(o));
    }
}