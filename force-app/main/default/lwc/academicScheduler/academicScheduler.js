import { LightningElement, track, api, wire } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import getPrograms from '@salesforce/apex/TimetableWizardController.getPrograms';
import getBatchesForProgram from '@salesforce/apex/TimetableWizardController.getBatchesForProgram';
import getBatchGroupsForBatch from '@salesforce/apex/TimetableWizardController.getBatchGroupsForBatch';
import getTermsForBatchGroup from '@salesforce/apex/TimetableWizardController.getTermsForBatchGroup';
import getDivisionsForTerms from '@salesforce/apex/TimetableWizardController.getDivisionsForTerms';
import getCoursesForDivision from '@salesforce/apex/TimetableWizardController.getCoursesForDivision';
import getCourseAssignments from '@salesforce/apex/TimetableWizardController.getCourseAssignments';
import getSessions from '@salesforce/apex/TimetableSessionController.getSessions';
import saveSession from '@salesforce/apex/TimetableSessionController.saveSession';
import deleteSession from '@salesforce/apex/TimetableSessionController.deleteSession';
import publishSessions from '@salesforce/apex/TimetableSessionController.publishSessions';
import getCourseActivities from '@salesforce/apex/TimetableSessionController.getCourseActivities';
import getFacultyForCourse from '@salesforce/apex/TimetableSessionController.getFacultyForCourse';
import getSessionFaculties from '@salesforce/apex/TimetableSessionController.getSessionFaculties';
import getSessionDivisions from '@salesforce/apex/TimetableWizardController.getSessionDivisions';

export default class AcademicScheduler extends LightningElement {
    @api recordId;
    @api title = 'Academic Scheduler';
    
    @track currentDate = new Date();
    @track currentView = 'week'; // Default to Week view
    
    // Date range for session filtering (reactive)
    @track dateFrom = '';
    @track dateTo = '';
    
    // Filter selections
    @track selectedProgram;
    @track selectedBatch;
    @track selectedBatchGroup;
    @track selectedTerm;
    @track selectedDivision;
    @track sessionDuration = null;
    
    // Filter options
    @track programOptions = [];
    @track batchOptions = [];
    @track batchGroupOptions = [];
    @track termOptions = [];
    @track divisionOptions = [];
    @track allDivisions = []; // Store all divisions for the grid
    
    // Modal state
    @track showModal = false;
    @track modalData = {
        program: null,
        batch: null,
        term: null,
        course: null,
        sessionTitle: ''
    };
    @track selectedSessionIndex = null; // For program selection
    @track isEditMode = false;
    @track selectedEventId = null;
    @track isLoading = false;
    @track isSaving = false;
    @track isLoadingAllDivisions = false; // Flag to prevent wiredSessions from interfering
    
    // Toast notification
    @track showToast = false;
    @track toastMessage = '';
    @track toastType = 'success';
    
    // Event form fields
    @track eventTitle = '';
    @track eventDate = '';
    @track eventStartTime = '09:00';
    @track eventEndTime = '10:00';
    @track eventColor = 'blue';
    @track selectedCourse = '';
    @track selectedCourseActivity = '';
    @track courseOptions = [];
    @track courseActivityOptions = [];
    @track selectedCourseDepartmentName = '';
    @track courseAssignments = []; // Legacy - keep for compatibility
    @track selectedAssignments = []; // Legacy - keep for compatibility
    @track showCourseAssignments = false; // Legacy - keep for compatibility
    // Per-session course assignments
    @track sessionCourseAssignments = {}; // Map of sessionIndex -> courseAssignments array
    @track sessionSelectedAssignments = {}; // Map of sessionIndex -> selectedAssignments array
    @track expandedSessionRows = {}; // Map of sessionIndex -> boolean (expanded state)
    @track existingSessionDivisions = [];
    @track isJointSession = false;
    @track selectedFacultyValue = '';
    @track facultyOptions = [];
    
    // Session rows for bulk scheduler modal
    @track sessionRows = [];
    
    // Track color options for getters
    get colorOptionsForGetter() {
        return this.colors.map(color => ({
            value: color,
            label: color.charAt(0).toUpperCase() + color.slice(1)
        }));
    }
    
    // Event data
    @track events = [];
    wiredSessionsResult;
    
    // Time slots: 8:00 to 19:00 (8 AM to 7 PM)
    timeSlots = [];
    
    // Color options
    colors = ['blue', 'green', 'purple', 'orange', 'red', 'pink'];
    
    // Format date to YYYY-MM-DD in local timezone (not UTC)
    formatDateLocal(date) {
        const year = date.getFullYear();
        const month = String(date.getMonth() + 1).padStart(2, '0');
        const day = String(date.getDate()).padStart(2, '0');
        return `${year}-${month}-${day}`;
    }
    
    // Get background color style for a given color name
    getColorBackgroundStyle(color) {
        const colorMap = {
            'blue': 'linear-gradient(135deg, #3b82f6 0%, #2563eb 100%)',
            'green': 'linear-gradient(135deg, #10b981 0%, #059669 100%)',
            'purple': 'linear-gradient(135deg, #8b5cf6 0%, #7c3aed 100%)',
            'orange': 'linear-gradient(135deg, #f59e0b 0%, #d97706 100%)',
            'red': 'linear-gradient(135deg, #ef4444 0%, #dc2626 100%)',
            'pink': 'linear-gradient(135deg, #ec4899 0%, #db2777 100%)'
        };
        return colorMap[color] || colorMap['blue'];
    }
    
    // Update date range when view or date changes
    updateDateRange() {
        let startDate, endDate;
        
        // Ensure currentDate is a Date object
        const currentDateObj = this.currentDate instanceof Date 
            ? this.currentDate 
            : new Date(this.currentDate);
        
        if (this.currentView === 'week') {
            // Week view: get start and end of week
            const startOfWeek = this.getStartOfWeek(currentDateObj);
            const endOfWeek = new Date(startOfWeek);
            endOfWeek.setDate(endOfWeek.getDate() + 6);
            startDate = this.formatDateLocal(startOfWeek);
            endDate = this.formatDateLocal(endOfWeek);
        } else {
            // Day view: single date - use local date, not UTC
            startDate = this.formatDateLocal(currentDateObj);
            endDate = startDate;
        }
        
        this.dateFrom = startDate;
        this.dateTo = endDate;
        
        console.log('updateDateRange called:', {
            currentView: this.currentView,
            currentDate: this.formatDateLocal(currentDateObj),
            dateFrom: this.dateFrom,
            dateTo: this.dateTo
        });
    }
    
    // Reactive getter for session filter
    get sessionFilter() {
        // Use tracked dateFrom and dateTo for reactivity
        // If not set, format currentDate in local timezone
        let startDate = this.dateFrom;
        let endDate = this.dateTo;
        
        if (!startDate && this.currentDate) {
            const currentDateObj = this.currentDate instanceof Date 
                ? this.currentDate 
                : new Date(this.currentDate);
            startDate = this.formatDateLocal(currentDateObj);
        }
        if (!endDate) {
            endDate = startDate;
        }
        
        // If a specific division is selected, use it
        // If "All Divisions" is selected, we'll fetch for each division separately
        // For @wire, we need a specific divisionId, so use first division if available
        const divisionId = this.selectedDivision || (this.allDivisions && this.allDivisions.length > 0 ? this.allDivisions[0].value : null);
        
        const filterPayload = {
            divisionId: divisionId,
            startDate: startDate,
            endDate: endDate
        };
        return JSON.stringify(filterPayload);
    }
    
    connectedCallback() {
        this.initializeTimeSlots();
        this.loadPrograms();
        this.loadCourseActivities();
        // Initialize date range
        this.updateDateRange();
    }
    
    initializeTimeSlots() {
        const slots = [];
        for (let hour = 8; hour <= 19; hour++) {
            const time24 = `${hour.toString().padStart(2, '0')}:00`;
            slots.push({
                key: `slot-${hour}`,
                hour: hour,
                time: time24
            });
        }
        this.timeSlots = slots;
    }
    
    // Wire getSessions to automatically load sessions when filter changes
    @wire(getSessions, { filterJson: '$sessionFilter' })
    wiredSessions(result) {
        this.wiredSessionsResult = result;
        
        // Don't interfere if we're manually loading all divisions
        if (this.isLoadingAllDivisions) {
            console.log('wiredSessions: Skipping because isLoadingAllDivisions is true');
            return;
        }
        
        // Only load sessions if we have a term selected (which means we have divisions)
        if (!this.selectedTerm || !this.allDivisions || this.allDivisions.length === 0) {
            this.events = [];
            this.isLoading = false;
            return;
        }
        
        // If "All Divisions" is selected, fetch sessions for each division separately
        // But only if we're not already loading
        // NOTE: Don't call loadSessionsForAllDivisions from wiredSessions - it causes race conditions
        // Instead, let the view handlers call it directly
        if (!this.selectedDivision && this.allDivisions.length > 0 && !this.isLoadingAllDivisions) {
            // Don't call loadSessionsForAllDivisions here - it will be called by view handlers
            // Just return without clearing events
            console.log('wiredSessions: All Divisions selected, but skipping loadSessionsForAllDivisions to avoid race condition');
            return;
        }
        
        // If a specific division is selected, use the wired result
        if (result.data) {
            const sessions = Array.isArray(result.data) ? result.data : [];
            // Map all sessions to events - filtering by division happens in getters
            // Force reactivity by creating a new array
            this.events = [...sessions.map(session => this.mapSessionToEvent(session))];
            console.log('wiredSessions: Loaded', this.events.length, 'events for specific division');
            this.isLoading = false;
        } else if (result.error) {
            console.error('Error loading sessions:', result.error);
            this.showToastMessage(this.getErrorMessage(result.error), 'error');
            this.events = [];
            this.isLoading = false;
        } else {
            this.isLoading = true;
        }
    }
    
    // Get session rows with color options computed
    get sessionRowsWithColors() {
        return this.sessionRows.map(session => {
            const colorOptions = this.colors.map(color => {
                const baseClass = `bulk-session-color-btn bulk-session-color-btn-${color}`;
                const isSelected = session.color === color;
                return {
                    value: color,
                    label: color.charAt(0).toUpperCase() + color.slice(1),
                    sessionButtonClass: isSelected ? `${baseClass} selected` : baseClass,
                    isSelected: isSelected
                };
            });
            return {
                ...session,
                colorOptions: colorOptions
            };
        });
    }
    
    // Get division rows for the grid
    get divisionRows() {
        // Show divisions if we have them loaded (from term selection)
        // If division is selected, show only that division
        const divisionsToShow = this.selectedDivision 
            ? this.allDivisions.filter(div => div.value === this.selectedDivision)
            : this.allDivisions;
            
        if (!divisionsToShow || divisionsToShow.length === 0) {
            return [];
        }
        
        // Ensure currentDate is a Date object and format it correctly
        // Use local date, not UTC, to match the date the user sees
        const currentDateObj = this.currentDate instanceof Date ? this.currentDate : new Date(this.currentDate);
        const currentDateStr = this.formatDateLocal(currentDateObj);
        
        // Debug logging
        console.log('divisionRows getter called:');
        console.log('  currentDateStr:', currentDateStr);
        console.log('  total events:', this.events.length);
        const eventsSample = this.events.slice(0, 5).map(e => {
            let dateStr = e.date;
            if (e.date instanceof Date) {
                dateStr = this.formatDateLocal(e.date);
            } else if (e.date) {
                dateStr = String(e.date).split('T')[0];
            }
            return { 
                id: e.id, 
                date: dateStr,
                dateRaw: String(e.date),
                dateType: typeof e.date,
                divisionId: String(e.divisionId), 
                title: e.title 
            };
        });
        console.log('  events sample:', JSON.stringify(eventsSample, null, 2));
        console.log('  divisionsToShow:', JSON.stringify(divisionsToShow.map(d => ({ value: String(d.value), label: d.label })), null, 2));
        
        return divisionsToShow.map(division => {
            // Get events for this division on the current date
            // Match by divisionId - convert both to strings for comparison
            const divisionEvents = this.events.filter(event => {
                // event.date should already be a string in YYYY-MM-DD format from Apex
                // Extract just the date part (YYYY-MM-DD) in case there's extra info
                let eventDateStr = null;
                if (event.date) {
                    // If it's a Date object, format it in local timezone
                    if (event.date instanceof Date) {
                        eventDateStr = this.formatDateLocal(event.date);
                    } else {
                        const dateStr = String(event.date);
                        // Extract YYYY-MM-DD pattern (first 10 characters should be the date)
                        if (dateStr.length >= 10) {
                            eventDateStr = dateStr.substring(0, 10);
                        } else {
                            eventDateStr = dateStr;
                        }
                    }
                }
                
                // Normalize division IDs for comparison
                const eventDivisionId = event.divisionId ? String(event.divisionId) : null;
                const divisionValue = division.value ? String(division.value) : null;
                
                const dateMatch = eventDateStr === currentDateStr;
                const divisionMatch = eventDivisionId === divisionValue;
                
                // Debug: log all events for this division to understand the mismatch
                if (eventDivisionId === divisionValue) {
                    if (!dateMatch && eventDateStr) {
                        console.log('  ❌ Date mismatch for division', division.label, ':', JSON.stringify({
                            eventId: event.id,
                            title: event.title,
                            eventDate: eventDateStr,
                            currentDate: currentDateStr,
                            eventDateRaw: String(event.date),
                            eventDateType: typeof event.date,
                            eventDateLength: eventDateStr ? eventDateStr.length : 0,
                            datesEqual: eventDateStr === currentDateStr,
                            dateCharCodes: eventDateStr ? Array.from(eventDateStr).map(c => c.charCodeAt(0)) : null
                        }, null, 2));
                    } else if (dateMatch) {
                        console.log('  ✓ Matched event:', JSON.stringify({
                            eventId: event.id,
                            title: event.title,
                            eventDate: eventDateStr,
                            currentDate: currentDateStr
                        }, null, 2));
                    }
                }
                
                return dateMatch && divisionMatch;
            });
            
            console.log(`  Division ${division.label}: found ${divisionEvents.length} events`);
            
            // Format events for display
            const formattedEvents = divisionEvents.map(event => {
                return this.formatEventForDivisionGrid(event);
            });
            
            return {
                key: `division-${division.value}`,
                id: division.value,
                name: division.label,
                term: division.termName || 'Trimester 1',
                termName: division.termName || 'Trimester 1',
                events: formattedEvents
            };
        });
    }
    
