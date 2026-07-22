import { LightningElement, track, api } from 'lwc';

export default class PocCustomCalendar extends LightningElement {
    @track currentMonth = new Date().getMonth();
    @track currentYear = new Date().getFullYear();
    @track selectedDate = null;
    @track events = [];
    @track daysInMonth = [];
    @track dayNames = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
    @track monthNames = [
        'January', 'February', 'March', 'April', 'May', 'June',
        'July', 'August', 'September', 'October', 'November', 'December'
    ];
    @track eventDays = [];
    @track calendarDays = [];
    @api recordId; // For use in record pages

    connectedCallback() {
        this.generateCalendar();
        this.fetchEvents();
    }

    generateCalendar() {
        const firstDay = new Date(this.currentYear, this.currentMonth, 1);
        const lastDay = new Date(this.currentYear, this.currentMonth + 1, 0);
        const daysInMonth = lastDay.getDate();
        
        // Get the day of week for the first day (0 = Sunday, 1 = Monday, etc.)
        const firstDayOfWeek = firstDay.getDay();
        
        // Create array for calendar days
        this.daysInMonth = [];
        
        // Add empty slots for days before the first day of the month
        for (let i = 0; i < firstDayOfWeek; i++) {
            this.daysInMonth.push(null);
        }
        
        // Add days of the month
        for (let day = 1; day <= daysInMonth; day++) {
            this.daysInMonth.push(day);
        }
        
        // Precompute calendar days with event information
        this.calendarDays = this.daysInMonth.map(day => ({
            day: day,
            hasEvent: day ? this.eventDays.includes(day) : false
        }));
    }

    updateEventDays() {
        this.eventDays = this.events.map(event => event.date);
        this.generateCalendar(); // Recalculate calendar with updated events
    }

    fetchEvents() {
        // Placeholder for fetching events from Salesforce
        // In a real implementation, this would use @wire or other data fetching mechanisms
        this.events = [
            { date: 15, title: 'Meeting with team', type: 'meeting' },
            { date: 20, title: 'Project deadline', type: 'deadline' },
            { date: 25, title: 'Conference call', type: 'call' }
        ];
        this.updateEventDays();
    }

    handlePrevMonth() {
        if (this.currentMonth === 0) {
            this.currentMonth = 11;
            this.currentYear--;
        } else {
            this.currentMonth--;
        }
        this.generateCalendar();
    }

    handleNextMonth() {
        if (this.currentMonth === 11) {
            this.currentMonth = 0;
            this.currentYear++;
        } else {
            this.currentMonth++;
        }
        this.generateCalendar();
    }

    handleDateSelect(event) {
        const day = event.target.dataset.day;
        if (day) {
            this.selectedDate = new Date(this.currentYear, this.currentMonth, parseInt(day));
            // Dispatch event to parent component if needed
            const selectedEvent = new CustomEvent('datechange', {
                detail: { date: this.selectedDate }
            });
            this.dispatchEvent(selectedEvent);
        }
    }

    get monthYearDisplay() {
        return `${this.monthNames[this.currentMonth]} ${this.currentYear}`;
    }

    // Method to navigate to a specific date
    navigateToDate(year, month) {
        this.currentYear = year;
        this.currentMonth = month;
        this.generateCalendar();
    }
}