public class EditAllpurchaseOrder {
public string currentRecID{get;set;}
    public List<Purchase_Order_Item__c> bomitemList {get;set;}

    public EditAllpurchaseOrder() {
        currentRecID=ApexPages.CurrentPage().getparameters().get('id');
        bomitemList=[SELECT Id, Name,Item_Name__c, Sales_UOM__c,Remark__c,Item_Code__c,Qty__c,Discount_In_Percentage__c
        FROM Purchase_Order_Item__c where Purchase_Order__c=:currentRecID]; 

        system.debug('oppList>>>>>>>'+bomitemList);  
    }
    Public Pagereference Save(){
        
        if(bomitemList.size()>0){
            system.debug('bomitemList======'+bomitemList);   
            update bomitemList; 
        }        
        pagereference pg= new pagereference('/'+currentRecID);
        pg.setRedirect(true);
        return pg;  
    }
    
    Public Pagereference Cancel(){
        
        pagereference pg=new pagereference('/'+currentRecID);
        pg.setRedirect(true);
        return pg;        
    } 
}