    formatEventForDivisionGrid(event) {
        const startHour = parseInt(event.startTime.split(':')[0], 10);
        const startMinute = parseInt(event.startTime.split(':')[1], 10);
        const endHour = parseInt(event.endTime.split(':')[0], 10);
        const endMinute = parseInt(event.endTime.split(':')[1], 10);
        
        // Calculate position (left) based on start time
        // Time slots are from 8:00 to 19:00 (12 hours total)
        // Each time slot represents 1 hour, so we have 12 slots
        const firstHour = 8; // First time slot hour
        const totalHours = 12; // Total number of hour slots (8 to 19)
        
        const hourIndex = startHour - firstHour; // 8:00 is index 0
        const minuteOffset = startMinute / 60; // Minutes as fraction of hour
        const leftPercent = ((hourIndex + minuteOffset) / totalHours) * 100;
        
        // Calculate width based on duration
        const startMinutes = startHour * 60 + startMinute;
        const endMinutes = endHour * 60 + endMinute;
        const durationHours = (endMinutes - startMinutes) / 60;
        const widthPercent = (durationHours / totalHours) * 100;
        
        // Extract course code from course name (e.g., "HR101 - Human Resources" -> "HR101")
        const courseCode = event.courseName ? event.courseName.split(' - ')[0] : 'N/A';
        
        // Get the full title - prefer courseName if available, otherwise use title
        const displayTitle = event.courseName ? event.courseName.split(' - ')[1] || event.title : event.title;
        
        // Ensure event ID is preserved for click handling
        return {
            ...event,
            id: event.id, // Explicitly preserve ID
            title: displayTitle, // Use full title for display
            style: `left: ${leftPercent}%; width: ${widthPercent}%;`,
            eventClass: `division-event event-${event.color}`,
            courseCode: courseCode,
            startTime: this.formatTime12(event.startTime),
            tooltip: `${displayTitle} - ${this.formatTime12(event.startTime)}`
        };
    }
    
    formatTime12(time24) {
        const [hours, minutes] = time24.split(':');
        const hour = parseInt(hours, 10);
        const hour12 = hour > 12 ? hour - 12 : hour === 0 ? 12 : hour;
        const ampm = hour >= 12 ? 'PM' : 'AM';
        return `${hour12}:${minutes} ${ampm}`;
    }
    
    mapSessionToEvent(session) {
        // Apex Date fields are serialized as strings in YYYY-MM-DD format when sent to LWC
        // However, sometimes Apex might serialize Date as ISO string with time, so we need to normalize
        let normalizedDate = session.sessionDate;
        
        // If it's a Date object, format it
        if (session.sessionDate instanceof Date) {
            normalizedDate = this.formatDateLocal(session.sessionDate);
        } else if (typeof session.sessionDate === 'string') {
            // Extract just the date part (YYYY-MM-DD) from ISO string if present
            const dateStr = session.sessionDate;
            if (dateStr.includes('T')) {
                // ISO format with time: "2026-01-22T00:00:00.000Z" -> "2026-01-22"
                normalizedDate = dateStr.substring(0, 10);
            } else if (dateStr.length >= 10) {
                // Already in YYYY-MM-DD format, use first 10 characters
                normalizedDate = dateStr.substring(0, 10);
            }
        }
        
        return {
            id: session.id,
            title: session.title || session.name || '',
            date: normalizedDate, // Normalized date string in YYYY-MM-DD format
            startTime: session.startTime,
            endTime: session.endTime,
            color: session.color || 'blue',
            divisionId: session.divisionId ? String(session.divisionId) : null,
            courseId: session.courseId,
            courseName: session.courseName,
            courseActivity: session.courseActivity,
            isJointSession: session.isJointSession || false,
            instructor: session.instructor || 'TBD' // You may need to fetch this from session data
        };
    }
    
    // Filter getters
    get isProgramNotSelected() {
        return !this.selectedProgram;
    }

    get isBatchNotSelected() {
        return !this.selectedBatch;
    }

    get isBatchGroupNotSelected() {
        return !this.selectedBatchGroup;
    }

    get isTermNotSelected() {
        return !this.selectedTerm;
    }

    get isDivisionNotSelected() {
        return !this.selectedDivision;
    }
    
    get isWeekView() {
        return this.currentView === 'week';
    }
    
    get isDayDivisionView() {
        return this.currentView === 'day' || this.currentView === 'dayDivision';
    }
    
    get isMonthView() {
        return this.currentView === 'month';
    }
    
    // Getters for filter options (mapping to new HTML variable names)
    get programs() {
        return this.programOptions;
    }
    
    get batches() {
        return this.batchOptions;
    }
    
    get batchGroups() {
        return this.batchGroupOptions;
    }
    
    get terms() {
        return this.termOptions;
    }
    
    get divisions() {
        // Add "All Divisions" option at the beginning
        const allDivisionsOption = {
            label: 'All Divisions',
            value: ''
        };
        
        // Return "All Divisions" option followed by all division options
        return [allDivisionsOption, ...this.divisionOptions];
    }
    
    get courses() {
        return this.courseOptions;
    }
    
    // View state getters
    get isWeekView() {
        return this.currentView === 'week';
    }
    
    get isDayView() {
        return this.currentView === 'day' || this.currentView === 'dayDivision';
    }
    
    get isMonthView() {
        return this.currentView === 'month';
    }
    
    get monthViewClass() {
        return `view-btn ${this.currentView === 'month' ? 'active' : ''}`;
    }
    
    get weekViewClass() {
        return `view-btn ${this.currentView === 'week' ? 'active' : ''}`;
    }
    
    get dayViewClass() {
        return `view-btn ${(this.currentView === 'day' || this.currentView === 'dayDivision') ? 'active' : ''}`;
    }
    
    get headerTitle() {
        return this.formattedCurrentDate;
    }
    
    get formattedCurrentDate() {
        if (this.currentView === 'week') {
            const startOfWeek = this.getStartOfWeek(this.currentDate);
            const endOfWeek = new Date(startOfWeek);
            endOfWeek.setDate(endOfWeek.getDate() + 6);
            
            const startStr = startOfWeek.toLocaleDateString('en-US', { month: 'long', day: 'numeric' });
            const endStr = endOfWeek.toLocaleDateString('en-US', { month: 'long', day: 'numeric', year: 'numeric' });
            const weekNum = this.getWeekNumber(startOfWeek);
            
            return `${startOfWeek.toLocaleDateString('en-US', { month: 'long' })} ${startOfWeek.getFullYear()} Week ${weekNum}`;
        } else {
            const options = { 
                month: 'long', 
                year: 'numeric',
                day: 'numeric',
                weekday: 'long'
            };
            return this.currentDate.toLocaleDateString('en-US', options);
        }
    }
    
    getStartOfWeek(date) {
        const d = new Date(date);
        const day = d.getDay();
        const diff = d.getDate() - day;
        return new Date(d.setDate(diff));
    }
    
    getWeekNumber(date) {
        const d = new Date(Date.UTC(date.getFullYear(), date.getMonth(), date.getDate()));
        const dayNum = d.getUTCDay() || 7;
        d.setUTCDate(d.getUTCDate() + 4 - dayNum);
        const yearStart = new Date(Date.UTC(d.getUTCFullYear(), 0, 1));
        return Math.ceil((((d - yearStart) / 86400000) + 1) / 7);
    }
    
    get weekDays() {
        const startOfWeek = this.getStartOfWeek(this.currentDate);
        const dayNames = ['SUN', 'MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT'];
        const today = new Date();
        today.setHours(0, 0, 0, 0);
        const days = [];
        
        for (let i = 0; i < 7; i++) {
            const date = new Date(startOfWeek);
            date.setDate(date.getDate() + i);
            const dateStr = this.formatDateLocal(date);
            const dateObj = new Date(date);
            dateObj.setHours(0, 0, 0, 0);
            const isToday = dateObj.getTime() === today.getTime();
            
            days.push({
                id: `day-${dateStr}`,
                key: dateStr,
                name: dayNames[date.getDay()],
                date: date.getDate(),
                dateStr: dateStr,
                headerClass: isToday ? 'day-header today' : 'day-header'
            });
        }
        
        return days;
    }
    
    // Week view data - time-based rows
    get weekViewData() {
        const hours = [];
        const startHour = 8;
        const endHour = 19;
        
        // Create hour rows
        for (let hour = startHour; hour <= endHour; hour++) {
            const hourLabel = `${hour.toString().padStart(2, '0')}:00`;
            const days = this.weekDays.map(day => {
                // Find events for this day and hour
                const dayEvents = this.events.filter(event => {
                    const eventDateStr = event.date instanceof Date 
                        ? this.formatDateLocal(event.date) 
                        : String(event.date).substring(0, 10);
                    
                    if (eventDateStr !== day.dateStr) return false;
                    
                    const eventHour = parseInt(event.startTime.split(':')[0], 10);
                    return eventHour === hour;
                });
                
                // Format sessions for display
                const sessions = dayEvents.map(event => {
                    const courseCode = event.courseName ? event.courseName.split(' - ')[0] : 'N/A';
                    const divisionName = this.allDivisions.find(d => d.value === event.divisionId)?.label || 'Unknown';
                    const eventColor = event.color || 'blue';
                    const backgroundColor = this.getColorBackgroundStyle(eventColor);
                    
                    return {
                        id: event.id,
                        courseCode: courseCode,
                        displayDivision: divisionName,
                        style: `background: ${backgroundColor};`
                    };
                });
                
                return {
                    id: `cell-${day.dateStr}-${hour}`,
                    dateString: day.dateStr,
                    hasSessions: sessions.length > 0,
                    sessions: sessions
                };
            });
            
            hours.push({
                hour: {
                    id: `hour-${hour}`,
                    value: hour,
                    label: hourLabel
                },
                days: days
            });
        }
        
        return hours;
    }
    
    // Day view data - time-based rows
    get dayViewData() {
        const hours = [];
        const startHour = 8;
        const endHour = 19;
        const currentDateStr = this.formatDateLocal(this.currentDate);
        
        // Create hour rows
        for (let hour = startHour; hour <= endHour; hour++) {
            const hourLabel = `${hour.toString().padStart(2, '0')}:00`;
            const divisions = this.divisionRows.map(division => {
                // Find event for this division and hour on current date
                const divisionEvent = division.events.find(event => {
                    const eventDateStr = event.date instanceof Date 
                        ? this.formatDateLocal(event.date) 
                        : String(event.date).substring(0, 10);
                    
                    if (eventDateStr !== currentDateStr) return false;
                    
                    const eventHour = parseInt(event.startTime.split(':')[0], 10);
                    return eventHour === hour;
                });
                
                if (divisionEvent) {
                    // divisionEvent is already formatted by formatEventForDivisionGrid
                    // It has courseCode and title properties already extracted
                    // Use the pre-formatted values directly
                    const courseCode = divisionEvent.courseCode || 'N/A';
                    const courseName = divisionEvent.title || 'Session';
                    const eventColor = divisionEvent.color || 'blue';
                    const backgroundColor = this.getColorBackgroundStyle(eventColor);
                    // For day view vertical layout, we don't need left/width positioning
                    // The card should take full width of the cell
                    const fullStyle = `background: ${backgroundColor}; width: 100%;`;
                    
                    return {
                        division: {
                            id: division.id,
                            name: division.name
                        },
                        hasSession: true,
                        session: {
                            id: divisionEvent.id,
                            displayCode: courseCode,
                            displayTitle: courseName,
                            displayFaculty: divisionEvent.instructor || 'TBD',
                            style: fullStyle
                        }
                    };
                } else {
                    return {
                        division: {
                            id: division.id,
                            name: division.name
                        },
                        hasSession: false,
                        session: null
                    };
                }
            });
            
            hours.push({
                hour: {
                    id: `hour-${hour}`,
                    value: hour,
                    label: hourLabel
                },
                divisions: divisions
            });
        }
        
        return hours;
    }
    
