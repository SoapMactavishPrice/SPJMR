import { LightningElement,api } from 'lwc';
 
export default class ApplicantDashboardMessageGmp extends LightningElement {
     _prgmdata='';
    bookingAddress = '';
bookingTime = '';
programName = '';
googleMapsUrl = '';
applicantName = '';
roundNumber = '';
interviewBooked=false

    @api
    get prgmdata() {
        return this._prgmdata;
    }
    set prgmdata(value) {
    try {
        this._prgmdata = value;

        if (Array.isArray(value) && value.length > 0) {
            console.log('Child received program data:', JSON.stringify(value));
            this.handleDataLoaded(value[0]);
        } else {
            console.error('Unexpected prgmData format:', value);
        }
    } catch (err) {
        console.error('Error in prgmData setter:', err);
    }
}
    handleDataLoaded(value){
        this.roundNumber = value.countBookings?value.countBookings:'1'
        this.bookingAddress = value.bookingInfo?value.bookingInfo.bookingAddress?value.bookingInfo.bookingAddress:'':''
        this.bookingTime = value.bookingInfo?value.bookingInfo.bookingStartTime?value.bookingInfo.bookingStartTime:'':''
        this.programName = value.programName?value.programName:''
        this.applicantName = value.applicantName?value.applicantName:''
        this.googleMapsUrl = 'https://www.google.com/maps/search/?api=1&query=' + this.bookingAddress;
        if(this.bookingTime && this.bookingAddress){
            console.log('Booked Interview ',this.interviewBooked)
            this.interviewBooked = true
        }
    }   
    
    
}