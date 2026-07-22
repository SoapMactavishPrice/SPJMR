import { LightningElement } from 'lwc';

export default class TestCalendar extends LightningElement {
    handleDateChange(event) {
        console.log('Selected date:', event.detail.date);
        // You can handle the selected date here
    }
}