    // Month view data
    get monthCalendarWeeks() {
        const weeks = [];
        const today = new Date();
        today.setHours(0, 0, 0, 0);
        
        // Get first day of month
        const firstDay = new Date(this.currentDate.getFullYear(), this.currentDate.getMonth(), 1);
        const lastDay = new Date(this.currentDate.getFullYear(), this.currentDate.getMonth() + 1, 0);
        
        // Get start of first week
        const startDate = new Date(firstDay);
        startDate.setDate(startDate.getDate() - startDate.getDay());
        
        // Generate weeks
        let currentDate = new Date(startDate);
        let weekNum = 0;
        
        while (currentDate <= lastDay || weekNum < 6) {
            const weekDays = [];
            
            for (let i = 0; i < 7; i++) {
                const dateStr = this.formatDateLocal(currentDate);
                const dateObj = new Date(currentDate);
                dateObj.setHours(0, 0, 0, 0);
                const isToday = dateObj.getTime() === today.getTime();
                const isCurrentMonth = currentDate.getMonth() === this.currentDate.getMonth();
                
                // Find events for this date
                const dayEvents = this.events.filter(event => {
                    const eventDateStr = event.date instanceof Date 
                        ? this.formatDateLocal(event.date) 
                        : String(event.date).substring(0, 10);
                    return eventDateStr === dateStr;
                });
                
                const sessions = dayEvents.slice(0, 3).map(event => {
                    const eventColor = event.color || 'blue';
                    const backgroundColor = this.getColorBackgroundStyle(eventColor);
                    // Format display text - prefer course name, then title
                    let displayText = 'Session';
                    if (event.courseName) {
                        // Extract course code from course name (e.g., "OPS101 - Operations" -> "OPS101")
                        const courseCode = event.courseName.split(' - ')[0];
                        displayText = courseCode;
                    } else if (event.title) {
                        displayText = event.title;
                    }
                    return {
                        id: event.id,
                        displayText: displayText,
                        style: `background: ${backgroundColor};`
                    };
                });
                
                weekDays.push({
                    id: `month-day-${dateStr}`,
                    date: currentDate.getDate(),
                    dateString: dateStr,
                    dayClass: `month-day ${isToday ? 'today' : ''} ${!isCurrentMonth ? 'other-month' : ''}`,
                    sessions: sessions,
                    hasMore: dayEvents.length > 3,
                    moreCount: dayEvents.length - 3
                });
                
                currentDate.setDate(currentDate.getDate() + 1);
            }
            
            weeks.push({
                id: `week-${weekNum}`,
                days: weekDays
            });
            
            weekNum++;
            if (weekNum >= 6) break;
        }
        
        return weeks;
    }
    
    // Get division rows for week view
    get weekDivisionRows() {
        // If division is selected, show only that division
        // Otherwise show all divisions
        const divisionsToShow = this.selectedDivision 
            ? this.allDivisions.filter(div => div.value === this.selectedDivision)
            : this.allDivisions;
            
        if (!divisionsToShow || divisionsToShow.length === 0) {
            return [];
        }
        
        const weekDaysList = this.weekDays;
        
        return divisionsToShow.map(division => {
            // Create a flat array of day-event pairs for template iteration
            const dayEventPairs = [];
            
            weekDaysList.forEach(day => {
                // Get events for this division on this day
                const divisionEvents = this.events.filter(event => {
                    // Normalize date format - use local timezone
                    let eventDateStr = null;
                    if (event.date instanceof Date) {
                        eventDateStr = this.formatDateLocal(event.date);
                    } else if (event.date) {
                        const dateStr = String(event.date);
                        eventDateStr = dateStr.length >= 10 ? dateStr.substring(0, 10) : dateStr;
                    }
                    
                    // Normalize division IDs for comparison
                    const eventDivisionId = event.divisionId ? String(event.divisionId) : null;
                    const divisionValue = division.value ? String(division.value) : null;
                    
                    return eventDateStr === day.dateStr && 
                           eventDivisionId === divisionValue;
                });
                
                // Format events for display
                const formattedEvents = divisionEvents.map(event => {
                    return this.formatEventForWeekGrid(event, day.dateStr);
                });
                
                // Add each day's events as a separate entry
                dayEventPairs.push({
                    dayKey: day.key,
                    dateStr: day.dateStr,
                    dayName: day.name,
                    dayDate: day.date,
                    events: formattedEvents
                });
            });
            
            return {
                key: `division-${division.value}`,
                id: division.value,
                name: division.label,
                termName: division.termName || 'Trimester 1',
                dayEventPairs: dayEventPairs
            };
        });
    }
    
    formatEventForWeekGrid(event, dateStr) {
        const startHour = parseInt(event.startTime.split(':')[0], 10);
        const startMinute = parseInt(event.startTime.split(':')[1], 10);
        const endHour = parseInt(event.endTime.split(':')[0], 10);
        const endMinute = parseInt(event.endTime.split(':')[1], 10);
        
        // Calculate position (top) based on start time
        // Assuming day starts at 8:00 AM (480 minutes) and ends at 7:00 PM (1140 minutes)
        const dayStartMinutes = 8 * 60; // 8:00 AM
        const dayEndMinutes = 19 * 60; // 7:00 PM
        const dayDuration = dayEndMinutes - dayStartMinutes; // 660 minutes
        
        const startMinutes = startHour * 60 + startMinute;
        const endMinutes = endHour * 60 + endMinute;
        
        // Calculate top position as percentage of day
        const topPercent = ((startMinutes - dayStartMinutes) / dayDuration) * 100;
        const heightPercent = ((endMinutes - startMinutes) / dayDuration) * 100;
        
        // Extract course code from course name (e.g., "OPS101 - Operations" -> "OPS101")
        const courseCode = event.courseName ? event.courseName.split(' - ')[0] : (event.courseId ? 'N/A' : 'N/A');
        // Get the course name (e.g., "OPS101 - Operations" -> "Operations")
        const courseName = event.courseName ? (event.courseName.split(' - ')[1] || event.courseName) : (event.title || 'N/A');
        
        // Format time in 24-hour format for display (e.g., "13:00")
        const time24 = event.startTime; // Already in 24-hour format (HH:mm)
        
        // Ensure event ID is preserved for click handling
        return {
            ...event,
            id: event.id, // Explicitly preserve ID
            title: courseName, // Course name for display
            style: `top: ${topPercent}%; height: ${heightPercent}%;`,
            eventClass: `week-event event-${event.color}`,
            courseCode: courseCode,
            time24: time24, // 24-hour format time
            tooltip: `${courseCode} - ${courseName} (${time24})`
        };
    }
    
    get showCourseAssignmentsAndNotEdit() {
        return this.showCourseAssignments && !this.isEditMode;
    }
    
    get showExistingDivisions() {
        return this.isEditMode && this.existingSessionDivisions.length > 0;
    }
    
    // Modal getters
    get isModalOpen() {
        return this.showModal;
    }
    
    get modalTitle() {
        return this.isEditMode ? 'Edit Session' : 'Add New Session';
    }
    
    get modalSubtitle() {
        return this.isEditMode ? 'Update session details' : 'Plan multiple sessions for a course in one go.';
    }
    
    get modalSessionRows() {
        // Ensure facultyOptions is always an array
        const facultyOptionsArray = Array.isArray(this.facultyOptions) ? this.facultyOptions : [];
        
        console.log('modalSessionRows getter called, facultyOptions count:', facultyOptionsArray.length);
        
        return this.sessionRows.map((session, index) => {
            // Filter faculty options to exclude already selected faculty for this session
            const selectedFacultyIds = this.getSelectedFacultyIdsForSession(session);
            const availableFacultyOptions = facultyOptionsArray.filter(faculty => 
                faculty && faculty.value && !selectedFacultyIds.includes(faculty.value)
            );
            
            // Create a unique key for the combobox to force re-render when faculty is added
            const facultyComboboxKey = `${session.key || `session-${index}`}-faculty-${selectedFacultyIds.length}`;
            
            // Ensure facultyOptions is always a valid array (never undefined or null)
            const safeFacultyOptions = Array.isArray(availableFacultyOptions) ? availableFacultyOptions : [];
            
            const rowData = {
                id: session.key || `session-${index}`,
                expandableKey: `${session.key || `session-${index}`}-expandable`,
                index: index,
                division: session.divisionId || '',
                date: session.date || this.formatDateLocal(this.currentDate),
                time: session.time || '09:00',
                duration: session.duration || this.sessionDuration || 60,
                facultyPills: this.getFacultyPillsForSession(session, index),
                facultyOptions: safeFacultyOptions, // Always an array, never undefined
                facultyPlaceholder: safeFacultyOptions.length > 0 ? 'Add faculty' : 'No faculty available',
                facultyComboboxKey: facultyComboboxKey,
                divisionOptions: this.divisionOptions,
                selectionCount: this.getSelectionCountForSession(index),
                rowClass: this.selectedSessionIndex === index ? 'selected-row' : '',
                isExpanded: this.expandedSessionRows[index] || false,
                expandedClass: this.expandedSessionRows[index] ? 'expanded' : '',
                courseAssignments: this.sessionCourseAssignments[index] || [],
                selectedAssignments: this.sessionSelectedAssignments[index] || [],
                allAssignmentsSelected: this.getAllAssignmentsSelectedForSession(index)
            };
            
            console.log(`Session ${index} facultyOptions:`, safeFacultyOptions.length, 'options');
            return rowData;
        });
    }
    
    getSelectedFacultyIdsForSession(session) {
        if (!session.facultyId) return [];
        if (Array.isArray(session.facultyId)) {
            return session.facultyId.filter(id => id);
        }
        return session.facultyId ? [session.facultyId] : [];
    }
    
    getAllAssignmentsSelectedForSession(sessionIndex) {
        const assignments = this.sessionCourseAssignments[sessionIndex] || [];
        const selected = this.sessionSelectedAssignments[sessionIndex] || [];
        if (assignments.length === 0) return false;
        return assignments.every(option => 
            selected.includes(option.assignmentKey)
        );
    }
    
    getCourseAssignmentsForSession(sessionIndex) {
        return this.sessionCourseAssignments[sessionIndex] || [];
    }
    
    getFacultyPillsForSession(session, sessionIndex) {
        if (!session.facultyId) return [];
        const facultyIds = Array.isArray(session.facultyId) ? session.facultyId : [session.facultyId];
        return facultyIds.filter(id => id).map(id => {
            const faculty = this.facultyOptions.find(f => f.value === id);
            return {
                value: id,
                label: faculty ? faculty.label : 'Unknown',
                sessionIndex: sessionIndex
            };
        });
    }
    
    getSelectionCountForSession(sessionIndex) {
        const selected = this.sessionSelectedAssignments[sessionIndex] || [];
        return selected.length;
    }
    
    
    get allAssignmentsSelected() {
        if (!this.courseAssignments || this.courseAssignments.length === 0) {
            return false;
        }
        return this.courseAssignments.every(option => 
            this.selectedAssignments.includes(option.assignmentKey)
        );
    }
    
    get sessionCount() {
        return this.sessionRows.length;
    }
    
    get conflictCount() {
        // TODO: Implement conflict detection logic
        return 0;
    }
    
    get conflictInfoClass() {
        return this.conflictCount > 0 ? 'conflict-warning' : '';
    }
    
    get toastClass() {
        return `toast toast-${this.toastType}`;
    }
    
    get colorOptions() {
        return this.colors.map(color => ({
            value: color,
            label: color.charAt(0).toUpperCase() + color.slice(1),
            buttonClass: `color-btn color-btn-${color} ${this.eventColor === color ? 'selected' : ''}`,
            isSelected: this.eventColor === color
        }));
    }
    
    get selectedFacultyForCombobox() {
        if (Array.isArray(this.selectedFacultyValue)) {
            return this.selectedFacultyValue.length > 0 ? this.selectedFacultyValue[0] : '';
        }
        return this.selectedFacultyValue || '';
    }
    
