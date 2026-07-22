public class InsertPRItemsController {
    public Id purchaseRequisitionId { get; set; }
    private Id selectedItemGroupId;
    public List<SelectOption> itemGroupOptions { get; set; }
    public List<SelectOption> uomOptions { get; set; }
    
    // Wrapper for row data
    public class ItemSelection {
        public Id itemId { get; set; }
        public String itemName { get; set; }
        public Boolean isSelected { get; set; }
        public Integer quantity { get; set; }
        public Id uomId { get; set; }
        public Decimal expectedPrice { get; set; }
    }
    public List<ItemSelection> availableItems { get; set; }

    // --- State management: Do NOT rebuild availableItems except when group changes ---
    public InsertPRItemsController() {
        purchaseRequisitionId = ApexPages.currentPage().getParameters().get('id');
        availableItems = new List<ItemSelection>();
        
        itemGroupOptions = new List<SelectOption>();
        itemGroupOptions.add(new SelectOption('', '-- Select Item Group --'));
        for (Item_Group__c ig : [SELECT Id, Name FROM Item_Group__c ORDER BY Name]) {
            itemGroupOptions.add(new SelectOption(ig.Id, ig.Name));
        }

        uomOptions = new List<SelectOption>{new SelectOption('', '--None--')};
        for (UOM_Master__c u : [SELECT Id, Name FROM UOM_Master__c ORDER BY Name]) {
            uomOptions.add(new SelectOption(u.Id, u.Name));
        }
    }

    public Id getSelectedItemGroupId() {
        return selectedItemGroupId;
    }

    public void setSelectedItemGroupId(Id value) {
        selectedItemGroupId = value;
        if (selectedItemGroupId != null && String.valueOf(selectedItemGroupId).trim() != '') {
            loadItems();
        } else {
            availableItems.clear();
        }
    }

    public void loadItems() {
        availableItems.clear();
        if (selectedItemGroupId != null && String.valueOf(selectedItemGroupId).trim() != '') {
            List<Item__c> items = [SELECT Id, Name FROM Item__c WHERE Item_Group__c = :selectedItemGroupId ORDER BY Name];
            for (Item__c i : items) {
                ItemSelection isel = new ItemSelection();
                isel.itemId = i.Id;
                isel.itemName = i.Name;
                isel.isSelected = false;
                isel.quantity = null;
                isel.uomId = null;
                isel.expectedPrice = null;
                availableItems.add(isel);
            }
        }
    }

    public PageReference saveSelectedItems() {
        System.debug('DEBUG: availableItems size=' + availableItems.size());
        Integer selectedCount = 0;
        for (ItemSelection sel : availableItems) {
            System.debug('DEBUG: Item: ' + sel.itemName + ', Selected: ' + sel.isSelected + ', Quantity: ' + sel.quantity + ', UOM: ' + sel.uomId + ', Price: ' + sel.expectedPrice);
            if (sel.isSelected) {
                selectedCount++;
            }
        }
        
        if (selectedCount == 0) {
            ApexPages.addMessage(new ApexPages.Message(ApexPages.Severity.ERROR, 'No items selected to insert.'));
            return null;
        }
        
        List<Purchase_Requisition_Items__c> itemsToInsert = new List<Purchase_Requisition_Items__c>();
        for (ItemSelection sel : availableItems) {
            if (sel.isSelected) {
                Purchase_Requisition_Items__c newItem = new Purchase_Requisition_Items__c();
                newItem.Purchase_Requisition__c = purchaseRequisitionId;
                newItem.PR_Item_Group__c = selectedItemGroupId;
                newItem.PR_Item_Name__c = sel.itemId;
                newItem.PR_Quantity__c = sel.quantity;
               // newItem.PR_UOM__c = sel.uomId;
                newItem.PR_Estimated_Cost__c = sel.expectedPrice;
                itemsToInsert.add(newItem);
            }
        }
        insert itemsToInsert;
        ApexPages.addMessage(new ApexPages.Message(ApexPages.Severity.CONFIRM, itemsToInsert.size() + ' Items inserted successfully.'));
        
        // Reset selections after insert
        for (ItemSelection sel : availableItems) {
            sel.isSelected = false;
            sel.quantity = null;
            sel.uomId = null;
            sel.expectedPrice = null;
        }
        return null;
    }

    public PageReference cancel() {
        if (purchaseRequisitionId != null) {
            PageReference pr = new PageReference('/' + purchaseRequisitionId);
            pr.setRedirect(true);
            return pr;
        }
        return null;
    }
}