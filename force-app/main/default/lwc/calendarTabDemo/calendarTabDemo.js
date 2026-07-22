import { LightningElement, track } from 'lwc';

export default class CalendarTabDemo extends LightningElement {
    @track selectedDate = null;
    @track currentDate = new Date();

    handleDateChange(event) {
        this.selectedDate = event.detail.date;
        console.log('Selected date:', this.selectedDate);
    }

    // Method to navigate to today's date
    goToToday() {
        const today = new Date();
        const calendar = this.template.querySelector('c-poc-custom-calendar');
        if (calendar) {
            calendar.navigateToDate(today.getFullYear(), today.getMonth());
        }
    }
}