    get selectedFacultyForDualListbox() {
        if (Array.isArray(this.selectedFacultyValue)) {
            return this.selectedFacultyValue;
        } else if (this.selectedFacultyValue && typeof this.selectedFacultyValue === 'string') {
            return [this.selectedFacultyValue];
        }
        return [];
    }
    
    get showFacultyDropdown() {
        return this.selectedCourse && this.facultyOptions.length > 0;
    }
    
    get isFacultyDisabled() {
        return this.isDivisionNotSelected || !this.selectedCourse;
    }
    
    get allAssignmentsSelected() {
        if (!this.courseAssignments || this.courseAssignments.length === 0) {
            return false;
        }
        return this.courseAssignments.every(option => 
            this.selectedAssignments.includes(option.assignmentKey)
        );
    }
    
    get sessionCount() {
        return this.sessionRows.length;
    }
    
    get conflictCount() {
        // TODO: Implement conflict detection logic
        return 0;
    }
    
    // Load Programs
    loadPrograms() {
        getPrograms()
            .then(result => {
                this.programOptions = result.map(option => ({
                    label: option.label,
                    value: option.value
                }));
            })
            .catch(error => {
                console.error('Error loading programs:', error);
            });
    }
    
    // Filter handlers
    handleProgramChange(event) {
        this.selectedProgram = event.detail.value;
        this.selectedBatch = null;
        this.selectedBatchGroup = null;
        this.selectedTerm = null;
        this.selectedDivision = null;
        this.sessionDuration = null;
        this.batchOptions = [];
        this.batchGroupOptions = [];
        this.termOptions = [];
        this.divisionOptions = [];
        this.allDivisions = [];
        
        if (this.selectedProgram) {
            getBatchesForProgram({ programId: this.selectedProgram })
                .then(result => {
                    this.batchOptions = result.map(option => ({
                        label: option.label,
                        value: option.value,
                        sessionDuration: option.sessionDuration || null
                    }));
                })
                .catch(error => {
                    console.error('Error loading batches:', error);
                });
        }
    }

    handleBatchChange(event) {
        this.selectedBatch = event.detail.value;
        this.selectedBatchGroup = null;
        this.selectedTerm = null;
        this.selectedDivision = null;
        this.batchGroupOptions = [];
        this.termOptions = [];
        this.divisionOptions = [];
        this.allDivisions = [];
        
        if (this.selectedBatch) {
            const selectedBatchOption = this.batchOptions.find(option => option.value === this.selectedBatch);
            this.sessionDuration = selectedBatchOption && selectedBatchOption.sessionDuration 
                ? selectedBatchOption.sessionDuration 
                : null;
            
            getBatchGroupsForBatch({ batchId: this.selectedBatch })
                .then(result => {
                    this.batchGroupOptions = result.map(option => ({
                        label: option.label,
                        value: option.value
                    }));
                })
                .catch(error => {
                    console.error('Error loading batch groups:', error);
                });
        } else {
            this.sessionDuration = null;
        }
    }

    handleBatchGroupChange(event) {
        this.selectedBatchGroup = event.detail.value;
        this.selectedTerm = null;
        this.selectedDivision = null;
        this.termOptions = [];
        this.divisionOptions = [];
        this.allDivisions = [];
        
        if (this.selectedBatchGroup) {
            getTermsForBatchGroup({ batchGroupId: this.selectedBatchGroup })
                .then(result => {
                    this.termOptions = result.map(option => ({
                        label: option.label,
                        value: option.value
                    }));
                })
                .catch(error => {
                    console.error('Error loading terms:', error);
                });
        }
    }

    handleTermChange(event) {
        this.selectedTerm = event.detail.value;
        this.selectedDivision = null;
        this.divisionOptions = [];
        this.allDivisions = [];
        this.events = []; // Clear events when term changes
        
        if (this.selectedTerm) {
            getDivisionsForTerms({ termIds: [this.selectedTerm] })
                .then(result => {
                    this.divisionOptions = result.map(option => ({
                        label: option.label,
                        value: option.value
                    }));
                    // Store all divisions for the grid
                    this.allDivisions = result.map(option => ({
                        label: option.label,
                        value: option.value,
                        termName: option.termName || 'Trimester 1'
                    }));
                    
                    // Update date range and refresh sessions
                    this.updateDateRange();
                    // Load sessions for all divisions when term is selected
                    // The @wire will handle specific division, but for "All Divisions" we need to load all
                    if (!this.selectedDivision) {
                        this.loadSessionsForAllDivisions();
                    } else {
                        // The @wire will automatically refresh when sessionFilter changes
                        setTimeout(() => {
                            if (this.wiredSessionsResult) {
                                refreshApex(this.wiredSessionsResult);
                            }
                        }, 0);
                    }
                })
                .catch(error => {
                    console.error('Error loading divisions:', error);
                });
        } else {
            // Clear date range if no term selected
            this.dateFrom = '';
            this.dateTo = '';
        }
    }
    
    // Load sessions for all divisions in the current term
    loadSessionsForAllDivisions() {
        if (!this.allDivisions || this.allDivisions.length === 0) {
            this.events = [];
            this.isLoading = false;
            this.isLoadingAllDivisions = false;
            return;
        }
        
        // Set flag to prevent wiredSessions from interfering
        this.isLoadingAllDivisions = true;
        
        // Use dateFrom and dateTo from reactive properties
        // Ensure currentDate is a Date object
        const currentDateObj = this.currentDate instanceof Date 
            ? this.currentDate 
            : new Date(this.currentDate);
        
        let startDate = this.dateFrom;
        let endDate = this.dateTo;
        
        // If dateFrom/dateTo are not set, calculate from currentDate based on view
        // Use local date formatting to avoid timezone issues
        if (!startDate || !endDate) {
            if (this.currentView === 'week') {
                const startOfWeek = this.getStartOfWeek(currentDateObj);
                const endOfWeek = new Date(startOfWeek);
                endOfWeek.setDate(endOfWeek.getDate() + 6);
                startDate = this.formatDateLocal(startOfWeek);
                endDate = this.formatDateLocal(endOfWeek);
            } else {
                startDate = this.formatDateLocal(currentDateObj);
                endDate = startDate;
            }
        }
        
        console.log('loadSessionsForAllDivisions: Loading sessions for date range:', startDate, 'to', endDate);
        console.log('  dateFrom:', this.dateFrom, 'dateTo:', this.dateTo);
        console.log('  currentView:', this.currentView);
        console.log('  currentDate:', this.currentDate);
        console.log('  allDivisions count:', this.allDivisions.length);
        
        this.isLoading = true;
        
        // Load sessions for each division and combine results
        const sessionPromises = this.allDivisions.map(division => {
            const filterPayload = {
                divisionId: division.value,
                startDate: startDate,
                endDate: endDate
            };
            
            console.log(`Loading sessions for division ${division.label} (${division.value}):`, JSON.stringify(filterPayload));
            
            return getSessions({ filterJson: JSON.stringify(filterPayload) })
                .then(result => {
                    console.log(`Result for division ${division.label}:`, result);
                    if (result && Array.isArray(result)) {
                        // Log raw session dates before mapping
                        const rawDates = result.map(s => ({
                            id: s.id,
                            sessionDate: s.sessionDate,
                            sessionDateType: typeof s.sessionDate,
                            sessionDateString: String(s.sessionDate)
                        }));
                        console.log(`Raw session dates for ${division.label}:`, JSON.stringify(rawDates, null, 2));
                        
                        const events = result.map(session => this.mapSessionToEvent(session));
                        console.log(`Mapped ${events.length} events for division ${division.label}`);
                        // Log mapped event dates
                        const mappedDates = events.map(e => ({
                            id: e.id,
                            date: e.date,
                            dateType: typeof e.date
                        }));
                        console.log(`Mapped event dates for ${division.label}:`, JSON.stringify(mappedDates, null, 2));
                        return events;
                    }
                    console.log(`No valid result array for division ${division.label}`);
                    return [];
                })
                .catch(error => {
                    console.error(`Error loading sessions for division ${division.label} (${division.value}):`, error);
                    return [];
                });
        });
        
        Promise.all(sessionPromises)
            .then(allSessions => {
                // Flatten the array of arrays into a single array
                // Force reactivity by creating a new array reference
                const flattenedEvents = allSessions.flat();
                
                // Filter events to only include those within the requested date range
                // This prevents timezone-shifted dates from appearing
                const filteredEvents = flattenedEvents.filter(event => {
                    if (!event.date) return false;
                    
                    // Normalize event date to YYYY-MM-DD format
                    let eventDateStr = event.date;
                    if (event.date instanceof Date) {
                        eventDateStr = this.formatDateLocal(event.date);
                    } else if (typeof event.date === 'string') {
                        // Extract date part from ISO string if present
                        if (event.date.includes('T')) {
                            eventDateStr = event.date.substring(0, 10);
                        } else if (event.date.length >= 10) {
                            eventDateStr = event.date.substring(0, 10);
                        }
                    }
                    
                    // Check if event date is within the requested range
                    const isInRange = eventDateStr >= startDate && eventDateStr <= endDate;
                    if (!isInRange) {
                        console.log(`Filtering out event ${event.id} with date ${eventDateStr} (requested range: ${startDate} to ${endDate})`);
                    }
                    return isInRange;
                });
                
                this.events = [...filteredEvents]; // Create new array reference to trigger reactivity
                
                console.log('loadSessionsForAllDivisions completed:');
                console.log('  Total events before filtering:', flattenedEvents.length);
                console.log('  Total events after filtering:', this.events.length);
                console.log('  Date range requested:', startDate, 'to', endDate);
                const eventsWithDates = this.events.map(e => ({
                    id: e.id,
                    date: String(e.date),
                    dateType: typeof e.date,
                    dateString: String(e.date),
                    divisionId: String(e.divisionId),
                    title: e.title,
                    color: e.color
                }));
                console.log('  Events with dates:', JSON.stringify(eventsWithDates, null, 2));
                this.isLoading = false;
                this.isLoadingAllDivisions = false; // Clear flag after loading
            })
            .catch(error => {
                console.error('Error loading sessions for all divisions:', error);
                this.events = [];
                this.isLoading = false;
                this.isLoadingAllDivisions = false; // Clear flag on error
            });
    }

    handleDivisionChange(event) {
        // Normalize empty string to null for "All Divisions"
        const value = event.detail.value;
        this.selectedDivision = (value === '' || value === null || value === undefined) ? null : value;
        
        // Load courses for the selected division (for the modal)
        if (this.selectedDivision) {
            this.isLoading = true;
            getCoursesForDivision({ divisionId: this.selectedDivision })
                .then(result => {
                    this.courseOptions = result.map(option => ({
                        label: option.label,
                        value: option.value,
                        departmentName: option.departmentName || null
                    }));
                })
                .catch(error => {
                    console.error('Error loading courses:', error);
                    this.courseOptions = [];
                });
        } else {
            this.courseOptions = [];
        }
        
        // Refresh sessions when division filter changes
        // If "All Divisions" is selected, load for all divisions
        // Otherwise, the @wire will automatically refresh when sessionFilter changes
        if (!this.selectedDivision && this.allDivisions && this.allDivisions.length > 0) {
            this.loadSessionsForAllDivisions();
        } else {
            setTimeout(() => {
                if (this.wiredSessionsResult) {
                    refreshApex(this.wiredSessionsResult);
                }
            }, 0);
        }
    }
    
    handleResetFilters() {
        this.selectedProgram = null;
        this.selectedBatch = null;
        this.selectedBatchGroup = null;
        this.selectedTerm = null;
        this.selectedDivision = null;
        this.batchOptions = [];
        this.batchGroupOptions = [];
        this.termOptions = [];
        this.divisionOptions = [];
        this.allDivisions = [];
        this.events = [];
    }
    
    // Navigation handlers
    handlePrevious() {
        this.handlePreviousPeriod();
    }
    
    handleNext() {
        this.handleNextPeriod();
    }
    
    handlePreviousPeriod() {
        const newDate = new Date(this.currentDate);
        if (this.currentView === 'week') {
            newDate.setDate(newDate.getDate() - 7);
        } else {
            newDate.setDate(newDate.getDate() - 1);
        }
        this.currentDate = newDate;
        this.updateDateRange();
        this.refreshSessions();
    }

    handleNextPeriod() {
        const newDate = new Date(this.currentDate);
        if (this.currentView === 'week') {
            newDate.setDate(newDate.getDate() + 7);
        } else {
            newDate.setDate(newDate.getDate() + 1);
        }
        this.currentDate = newDate;
        this.updateDateRange();
        this.refreshSessions();
    }

    handleToday() {
        this.currentDate = new Date();
        this.updateDateRange();
        this.refreshSessions();
    }
    
