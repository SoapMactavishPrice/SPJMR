import { LightningElement,track,wire } from 'lwc';
import LightningModal from 'lightning/modal';
import getAccounts from '@salesforce/apex/AssignLeadHelper.getAccounts'

export default class ConvertLeadModal extends LightningModal {
    @track boolean_newExisting = true
    @track value;
    @track accounts;
    isListening = false;

    
    pickListOrdered;
    searchResults;
    selectedSearchResult;

    @wire(getAccounts,{key:'$searchKey'})
    wiredAccounts({data,error}){
        if(data){
                this.pickListOrdered = result.sort((a, b) =>
                a.label.localeCompare(b.label)
            );
        }
    }

    get selectedValue() {
        return this.selectedSearchResult?.label ?? null;
    }


    get accountOptions(){
        return[
            {label:'New Account',value:'New'},
            {label:'Existing Account',value:'Existing'}
        ]
    }

    handleChangeRadio(event){
        const val = event.target.value
        val === 'New'?this.boolean_newExisting = true:this.boolean_newExisting = false;
    }

    hideDropdown(event) {
        const cmpName = this.template.host.tagName;
        const clickedElementSrcName = event.target.tagName;
        const isClickedOutside = cmpName !== clickedElementSrcName;
        if (this.searchResults && isClickedOutside) {
            this.clearSearchResults();
        }
    }

    search(event) {
        const input = event.detail.value.toLowerCase();
        const result = this.pickListOrdered.filter((pickListOption) =>
            pickListOption.label.toLowerCase().includes(input)
        );
        this.searchResults = result;
    }


     selectSearchResult(event) {
        const selectedValue = event.currentTarget.dataset.value;
        this.selectedSearchResult = this.pickListOrdered.find(
            (pickListOption) => pickListOption.value === selectedValue
        );
        this.clearSearchResults();
    }


    clearSearchResults() {
        this.searchResults = null;
    }

    showPickListOptions() {
        if (!this.searchResults) {
            this.searchResults = this.pickListOrdered;
        }
    }

    renderedCallback(){
        if (this.isListening) return;

        window.addEventListener("click", (event) => {
            this.hideDropdown(event);
        });
        this.isListening = true;
    }

    connectedCallback(){
        this.value = 'New';
        /*
        getAccounts()
        .then((result) => {
            this.pickListOrdered = result.sort((a, b) =>
                a.label.localeCompare(b.label)
            );
        });
        */
    }
}