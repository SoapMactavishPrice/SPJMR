import { LightningElement,api } from 'lwc';

export default class ApplicantDashboardMessageParent extends LightningElement {
    _data;
    gmpData=[];
    isGMPPresent = false;
     @api
    get data(){
        return this._data
    }

    set data(value){
        this._data = value; 

        if(this._data){
            console.log('Received Data from Parent for dashboard is ',JSON.stringify(this._data))
            var searchGMP =  this._data.find(value=>(value.programCode=='GMP') && !(value.isRejected))
            console.log('Is GMP Found? ',JSON.stringify(searchGMP))
            if(searchGMP){
                this.gmpData = [searchGMP]
                this.isGMPPresent = true
            }
        }
    }
    
}