    refreshSessions() {
        // Ensure date range is updated first
        this.updateDateRange();
        
        // Force refresh sessions when view changes
        // If "All Divisions" is selected, use loadSessionsForAllDivisions
        if (!this.selectedDivision && this.allDivisions.length > 0) {
            // Small delay to ensure dateFrom/dateTo are updated
            setTimeout(() => {
                this.loadSessionsForAllDivisions();
            }, 0);
        } else {
            // Otherwise, refresh the wired result
            setTimeout(() => {
                if (this.wiredSessionsResult) {
                    refreshApex(this.wiredSessionsResult).then(() => {
                        // Ensure events are updated after refresh
                        this.isLoading = false;
                    });
                }
            }, 0);
        }
    }
    
    // Unified view change handler
    handleViewChange(event) {
        const view = event.currentTarget.dataset.view;
        if (view === 'month') {
            this.handleMonthView();
        } else if (view === 'week') {
            this.handleWeekView();
        } else if (view === 'day') {
            this.handleDayDivisionView();
        }
    }
    
    handleMonthView() {
        this.currentView = 'month';
        this.refreshSessions();
    }
    
    handleWeekView() {
        this.currentView = 'week';
        this.updateDateRange();
        
        // Small delay to ensure dateFrom/dateTo are updated before loading
        setTimeout(() => {
            // If "All Divisions" is selected, load for all divisions
            if (!this.selectedDivision && this.allDivisions && this.allDivisions.length > 0) {
                this.loadSessionsForAllDivisions();
            } else {
                this.refreshSessions();
            }
        }, 50);
    }
    
    handleDayDivisionView() {
        this.currentView = 'day';
        this.updateDateRange();
        // Use setTimeout to ensure dateFrom/dateTo are updated
        setTimeout(() => {
            this.refreshSessions();
        }, 0);
    }
    
    // Unified filter change handler
    handleFilterChange(event) {
        const field = event.currentTarget.dataset.field || event.currentTarget.name;
        const value = event.detail ? event.detail.value : event.target.value;
        
        // Create a synthetic event object for existing handlers
        const syntheticEvent = { detail: { value } };
        
        switch(field) {
            case 'program':
                this.selectedProgram = value;
                this.handleProgramChange(syntheticEvent);
                break;
            case 'batch':
                this.selectedBatch = value;
                this.handleBatchChange(syntheticEvent);
                break;
            case 'batchGroup':
                this.selectedBatchGroup = value;
                this.handleBatchGroupChange(syntheticEvent);
                break;
            case 'term':
                this.selectedTerm = value;
                this.handleTermChange(syntheticEvent);
                break;
            case 'division':
                // Normalize empty string to null for "All Divisions"
                this.selectedDivision = (value === '' || value === null || value === undefined) ? null : value;
                this.handleDivisionChange(syntheticEvent);
                break;
        }
    }
    
    // Slot click handler (for empty cells)
    handleSlotClick(event) {
        event.stopPropagation();
        const date = event.currentTarget.dataset.date;
        const hour = event.currentTarget.dataset.hour;
        const division = event.currentTarget.dataset.division;
        
        if (!date) return;
        
        const startTime = hour ? `${hour.toString().padStart(2, '0')}:00` : '09:00';
        const duration = this.sessionDuration || 60;
        
        this.openBulkSessionModal(date, startTime, duration, division);
    }
    
    // Session click handler (for existing sessions)
    handleSessionClick(event) {
        event.stopPropagation();
        event.preventDefault();
        
        // Get session ID from the clicked element or closest parent with data-session-id
        // In LWC, data-session-id becomes dataset.sessionId (camelCase)
        let sessionId = event.currentTarget?.dataset?.sessionId;
        
        // If not found, try from target or closest element
        if (!sessionId) {
            const targetElement = event.target;
            sessionId = targetElement?.dataset?.sessionId;
            
            // If still not found, try closest parent with the attribute
            if (!sessionId && targetElement) {
                const closestElement = targetElement.closest('[data-session-id]');
                if (closestElement) {
                    // Access the dataset property correctly
                    sessionId = closestElement.dataset?.sessionId || 
                               closestElement.getAttribute('data-session-id');
                }
            }
        }
        
        console.log('handleSessionClick called with sessionId:', sessionId);
        console.log('currentTarget:', event.currentTarget);
        console.log('target:', event.target);
        console.log('currentTarget dataset:', event.currentTarget?.dataset);
        
        if (!sessionId) {
            console.error('No session ID found in click event', event);
            console.error('Available dataset keys:', Object.keys(event.currentTarget?.dataset || {}));
            return;
        }
        
        // Call handleEventClick with a properly structured event object
        // handleEventClick expects event.currentTarget.dataset.id or event.currentTarget.dataset.eventId
        const syntheticEvent = {
            currentTarget: {
                dataset: {
                    id: sessionId,
                    eventId: sessionId,
                    sessionId: sessionId
                }
            },
            target: event.target,
            stopPropagation: () => {},
            preventDefault: () => {}
        };
        
        this.handleEventClick(syntheticEvent);
    }
    
    // Modal handlers
    handleModalInputChange(event) {
        const field = event.currentTarget.dataset.field;
        const value = event.detail.value;
        
        if (field === 'program') {
            this.modalData.program = value;
            this.selectedProgram = value;
            this.handleProgramChange({ detail: { value } });
        } else if (field === 'batch') {
            this.modalData.batch = value;
            this.selectedBatch = value;
            this.handleBatchChange({ detail: { value } });
        } else if (field === 'term') {
            this.modalData.term = value;
            this.selectedTerm = value;
            this.handleTermChange({ detail: { value } });
        } else if (field === 'course') {
            this.modalData.course = value;
            this.selectedCourse = value;
            this.handleCourseChange({ detail: { value } });
        } else if (field === 'sessionTitle') {
            this.modalData.sessionTitle = value;
            this.eventTitle = value;
        }
    }
    
    handleSessionFieldChange(event) {
        const index = parseInt(event.currentTarget.dataset.index, 10);
        const field = event.currentTarget.dataset.field;
        const value = event.detail.value;
        
        if (index >= 0 && index < this.sessionRows.length) {
            this.sessionRows = this.sessionRows.map((row, i) => {
                if (i === index) {
                    const updatedRow = { ...row, [field]: value };
                    // If division changed and course is selected, load assignments for this session
                    if (field === 'divisionId' && value && this.selectedCourse) {
                        this.loadCourseAssignmentsForSession(index, value);
                    }
                    return updatedRow;
                }
                return row;
            });
        }
    }
    
    loadCourseAssignmentsForSession(sessionIndex, divisionId) {
        if (!this.selectedCourse || !divisionId) {
            this.sessionCourseAssignments = { ...this.sessionCourseAssignments, [sessionIndex]: [] };
            this.sessionSelectedAssignments = { ...this.sessionSelectedAssignments, [sessionIndex]: [] };
            return;
        }
        
        const courseValue = this.selectedCourse;
        const parts = courseValue.split('|');
        const learningCourseId = parts.length > 1 ? parts[1] : null;
        
        if (!learningCourseId) {
            this.sessionCourseAssignments = { ...this.sessionCourseAssignments, [sessionIndex]: [] };
            this.sessionSelectedAssignments = { ...this.sessionSelectedAssignments, [sessionIndex]: [] };
            return;
        }
        
        const currentProgramId = this.selectedProgram || null;
        const currentBatchId = this.selectedBatch || null;
        const currentBatchGroupId = this.selectedBatchGroup || null;
        const currentTermId = this.selectedTerm || null;
        
        getCourseAssignments({ 
            learningCourseId: learningCourseId, 
            currentDivisionId: divisionId,
            currentProgramId: currentProgramId,
            currentBatchId: currentBatchId,
            currentBatchGroupId: currentBatchGroupId,
            currentTermId: currentTermId
        })
            .then(result => {
                const assignments = Array.isArray(result) ? result : [];
                const formattedAssignments = assignments.map((option, idx) => ({
                    ...option,
                    assignmentKey: this.getAssignmentKey(option, idx),
                    isSelected: false,
                    divisionName: option.divisions && option.divisions.length > 0 
                        ? option.divisions[0].divisionName 
                        : '',
                    divisionId: option.divisions && option.divisions.length > 0 
                        ? option.divisions[0].divisionId 
                        : ''
                }));
                
                this.sessionCourseAssignments = { 
                    ...this.sessionCourseAssignments, 
                    [sessionIndex]: formattedAssignments 
                };
                this.sessionSelectedAssignments = { 
                    ...this.sessionSelectedAssignments, 
                    [sessionIndex]: [] 
                };
            })
            .catch(error => {
                console.error('Error loading course assignments for session:', error);
                this.sessionCourseAssignments = { ...this.sessionCourseAssignments, [sessionIndex]: [] };
                this.sessionSelectedAssignments = { ...this.sessionSelectedAssignments, [sessionIndex]: [] };
            });
    }
    
    handleToggleSessionRow(event) {
        const index = parseInt(event.currentTarget.dataset.index, 10);
        const isExpanded = this.expandedSessionRows[index] || false;
        this.expandedSessionRows = { ...this.expandedSessionRows, [index]: !isExpanded };
        
        // If expanding and division is set, load assignments if not already loaded
        if (!isExpanded && index >= 0 && index < this.sessionRows.length) {
            const session = this.sessionRows[index];
            if (session.divisionId && this.selectedCourse && !this.sessionCourseAssignments[index]) {
                this.loadCourseAssignmentsForSession(index, session.divisionId);
            }
        }
    }
    
    handleSessionAssignmentToggle(event) {
        const sessionIndex = parseInt(event.currentTarget.dataset.sessionIndex, 10);
        const key = event.currentTarget.dataset.key;
        const isChecked = event.currentTarget.checked;
        
        const currentSelected = this.sessionSelectedAssignments[sessionIndex] || [];
        let updatedSelected;
        
        if (isChecked) {
            updatedSelected = [...currentSelected, key];
        } else {
            updatedSelected = currentSelected.filter(k => k !== key);
        }
        
        this.sessionSelectedAssignments = { 
            ...this.sessionSelectedAssignments, 
            [sessionIndex]: updatedSelected 
        };
        
        // Update isSelected in courseAssignments
        const assignments = this.sessionCourseAssignments[sessionIndex] || [];
        this.sessionCourseAssignments = {
            ...this.sessionCourseAssignments,
            [sessionIndex]: assignments.map(option => ({
                ...option,
                isSelected: updatedSelected.includes(option.assignmentKey)
            }))
        };
    }
    
    handleSelectAllSessionAssignments(event) {
        const sessionIndex = parseInt(event.currentTarget.dataset.sessionIndex, 10);
        const isChecked = event.target.checked;
        
        const assignments = this.sessionCourseAssignments[sessionIndex] || [];
        
        if (isChecked) {
            this.sessionSelectedAssignments = {
                ...this.sessionSelectedAssignments,
                [sessionIndex]: assignments.map(option => option.assignmentKey)
            };
        } else {
            this.sessionSelectedAssignments = {
                ...this.sessionSelectedAssignments,
                [sessionIndex]: []
            };
        }
        
        // Update isSelected
        this.sessionCourseAssignments = {
            ...this.sessionCourseAssignments,
            [sessionIndex]: assignments.map(option => ({
                ...option,
                isSelected: isChecked
            }))
        };
    }
    
    handleAddSession() {
        this.handleAddSessionRow();
    }
    
    handleDeleteSession(event) {
        event.stopPropagation();
        const index = parseInt(event.currentTarget.dataset.index, 10);
        this.handleRemoveSessionRow({ currentTarget: { dataset: { index } } });
    }
    
    handleSaveSession() {
        this.handleSaveAllSessions();
    }
    
    stopModalPropagation(event) {
        event.stopPropagation();
    }
    
    handleSelectSessionRow(event) {
        const index = parseInt(event.currentTarget.dataset.index, 10);
        this.selectedSessionIndex = index;
    }
    
    handleRemoveFaculty(event) {
        event.stopPropagation();
        const sessionIndex = parseInt(event.currentTarget.dataset.sessionIndex, 10);
        const facultyId = event.currentTarget.dataset.faculty;
        
        if (sessionIndex >= 0 && sessionIndex < this.sessionRows.length) {
            this.sessionRows = this.sessionRows.map((row, i) => {
                if (i === sessionIndex) {
                    const facultyIds = Array.isArray(row.facultyId) ? row.facultyId : (row.facultyId ? [row.facultyId] : []);
                    const updatedFacultyIds = facultyIds.filter(id => id !== facultyId);
                    return { ...row, facultyId: updatedFacultyIds.length === 1 ? updatedFacultyIds[0] : updatedFacultyIds };
                }
                return row;
            });
        }
    }
    
