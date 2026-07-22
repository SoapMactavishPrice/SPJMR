public class editAllPurchaseRequistionItem {
 public string currentRecID{get;set;}
    public List<Purchase_Requistion_Line_Item__c> bomitemList {get;set;}

    public editAllPurchaseRequistionItem() {
        currentRecID=ApexPages.CurrentPage().getparameters().get('id');
        bomitemList=[  SELECT Id, Name,Item_Name__c, Sales_UOM__c,Remark__c,Item_Code__c, Quantity__c
        FROM Purchase_Requistion_Line_Item__c where Purchase_Requisition__c=:currentRecID]; 

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