    handleFacultyChange(event) {
        const index = parseInt(event.currentTarget.dataset.index, 10);
        const facultyId = event.detail.value;
        
        if (index >= 0 && index < this.sessionRows.length && facultyId) {
            this.sessionRows = this.sessionRows.map((row, i) => {
                if (i === index) {
                    const existingFacultyIds = Array.isArray(row.facultyId) ? row.facultyId : (row.facultyId ? [row.facultyId] : []);
                    if (!existingFacultyIds.includes(facultyId)) {
                        // Always store as array to support multiple faculty
                        return { ...row, facultyId: [...existingFacultyIds, facultyId] };
                    }
                }
                return row;
            });
            // The combobox will automatically clear because the key changes, forcing a re-render
        }
    }
    
    
    // Event handlers
    handleNewBooking() {
        // Check if we have term selected (to show divisions)
        if (!this.selectedTerm) {
            this.showToastMessage('Please select a term first', 'error');
            return;
        }
        this.isEditMode = false;
        this.selectedEventId = null;
        this.resetEventForm();
        // Initialize modal data
        this.modalData = {
            program: this.selectedProgram || null,
            batch: this.selectedBatch || null,
            term: this.selectedTerm || null,
            course: this.selectedCourse || null,
            sessionTitle: ''
        };
        // Initialize with one session row
        this.sessionRows = [{
            key: `session-${Date.now()}`,
            divisionId: this.selectedDivision || '',
            date: this.formatDateLocal(this.currentDate),
            time: this.eventStartTime || '09:00',
            duration: this.sessionDuration || 60,
            facultyId: [], // Use array to support multiple faculty
            color: 'blue'
        }];
        
        // If a course is already selected, load faculty for it
        if (this.selectedCourse) {
            console.log('Course already selected in handleNewBooking, loading faculty:', this.selectedCourse);
            this.loadFacultyForCourse();
        }
        
        this.showModal = true;
    }
    
    handleAddSessionRow() {
        const newRow = {
            key: `session-${Date.now()}-${Math.random()}`,
            divisionId: '',
            date: this.formatDateLocal(this.currentDate),
            time: '09:00',
            duration: this.sessionDuration || 60,
            facultyId: [], // Use array to support multiple faculty
            color: 'blue' // Default color
        };
        this.sessionRows = [...this.sessionRows, newRow];
    }
    
    handleSessionColorChange(event) {
        const index = parseInt(event.currentTarget.dataset.index, 10);
        const color = event.currentTarget.dataset.color;
        this.sessionRows = this.sessionRows.map((row, i) => 
            i === index ? { ...row, color: color } : row
        );
    }
    
    get colorOptions() {
        return this.colors.map(color => ({
            value: color,
            label: color.charAt(0).toUpperCase() + color.slice(1),
            buttonClass: `color-btn color-btn-${color} ${this.eventColor === color ? 'selected' : ''}`,
            isSelected: this.eventColor === color
        }));
    }
    
    handleRemoveSessionRow(event) {
        const index = parseInt(event.currentTarget.dataset.index, 10);
        this.sessionRows = this.sessionRows.filter((row, i) => i !== index);
        // Clean up per-session data - reindex everything
        const newSessionCourseAssignments = {};
        const newSessionSelectedAssignments = {};
        const newExpandedSessionRows = {};
        this.sessionRows.forEach((row, i) => {
            const oldIndex = i < index ? i : i + 1;
            if (this.sessionCourseAssignments[oldIndex]) {
                newSessionCourseAssignments[i] = this.sessionCourseAssignments[oldIndex];
            }
            if (this.sessionSelectedAssignments[oldIndex]) {
                newSessionSelectedAssignments[i] = this.sessionSelectedAssignments[oldIndex];
            }
            if (this.expandedSessionRows[oldIndex]) {
                newExpandedSessionRows[i] = this.expandedSessionRows[oldIndex];
            }
        });
        this.sessionCourseAssignments = newSessionCourseAssignments;
        this.sessionSelectedAssignments = newSessionSelectedAssignments;
        this.expandedSessionRows = newExpandedSessionRows;
    }
    
    handleSessionDivisionChange(event) {
        const index = parseInt(event.currentTarget.dataset.index, 10);
        const divisionId = event.detail.value;
        this.sessionRows = this.sessionRows.map((row, i) => 
            i === index ? { ...row, divisionId: divisionId } : row
        );
    }
    
    handleSessionDateChange(event) {
        const index = parseInt(event.currentTarget.dataset.index, 10);
        const date = event.target.value;
        this.sessionRows = this.sessionRows.map((row, i) => 
            i === index ? { ...row, date: date } : row
        );
    }
    
    handleSessionTimeChange(event) {
        const index = parseInt(event.currentTarget.dataset.index, 10);
        const time = event.target.value;
        this.sessionRows = this.sessionRows.map((row, i) => 
            i === index ? { ...row, time: time } : row
        );
    }
    
    handleSessionDurationChange(event) {
        const index = parseInt(event.currentTarget.dataset.index, 10);
        const duration = parseInt(event.target.value, 10) || 60;
        this.sessionRows = this.sessionRows.map((row, i) => 
            i === index ? { ...row, duration: duration } : row
        );
    }
    
    handleSessionFacultyChange(event) {
        const index = parseInt(event.currentTarget.dataset.index, 10);
        const facultyId = event.detail.value;
        this.sessionRows = this.sessionRows.map((row, i) => 
            i === index ? { ...row, facultyId: facultyId } : row
        );
    }
    
    handleModalProgramChange(event) {
        this.handleProgramChange(event);
    }
    
    handleModalBatchChange(event) {
        this.handleBatchChange(event);
    }
    
    handleModalTermChange(event) {
        this.handleTermChange(event);
    }
    
    handleCellClick(event) {
        // Stop event propagation to prevent triggering parent click handlers
        event.stopPropagation();
        
        // Check if we have divisions loaded (from term selection)
        if (!this.allDivisions || this.allDivisions.length === 0) {
            this.showToastMessage('Please select a term first to view the schedule', 'error');
            return;
        }
        
        const hour = parseInt(event.currentTarget.dataset.hour, 10);
        const divisionId = event.currentTarget.dataset.division;
        const clickedDate = this.formatDateLocal(this.currentDate);
        
        // Calculate end time based on duration or default to 1 hour
        let endHour = hour + 1;
        let endMinutes = 0;
        if (this.sessionDuration && this.sessionDuration > 0) {
            const totalStartMinutes = hour * 60;
            const totalEndMinutes = totalStartMinutes + this.sessionDuration;
            endHour = Math.floor(totalEndMinutes / 60);
            endMinutes = totalEndMinutes % 60;
        }
        
        const startTime = `${hour.toString().padStart(2, '0')}:00`;
        const endTime = `${endHour.toString().padStart(2, '0')}:${endMinutes.toString().padStart(2, '0')}`;
        const duration = this.sessionDuration || 60;
        
        // Set the division for the new event (from the clicked cell)
        const targetDivision = divisionId || this.selectedDivision || (this.allDivisions.length > 0 ? this.allDivisions[0].value : '');
        
        // Open bulk session modal with pre-populated data
        this.openBulkSessionModal(clickedDate, startTime, duration, targetDivision);
    }
    
    handleWeekCellClick(event) {
        // Stop event propagation to prevent triggering event clicks
        event.stopPropagation();
        
        // Only handle if clicking on empty cell (not on an event)
        if (event.target.classList.contains('week-event') || event.target.closest('.week-event')) {
            return; // Let handleEventClick handle it
        }
        
        // Check if we have divisions loaded
        if (!this.allDivisions || this.allDivisions.length === 0) {
            this.showToastMessage('Please select a term first to view the schedule', 'error');
            return;
        }
        
        const clickedDate = event.currentTarget.dataset.dayDate || event.currentTarget.dataset.date;
        const divisionId = event.currentTarget.dataset.dayDivision || event.currentTarget.dataset.division;
        
        // Default to 9:00 AM for week view clicks
        const startTime = '09:00';
        const duration = this.sessionDuration || 60;
        
        // Open bulk session modal with pre-populated data
        this.openBulkSessionModal(clickedDate, startTime, duration, divisionId);
    }
    
    openBulkSessionModal(date, startTime, duration, divisionId) {
        // Reset form state
        this.isEditMode = false;
        this.selectedEventId = null;
        this.resetEventForm();
        
        // Initialize modal data
        this.modalData = {
            program: this.selectedProgram || null,
            batch: this.selectedBatch || null,
            term: this.selectedTerm || null,
            course: this.selectedCourse || null,
            sessionTitle: ''
        };
        
        // Pre-populate form with clicked cell data
        this.eventDate = date;
        this.eventStartTime = startTime;
        
        // Calculate end time from start time and duration
        const [startHour, startMin] = startTime.split(':').map(Number);
        const totalStartMinutes = startHour * 60 + startMin;
        const totalEndMinutes = totalStartMinutes + duration;
        const endHour = Math.floor(totalEndMinutes / 60);
        const endMin = totalEndMinutes % 60;
        this.eventEndTime = `${endHour.toString().padStart(2, '0')}:${endMin.toString().padStart(2, '0')}`;
        
        // Create initial session row
        this.sessionRows = [{
            key: `session-${Date.now()}`,
            divisionId: divisionId || this.selectedDivision || '',
            date: date,
            time: startTime,
            duration: duration,
            facultyId: [], // Use array to support multiple faculty
            color: 'blue' // Default color
        }];
        
        // Load courses for the selected division
        const targetDivision = divisionId || this.selectedDivision;
        if (targetDivision) {
            getCoursesForDivision({ divisionId: targetDivision })
                .then(result => {
                    this.courseOptions = result.map(option => ({
                        label: option.label,
                        value: option.value,
                        departmentName: option.departmentName || null
                    }));
                    console.log('Courses loaded for division:', targetDivision, this.courseOptions.length);
                    
                    // If a course is already selected, load faculty for it
                    if (this.selectedCourse) {
                        console.log('Course already selected, loading faculty:', this.selectedCourse);
                        this.loadFacultyForCourse();
                    }
                })
                .catch(error => {
                    console.error('Error loading courses:', error);
                    this.courseOptions = [];
                });
        } else if (this.selectedCourse) {
            // If no division but course is selected, still try to load faculty
            console.log('No division but course selected, loading faculty:', this.selectedCourse);
            this.loadFacultyForCourse();
        } else if (this.allDivisions && this.allDivisions.length > 0) {
            // If no specific division, load courses for the first division as default
            const firstDivision = this.allDivisions[0].value;
            getCoursesForDivision({ divisionId: firstDivision })
                .then(result => {
                    this.courseOptions = result.map(option => ({
                        label: option.label,
                        value: option.value,
                        departmentName: option.departmentName || null
                    }));
                    
                    // If a course is already selected, load faculty for it
                    if (this.selectedCourse) {
                        console.log('Course already selected after loading courses, loading faculty:', this.selectedCourse);
                        this.loadFacultyForCourse();
                    }
                })
                .catch(error => {
                    console.error('Error loading courses:', error);
                    this.courseOptions = [];
                });
        }
        
        // Open the modal
        this.showModal = true;
        console.log('Bulk session modal opened with:', { date, startTime, duration, divisionId });
    }
    
    handleEventClick(event) {
        event.stopPropagation();
        event.preventDefault();
        
        // Get event ID from data attribute - try multiple ways
        let eventId = event.currentTarget?.dataset?.id || 
                      event.currentTarget?.dataset?.eventId ||
                      event.currentTarget?.dataset?.sessionId ||
                      event.target?.dataset?.id ||
                      event.target?.dataset?.eventId ||
                      event.target?.dataset?.sessionId ||
                      event.target?.closest('[data-id]')?.dataset?.id ||
                      event.target?.closest('[data-event-id]')?.dataset?.eventId ||
                      event.target?.closest('[data-session-id]')?.dataset?.sessionId;
        
        if (!eventId) {
            console.error('No event ID found in click event', event);
            console.error('currentTarget:', event.currentTarget);
            console.error('target:', event.target);
            return;
        }
        
        console.log('handleEventClick called with eventId:', eventId);
        console.log('Total events available:', this.events.length);
        
        const selectedEvent = this.events.find(e => {
            // Try both string and ID comparison - normalize both to strings for comparison
            const eventIdStr = String(eventId).trim();
            const eIdStr = String(e.id).trim();
            // Exact match (most common case)
            if (eIdStr === eventIdStr) return true;
            // Also try direct comparison
            if (e.id === eventId) return true;
            // Try case-insensitive match
            if (eIdStr.toLowerCase() === eventIdStr.toLowerCase()) return true;
            return false;
        });
        
        if (!selectedEvent) {
            console.error('Event not found for ID:', eventId);
            console.error('Event ID type:', typeof eventId);
            console.error('Available event IDs:', this.events.map(e => ({ id: e.id, type: typeof e.id })));
            console.error('First few events:', this.events.slice(0, 3).map(e => ({ id: e.id, title: e.title, date: e.date })));
            // Don't return early - try to open modal with basic info
            console.warn('Attempting to open modal with limited event data');
            // Still try to open modal, but with minimal data
            this.isEditMode = true;
            this.selectedEventId = eventId;
            this.showModal = true;
            return;
        }
        
        console.log('Found matching event:', selectedEvent);
        
        if (selectedEvent) {
            this.isEditMode = true;
            this.selectedEventId = eventId;
            this.eventTitle = selectedEvent.title || '';
            this.eventDate = selectedEvent.date || '';
            this.eventStartTime = selectedEvent.startTime || '09:00';
            this.eventEndTime = selectedEvent.endTime || '10:00';
            this.eventColor = selectedEvent.color || 'blue';
            
            // Calculate duration from start and end time
            const startParts = this.eventStartTime.split(':');
            const endParts = this.eventEndTime.split(':');
            const startMinutes = parseInt(startParts[0]) * 60 + parseInt(startParts[1]);
            const endMinutes = parseInt(endParts[0]) * 60 + parseInt(endParts[1]);
            const calculatedDuration = endMinutes - startMinutes;
            
            const courseName = selectedEvent.courseName || '';
            if (courseName) {
                // Load courses for the division first
                const divisionId = selectedEvent.divisionId;
                if (divisionId) {
                    getCoursesForDivision({ divisionId: divisionId })
                        .then(result => {
                            this.courseOptions = result.map(option => ({
                                label: option.label,
                                value: option.value,
                                departmentName: option.departmentName || null
                            }));
                            
                            // Now find matching course
                            const matchingOption = this.courseOptions.find(opt => opt.value && opt.value.startsWith(courseName + '|'));
                            this.selectedCourse = matchingOption ? matchingOption.value : courseName;
                            if (this.selectedCourse && matchingOption) {
                                this.selectedCourseDepartmentName = matchingOption.departmentName || '';
                            } else {
                                this.selectedCourseDepartmentName = '';
                            }
                            if (this.selectedCourse) {
                                this.loadCourseAssignments();
                                this.loadFacultyForCourse();
                            }
                        })
                        .catch(error => {
                            console.error('Error loading courses:', error);
                            this.courseOptions = [];
                        });
                }
            } else {
                this.selectedCourse = '';
                this.selectedCourseDepartmentName = '';
            }
            
            this.selectedCourseActivity = selectedEvent.courseActivity || '';
            this.isJointSession = selectedEvent.isJointSession || false;
            
            // Create initial session row with event data
            // IMPORTANT: Include the session ID so we can update instead of create
            this.sessionRows = [{
                key: `session-${eventId}`,
                sessionId: eventId, // Store the session ID for updates
                divisionId: selectedEvent.divisionId || '',
                date: selectedEvent.date || '',
                time: selectedEvent.startTime || '09:00',
                duration: calculatedDuration,
                facultyId: [], // Will be populated by loadExistingSessionFaculties
                color: selectedEvent.color || 'blue'
            }];
            
            // Load session divisions and faculties, then update session row
            this.loadExistingSessionDivisions(eventId);
            
            // Ensure we have a promise to chain
            const facultyPromise = this.loadExistingSessionFaculties(eventId);
            if (facultyPromise && typeof facultyPromise.then === 'function') {
                facultyPromise
                    .then(() => {
                        // Update session row with faculty data
                        if (this.sessionRows.length > 0) {
                            // Ensure facultyId is always an array
                            if (Array.isArray(this.selectedFacultyValue)) {
                                this.sessionRows[0].facultyId = this.selectedFacultyValue;
                            } else if (this.selectedFacultyValue) {
                                this.sessionRows[0].facultyId = [this.selectedFacultyValue];
                            } else {
                                this.sessionRows[0].facultyId = [];
                            }
                            // Preserve the sessionId when updating faculty
                            if (!this.sessionRows[0].sessionId && this.selectedEventId) {
                                this.sessionRows[0].sessionId = this.selectedEventId;
                            }
                        }
                        console.log('Session data loaded, opening modal');
                    })
                    .catch(error => {
                        console.error('Error loading session faculties:', error);
                        // Still open modal even if faculty loading fails
                    })
                    .finally(() => {
                        // Always open modal, even if there were errors
                        console.log('Setting showModal to true');
                        this.showModal = true;
                    });
            } else {
                // If loadExistingSessionFaculties doesn't return a promise, open modal immediately
                console.log('loadExistingSessionFaculties did not return a promise, opening modal immediately');
                this.showModal = true;
            }
        }
    }
    
    // Modal handlers
    handleCloseModal() {
        this.showModal = false;
        this.isEditMode = false;
        this.selectedEventId = null;
        this.selectedSessionIndex = null;
        this.resetEventForm();
    }

    handleModalClick(event) {
        event.stopPropagation();
    }
    
    stopModalPropagation(event) {
        event.stopPropagation();
    }
    
    resetEventForm() {
        this.eventTitle = '';
        this.eventDate = '';
        this.eventStartTime = '09:00';
        this.eventEndTime = '10:00';
        this.eventColor = 'blue';
        this.selectedCourse = '';
        this.selectedCourseActivity = '';
        this.courseAssignments = [];
        this.selectedAssignments = [];
        this.showCourseAssignments = false;
        this.existingSessionDivisions = [];
        this.isJointSession = false;
        this.selectedFacultyValue = '';
        this.facultyOptions = [];
        this.selectedCourseDepartmentName = '';
        this.sessionRows = [];
        this.selectedSessionIndex = null;
        this.sessionCourseAssignments = {};
        this.sessionSelectedAssignments = {};
        this.expandedSessionRows = {};
        // Reset modal data
        this.modalData = {
            program: this.selectedProgram || null,
            batch: this.selectedBatch || null,
            term: this.selectedTerm || null,
            course: this.selectedCourse || null,
            sessionTitle: this.eventTitle || ''
        };
    }
    
    // Form handlers
    handleTitleChange(event) {
        this.eventTitle = event.target.value;
    }

    handleDateChange(event) {
        this.eventDate = event.target.value;
    }

    handleStartTimeChange(event) {
        this.eventStartTime = event.target.value;
    }

    handleEndTimeChange(event) {
        this.eventEndTime = event.target.value;
    }

    handleColorSelect(event) {
        this.eventColor = event.currentTarget.dataset.color;
    }
    
    handleCourseChange(event) {
        this.selectedCourse = event.detail.value;
        this.selectedAssignments = [];
        this.showCourseAssignments = false;
        this.selectedFacultyValue = this.isJointSession ? [] : '';
        this.facultyOptions = [];
        
        if (this.selectedCourse) {
            const selectedOption = this.courseOptions.find(opt => opt.value === this.selectedCourse);
            if (selectedOption && selectedOption.departmentName) {
                this.selectedCourseDepartmentName = selectedOption.departmentName;
            } else {
                this.selectedCourseDepartmentName = '';
            }
            
            this.loadCourseAssignments();
            this.loadFacultyForCourse();
            
            // Load assignments for all existing session rows that have divisions
            this.sessionRows.forEach((session, index) => {
                if (session.divisionId) {
                    this.loadCourseAssignmentsForSession(index, session.divisionId);
                }
            });
        } else {
            this.selectedCourseDepartmentName = '';
            this.courseAssignments = [];
            // Clear all per-session assignments
            this.sessionCourseAssignments = {};
            this.sessionSelectedAssignments = {};
        }
    }
    
    loadCourseAssignments() {
        if (!this.selectedCourse) {
            this.courseAssignments = [];
            this.showCourseAssignments = false;
            return;
        }
        
        const courseValue = this.selectedCourse;
        const parts = courseValue.split('|');
        const learningCourseId = parts.length > 1 ? parts[1] : null;
        
        if (!learningCourseId) {
            console.error('LearningCourseId not found in course selection');
            this.courseAssignments = [];
            this.showCourseAssignments = false;
            return;
        }
        
        const currentDivisionId = this.selectedDivision || null;
        const currentProgramId = this.selectedProgram || null;
        const currentBatchId = this.selectedBatch || null;
        const currentBatchGroupId = this.selectedBatchGroup || null;
        const currentTermId = this.selectedTerm || null;
        
        getCourseAssignments({ 
            learningCourseId: learningCourseId, 
            currentDivisionId: currentDivisionId,
            currentProgramId: currentProgramId,
            currentBatchId: currentBatchId,
            currentBatchGroupId: currentBatchGroupId,
            currentTermId: currentTermId
        })
            .then(result => {
                const assignments = Array.isArray(result) ? result : [];
                this.courseAssignments = assignments.map((option, index) => ({
                    ...option,
                    assignmentKey: this.getAssignmentKey(option, index),
                    isSelected: false,
                    divisionName: option.divisions && option.divisions.length > 0 
                        ? option.divisions[0].divisionName 
                        : '',
                    divisionId: option.divisions && option.divisions.length > 0 
                        ? option.divisions[0].divisionId 
                        : ''
                }));
                this.showCourseAssignments = this.courseAssignments.length > 0;
                this.selectedAssignments = [];
                this.updateAssignmentSelection();
            })
            .catch(error => {
                console.error('Error loading course assignments:', error);
                this.courseAssignments = [];
                this.showCourseAssignments = false;
            });
    }
    
    getAssignmentKey(option, index) {
        const divisionId = option.divisions && option.divisions.length > 0 
            ? option.divisions[0].divisionId 
            : '';
        return `${option.programId || ''}_${option.batchId || ''}_${option.batchGroupId || ''}_${option.termId || ''}_${divisionId}_${index}`;
    }
    
    handleAssignmentToggle(event) {
        const key = event.currentTarget.dataset.key;
        const isChecked = event.currentTarget.checked;
        
        if (isChecked) {
            if (!this.selectedAssignments.includes(key)) {
                this.selectedAssignments = [...this.selectedAssignments, key];
            }
        } else {
            this.selectedAssignments = this.selectedAssignments.filter(k => k !== key);
        }
        
        this.updateAssignmentSelection();
    }
    
    updateAssignmentSelection() {
        this.courseAssignments = this.courseAssignments.map(option => ({
            ...option,
            isSelected: this.selectedAssignments.includes(option.assignmentKey)
        }));
    }
    
    handleSelectAllAssignments(event) {
        const isChecked = event.target.checked;
        
        if (isChecked) {
            this.selectedAssignments = this.courseAssignments.map(option => option.assignmentKey);
        } else {
            this.selectedAssignments = [];
        }
        
        this.updateAssignmentSelection();
    }
    
    handleCourseActivityChange(event) {
        this.selectedCourseActivity = event.detail.value;
    }

    handleJointSessionChange(event) {
        const wasJointSession = this.isJointSession;
        this.isJointSession = event.target.checked;
        
        if (this.isJointSession && !wasJointSession) {
            if (this.selectedFacultyValue && typeof this.selectedFacultyValue === 'string') {
                this.selectedFacultyValue = [this.selectedFacultyValue];
            } else if (!Array.isArray(this.selectedFacultyValue)) {
                this.selectedFacultyValue = [];
            }
        } else if (!this.isJointSession && wasJointSession) {
            if (Array.isArray(this.selectedFacultyValue) && this.selectedFacultyValue.length > 0) {
                this.selectedFacultyValue = this.selectedFacultyValue[0];
            } else {
                this.selectedFacultyValue = '';
            }
        }
        
        if (this.selectedCourse && this.facultyOptions.length === 0) {
            this.loadFacultyForCourse();
        }
    }

    handleFacultyChange(event) {
        this.selectedFacultyValue = event.detail.value;
    }
    
    loadFacultyForCourse() {
        if (!this.selectedCourse) {
            this.facultyOptions = [];
            return;
        }

        console.log('Loading faculty for course:', this.selectedCourse);
        getFacultyForCourse({ courseId: this.selectedCourse })
            .then(result => {
                this.facultyOptions = Array.isArray(result) ? result : [];
                console.log('Faculty loaded:', this.facultyOptions.length, 'options');
            })
            .catch(error => {
                console.error('Error loading faculty:', error);
                this.showToastMessage('Error loading faculty: ' + this.getErrorMessage(error), 'error');
                this.facultyOptions = [];
            });
    }
    
    loadExistingSessionDivisions(sessionId) {
        if (!sessionId) {
            this.existingSessionDivisions = [];
            return;
        }
        
        getSessionDivisions({ sessionId: sessionId })
            .then(result => {
                this.existingSessionDivisions = Array.isArray(result) ? result : [];
            })
            .catch(error => {
                console.error('Error loading existing session divisions:', error);
                this.existingSessionDivisions = [];
            });
    }

    loadExistingSessionFaculties(sessionId) {
        if (!sessionId) {
            this.selectedFacultyValue = this.isJointSession ? [] : '';
            return Promise.resolve(); // Return resolved promise so .then() can still be called
        }
        
        return getSessionFaculties({ sessionId: sessionId })
            .then(result => {
                const facultyIds = Array.isArray(result) ? result : [];
                if (this.isJointSession) {
                    this.selectedFacultyValue = facultyIds;
                } else {
                    this.selectedFacultyValue = facultyIds.length > 0 ? facultyIds[0] : '';
                }
            })
            .catch(error => {
                console.error('Error loading existing session faculties:', error);
                this.selectedFacultyValue = this.isJointSession ? [] : '';
            });
    }
    
    loadCourseActivities() {
        getCourseActivities()
            .then(result => {
                this.courseActivityOptions = Array.isArray(result) ? result : [];
            })
            .catch(error => {
                this.showToastMessage(this.getErrorMessage(error), 'error');
            });
    }
    
    ensureDivisionSelected() {
        // For creating new sessions, we need at least one division selected
        // But we can also allow creating if we have divisions loaded (user can select in modal)
        if (!this.selectedDivision && (!this.allDivisions || this.allDivisions.length === 0)) {
            this.showToastMessage('Please select a term and division before scheduling sessions', 'error');
            return false;
        }
        return true;
    }
    
    buildSessionPayload(sourceEvent = {}) {
        const divisionId = sourceEvent.divisionId || this.selectedDivision;
        const divisionIds = sourceEvent.divisionIds || null;
        const sessionDate = sourceEvent.date instanceof Date
            ? this.formatDateLocal(sourceEvent.date)
            : sourceEvent.date;
        
        if (!divisionId && (!divisionIds || divisionIds.length === 0)) {
            throw new Error('Please select at least one division before saving a session.');
        }
        if (!sourceEvent.title) {
            throw new Error('Session title is required.');
        }
        if (!sessionDate) {
            throw new Error('Session date is required.');
        }
        if (!sourceEvent.startTime || !sourceEvent.endTime) {
            throw new Error('Start time and end time are required.');
        }

        // Use faculty IDs from sourceEvent if provided (for bulk scheduler), otherwise use selectedFacultyValue
        const facultyIds = sourceEvent.selectedFacultyIds || this.normalizeFacultyIds(this.selectedFacultyValue);

        const payload = {
            sessionId: sourceEvent.id || null,
            sessionName: sourceEvent.title,
            divisionId: divisionId,
            divisionIds: divisionIds,
            batchWiseCourseId: sourceEvent.batchWiseCourseId || null,
            courseId: sourceEvent.courseId || this.selectedCourse || null,
            sessionDate: sessionDate,
            startTime: this.combineDateAndTime(sessionDate, sourceEvent.startTime),
            endTime: this.combineDateAndTime(sessionDate, sourceEvent.endTime),
            numberOfSessions: sourceEvent.numberOfSessions || 1,
            description: sourceEvent.description || '',
            courseActivity: sourceEvent.courseActivity || null,
            color: sourceEvent.color || 'blue',
            isJointSession: facultyIds.length > 1,
            selectedFacultyIds: facultyIds
        };
        return payload;
    }
    
    normalizeFacultyIds(facultyValue) {
        const valueToNormalize = facultyValue !== undefined ? facultyValue : this.selectedFacultyValue;
        if (Array.isArray(valueToNormalize)) {
            return valueToNormalize.filter(id => id && id.trim() !== '');
        } else if (valueToNormalize && typeof valueToNormalize === 'string' && valueToNormalize.trim() !== '') {
            return [valueToNormalize];
        }
        return [];
    }

    combineDateAndTime(dateStr, timeStr) {
        if (!dateStr || !timeStr) {
            return null;
        }
        const normalizedTime = timeStr.length === 5 ? `${timeStr}:00` : timeStr;
        const combined = new Date(`${dateStr}T${normalizedTime}`);
        if (Number.isNaN(combined.getTime())) {
            throw new Error('Invalid date or time provided.');
        }
        return combined.toISOString();
    }
    
    handleSaveAllSessions() {
        // Validate required fields
        if (!this.eventTitle || !this.selectedCourse) {
            this.showToastMessage('Please fill in Session Title and select a Course', 'error');
            return;
        }

        if (!this.sessionRows || this.sessionRows.length === 0) {
            this.showToastMessage('Please add at least one session', 'error');
            return;
        }

        // Validate all session rows
        for (let i = 0; i < this.sessionRows.length; i++) {
            const session = this.sessionRows[i];
            if (!session.divisionId) {
                this.showToastMessage(`Session ${i + 1}: Please select a division`, 'error');
                return;
            }
            if (!session.date) {
                this.showToastMessage(`Session ${i + 1}: Please select a date`, 'error');
                return;
            }
            if (!session.time) {
                this.showToastMessage(`Session ${i + 1}: Please select a time`, 'error');
                return;
            }
            if (!session.duration || session.duration < 15) {
                this.showToastMessage(`Session ${i + 1}: Please enter a valid duration (minimum 15 minutes)`, 'error');
                return;
            }
        }

        // Calculate end time for each session based on start time and duration
        // For each session row, check if it has selected assignments
        // If yes, create one session per selected assignment
        // If no, create a single session with the division from the row
        const sessionPromises = [];
        
        this.sessionRows.forEach((session, sessionIndex) => {
            const startTime = session.time;
            const [hours, minutes] = startTime.split(':').map(Number);
            const startMinutes = hours * 60 + minutes;
            const endMinutes = startMinutes + session.duration;
            const endHours = Math.floor(endMinutes / 60);
            const endMins = endMinutes % 60;
            const endTime = `${endHours.toString().padStart(2, '0')}:${endMins.toString().padStart(2, '0')}`;

            const selectedAssignments = this.sessionSelectedAssignments[sessionIndex] || [];
            const courseAssignments = this.sessionCourseAssignments[sessionIndex] || [];
            
            if (selectedAssignments.length > 0 && courseAssignments.length > 0) {
                // Create one session per selected assignment
                const selectedOptions = courseAssignments.filter(option => 
                    selectedAssignments.includes(option.assignmentKey)
                );
                
                selectedOptions.forEach(option => {
                    const payloadSource = {
                        id: session.sessionId || null,
                        title: this.eventTitle,
                        date: session.date,
                        startTime: startTime,
                        endTime: endTime,
                        description: '',
                        divisionId: option.divisionId || session.divisionId,
                        courseId: this.selectedCourse,
                        batchWiseCourseId: null,
                        numberOfSessions: 1,
                        color: session.color || 'blue',
                        courseActivity: this.selectedCourseActivity || null,
                        selectedFacultyIds: session.facultyId ? (Array.isArray(session.facultyId) ? session.facultyId : [session.facultyId]) : []
                    };

                    let sessionPayload;
                    try {
                        sessionPayload = this.buildSessionPayload(payloadSource);
                    } catch (error) {
                        throw new Error(`Error building payload for session: ${error.message}`);
                    }

                    sessionPromises.push(saveSession({ requestJson: JSON.stringify(sessionPayload) }));
                });
            } else {
                // Create single session with division from row
                const payloadSource = {
                    id: session.sessionId || null,
                    title: this.eventTitle,
                    date: session.date,
                    startTime: startTime,
                    endTime: endTime,
                    description: '',
                    divisionId: session.divisionId,
                    courseId: this.selectedCourse,
                    batchWiseCourseId: null,
                    numberOfSessions: 1,
                    color: session.color || 'blue',
                    courseActivity: this.selectedCourseActivity || null,
                    selectedFacultyIds: session.facultyId ? (Array.isArray(session.facultyId) ? session.facultyId : [session.facultyId]) : []
                };

                let sessionPayload;
                try {
                    sessionPayload = this.buildSessionPayload(payloadSource);
                } catch (error) {
                    throw new Error(`Error building payload for session: ${error.message}`);
                }

                sessionPromises.push(saveSession({ requestJson: JSON.stringify(sessionPayload) }));
            }
        });

        if (sessionPromises.length === 0) {
            this.showToastMessage('No sessions to save. Please add at least one session.', 'error');
            return;
        }

        console.log('Saving', sessionPromises.length, 'session(s)');
        this.isSaving = true;
        Promise.all(sessionPromises)
            .then(() => {
                // Check if we were editing or creating
                const isEdit = this.isEditMode && this.sessionRows.some(s => s.sessionId);
                const action = isEdit ? 'updated' : 'created';
                const totalSessionsCreated = sessionPromises.length;
                const successMessage = `Successfully ${action} ${totalSessionsCreated} session(s)`;
                console.log('Sessions saved successfully:', successMessage);
                this.showToastMessage(successMessage, 'success');
                this.handleCloseModal();
                
                // Force refresh sessions - ensure date range is updated first
                this.updateDateRange();
                
                // Use a small delay to ensure dateFrom/dateTo are set
                setTimeout(() => {
                    // If "All Divisions" is selected, reload all divisions
                    if (!this.selectedDivision && this.allDivisions.length > 0) {
                        this.loadSessionsForAllDivisions();
                    } else {
                        // Refresh wired result for specific division
                        if (this.wiredSessionsResult) {
                            refreshApex(this.wiredSessionsResult).then(() => {
                                this.isLoading = false;
                            });
                        }
                    }
                }, 100); // Small delay to ensure state is updated
            })
            .catch(error => {
                console.error('Error saving sessions:', error);
                const errorMessage = this.getErrorMessage(error);
                console.error('Error details:', errorMessage);
                this.showToastMessage('Error saving sessions: ' + errorMessage, 'error');
            })
            .finally(() => {
                this.isSaving = false;
            });
    }
    
    handleSaveEvent() {
        // Legacy method - now redirects to bulk save
        this.handleSaveAllSessions();
    }
    
    createSessionWithMultipleDivisions(basePayload) {
        if (!this.selectedAssignments || this.selectedAssignments.length === 0) {
            this.showToastMessage('Please select at least one assignment', 'error');
            return;
        }
        
        const selectedOptions = this.courseAssignments.filter(option => 
            this.selectedAssignments.includes(option.assignmentKey)
        );
        
        if (selectedOptions.length === 0) {
            this.showToastMessage('Please select at least one assignment', 'error');
            return;
        }
        
        const divisionIds = new Set();
        
        if (this.selectedDivision) {
            divisionIds.add(this.selectedDivision);
        }
        
        for (const option of selectedOptions) {
            if (option.divisionId) {
                divisionIds.add(option.divisionId);
            }
        }
        
        const divisionIdsArray = Array.from(divisionIds);
        
        if (divisionIdsArray.length === 0) {
            this.showToastMessage('No valid divisions found', 'error');
            return;
        }
        
        const payload = {
            ...basePayload,
            divisionIds: divisionIdsArray,
            courseId: this.selectedCourse
        };
        
        let sessionPayload;
        try {
            sessionPayload = this.buildSessionPayload(payload);
        } catch (error) {
            this.showToastMessage(error.message, 'error');
            return;
        }
        
        this.isSaving = true;
        saveSession({ requestJson: JSON.stringify(sessionPayload) })
            .then(() => {
                const successMessage = this.isEditMode 
                    ? `Session updated successfully with ${divisionIdsArray.length} division(s)` 
                    : `Session created successfully with ${divisionIdsArray.length} division(s)`;
                this.showToastMessage(successMessage, 'success');
                this.handleCloseModal();
                if (this.wiredSessionsResult) {
                    return refreshApex(this.wiredSessionsResult);
                }
            })
            .catch(error => {
                this.showToastMessage(this.getErrorMessage(error), 'error');
            })
            .finally(() => {
                this.isSaving = false;
            });
    }

    handleDeleteEvent() {
        if (!this.selectedEventId) {
            return;
        }

        const eventToDelete = this.events.find(e => e.id === this.selectedEventId);
        this.isLoading = true;
        deleteSession({ sessionId: this.selectedEventId })
            .then(() => {
                const eventName = eventToDelete ? eventToDelete.title : 'Session';
                this.showToastMessage(`"${eventName}" deleted`, 'success');
                this.handleCloseModal();
                if (this.wiredSessionsResult) {
                    return refreshApex(this.wiredSessionsResult);
                }
            })
            .catch(error => {
                this.showToastMessage(this.getErrorMessage(error), 'error');
            })
            .finally(() => {
                this.isLoading = false;
            });
    }
    
    getErrorMessage(error) {
        if (!error) {
            return 'Something went wrong';
        }
        if (Array.isArray(error.body)) {
            return error.body.map(e => e.message).join(', ');
        }
        if (error.body && error.body.message) {
            return error.body.message;
        }
        return error.message || 'Something went wrong';
    }
    
    showToastMessage(message, type = 'success') {
        this.toastMessage = message;
        this.toastType = type;
        this.showToast = true;
        
        setTimeout(() => {
            this.showToast = false;
        }, 3000);
    }

    handleCloseToast() {
        this.showToast = false;
    }
}