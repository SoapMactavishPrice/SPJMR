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
import cancelSession from '@salesforce/apex/TimetableSessionController.cancelSession';
import publishSessions from '@salesforce/apex/TimetableSessionController.publishSessions';
import getCourseActivities from '@salesforce/apex/TimetableSessionController.getCourseActivities';
import getSessionTypes from '@salesforce/apex/TimetableSessionController.getSessionTypes';
import getFacultyForCourse from '@salesforce/apex/TimetableSessionController.getFacultyForCourse';
import getFacultiesForFilter from '@salesforce/apex/TimetableSessionController.getFacultiesForFilter';
import getSessionFaculties from '@salesforce/apex/TimetableSessionController.getSessionFaculties';
import getFacultyConflictsForSessions from '@salesforce/apex/TimetableSessionController.getFacultyConflictsForSessions';
import getDivisionSessionConflictsForSessions from '@salesforce/apex/TimetableSessionController.getDivisionSessionConflictsForSessions';
import getFacultyCalendarConflictsForSessions from '@salesforce/apex/TimetableSessionController.getFacultyCalendarConflictsForSessions';
import getSessionDivisions from '@salesforce/apex/TimetableWizardController.getSessionDivisions';
import getEligibleMakeupStudents from '@salesforce/apex/TimetableSessionController.getEligibleMakeupStudents';
import refreshAttendees from '@salesforce/apex/TimetableSessionController.refreshAttendees';


export default class TimetableCalendar extends LightningElement {
    static ALL_DIVISIONS_VALUE = 'ALL';
    static MONTH_VIEW_VISIBLE_EVENT_LIMIT = 3;
    // Global calendar hours (applies to grids + time picklists)

    static DAY_START_HOUR = 0;  // 12 AM
    static DAY_END_HOUR = 23;   // 11.59 PM
    static SESSION_TITLE_MAX_LENGTH = 60;

    /** Maps Division_Color__c picklist API text (normalized key) to #RRGGBB — keep in sync with TimetableSessionController.divisionColorHexByKey and Session__c.Color__c */
    static DIVISION_COLOR_HEX = {
        softpeachbeige: '#FAE3D6',
        lightsagegreen: '#9EB094',
        mutedbrown: '#B58460',
        brickred: '#B44E4E',
        mustardyellow: '#C99500',
        teal: '#54B1AC',
        paleolive: '#B2B28D',
        steelblue: '#406EA8',
        lightgray: '#AAAFAA',
        limeyellow: '#C0C600',
        darkmaroon: '#7A3000',
        purple: '#702B99',
        blue: '#406EA8',
        gray: '#AAAFAA',
        grey: '#AAAFAA',
        green: '#9EB094',
        orange: '#C99500',
        red: '#B44E4E'
    };

    static normalizeDivisionColorKey(picklistValue) {
        if (picklistValue == null || picklistValue === '') return '';
        return String(picklistValue).toLowerCase().replace(/[^a-z0-9]/g, '');
    }

    static divisionPicklistToHex(picklistValue) {
        const k = TimetableCalendar.normalizeDivisionColorKey(picklistValue);
        return k ? (TimetableCalendar.DIVISION_COLOR_HEX[k] || null) : null;
    }

    static legacyTokenToHex(token) {
        if (!token || typeof token !== 'string') return null;
        const k = String(token).toLowerCase().trim();
        return TimetableCalendar.DIVISION_COLOR_HEX[k] || null;
    }

    /**
     * Calendar tile color.
     * Prefer Division Color for the session-division row; Session.Color__c is a fallback.
     * (Conflict-create previously wrote default steel blue #406EA8 even when Division was Brick Red —
     * preferring stored hex made those tiles look blue.)
     */
    static resolveEventDisplayHex(divisionColorPicklist, storedSessionColor) {
        const fromDiv = TimetableCalendar.divisionPicklistToHex(divisionColorPicklist);
        if (fromDiv) return fromDiv;
        const s = storedSessionColor != null ? String(storedSessionColor).trim() : '';
        if (s && /^#[0-9A-Fa-f]{6}$/i.test(s)) return s.toUpperCase();
        const leg = TimetableCalendar.legacyTokenToHex(s);
        if (leg) return leg;
        return '#406EA8';
    }

    /** Relative luminance 0–1 for #RRGGBB (sRGB). */
    static hexLuminance(hex) {
        if (!hex || !/^#[0-9A-Fa-f]{6}$/i.test(hex)) return 0.5;
        const n = parseInt(hex.slice(1), 16);
        const channel = (c) => {
            const v = c / 255;
            return v <= 0.03928 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4);
        };
        const r = channel((n >> 16) & 255);
        const g = channel((n >> 8) & 255);
        const b = channel(n & 255);
        return 0.2126 * r + 0.7152 * g + 0.0722 * b;
    }

    /** White text is unreadable on Soft Peach / Light Gray / Lime Yellow tiles. */
    static eventTextColorForHex(hex) {
        return TimetableCalendar.hexLuminance(hex) > 0.55 ? '#1a1a1a' : '#ffffff';
    }

    static eventTintInlineStyle(hex) {
        if (!hex) return '';
        const fg = TimetableCalendar.eventTextColorForHex(hex);
        return `background-color: ${hex}; color: ${fg};`;
    }
    /** Day view: pixels per hour (row height). Larger value shows time/title/course on tiles without truncation. */
    static DAY_VIEW_HOUR_HEIGHT = 80;
    @api recordId;
    @api title = 'Timetable';
    
    @track currentDate = new Date();
    @track currentView = 'week';
    @track currentTime = new Date(); // separate tick for current-time indicator
    
    // Filter selections
    @track selectedProgram;
    @track selectedBatch;
    @track selectedBatchGroup;
    @track selectedTerm;
    @track selectedDivision;
    @track modalDivisionId = null; // For creating sessions from All Divisions grids
    @track sessionDuration = null; // Session duration in minutes from selected batch
    @track selectedFilterFacultyIds = []; // Left sidebar: multi-select faculty filter
    @track filterFacultyOptions = []; // Faculty options for sidebar filter (Division -> Course -> Faculty)
    @track filterFacultyComboboxValue = ''; // Sidebar faculty picklist value (cleared after add)
    @track filterScheduleTypeDraft = false;
    @track filterScheduleTypePublished = false;
    
    // Filter options
    @track programOptions = [];
    @track batchOptions = [];
    @track batchGroupOptions = [];
    @track termOptions = [];
    @track divisionOptions = [];
    @track showModal = false;
    @track isEditMode = false;
    @track selectedEventId = null;
    // RSVP read-back (Target 1): live attendee responses shown in the edit modal.
    @track attendeeSummary = null;
    @track attendeeLoading = false;
    @track attendeeMessage = '';
    /** Division of the tile the user clicked (All Divisions view); used so Existing Session Divisions excludes the correct division. */
    @track clickedTileDivisionId = null;
    @track isLoading = false;
    @track isSaving = false;
    
    // Drag and Drop state
    @track isDragging = false;
    /** When dragging/resizing, disambiguate Session__c rows that differ by Division__c only */
    @track draggedEventDivisionId = null;
    @track draggedEventId = null;
    @track draggedEventTitle = '';
    @track dropTargetDay = null;
    @track dropTargetHour = null;
    
    // Resize state
    @track isResizing = false;
    @track resizingEventId = null;
    
    // Toast notification
    @track showToast = false;
    @track toastMessage = '';
    @track toastType = 'success';

    // Session hover tooltip (custom dark card)
    @track hoveredEventTooltip = null;
    @track tooltipPosition = { x: 0, y: 0 };
    @track showMonthMoreEventsModal = false;
    @track monthMoreEventsDate = '';
    @track monthMoreEventsList = [];

    /** Publish flow: date range modal + server call */
    @track showPublishModal = false;
    @track publishFromDate = '';
    @track publishToDate = '';
    @track isPublishingSessions = false;

    @track showFacultyNotifyModal = false;
    @track isPublishNotifyPrompt = false;
    @track isRepublishNotifyPrompt = false;
    facultyNotifyResolve = null;

    /** True while a Save/Republish from the edit modal is already running (double-click guard). */
    saveEventInFlight = false;

    // Event form fields
    @track eventTitle = '';
    @track eventDate = '';
    @track eventStartTime = '09:00';
    @track eventEndTime = '10:00';
    @track eventLocation = '';
    @track eventDescription = '';
    @track eventClassRoom = '';
    @track eventRemark = '';
    @track eventUrl = '';
    @track selectedCourse = '';
    @track selectedCourseActivity = '';
    @track courseOptions = [];
    @track courseActivityOptions = [];
    @track sessionTypeOptions = [];
    @track selectedSessionType = '';
    @track selectedCourseDepartmentName = '';
    @track courseAssignments = [];
    @track selectedAssignments = []; // Array of selected assignment keys
    @track showCourseAssignments = false;
    @track existingSessionDivisions = []; // Existing divisions for edit mode (read-only)
    @track editAddCourseAssignments = []; // Programs/divisions using this course (edit modal, add to division)
    @track editAddSelectedKeys = []; // Selected assignment keys to add session to (edit modal)
    @track isJointSession = false;
    @track selectedFacultyValue = ''; // Internal value - string for single, array for multi
    @track facultyOptions = [];
    @track editFacultyComboboxValue = ''; // Reset after adding faculty in edit modal
    /** When Joint Session: multiple faculty IDs for the Faculty (lead) role; first is sent as leadFacultyId to backend */
    @track editLeadFacultyIds = [];
    /** Faculty id->name from server when opening edit modal (session faculty from getSessions); used so pills show names even if faculty was removed from Instructor__c for that program course */
    @track editModalFacultyNameList = [];
    
    // Create Sessions (multi-session) modal state
    @track createSessionsList = [];
    @track activeCreateSessionIndex = 0;
    /** Set true when user clicks Create Sessions; inline validation errors only show after that. */
    @track createSessionsSaveAttempted = false;
    @track facultyConflicts = [];
    @track calendarConflicts = []; // Google Calendar conflicts
    @track sessionConflicts = [];
    @track showConflictsModal = false;
    /** When true, skip conflict precheck modal and pass ignoreConflicts to Apex. */
    @track pendingConflictOverride = false;
    /** Which save path to re-run after Submit-anyway: 'create' | 'edit' | 'persist'. */
    conflictOverrideSaveMode = null;
    /** The drag/drop or resize record to re-save on Submit-anyway ('persist' mode only). */
    pendingOverrideEvent = null;
    @track studentConflicts = [];
    @track showStudentConflictsModal = false;
    @track modalProgram = '';
    @track modalBatch = '';
    @track modalTerm = '';
    @track modalCourse = '';
    @track modalBatchOptions = [];
    @track modalTermOptions = [];
    @track modalCourseOptions = [];
    @track eligibleStudentOptions = [];
    @track selectedStudentIds = [];
    @track studentNames = [];
    studentDivisionMap = {};
    @track editEnrolledStudentOptions = [];
    @track editEnrolledSelectedIds = [];
    editStudentDivisionMap = {};

    
    
    // Getter to show course assignments only when not in edit mode
    get showCourseAssignmentsAndNotEdit() {
        return this.showCourseAssignments && !this.isEditMode;
    }
    
    // Getter to show existing divisions in edit mode (show when there are any; table may show filtered list)
    get showExistingDivisions() {
        return this.isEditMode && (this.existingSessionDivisions || []).length > 0;
    }

    // Allow drag/drop only when viewing All Divisions; disable it for single-division view
    get canDragEvents() {
        return this.isAllDivisionsSelected;
    }

    // True when the session being edited is already published, so saving it republishes it.
    // Drives both the button label and which copy the notification prompt shows, because a
    // republish notifies a different audience than a create or a draft edit.
    get isRepublishSave() {
        if (!this.isEditMode || !this.selectedEventId) return false;
        const editingEvent = this.findEventRowForSession(this.selectedEventId, this.clickedTileDivisionId);
        const scheduleType = editingEvent && editingEvent.scheduleType ? String(editingEvent.scheduleType).toLowerCase() : '';
        return scheduleType === 'published' || scheduleType === 'republished';
    }

    get saveSessionButtonLabel() {
        return this.isRepublishSave ? 'Republish Session' : 'Save Session';
    }

    // Division context of the session we're editing (the division of the tile user clicked, so we exclude it from "Existing Session Divisions")
    get currentEditDivisionId() {
        if (!this.isEditMode || !this.selectedEventId) return null;
        // Prefer the division of the tile actually clicked (All Divisions view); otherwise fall back to first matching event
        if (this.clickedTileDivisionId) return this.clickedTileDivisionId;
        if (!this.events || !this.events.length) return null;
        const editingEvent = this.findEventRowForSession(this.selectedEventId, this.clickedTileDivisionId);
        return (editingEvent && editingEvent.divisionId) ? editingEvent.divisionId : null;
    }

    // Existing session divisions excluding the current view division (the one user clicked to view)
    get filteredExistingSessionDivisions() {
        const list = this.existingSessionDivisions || [];
        const currentId = this.currentEditDivisionId;
        if (!currentId) return list;
        return list.filter(d => {
            const divId = (d && d.divisionId) ? String(d.divisionId).trim() : '';
            return !this.idsEqual(divId, currentId);
        });
    }

    get hasFilteredExistingDivisionsRows() {
        const list = this.filteredExistingSessionDivisions || [];
        return list.length > 0;
    }

    get showEditAddDivisionsSection() {
        return this.isEditMode && this.selectedBatchAllowsMultiProgram && !this.isEditSessionReadOnly;
    }

    get hasEditAddDivisionsRows() {
        const list = this.editAddCourseAssignmentsFiltered || [];
        return list.length > 0;
    }

    get editAddCourseAssignmentsFiltered() {
        const list = this.editAddCourseAssignments || [];
        const currentId = this.currentEditDivisionId;
        const existingDivisions = this.existingSessionDivisions || [];
        const sessionDate = this.normalizeDateString(this.eventDate);
        const filtered = list.filter(a => {
            if (this.isAssignmentCurrentContext(a)) return false;
            if (!this.isAssignmentValidForSessionDate(a, sessionDate)) return false;
            const divId = this.getAssignmentDivisionId(a);
            const alreadyInSession = existingDivisions.some(d => this.idsEqual(d.divisionId, divId));
            if (alreadyInSession) return false;
            if (currentId && this.idsEqual(divId, currentId)) return false;
            return true;
        });
        const selectedKeys = (this.editAddSelectedKeys || []).map(k => String(k).trim()).filter(Boolean);
        return filtered.map(a => {
            const key = (a.assignmentKey != null ? String(a.assignmentKey).trim() : '') || '';
            return {
                ...a,
                isSelected: key && selectedKeys.includes(key),
                rowClass: key && selectedKeys.includes(key) ? 'program-row selected' : 'program-row'
            };
        });
    }
    
    // Create Sessions modal: show new multi-session UX when adding (not editing)
    get isCreateSessionsMode() {
        return this.showModal && !this.isEditMode;
    }
    
    // Modal top picklist options (include "All" when applicable)
    get modalProgramOptionsWithAll() {
        const all = [{ label: 'All Programs', value: '' }];
        return [...all, ...(this.programOptions || [])];
    }
    
    get modalBatchOptionsWithAll() {
        const all = [{ label: 'All Batches', value: '' }];
        const opts = (this.modalBatchOptions && this.modalBatchOptions.length) ? this.modalBatchOptions : this.batchOptions;
        return [...all, ...(opts || [])];
    }
    
    get modalTermOptionsWithAll() {
        const all = [{ label: 'All Terms', value: '' }];
        const opts = (this.modalTermOptions && this.modalTermOptions.length) ? this.modalTermOptions : this.termOptions;
        return [...all, ...(opts || [])];
    }
    
    /** Inline validation errors for one session (shown below each field). Faculty error only shown after user clicks Create Sessions. */
    getErrorsForSessionAtIndex(index) {
        const list = this.createSessionsList || [];
        const s = list[index];
        if (!s) return { urlError: null, startTimeError: null, endTimeError: null, orderError: null, facultyError: null, classRoomError: null, remarkError: null };
        const urlError = null;
        const startStr = s.startTime ? String(s.startTime).trim() : '';
        const endStr = s.endTime ? String(s.endTime).trim() : '';
        let startTimeError = null;
        let endTimeError = null;
        let orderError = null;
    /* --- COMMENTED OUT: 9AM/10PM time-of-day restriction (no longer required)SE-1015 ---    
        if (startStr) {
            if (this.isTimeBefore9AM(s.startTime)) {
                startTimeError = 'Start time must be 9:00 AM or later.';
            } else if (this.isTimeBeyond10PM(s.startTime)) {
              startTimeError = 'Start time must be 10:00 PM or earlier.';
            }
        }
       if (endStr) {
             if (this.isTimeBefore9AM(s.endTime)) {
              endTimeError = 'End time must be 9:00 AM or later.';
         } else if (this.isTimeBeyond10PM(s.endTime)) {
               //endTimeError = 'End time must be 10:00 PM or earlier.';
        }
    }   
      --- END COMMENTED OUT --- */
  
        if (startStr && endStr && this.parseTimeToMinutes(endStr) <= this.parseTimeToMinutes(startStr)) orderError = 'End time must be after start time.';
        const classRoomError = this.isNegativeFieldValue(s.classRoom) ? "Negative values and values starting with '-' are not allowed." : null;
        const remarkError = this.isNegativeFieldValue(s.remark) ? "Negative values and values starting with '-' are not allowed." : null;
        let facultyError = null;
        if (this.createSessionsSaveAttempted) {
            const hasFaculty = (s.facultyIds || []).length > 0;
            const hasLead = this.sessionHasLeadFaculty(s);
            if (!hasFaculty) {
                facultyError = 'Faculty is required.';
            } else if (!hasLead) {
                facultyError = 'At least one Faculty (lead) is required. Support faculty alone is not enough.';
            }
        }
        return { urlError, startTimeError, endTimeError, orderError, facultyError, classRoomError, remarkError };
    }

    get createSessionsWithIndex() {
        return (this.createSessionsList || []).map((session, index) => {
            const mergedCount = (session.selectedAssignmentKeys || []).length;
            const facultyIds = session.facultyIds || [];
            const isJoint = this.isCourseActivityJointSession(session.courseActivity);
            // Faculty (lead): single when not Joint, multiple when Joint
            const leadFacultyIds = (session.leadFacultyIds && session.leadFacultyIds.length > 0)
                ? session.leadFacultyIds
                : (session.leadFacultyId ? [session.leadFacultyId] : []);
            const leadId = leadFacultyIds.length > 0 ? leadFacultyIds[0] : '';
            // Support: all facultyIds not in leadFacultyIds
            const supportIds = (session.facultyIds || []).filter(id =>
                !leadFacultyIds.some(lid => this.idsEqual(lid, id))
            );
            const facultyCount = facultyIds.length;
            const durationLabel = this.getSessionDurationLabel(session.startTime, session.endTime);
            const leadFacultyPills = leadFacultyIds.map(id => ({
                value: id,
                label: this.getFacultyLabelById(id, this.facultyOptions) || id
            }));
            const supportFacultyPills = supportIds.map(id => ({
                value: id,
                label: this.getFacultyLabelById(id, this.facultyOptions) || id
            }));
            const availableSupportFaculty = (this.facultyOptions || []).filter(f =>
                f.value && !facultyIds.some(fid => this.idsEqual(f.value, fid))
            );
            const allFacultyOptions = (this.facultyOptions || []).slice();
            // Exclude already-selected faculty from dropdowns (remove pill to make them appear again)
            const leadFacultyOptions = allFacultyOptions.filter(f =>
                f.value && !leadFacultyIds.some(lid => this.idsEqual(f.value, lid))
            );
            return {
                ...session,
                index,
                displayNumber: index + 1,
                isSelected: this.activeCreateSessionIndex === index,
                cardClass: this.activeCreateSessionIndex === index ? 'session-card selected' : 'session-card',
                mergedCount,
                facultyCount,
                durationLabel,
                isJointSession: isJoint,
                leadFacultyId: leadId,
                leadFacultyIds,
                facultyPills: [...leadFacultyPills, ...supportFacultyPills],
                leadFacultyPills,
                supportFacultyPills,
                leadFacultyOptions,
                availableFacultyOptions: availableSupportFaculty,
                facultyComboboxValueDisplay: '',
                facultyPlaceholder: isJoint ? 'Select Faculty (Multiple)' : 'Select Faculty',
                fieldErrors: this.getErrorsForSessionAtIndex(index)
            };
        });
    }
    
    getSessionDurationLabel(startTime, endTime) {
        if (!startTime || !endTime) return '0h';
        const [sh, sm] = (startTime || '0:0').split(':').map(n => parseInt(n, 10) || 0);
        const [eh, em] = (endTime || '0:0').split(':').map(n => parseInt(n, 10) || 0);
        const startM = sh * 60 + sm;
        const endM = eh * 60 + em;
        const durationM = Math.max(0, endM - startM);
        const h = Math.floor(durationM / 60);
        const m = durationM % 60;
        if (m === 0) return h + 'h';
        if (h === 0) return m + 'm';
        return h + 'h ' + m + 'm';
    }
    
    get createSessionProgramsForMerge() {
        if (!this.courseAssignments || this.courseAssignments.length === 0) return [];
        const activeSession = this.createSessionsList[this.activeCreateSessionIndex];
        const sessionDate = this.normalizeDateString(activeSession ? activeSession.date : null);
        const selectedKeys = (activeSession ? (activeSession.selectedAssignmentKeys || []) : [])
            .map(k => k != null ? String(k).trim() : '')
            .filter(Boolean);
        // Exclude the row that matches the current top filters (program, batch, batch group, term, division)
        const filtered = this.courseAssignments.filter(
            (a) => !this.isAssignmentCurrentContext(a) && this.isAssignmentValidForSessionDate(a, sessionDate)
        );
        return filtered.map(a => {
            const key = a.assignmentKey != null ? String(a.assignmentKey).trim() : '';
            const isSelected = key && selectedKeys.includes(key);
            return {
                ...a,
                isSelected,
                rowClass: isSelected ? 'program-row selected' : 'program-row'
            };
        });
    }

    // Returns true if the assignment matches the currently selected program/batch/batch group/term/division (should be excluded from merge list)
    isAssignmentCurrentContext(assignment) {
        if (!assignment) return false;
        // Need at least division to be selected (single-division context)
        if (!this.selectedDivision || this.selectedDivision === TimetableCalendar.ALL_DIVISIONS_VALUE) return false;
        const divId = this.getAssignmentDivisionId(assignment);
        const idMatch = this.idsEqual(assignment.programId, this.selectedProgram) &&
            this.idsEqual(assignment.batchId, this.selectedBatch) &&
            this.idsEqual(assignment.batchGroupId, this.selectedBatchGroup) &&
            this.idsEqual(assignment.termId, this.selectedTerm) &&
            this.idsEqual(divId, this.selectedDivision);
        if (idMatch) return true;
        // Fallback: match by names (handles ID format/caching differences)
        const sameProgram = this.strEqual(assignment.programName, this.selectedProgramLabel);
        const sameBatch = this.strEqual(assignment.batchName, this.selectedBatchLabel);
        const sameBatchGroup = this.strEqual(assignment.batchGroupName, this.selectedBatchGroupLabel);
        const sameTerm = this.strEqual(assignment.termName, this.selectedTermLabel);
        const sameDivision = this.strEqual(assignment.divisionName, this.selectedDivisionLabel);
        return sameProgram && sameBatch && sameBatchGroup && sameTerm && sameDivision;
    }

    strEqual(a, b) {
        const sa = (a != null && a !== '') ? String(a).trim() : '';
        const sb = (b != null && b !== '') ? String(b).trim() : '';
        return sa === sb;
    }

    idsEqual(a, b) {
        const sa = (a != null && a !== '') ? String(a).trim() : '';
        const sb = (b != null && b !== '') ? String(b).trim() : '';
        if (sa === sb) return true;
        const ea = this.extractSalesforceId(sa);
        const eb = this.extractSalesforceId(sb);
        if (ea && eb) return ea.substring(0, 15) === eb.substring(0, 15);
        return false;
    }

    /** Resolve faculty display label by id; uses idsEqual so 15-char and 18-char Ids match. */
    getFacultyLabelById(id, options) {
        if (!id) return '';
        const opts = options || this.facultyOptions || [];
        const opt = opts.find(f => f.value && this.idsEqual(f.value, id));
        return (opt && opt.label) ? opt.label : '';
    }

    get allCreateSessionProgramsSelected() {
        const activeSession = this.createSessionsList[this.activeCreateSessionIndex];
        if (!activeSession || !this.courseAssignments || this.courseAssignments.length === 0) return false;
        const sessionDate = this.normalizeDateString(activeSession.date);
        const filtered = this.courseAssignments.filter(
            (a) => !this.isAssignmentCurrentContext(a) && this.isAssignmentValidForSessionDate(a, sessionDate)
        );
        if (filtered.length === 0) return false;
        const selected = activeSession.selectedAssignmentKeys || [];
        return selected.length === filtered.length;
    }

    /**
     * Assignment row is visible only when selected session date lies within term bounds.
     * If term bounds are missing, keep backward-compatible behavior and allow the row.
     */
    isAssignmentValidForSessionDate(assignment, sessionDate) {
        const d = this.normalizeDateString(sessionDate);
        if (!assignment || !d) return true;
        const start = this.normalizeDateString(assignment.termStartDate);
        const end = this.normalizeDateString(assignment.termEndDate);
        if (!start || !end) return true;
        return d >= start && d <= end;
    }
    
    get totalCreateSessionsCount() {
        return (this.createSessionsList || []).length;
    }

    /** True when there is more than one session, so delete is allowed (hide trash when only one session). */
    get showCreateSessionDeleteButton() {
        return (this.createSessionsList || []).length > 1;
    }
    
    get totalCreateSessionProgramsMerged() {
        return (this.createSessionsList || []).reduce((sum, s) => sum + (s.selectedAssignmentKeys || []).length, 0);
    }

    /** Total number of faculty members in conflict (not number of conflicting-session rows). */
    get facultyConflictsCount() {
        const list = this.facultyConflicts || [];
        let total = 0;
        for (const c of list) {
            const names = c.facultyNames;
            if (Array.isArray(names)) {
                total += names.length;
            }
        }
        return total;
    }

    get hasFacultyConflicts() {
        return this.facultyConflictsCount > 0;
    }

    get hasFacultyConflictsDisabled() {
        return !this.hasAnyBlockingConflicts;
    }

    get hasFacultySessionConflictsToShow() {
        return this.facultyConflictsWithDisplay.length > 0;
    }

    get hasSessionConflictsToShow() {
        return this.sessionConflictsWithDisplay.length > 0;
    }

    get hasAnyBlockingConflicts() {
        return this.hasFacultySessionConflictsToShow
            || this.hasSessionConflictsToShow
            || this.hasCalendarConflictsToShow;
    }

    /** Accordion sections open by default when they have data. */
    get conflictsAccordionActiveSections() {
        const open = [];
        if (this.hasCalendarConflictsToShow) open.push('gcal');
        if (this.hasFacultySessionConflictsToShow) open.push('faculty');
        if (this.hasSessionConflictsToShow) open.push('session');
        return open;
    }

    get facultyConflictsWithDisplay() {
        return (this.facultyConflicts || []).map((c, i) => {
            const parts = [
                c.conflictingCourseName,
                c.conflictingDivisionNames,
                c.conflictingProgramName,
                c.conflictingBatchName,
                c.conflictingBatchGroupName,
                c.conflictingTermName
            ].filter(Boolean);
            const proposedParts = [
                c.proposedCourseName,
                c.proposedDivisionNames,
                c.proposedProgramName,
                c.proposedBatchName,
                c.proposedBatchGroupName,
                c.proposedTermName
            ].filter(Boolean);
            return {
                ...c,
                facultyNamesStr: (c.facultyNames || []).join(', ') || '—',
                conflictingContextStr: parts.join(' · ') || '',
                hasConflictingContext: parts.length > 0,
                hasProposedContext: proposedParts.length > 0,
                conflictKey: `conflict-${i}-${c.proposedSessionName || ''}-${c.conflictingDateStr || ''}-${c.conflictingTimeStr || ''}`
            };
        });
    }

    /** True when there are Google Calendar conflicts to show as separate cards above the faculty cards. */
    get hasCalendarConflictsToShow() {
        return this.calendarConflictsWithDisplay.length > 0;
    }

    /**
     * Google Calendar conflicts, shaped for their own grey cards (shown above the faculty cards).
     * Skips events that map to a Salesforce session (isSalesforceSession) — that clash is already
     * shown in the Faculty session conflict card's "Conflicting session" column, so the Google
     * card would be a duplicate. Only genuine external/personal Google events get a card here.
     */
    get calendarConflictsWithDisplay() {
        return (this.calendarConflicts || [])
            .filter(g => g.isSalesforceSession !== true)
            .map((g, i) => ({
                key: `gcal-${i}-${g.conflictingEventId || g.conflictingSummary || ''}`,
                facultyName: g.facultyName || '—',
                proposedSessionName: g.proposedSessionName,
                proposedDateStr: g.proposedDateStr,
                proposedTimeStr: g.proposedTimeStr,
                conflictingSummary: g.conflictingSummary,
                conflictingTimeStr: g.conflictingTimeStr
            }));
    }

    get sessionConflictsWithDisplay() {
        return (this.sessionConflicts || []).map((c, i) => {
            const parts = [
                c.conflictingCourseName,
                c.conflictingProgramName,
                c.conflictingBatchName,
                c.conflictingBatchGroupName,
                c.conflictingTermName,
                c.conflictingDivisionNames
            ].filter(Boolean);
            const proposedParts = [
                c.proposedCourseName,
                c.proposedProgramName,
                c.proposedBatchName,
                c.proposedBatchGroupName,
                c.proposedTermName,
                c.proposedDivisionNames
            ].filter(Boolean);
            return {
                ...c,
                hasConflictingContext: parts.length > 0,
                hasProposedContext: proposedParts.length > 0,
                conflictKey: `session-conflict-${i}-${c.proposedSessionName || ''}-${c.conflictingDateStr || ''}-${c.conflictingTimeStr || ''}`
            };
        });
    }

    get studentConflictsWithDisplay() {
        return (this.studentConflicts || []).map((c, i) => ({
            ...c,
            studentNamesStr: Array.isArray(c.studentNames) ? c.studentNames.join(', ') : (c.studentNames || ''),
            conflictKey: `student-conflict-${i}-${c.proposedSessionName || ''}-${c.conflictingSessionName || ''}-${c.conflictingDateStr || ''}-${c.conflictingTimeStr || ''}`
        }));
    }

    get hasActiveCreateSession() {
        return this.activeCreateSessionIndex >= 0 && this.activeCreateSessionIndex < (this.createSessionsList || []).length;
    }
    
    get activeCreateSessionDisplayNumber() {
        return this.hasActiveCreateSession ? this.activeCreateSessionIndex + 1 : '';
    }
    
    get createSessionsModalClass() {
        const base = 'modal-content';
        return this.isCreateSessionsMode ? base + ' create-sessions-modal' : base;
    }
    
    // Recurring event fields
    @track isRecurring = false;
    @track recurringType = 'weekly';
    @track recurringInterval = 1;
    @track recurringEndDate = '';
    @track selectedWeekdays = [1]; // Default to Monday (0=Sun, 1=Mon, etc.)
    
    // Event data retrieved from Apex
    @track events = [];
    
    // Wired result for refreshApex
    wiredSessionsResult;

    // Bump this after saving a session so sessions wire re-runs and faculty filter reflects updates
    @track sessionsRefreshKey = 0;

    // Time slots configuration
    timeSlots = [];

    // Auto-scroll week/day grid so sessions don't appear "stuck at bottom"
    pendingAutoScroll = false;
    lastAutoScrollKey = '';
    
    // Reactive getter for session filter
    get sessionFilter() {
        const isAll = this.isAllDivisionsSelected;
        const divisionId = !isAll ? (this.selectedDivision || null) : null;
        const divisionIds = isAll ? this.allDivisionIds : null;
        const shouldFilterByDivision = !!divisionId || (divisionIds && divisionIds.length > 0);
        const { startDate, endDate } = shouldFilterByDivision
            ? this.getCurrentViewDateRange()
            : { startDate: null, endDate: null };
        const filterPayload = { divisionId, divisionIds, startDate, endDate };
        if (this.selectedFilterFacultyIds && this.selectedFilterFacultyIds.length > 0) {
            filterPayload.facultyIds = this.selectedFilterFacultyIds;
        }
        const scheduleTypes = [];
        if (this.filterScheduleTypeDraft) scheduleTypes.push('Draft');
        if (this.filterScheduleTypePublished) scheduleTypes.push('Published');
        filterPayload.scheduleTypes = scheduleTypes.length > 0 ? scheduleTypes : ['Draft', 'Published'];
        filterPayload._refresh = this.sessionsRefreshKey;
        return JSON.stringify(filterPayload);
    }
    
    connectedCallback() {
        this.initializeTimeSlots();
        this.startTimeIndicatorUpdate();
        this.generateRecurringEvents();
        this.loadPrograms();
        this.loadCourseActivities();
        this.loadSessionTypes();
    }

    renderedCallback() {
        if (!this.pendingAutoScroll) return;
        if (this.currentView === 'month') return;
        if (!this.selectedDivision) {
            this.pendingAutoScroll = false;
            return;
        }

        const key = this.getAutoScrollKey();
        if (key && key === this.lastAutoScrollKey) {
            this.pendingAutoScroll = false;
            return;
        }

        const gridContainer = this.template.querySelector('.time-grid-container');
        if (!gridContainer) return;

        const targetTop = this.getAutoScrollTop(gridContainer);
        if (Number.isFinite(targetTop)) {
            gridContainer.scrollTop = targetTop;
        }

        this.lastAutoScrollKey = key;
        this.pendingAutoScroll = false;
    }
    
    // Wire getSessions to automatically load sessions when filter changes
    @wire(getSessions, { filterJson: '$sessionFilter' })
    wiredSessions(result) {
        this.wiredSessionsResult = result;
        
        // If no division is selected, clear events
        if (!this.selectedDivision) {
            this.events = [];
            this.isLoading = false;
            return;
        }

        // All Divisions but wizard returned no divisions for this term → never show org-wide sessions
        if (this.isAllDivisionsSelected && (!this.allDivisionIds || this.allDivisionIds.length === 0)) {
            this.events = [];
            this.isLoading = false;
            return;
        }
        
        if (result.data) {
            const sessions = Array.isArray(result.data) ? result.data : [];
            this.events = sessions.map(session => this.mapSessionToEvent(session));
            this.isLoading = false;
            this.requestAutoScroll();
        } else if (result.error) {
            this.showToastMessage(this.getErrorMessage(result.error), 'error');
            this.isLoading = false;
        } else {
            // Still loading
            this.isLoading = true;
        }
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
        return !this.selectedDivision || this.isAllDivisionsSelected;
    }

    // In edit modal: enable Course/Department/Course Activity when editing a session that has a division (e.g. opened from "All Divisions" tile)
    get isEditModalCourseFieldsDisabled() {
        if (this.isEditSessionReadOnly) return true;
        if (this.isEditMode && this.selectedEventId && this.events && this.events.length > 0) {
            const selectedEvent = this.findEventRowForSession(this.selectedEventId, this.clickedTileDivisionId);
            if (selectedEvent && selectedEvent.divisionId) {
                return false; // We have division context from the session
            }
        }
        return this.isDivisionNotSelected;
    }

    get isFacultyFilterDisabled() {
        if (this.isAllDivisionsSelected) return false;
        return !this.selectedDivision;
    }

    get isAllDivisionsSelected() {
        return this.selectedDivision === TimetableCalendar.ALL_DIVISIONS_VALUE;
    }

    get selectedDivisionLabel() {
        if (!this.selectedDivision || this.isAllDivisionsSelected) {
            return '';
        }
        const selected = String(this.selectedDivision);
        const match = (this.divisionOptions || []).find(o => o && String(o.value) === selected);
        return match && match.label ? String(match.label) : selected;
    }

    get selectedProgramLabel() {
        if (!this.selectedProgram) return '';
        const match = (this.programOptions || []).find(o => o && String(o.value) === String(this.selectedProgram));
        return match && match.label ? String(match.label) : '';
    }

    get selectedBatchLabel() {
        if (!this.selectedBatch) return '';
        const match = (this.batchOptions || []).find(o => o && String(o.value) === String(this.selectedBatch));
        return match && match.label ? String(match.label) : '';
    }

    get selectedBatchGroupLabel() {
        if (!this.selectedBatchGroup) return '';
        const match = (this.batchGroupOptions || []).find(o => o && String(o.value) === String(this.selectedBatchGroup));
        return match && match.label ? String(match.label) : '';
    }

    get selectedBatchAllowsMultiProgram() {
        if (!this.selectedBatch) return false;
        const opt = (this.batchOptions || []).find(o => o && String(o.value) === String(this.selectedBatch));
        return opt ? opt.allowMultiProgramBatch === true : false;
    }

    get allowMultiProgramDisabledMessage() {
        if (!this.selectedBatch) return '';
        const opt = (this.batchOptions || []).find(o => o && String(o.value) === String(this.selectedBatch));
        return (opt && opt.allowMultiProgramBatch === false) ? 'Allow multi program on batch is disabled.' : '';
    }

    get selectedTermLabel() {
        if (!this.selectedTerm) return '';
        const match = (this.termOptions || []).find(o => o && String(o.value) === String(this.selectedTerm));
        return match && match.label ? String(match.label) : '';
    }

    get allDivisionIds() {
        return (this.divisionOptions || [])
            .map(opt => opt && opt.value)
            .filter(val => val && val !== TimetableCalendar.ALL_DIVISIONS_VALUE);
    }

    get createModalDivisionLabel() {
        if (!this.selectedDivision) return '—';
        if (this.isAllDivisionsSelected) {
            if (this.modalDivisionId) {
                const match = (this.divisionOptions || []).find(o => o && String(o.value) === String(this.modalDivisionId));
                return (match && match.label) ? String(match.label) : (this.modalDivisionId || '—');
            }
            return 'Select Division';
        }
        return this.selectedDivisionLabel || this.selectedDivision || '—';
    }

    /** Create Sessions modal: division dropdown options when All Divisions (exclude "All Divisions" option). */
    get createModalDivisionOptions() {
        if (!this.isAllDivisionsSelected) return [];
        return (this.divisionOptions || [])
            .filter(o => o && o.value && o.value !== TimetableCalendar.ALL_DIVISIONS_VALUE)
            .map(o => ({ label: o.label || String(o.value), value: o.value }));
    }

    get createModalProgramLabel() {
        if (!this.modalProgram) return 'All Programs';
        const match = (this.modalProgramOptionsWithAll || []).find(o => o && String(o.value) === String(this.modalProgram));
        return (match && match.label) ? String(match.label) : (this.modalProgram || 'All Programs');
    }

    get createModalBatchLabel() {
        if (!this.modalBatch) return 'All Batches';
        const match = (this.modalBatchOptionsWithAll || []).find(o => o && String(o.value) === String(this.modalBatch));
        return (match && match.label) ? String(match.label) : (this.modalBatch || 'All Batches');
    }

    get createModalTermLabel() {
        if (!this.modalTerm) return 'All Terms';
        const match = (this.modalTermOptionsWithAll || []).find(o => o && String(o.value) === String(this.modalTerm));
        return (match && match.label) ? String(match.label) : (this.modalTerm || 'All Terms');
    }

    get createModalCourseLabel() {
        if (!this.modalCourse) return 'Select Course';
        const match = (this.modalCourseOptions || []).find(o => o && String(o.value) === String(this.modalCourse));
        return (match && match.label) ? String(match.label) : (this.modalCourse.split('|')[0] || 'Select Course');
    }

    get facultyFilterOptionsWithChecked() {
        const selected = this.selectedFilterFacultyIds || [];
        return (this.filterFacultyOptions || []).map(opt => ({
            ...opt,
            checked: selected.includes(opt.value)
        }));
    }

    /** Pills for selected faculty in the sidebar filter (label + value for remove) */
    get filterFacultyPills() {
        const selected = this.selectedFilterFacultyIds || [];
        const options = this.filterFacultyOptions || [];
        return selected.map(id => {
            const label = this.getFacultyLabelById(id, options);
            return { value: id, label: label || id };
        });
    }

    /** Options for the "add faculty" combobox in sidebar (exclude already selected) */
    get filterAvailableFacultyOptions() {
        const selected = this.selectedFilterFacultyIds || [];
        return (this.filterFacultyOptions || []).filter(opt =>
            opt.value && !selected.some(sid => this.idsEqual(opt.value, sid))
        );
    }

    get hasFilterFacultyPills() {
        return (this.filterFacultyPills || []).length > 0;
    }

    get hasNoFacultyOptions() {
        return this.selectedDivision && (!this.filterFacultyOptions || this.filterFacultyOptions.length === 0);
    }

    /** Sidebar faculty combobox always shows placeholder (add-only); value kept in sync for re-selection. */
    get filterFacultyComboboxValueDisplay() {
        return '';
    }
    // SE-502: Returns true when course activity is Make Up Exam
    // and studentNames array has data — controls enrolled students visibility in edit session
    get showEnrolledStudents() {
    return this.selectedCourseActivity === 'Make Up Exam' &&
           Array.isArray(this.studentNames) &&
           this.studentNames.length > 0;
    }

    /** Hard reset for sidebar faculty combobox so removed faculty can be re-selected (single or multiple). */
    resetSidebarFacultyCombobox() {
        this.filterFacultyComboboxValue = '';
        // Defer DOM clear so LWC has re-rendered; fixes multi-remove case where combobox kept removed name.
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        setTimeout(() => {
            try {
                const combo = this.template.querySelector(
                    '.faculty-filter-picklist lightning-combobox'
                );
                if (combo) {
                    combo.value = null;
                }
            } catch (e) {
                // Non-critical; ignore
            }
        }, 0);
    }

    // Load Programs (filtered by Program Team; single program auto-selected)
    loadPrograms() {
        getPrograms()
            .then(result => {
                const options = (result && result.options) ? result.options : [];
                this.programOptions = options.map(option => ({
                    label: option.label,
                    value: option.value
                }));
                const defaultId = (result && result.defaultProgramId) ? result.defaultProgramId : null;
                if (defaultId) {
                    this.selectedProgram = defaultId;
                    getBatchesForProgram({ programId: defaultId })
                        .then(batchResult => {
                            this.batchOptions = (batchResult || []).map(option => ({
                                label: option.label,
                                value: option.value,
                                sessionDuration: option.sessionDuration != null ? Math.round(Number(option.sessionDuration)) : null,
                                allowMultiProgramBatch: option.allowMultiProgramBatch === true
                            }));
                        })
                        .catch(err => console.error('Error loading batches for default program:', err));
                }
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
        this.sessionDuration = null; // Clear session duration when batch is deselected
        this.batchOptions = [];
        this.batchGroupOptions = [];
        this.termOptions = [];
        this.divisionOptions = [];
        
        if (this.selectedProgram) {
            getBatchesForProgram({ programId: this.selectedProgram })
                .then(result => {
                    const options = (result || []).map(option => ({
                        label: option.label,
                        value: option.value,
                        sessionDuration: option.sessionDuration != null ? Math.round(Number(option.sessionDuration)) : null,
                        allowMultiProgramBatch: option.allowMultiProgramBatch === true
                    }));
                    this.batchOptions = options;
                    // Auto-select batch when only one option so payload always has batchId (and Batch field populates on Session)
                    if (options.length === 1 && options[0].value) {
                        this.selectedBatch = options[0].value;
                        const raw = options[0].sessionDuration != null ? options[0].sessionDuration : null;
                        this.sessionDuration = raw != null ? Math.round(Number(raw)) : null;
                        getBatchGroupsForBatch({ batchId: this.selectedBatch })
                            .then(bgResult => {
                                this.batchGroupOptions = (bgResult || []).map(opt => ({ label: opt.label, value: opt.value }));
                            })
                            .catch(() => { this.batchGroupOptions = []; });
                    }
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
        
        // Store session duration from the selected batch (round to whole minutes: 45.9→46, 45.4→45)
        if (this.selectedBatch) {
            const selectedBatchOption = this.batchOptions.find(option => option.value === this.selectedBatch);
            const raw = selectedBatchOption && selectedBatchOption.sessionDuration != null ? selectedBatchOption.sessionDuration : null;
            this.sessionDuration = raw != null ? Math.round(Number(raw)) : null;
            
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
        
        if (this.selectedBatchGroup) {
            getTermsForBatchGroup({ batchGroupId: this.selectedBatchGroup })
                .then(result => {
                    this.termOptions = result.map(option => ({
                        label: option.label,
                        value: option.value,
                        termStartDate: option.termStartDate || null,
                        termEndDate: option.termEndDate || null
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
        this.selectedFilterFacultyIds = [];
        this.filterFacultyComboboxValue = '';
        this.filterFacultyOptions = [];
        
        if (this.selectedTerm) {
            getDivisionsForTerms({ termIds: [this.selectedTerm] })
                .then(result => {
                    const fetched = (result || []).map(option => ({
                        label: option.label,
                        value: option.value,
                        divisionColor: (option.divisionColor && String(option.divisionColor).trim()) ? String(option.divisionColor).trim() : null
                    }));

                    this.divisionOptions = [
                        { label: 'All Divisions', value: TimetableCalendar.ALL_DIVISIONS_VALUE },
                        ...fetched
                    ];
                })
                .catch(error => {
                    console.error('Error loading divisions:', error);
                });
        }
    }

    handleDivisionChange(event) {
        this.selectedDivision = event.detail.value; // This is now a division ID
        this.modalDivisionId = null;
        this.selectedFilterFacultyIds = [];
        this.filterFacultyComboboxValue = '';
        this.loadFacultiesForFilter();

        // Load courses for the selected division (skip for "All Divisions")
        if (this.selectedDivision && !this.isAllDivisionsSelected) {
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
        } else if (this.isAllDivisionsSelected) {
            // Browsing mode: don't load courses because there's no single division context
            this.courseOptions = [];
        } else {
            this.courseOptions = [];
            this.filterFacultyOptions = [];
            this.events = [];
        }
        
        // Force refresh of sessions when division changes
        setTimeout(() => {
            if (this.wiredSessionsResult) {
                refreshApex(this.wiredSessionsResult);
            }
        }, 0);

        this.requestAutoScroll();
    }

    handleScheduleTypeDraftChange(event) {
        this.filterScheduleTypeDraft = event.target.checked;
        // Bust cached wire results for this schedule-type combination.
        this.sessionsRefreshKey = Date.now();
        if (this.wiredSessionsResult) {
            refreshApex(this.wiredSessionsResult);
        }
    }

    handleScheduleTypePublishedChange(event) {
        this.filterScheduleTypePublished = event.target.checked;
        // Bust cached wire results for this schedule-type combination.
        this.sessionsRefreshKey = Date.now();
        if (this.wiredSessionsResult) {
            refreshApex(this.wiredSessionsResult);
        }
    }

    loadFacultiesForFilter() {
        if (!this.selectedDivision) {
            this.filterFacultyOptions = [];
            return;
        }
        const divisionId = this.isAllDivisionsSelected ? null : this.selectedDivision;
        const divisionIds = this.isAllDivisionsSelected ? this.allDivisionIds : null;
        getFacultiesForFilter({ divisionId, divisionIds })
            .then(result => {
                this.filterFacultyOptions = (result || []).map(o => ({ label: o.label, value: o.value }));
            })
            .catch(() => {
                this.filterFacultyOptions = [];
            });
    }

    handleFacultyFilterChange(event) {
        const value = event.detail.value;
        this.selectedFilterFacultyIds = Array.isArray(value) ? value : (value ? [value] : []);
        if (!this.selectedFilterFacultyIds || this.selectedFilterFacultyIds.length === 0) {
            this.resetSidebarFacultyCombobox();
        }
    }

    handleFacultyFilterCheck(event) {
        const facultyId = event.currentTarget.dataset.facultyId;
        const checked = event.target.checked;
        if (!facultyId) return;
        let ids = [...(this.selectedFilterFacultyIds || [])];
        if (checked) {
            if (!ids.includes(facultyId)) ids.push(facultyId);
        } else {
            ids = ids.filter(id => id !== facultyId);
        }
        this.selectedFilterFacultyIds = ids;
        if (!ids || ids.length === 0) {
            this.resetSidebarFacultyCombobox();
        }
    }

    handleFilterFacultyAdd(event) {
        const value = event.detail.value;
        if (!value) return;
        const ids = [...(this.selectedFilterFacultyIds || [])];
        if (!ids.includes(value)) ids.push(value);
        this.selectedFilterFacultyIds = ids;
        this.filterFacultyComboboxValue = '';
    }

    handleFilterFacultyRemove(event) {
        const facultyId = event.currentTarget.dataset.facultyId;
        if (!facultyId) return;
        this.selectedFilterFacultyIds = (this.selectedFilterFacultyIds || []).filter(id => id !== facultyId);
        // Always hard-reset the combobox so it never shows a removed faculty as selected
        this.resetSidebarFacultyCombobox();
    }

    handleCourseChange(event) {
        this.selectedCourse = event.detail.value;
        this.selectedAssignments = [];
        this.showCourseAssignments = false;
        // Clear both Faculty (lead) and Support Faculty when course changes (create and edit session)
        this.selectedFacultyValue = [];
        this.editLeadFacultyIds = [];
        this.editFacultyComboboxValue = '';
        this.facultyOptions = [];
        
        // Update department name based on selected course
        if (this.selectedCourse) {
            const selectedOption = this.courseOptions.find(opt => opt.value === this.selectedCourse);

            
            if (selectedOption && selectedOption.departmentName) {
                this.selectedCourseDepartmentName = selectedOption.departmentName;
            } else {
                this.selectedCourseDepartmentName = '';
            }
            
            this.loadCourseAssignments();
            // Always load faculty when course is selected
            this.loadFacultyForCourse();
        } else {
            this.selectedCourseDepartmentName = '';
            this.courseAssignments = [];
        }
        // Clear students when course changes
    this.eligibleStudentOptions = [];
    this.selectedStudentIds = [];
    this.studentDivisionMap = {};
    const idx = this.activeCreateSessionIndex;
    if (idx != null && this.createSessionsList && this.createSessionsList[idx]) {
        const u = [...this.createSessionsList];
        u[idx] = { ...u[idx], selectedStudentIds: [], 
        selectedAssignmentKeys: [] // ← ADD THIS — clears checked programs
        };
        this.createSessionsList = u;
    }
}
    
    loadExistingSessionDivisions(sessionId) {
        if (!sessionId) {
            this.existingSessionDivisions = [];
            return Promise.resolve();
        }
        // refreshKey forces a fresh server read so reopened modal shows current state (e.g. after Remove + Save)
        return getSessionDivisions({ sessionId: sessionId, refreshKey: String(Date.now()) })
            .then(result => {
                // Only apply result if this is still the session we opened (avoid stale/out-of-order response)
                if (this.selectedEventId !== sessionId) return;
                const list = Array.isArray(result) ? result : [];
                this.existingSessionDivisions = [...list];
            })
            .catch(error => {
                console.error('Error loading existing session divisions:', error);
                if (this.selectedEventId === sessionId) {
                    this.existingSessionDivisions = [];
                }
            });
    }

    loadEditAddCourseAssignments() {
        this.editAddSelectedKeys = [];
        const courseValue = this.selectedCourse;
        if (!courseValue || !courseValue.includes('|')) {
            this.editAddCourseAssignments = [];
            return;
        }
        const parts = courseValue.split('|');
        const learningCourseId = parts.length > 1 ? parts[1].trim() : null;
        if (!learningCourseId) {
            this.editAddCourseAssignments = [];
            return;
        }
        const currentDivisionId = this.selectedDivision && this.selectedDivision !== TimetableCalendar.ALL_DIVISIONS_VALUE ? this.selectedDivision : null;
        const currentProgramId = this.selectedProgram || null;
        const currentBatchId = this.selectedBatch || null;
        const currentBatchGroupId = this.selectedBatchGroup || null;
        const currentTermId = this.selectedTerm || null;
        getCourseAssignments({
            learningCourseId,
            currentDivisionId,
            currentProgramId,
            currentBatchId,
            currentBatchGroupId,
            currentTermId
        })
            .then(result => {
                const list = Array.isArray(result) ? result : [];
                this.editAddCourseAssignments = list.map((option, index) => ({
                    ...option,
                    assignmentKey: this.getAssignmentKey(option, index),
                    divisionName: option.divisions && option.divisions[0] ? option.divisions[0].divisionName : '',
                    divisionId: option.divisions && option.divisions[0] ? (option.divisions[0].divisionId || option.divisions[0].id) : ''
                }));
            })
            .catch(() => {
                this.editAddCourseAssignments = [];
            });
    }

    loadExistingSessionFaculties(sessionId) {
        if (!sessionId) {
            this.selectedFacultyValue = [];
            return;
        }
        
        getSessionFaculties({ sessionId: sessionId })
            .then(result => {
                const facultyIds = Array.isArray(result) ? result : [];
                this.selectedFacultyValue = facultyIds;
                if (this.editLeadFacultyIds.length === 0 && facultyIds.length > 0) {
                    this.editLeadFacultyIds = [facultyIds[0]];
                }
                this.editFacultyComboboxValue = '';
            })
            .catch(error => {
                console.error('Error loading existing session faculties:', error);
                this.selectedFacultyValue = [];
            });
    }
    
    loadCourseAssignments() {
        if (!this.selectedCourse) {
            this.courseAssignments = [];
            this.showCourseAssignments = false;
            return;
        }
        
        // Extract LearningCourseId from selectedCourse value
        // Format: "courseName|learningCourseId"
        const courseValue = this.selectedCourse;
        const parts = courseValue.split('|');
        const learningCourseId = parts.length > 1 ? parts[1] : null;
        
        if (!learningCourseId) {
            console.error('LearningCourseId not found in course selection');
            this.courseAssignments = [];
            this.showCourseAssignments = false;
            return;
        }
        
        // Pass full context so server can exclude the "already selected" row (program, batch, batch group, term, division)
        const currentDivisionId = this.selectedDivision && this.selectedDivision !== TimetableCalendar.ALL_DIVISIONS_VALUE ? this.selectedDivision : null;
        const currentProgramId = this.selectedProgram || null;
        const currentBatchId = this.selectedBatch || null;
        const currentBatchGroupId = this.selectedBatchGroup || null;
        const currentTermId = this.selectedTerm || null;
        // DEBUG: compare what we send to Apex
        console.debug('[loadCourseAssignments] Sending context:', {
            learningCourseId,
            currentDivisionId,
            currentProgramId,
            currentBatchId,
            currentBatchGroupId,
            currentTermId
        });
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
                // Add computed properties to each assignment for template use
                this.courseAssignments = assignments.map((option, index) => ({
                    ...option,
                    assignmentKey: this.getAssignmentKey(option, index),
                    isSelected: false, // Will be computed in getter
                    divisionName: option.divisions && option.divisions.length > 0 
                        ? option.divisions[0].divisionName 
                        : '',
                    divisionId: option.divisions && option.divisions.length > 0 
                        ? option.divisions[0].divisionId 
                        : ''   
                }));
                this.showCourseAssignments = this.courseAssignments.length > 0;
                // Start with all assignments unselected - user must select manually
                this.selectedAssignments = [];
                // Update isSelected for each assignment
                this.updateAssignmentSelection();
            })
            .catch(error => {
                console.error('Error loading course assignments:', error);
                this.courseAssignments = [];
                this.showCourseAssignments = false;
            });
    }
    
    getAssignmentKey(option, index) {
        // Create a unique key for each assignment combination including division
        const divisionId = option.divisions && option.divisions.length > 0
            ? (option.divisions[0].divisionId || option.divisions[0].id || '')
            : '';
        return `${option.programId || ''}_${option.batchId || ''}_${option.batchGroupId || ''}_${option.termId || ''}_${divisionId}_${index}`;
    }

    getAssignmentDivisionId(assignment) {
        if (!assignment) return null;
        const fromDivisions = assignment.divisions && assignment.divisions[0]
            ? (assignment.divisions[0].divisionId || assignment.divisions[0].id)
            : null;
        const id = fromDivisions || assignment.divisionId;
        if (id == null || id === '') return null;
        const str = String(id).trim();
        return str.length > 0 ? str : null;
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
        
        // Update isSelected for each assignment
        this.updateAssignmentSelection();
    }
    
    updateAssignmentSelection() {
        this.courseAssignments = this.courseAssignments.map(option => ({
            ...option,
            isSelected: this.selectedAssignments.includes(option.assignmentKey)
        }));
    }

    /** Returns true when Course Activity is "Joint Session" (by value or label). */
    isCourseActivityJointSession(activity) {
        if (!activity) return false;
        const s = String(activity).toLowerCase();
        return s.indexOf('joint') >= 0;
    }

    handleCourseActivityChange(event) {
        const value = event.detail.value || '';
        const wasJointSession = this.isJointSession;
        const leadIds = this.editLeadFacultyIds || [];
        const hasLead = leadIds.length > 0;
        const leadId = hasLead ? leadIds[0] : '';
        // Snapshot support so we can restore after any re-render/combobox change that might clear it
        const supportSnapshot = [...(this.editSupportFacultyIds || [])];

        this.selectedCourseActivity = value;
        this.isJointSession = this.isCourseActivityJointSession(value);

        if (this.isJointSession && !wasJointSession) {
            this.editLeadFacultyIds = leadId ? [leadId] : [];
            this.selectedFacultyValue = leadId ? [leadId, ...supportSnapshot] : supportSnapshot;
        } else if (!this.isJointSession && wasJointSession) {
            // Single lead only; preserve support faculty (do not clear support when changing course activity)
            this.editLeadFacultyIds = leadId ? [leadId] : [];
            this.selectedFacultyValue = leadId ? [leadId, ...supportSnapshot] : (supportSnapshot.length > 0 ? supportSnapshot : '');
        } else if (!this.isJointSession) {
            // Non–Joint to non–Joint (e.g. End Term → Tutorials): keep lead and support so support faculty is not lost
            this.selectedFacultyValue = leadId ? [leadId, ...supportSnapshot] : (supportSnapshot.length > 0 ? supportSnapshot : '');
        }

        if (this.selectedCourse && this.facultyOptions.length === 0) {
            this.loadFacultyForCourse();
        }

        // Deferred restore: re-apply lead + support after any re-render so support is not cleared by a spurious combobox change
        if (!this.isJointSession && (leadId || supportSnapshot.length > 0)) {
            // eslint-disable-next-line @lwc/lwc/no-async-operation
            setTimeout(() => {
                const currentLead = (this.editLeadFacultyIds && this.editLeadFacultyIds.length > 0) ? this.editLeadFacultyIds[0] : leadId;
                this.selectedFacultyValue = currentLead
                    ? [currentLead, ...supportSnapshot]
                    : (supportSnapshot.length > 0 ? supportSnapshot : '');
            }, 0);
        }
    }

    handleJointSessionChange(event) {
        const wasJointSession = this.isJointSession;
        this.isJointSession = event.target.checked;

        const leadIds = this.editLeadFacultyIds || [];
        const hasLead = leadIds.length > 0;
        const leadId = hasLead ? leadIds[0] : '';
        const support = this.editSupportFacultyIds || [];
        if (this.isJointSession && !wasJointSession) {
            this.editLeadFacultyIds = leadId ? [leadId] : [];
            this.selectedFacultyValue = leadId ? [leadId, ...support] : support;
        } else if (!this.isJointSession && wasJointSession) {
            // Single lead only; preserve support faculty
            this.editLeadFacultyIds = leadId ? [leadId] : [];
            this.selectedFacultyValue = leadId ? [leadId, ...support] : (support.length > 0 ? support : '');
        }

        if (this.selectedCourse && this.facultyOptions.length === 0) {
            this.loadFacultyForCourse();
        }
    }

    handleFacultyChange(event) {
        // For lightning-combobox: event.detail.value is a string
        // For lightning-dual-listbox: event.detail.value is an array
        this.selectedFacultyValue = event.detail.value;
    }

    // Getter to return the correct format for lightning-combobox (single select)
    get selectedFacultyForCombobox() {
        // Single-select mode: must be a string
        if (Array.isArray(this.selectedFacultyValue)) {
            return this.selectedFacultyValue.length > 0 ? this.selectedFacultyValue[0] : '';
        }
        return this.selectedFacultyValue || '';
    }

    // Getter to return the correct format for lightning-dual-listbox (multi select)
    get selectedFacultyForDualListbox() {
        // Multi-select mode: must be an array
        if (Array.isArray(this.selectedFacultyValue)) {
            return this.selectedFacultyValue;
        } else if (this.selectedFacultyValue && typeof this.selectedFacultyValue === 'string') {
            return [this.selectedFacultyValue];
        }
        return [];
    }

    /**
     * Division for scoping faculty to the Programme Course on this division's Course Offering (not every Programme Course for the Learning Course).
     */
    getDivisionIdForFacultyQuery() {
        if (!this.isEditMode) {
            if (this.isAllDivisionsSelected) {
                return this.modalDivisionId || null;
            }
            return (this.selectedDivision && this.selectedDivision !== TimetableCalendar.ALL_DIVISIONS_VALUE)
                ? this.selectedDivision
                : null;
        }
        if (this.isAllDivisionsSelected) {
            return this.currentEditDivisionId || this.clickedTileDivisionId || null;
        }
        return (this.selectedDivision && this.selectedDivision !== TimetableCalendar.ALL_DIVISIONS_VALUE)
            ? this.selectedDivision
            : null;
    }

    loadFacultyForCourse() {
        const courseId = (!this.isEditMode && this.modalCourse) ? this.modalCourse : this.selectedCourse;
        if (!courseId) {
            this.facultyOptions = [];
            return;
        }

        const divisionId = this.getDivisionIdForFacultyQuery();
        getFacultyForCourse({ courseId, divisionId: divisionId || undefined })
            .then(result => {
                this.facultyOptions = Array.isArray(result) ? result : [];
            })
            .catch(error => {
                console.error('Error loading faculty:', error);
                this.facultyOptions = [];
            });
    }

    // Getter to determine if faculty dropdown should be shown
    get showFacultyDropdown() {
        return this.selectedCourse && this.facultyOptions.length > 0;
    }

    // Getter to determine if faculty dropdown should be disabled
    get isFacultyDisabled() {
        if (this.isEditSessionReadOnly) return true;
        // When editing a session that has division context (e.g. opened from All Divisions), only require course
        if (this.isEditMode && this.selectedEventId && this.events && this.events.length > 0) {
            const selectedEvent = this.findEventRowForSession(this.selectedEventId, this.clickedTileDivisionId);
            if (selectedEvent && selectedEvent.divisionId) {
                return !this.selectedCourse;
            }
        }
        return this.isDivisionNotSelected || !this.selectedCourse;
    }

    // Edit modal: Faculty (single or multiple when Joint) and Support Faculty (multi). Only derive from editLeadFacultyIds so support is never shown as lead.
    get editLeadFacultyId() {
        if (this.editLeadFacultyIds && this.editLeadFacultyIds.length > 0) {
            return this.editLeadFacultyIds[0];
        }
        return '';
    }

    get editSupportFacultyIds() {
        const leadIds = this.editLeadFacultyIds || [];
        const v = this.selectedFacultyValue;
        const arr = Array.isArray(v) ? v : (v ? [v] : []);
        return arr.filter(id => !leadIds.some(lid => this.idsEqual(lid, id)));
    }

    get editLeadFacultyPills() {
        const isMulti = this.isMultiFacultySession(this.selectedSessionType);
        const leadIds = isMulti &&this.editLeadFacultyIds &&
        this.editLeadFacultyIds.length > 0
        ? this.editLeadFacultyIds
        : (this.editLeadFacultyId
            ? [this.editLeadFacultyId]
            : []);
        const opts = this.facultyOptions || [];
        const nameList = this.editModalFacultyNameList || [];
        return leadIds.map(id => {
            const fromServer = nameList.find(entry => entry.id && this.idsEqual(entry.id, id));
            const label = (fromServer && fromServer.name) ? fromServer.name : this.getFacultyLabelById(id, opts);
            return { value: id, label: label || id };
        });
    }

    get editSupportFacultyPills() {
        const ids = this.editSupportFacultyIds;
        const opts = this.facultyOptions || [];
        const nameList = this.editModalFacultyNameList || [];
        return ids.map(id => {
            const fromServer = nameList.find(entry => entry.id && this.idsEqual(entry.id, id));
            const label = (fromServer && fromServer.name) ? fromServer.name : this.getFacultyLabelById(id, opts);
            return { value: id, label: label || id };
        });
    }

    get editNoLeadFacultySelected() {
        return !this.editLeadFacultyId;
    }

    /** Faculty dropdown: exclude all already-selected faculty (lead group) so they don't show until removed. */
    get editLeadFacultyOptions() {
        const leadIds = this.editLeadFacultyIds || [];
        return (this.facultyOptions || []).filter(o =>
            o.value && !leadIds.some(lid => this.idsEqual(o.value, lid))
        );
    }

    /** Support dropdown: exclude all in faculty (lead) and support so they don't show until removed. */
    get editSupportFacultyOptions() {
        const leadIds = this.editLeadFacultyIds || [];
        const supportIds = this.editSupportFacultyIds || [];
        return (this.facultyOptions || []).filter(o => {
            if (!o.value) return false;
            if (leadIds.some(lid => this.idsEqual(o.value, lid))) return false;
            return !supportIds.some(sid => this.idsEqual(o.value, sid));
        });
    }

    // Legacy: combined pills for any code that still references (e.g. tooltip)
    get editFacultyPills() {
        const ids = Array.isArray(this.selectedFacultyValue)
            ? this.selectedFacultyValue
            : (this.selectedFacultyValue ? [this.selectedFacultyValue] : []);
        const opts = this.facultyOptions || [];
        const nameList = this.editModalFacultyNameList || [];
        return ids.map(id => {
            const fromServer = nameList.find(entry => entry.id && this.idsEqual(entry.id, id));
            const label = (fromServer && fromServer.name) ? fromServer.name : this.getFacultyLabelById(id, opts);
            return { value: id, label: label || id };
        });
    }

    get editNoFacultySelected() {
        return !this.editLeadFacultyId;
    }

    get editAvailableFacultyOptions() {
        const leadIds = this.editLeadFacultyIds || [];
        const supportIds = this.editSupportFacultyIds || [];
        return (this.facultyOptions || []).filter(o => {
            if (!o.value) return false;
            if (leadIds.some(lid => this.idsEqual(o.value, lid))) return false;
            return !supportIds.some(sid => this.idsEqual(o.value, sid));
        });
    }

    handleEditLeadFacultyChange(event) {
        const value = event.detail.value || '';
        const v = this.selectedFacultyValue;
        const arr = Array.isArray(v) ? v : (v ? [v] : []);
        const leadIds = this.editLeadFacultyIds || [];
        const supportIds = arr.filter(id => !leadIds.some(lid => this.idsEqual(lid, id)));
        const isMulti = this.isMultiFacultySession(this.selectedSessionType);
        if (isMulti) {
            if (leadIds.some(lid => this.idsEqual(lid, value))) return;
            const newLeadIds = [...leadIds, value];
            this.editLeadFacultyIds = newLeadIds;
            this.selectedFacultyValue = [...newLeadIds, ...supportIds];
        } else {
            this.editLeadFacultyIds = value ? [value] : [];
            this.selectedFacultyValue = value ? [value, ...supportIds] : supportIds;
        }
        this.editFacultyComboboxValue = '';
        this.resetEditFacultyCombobox();
        this.loadFacultyConflicts(); //1002
    }

   handleSessionTypeChange(event) {

    this.selectedSessionType = event.detail.value || '';

    const isMulti = this.isMultiFacultySession(this.selectedSessionType);

    if (!Array.isArray(this.editLeadFacultyIds)) {
        this.editLeadFacultyIds = [];
    }

    if (!Array.isArray(this.selectedFacultyValue)) {
        this.selectedFacultyValue = [];
    }

    // If session becomes single faculty type
    if (!isMulti) {

        const firstLeadFaculty =
            this.editLeadFacultyIds.length > 0
                ? this.editLeadFacultyIds[0]
                : null;

        // Keep only first faculty
        this.editLeadFacultyIds = firstLeadFaculty
            ? [firstLeadFaculty]
            : [];

        // IMPORTANT
        // selectedFacultyValue should also contain ONLY first faculty
        this.selectedFacultyValue = firstLeadFaculty
            ? [firstLeadFaculty]
            : [];
    }

    // Force rerender
    this.editLeadFacultyIds = [...this.editLeadFacultyIds];
    this.selectedFacultyValue = [...this.selectedFacultyValue];
}

    handleEditSupportFacultyAdd(event) {
        const value = event.detail.value;
        if (!value) return;
        const leadIds = this.editLeadFacultyIds || [];
        const support = this.editSupportFacultyIds || [];
        if (leadIds.some(lid => this.idsEqual(lid, value))) return;
        if (support.some(sid => this.idsEqual(sid, value))) return;
        this.selectedFacultyValue = [...leadIds, ...support, value];
        this.editFacultyComboboxValue = '';
        this.resetEditFacultyCombobox();
    }

    handleEditSupportFacultyRemove(event) {
        const facultyId = event.currentTarget.dataset.faculty;
        if (!facultyId) return;
        const leadIds = this.editLeadFacultyIds || [];
        const support = this.editSupportFacultyIds.filter(id => !this.idsEqual(id, facultyId));
        this.selectedFacultyValue = [...leadIds, ...support];
        this.resetEditFacultyCombobox();
    }

    handleEditFacultyAdd(event) {
        const value = event.detail.value;
        if (!value) return;
        if (this.isJointSession) {
            this.handleEditSupportFacultyAdd(event);
            return;
        }
        this.selectedFacultyValue = value || '';
        this.editFacultyComboboxValue = '';
        this.resetEditFacultyCombobox();
        this.loadFacultyConflicts(); //1002
    }

    handleEditFacultyRemove(event) {
        const facultyId = event.currentTarget.dataset.faculty;
        if (!facultyId) return;
        const v = this.selectedFacultyValue;
        const facultyIds = Array.isArray(v) ? v : (v ? [v] : []);
        const leadFacultyIds = this.editLeadFacultyIds || [];
        const supportIds = facultyIds.filter(id =>
            !leadFacultyIds.some(lid => this.idsEqual(lid, id))
        );
        const isFromLead = leadFacultyIds.some(lid => this.idsEqual(lid, facultyId));
        if (this.isJointSession) {
            if (isFromLead) {
                const newLeadFacultyIds = leadFacultyIds.filter(id => !this.idsEqual(id, facultyId));
                this.editLeadFacultyIds = newLeadFacultyIds;
                this.selectedFacultyValue = [...newLeadFacultyIds, ...supportIds];
            } else {
                this.handleEditSupportFacultyRemove(event);
            }
        } else {
            this.editLeadFacultyIds = [];
            this.selectedFacultyValue = '';
        }
        this.editFacultyComboboxValue = '';
        this.resetEditFacultyCombobox();
        this.loadFacultyConflicts(); //1002
    }
    
    /** Hard reset for edit modal faculty combobox(es) so removed faculty can be re-selected. */
    resetEditFacultyCombobox() {
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        setTimeout(() => {
            try {
                const combos = this.template.querySelectorAll('.edit-faculty-selector lightning-combobox');
                (combos || []).forEach(combo => { if (combo) combo.value = null; });
            } catch (e) {
                // Non-critical; ignore
            }
        }, 0);
    }

    // Getter for edit modal faculty combobox - always returns empty to show placeholder (same as sidebar pattern)
    get editFacultyComboboxValueDisplay() {
        return '';
    }

    /** Edit modal: disable Save when saving, validation errors, or read-only. */
    get editSessionSaveDisabled() {
        return this.isSaving || this.hasEditSessionValidationErrors || this.isEditSessionReadOnly;
    }

    /** Past / completed sessions: no edits (except viewing attendance); uses form date when user changes it. */
    get isEditSessionReadOnly() {
        if (!this.isEditMode || !this.selectedEventId) return false;
        const editingEvent = this.findEventRowForSession(this.selectedEventId, this.clickedTileDivisionId);
        const dateStr = (this.eventDate && String(this.eventDate).trim())
            || (editingEvent && editingEvent.date)
            || '';
        if (this.isSessionCompletedByDate(dateStr)) {
            return true;
        }
        return editingEvent ? editingEvent.isCompleted === true : false;
    }

    /** True if any session has no faculty selected at all. */
    get createSessionsMissingFaculty() {
        const list = this.createSessionsList || [];
        return list.some(s => (s.facultyIds || []).length === 0);
    }

    /** True if session has at least one Faculty (lead); support-only is not enough. */
    sessionHasLeadFaculty(session) {
        if (!session) return false;
        const leadIds = session.leadFacultyIds;
        if (leadIds && Array.isArray(leadIds) && leadIds.length > 0) return true;
        const leadId = session.leadFacultyId;
        return leadId != null && String(leadId).trim() !== '';
    }

    /** True if any session has faculty selected but no Faculty (lead) — support-only is invalid. */
    get createSessionsHasNoLeadFaculty() {
        const list = this.createSessionsList || [];
        return list.some(s => {
            const hasFaculty = (s.facultyIds || []).length > 0;
            return hasFaculty && !this.sessionHasLeadFaculty(s);
        });
    }

    /** Create Sessions modal: disable when saving, time error, no faculty, only support (no lead), or negative Class Room/Remark. */
    get isCreateSessionsSaveDisabled() {
        return this.isSaving || this.createSessionsHasTimeError
            || this.createSessionsMissingFaculty || this.createSessionsHasNoLeadFaculty
            || this.createSessionsHasNegativeField;
    }

    get createSessionsHasNegativeField() {
        const list = this.createSessionsList || [];
        return list.some(s => this.isNegativeFieldValue(s.classRoom) || this.isNegativeFieldValue(s.remark));
    }

    /** User-facing validation error messages for Create Sessions modal (so user knows why the button is disabled). */
    get createSessionsValidationErrors() {
        const list = this.createSessionsList || [];
        const errors = [];
        list.forEach((s, i) => {
            const sessionNum = i + 1;
            const sessionLabel = `Session ${sessionNum}`;
            const hasFaculty = (s.facultyIds || []).length > 0;
            const hasLead = this.sessionHasLeadFaculty(s);
            if (hasFaculty && !hasLead) {
                errors.push({ key: `lead-${i}`, message: `${sessionLabel}: At least one Faculty (lead) is required. Support faculty alone is not enough.` });
            }
            if (this.isNegativeFieldValue(s.classRoom)) {
                errors.push({ key: `classRoom-${i}`, message: `${sessionLabel}: Negative values and values starting with '-' are not allowed.` });
            }
            if (this.isNegativeFieldValue(s.remark)) {
                errors.push({ key: `remark-${i}`, message: `${sessionLabel}: Negative values and values starting with '-' are not allowed.` });
            }
            const startStr = s.startTime ? String(s.startTime).trim() : '';
            const endStr = s.endTime ? String(s.endTime).trim() : '';
            if (!startStr || !endStr) {
                errors.push({ key: `required-${i}`, message: `${sessionLabel}: Date and start/end time are required.` });
            } else {
                /* --- COMMENTED OUT: 9AM/10PM time-of-day restriction (no longer required) ---
               if (this.isTimeBefore9AM(s.startTime)) {
                  errors.push({ key: `start-am-${i}`, message: `${sessionLabel}: Start time must be 9:00 AM or later.` });
              } else if (this.isTimeBeyond10PM(s.startTime)) {
                  errors.push({ key: `start-pm-${i}`, message: `${sessionLabel}: Start time must be 10:00 PM or earlier.` });
               }
                if (this.isTimeBefore9AM(s.endTime)) {
                   errors.push({ key: `end-am-${i}`, message: `${sessionLabel}: End time must be 9:00 AM or later.` });
              } else if (this.isTimeBeyond10PM(s.endTime)) {
                   //errors.push({ key: `end-pm-${i}`, message: `${sessionLabel}: End time must be 10:00 PM or earlier.` });
               }
                  --- END COMMENTED OUT --- */
                const startM = this.parseTimeToMinutes(s.startTime);
                const endM = this.parseTimeToMinutes(s.endTime);
                if (endM <= startM) {
                    errors.push({ key: `order-${i}`, message: `${sessionLabel}: End time must be after start time.` });
                }
            }
        });
        return errors;
    }

    get hasCreateSessionsValidationErrors() {
        return (this.createSessionsValidationErrors || []).length > 0;
    }

    /** User-facing validation error messages for Edit Session modal. */
    get editSessionValidationErrors() {
        const errors = [];
        if (this.isNegativeFieldValue(this.eventClassRoom)) {
            errors.push({ key: 'classRoom', message: "Negative values and values starting with '-' are not allowed." });
        }
        if (this.isNegativeFieldValue(this.eventRemark)) {
            errors.push({ key: 'remark', message: "Negative values and values starting with '-' are not allowed." });
        }
        const startStr = this.eventStartTime ? String(this.eventStartTime).trim() : '';
        const endStr = this.eventEndTime ? String(this.eventEndTime).trim() : '';
        if (startStr && endStr) {
              /* --- COMMENTED OUT: 9AM/10PM time-of-day restriction (no longer required) SE-1015 ---
            if (this.isTimeBefore9AM(this.eventStartTime)) {
               errors.push({ key: 'start-am', message: 'Start time must be 9:00 AM or later.' });
            } else if (this.isTimeBeyond10PM(this.eventStartTime)) {
              errors.push({ key: 'start-pm', message: 'Start time must be 10:00 PM or earlier.' });
            }
            if (this.isTimeBefore9AM(this.eventEndTime)) {
             errors.push({ key: 'end-am', message: 'End time must be 9:00 AM or later.' });
            } else if (this.isTimeBeyond10PM(this.eventEndTime)) {
                //errors.push({ key: 'end-pm', message: 'End time must be 10:00 PM or earlier.' });
          }
            --- END COMMENTED OUT ---SE-1015 */
            if (this.parseTimeToMinutes(endStr) <= this.parseTimeToMinutes(startStr)) {
                errors.push({ key: 'order', message: 'End time must be after start time.' });
            }
        }
        return errors;
    }

    get hasEditSessionValidationErrors() {
        return (this.editSessionValidationErrors || []).length > 0;
    }

    /** Inline validation errors for Edit Session modal (shown below each field). */
    get editSessionFieldErrors() {
        const urlError = null;
        const classRoomError = this.isNegativeFieldValue(this.eventClassRoom) ? "Negative values and values starting with '-' are not allowed." : null;
        const remarkError = this.isNegativeFieldValue(this.eventRemark) ? "Negative values and values starting with '-' are not allowed." : null;
        const startStr = this.eventStartTime ? String(this.eventStartTime).trim() : '';
        const endStr = this.eventEndTime ? String(this.eventEndTime).trim() : '';
        let startTimeError = null;
        let endTimeError = null;
        let orderError = null;
    /* --- COMMENTED OUT: 9AM/10PM time-of-day restriction (no longer required) SE-1015---    
       if (startStr) {
            if (this.isTimeBefore9AM(this.eventStartTime)) {
                startTimeError = 'Start time must be 9:00 AM or later.';
          } else if (this.isTimeBeyond10PM(this.eventStartTime)) {
                startTimeError = 'Start time must be 10:00 PM or earlier.';
            }
        }
        if (endStr) {
            if (this.isTimeBefore9AM(this.eventEndTime)) {
                endTimeError = 'End time must be 9:00 AM or later.';
            } else if (this.isTimeBeyond10PM(this.eventEndTime)) {
                //endTimeError = 'End time must be 10:00 PM or earlier.';
            }
        }  
    --- END COMMENTED OUT --- */
        if (startStr && endStr && this.parseTimeToMinutes(endStr) <= this.parseTimeToMinutes(startStr)) orderError = 'End time must be after start time.';
        return { urlError, startTimeError, endTimeError, orderError, classRoomError, remarkError };
    }

    // Getter for faculty placeholder text
    get facultyPlaceholder() {
        return this.isJointSession ? 'Select Faculty (Multiple)' : 'Select Faculty';
    }

    // Getter to determine if department name should be shown
    get showDepartmentName() {
        return this.selectedCourse && this.selectedCourseDepartmentName && 
               this.selectedCourseDepartmentName.trim() !== '';
    }

    disconnectedCallback() {
        if (this.timeIndicatorInterval) {
            clearInterval(this.timeIndicatorInterval);
        }
    }

    initializeTimeSlots() {
        const slots = [];
        for (let hour = TimetableCalendar.DAY_START_HOUR; hour <= TimetableCalendar.DAY_END_HOUR; hour++) {
            const time24 = `${hour.toString().padStart(2, '0')}:00`;
            slots.push({
                key: `slot-${hour}`,
                hour: hour,
                time: time24, // Show in 24-hour format (09:00, 10:00, 13:00, etc.)
                time24: time24
            });
        }
        this.timeSlots = slots;
    }

    formatDateLocal(date) {
        const d = date instanceof Date ? date : new Date(date);
        const year = d.getFullYear();
        const month = String(d.getMonth() + 1).padStart(2, '0');
        const day = String(d.getDate()).padStart(2, '0');
        return `${year}-${month}-${day}`;
    }

    getNextWeekdayDate(dateStr) {
        if (!dateStr) return this.formatDateLocal(new Date());
        const d = new Date(dateStr + 'T12:00:00');
        if (isNaN(d.getTime())) return this.formatDateLocal(new Date());
        d.setDate(d.getDate() + 1);
        return this.formatDateLocal(d);
    }

    normalizeDateString(value) {
        if (!value) return null;
        if (value instanceof Date) return this.formatDateLocal(value);
        const s = String(value);
        // Apex Date is usually "YYYY-MM-DD" but be defensive if we ever get an ISO datetime.
        return s.includes('T') ? s.split('T')[0] : s;
    }

    /** Term bounds from timetable term dropdowns (populated by getTermsForBatchGroup). */
    getTermBoundsForId(termId) {
        if (!termId) {
            return null;
        }
        const id = String(termId);
        const lists = [this.termOptions, this.modalTermOptions];
        for (const opts of lists) {
            const o = (opts || []).find((x) => x && String(x.value) === id);
            if (o && o.termStartDate && o.termEndDate) {
                return { start: String(o.termStartDate), end: String(o.termEndDate) };
            }
        }
        return null;
    }

    /**
     * Ensures session calendar date is within AcademicTerm Term_Start_Date__c .. Term_End_Date__c.
     * Skips if term is not selected or term bounds were not returned (e.g. stale cache).
     */
    validateSessionDateWithinTermBounds(sessionDateStr, termId) {
        const bounds = this.getTermBoundsForId(termId);
        if (!bounds || !bounds.start || !bounds.end) {
            return;
        }
        const d = this.normalizeDateString(sessionDateStr);
        if (!d) {
            return;
        }
        if (d < bounds.start || d > bounds.end) {
            throw new Error(
                `Session date must fall within the selected term (${this.formatDateShortMonthYear(bounds.start)} – ${this.formatDateShortMonthYear(bounds.end)}).`
            );
        }
    }

    /** Date display format: DD-MMM-YYYY (e.g. 20-Apr-2026). */
    formatDateShortMonthYear(value) {
        if (!value) return '';
        const s = String(value).trim();
        const iso = s.includes('T') ? s.split('T')[0] : s;
        const parts = iso.split('-');
        if (parts.length !== 3) return iso;
        const year = parts[0];
        const monthNum = Number(parts[1]);
        const day = parts[2];
        const monthNames = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
        const month = monthNum >= 1 && monthNum <= 12 ? monthNames[monthNum - 1] : parts[1];
        return `${day}-${month}-${year}`;
    }

    normalizeIdString(value) {
        if (!value) return null;
        return String(value);
    }

    /**
     * Resolves the calendar row for a session. Multiple rows share the same Session Id (one per Session_Division__c);
     * pass divisionId from the clicked/hovered tile when present.
     *
     * @param {string} sessionId Session__c Id
     * @param {string} [divisionIdOpt] Division__c Id from data-division-id
     * @returns {object|undefined} Event row or undefined
     */
    findEventRowForSession(sessionId, divisionIdOpt) {
        const list = this.events || [];
        const sid = sessionId != null ? String(sessionId).trim() : '';
        if (!sid) return undefined;
        const div = divisionIdOpt != null && String(divisionIdOpt).trim() !== ''
            ? String(divisionIdOpt).trim()
            : '';
        if (div) {
            const match = list.find(e => e && String(e.id) === sid && this.idsEqual(e.divisionId, div));
            if (match) return match;
        }
        return list.find(e => e && String(e.id) === sid);
    }

    /**
     * Returns true if the value is invalid: negative number, or any value starting with '-'.
     * Empty, valid text (not starting with '-'), zero and positive numbers return false.
     */
    isNegativeFieldValue(value) {
        const trimmed = value != null ? String(value).trim() : '';
        if (trimmed === '') return false;
        if (trimmed.startsWith('-')) return true;
        const n = Number(trimmed);
        return !Number.isNaN(n) && n < 0;
    }

    extractSalesforceId(value) {
        if (!value) return null;
        const idRegex = /[a-zA-Z0-9]{15,18}/;

        if (typeof value === 'string') {
            const m = value.match(idRegex);
            return m ? m[0] : null;
        }

        try {
            const s = String(value);
            const m1 = s.match(idRegex);
            if (m1) return m1[0];
        } catch (e) {
            // ignore
        }

        try {
            const j = JSON.stringify(value);
            const m2 = j && j.match ? j.match(idRegex) : null;
            if (m2) return m2[0];
        } catch (e) {
            // ignore
        }

        return null;
    }

    startTimeIndicatorUpdate() {
        this.timeIndicatorInterval = setInterval(() => {
            // Re-render only the current-time indicator without changing the visible date range
            this.currentTime = new Date();
        }, 60000);
    }

    getDateString(daysOffset) {
        const date = new Date();
        date.setDate(date.getDate() + daysOffset);
        return date.toISOString().split('T')[0];
    }

    // Generate recurring event instances
    generateRecurringEvents() {
        const startOfWeek = this.getStartOfWeek(this.currentDate);
        const endOfWeek = new Date(startOfWeek);
        endOfWeek.setDate(endOfWeek.getDate() + 6);
        
        // This is a simplified version - in production, you'd generate instances within the visible range
        // The actual recurring instances would be generated server-side
    }

    loadCourseActivities() {
        getCourseActivities()
            .then(result => {
                this.courseActivityOptions = Array.isArray(result) ? result : [];
            })
            .catch(error => {
                // Non-blocking: just show a toast if picklist values fail to load
                this.showToastMessage(this.getErrorMessage(error), 'error');
            });
    }

    loadSessionTypes() {
    getSessionTypes()
        .then(result => {
            this.sessionTypeOptions = Array.isArray(result) ? result : [];
        })
        .catch(error => {
            this.showToastMessage(this.getErrorMessage(error), 'error');
        });
  }

    loadSessions(showSpinner = true) {
        // If no division is selected yet, clear events
        if (!this.selectedDivision) {
            this.events = [];
            this.isLoading = false;
            return Promise.resolve();
        }

        // Set loading state - the @wire will handle the actual data loading
        if (showSpinner) {
            this.isLoading = true;
        }
        
        // The @wire decorator will automatically trigger when sessionFilter changes
        // We just need to refresh if we have an existing wired result
        if (this.wiredSessionsResult) {
            return refreshApex(this.wiredSessionsResult);
        }
        
        return Promise.resolve();
    }

    mapSessionToEvent(session) {
        const divisionId = this.extractSalesforceId(session.divisionId) || this.normalizeIdString(session.divisionId);
        const divisionName = session.divisionName ? String(session.divisionName) : null;
        const divisionKey = divisionId && /^[a-zA-Z0-9]{15,18}$/.test(divisionId)
            ? divisionId
            : (divisionName || divisionId);

        const facultyNames = (session.facultyNames && Array.isArray(session.facultyNames)) ? session.facultyNames : [];
        const leadFacultyNames = (session.leadFacultyNames && Array.isArray(session.leadFacultyNames)) ? session.leadFacultyNames : [];
        const supportFacultyNames = (session.supportFacultyNames && Array.isArray(session.supportFacultyNames)) ? session.supportFacultyNames : [];
        const selectedFacultyIds = (session.selectedFacultyIds && Array.isArray(session.selectedFacultyIds))
            ? session.selectedFacultyIds.map(id => String(id))
            : [];
        const leadFacultyId = session.leadFacultyId != null && String(session.leadFacultyId).trim() !== '' ? String(session.leadFacultyId).trim() : null;
        const leadFacultyIds = (session.leadFacultyIds && Array.isArray(session.leadFacultyIds) && session.leadFacultyIds.length > 0)
            ? session.leadFacultyIds.map(id => id != null ? String(id).trim() : '').filter(id => id !== '')
            : (leadFacultyId ? [leadFacultyId] : []);
        const divisionColorPicklist = session.divisionColor != null && String(session.divisionColor).trim() !== ''
            ? String(session.divisionColor).trim()
            : null;
        const storedColor = session.color != null ? String(session.color).trim() : '';
        // Prefer divisionOptions color for this row's division when API divisionColor is missing
        const optionColor = (() => {
            const opts = this.divisionOptions || [];
            const match = opts.find(o => o && this.idsEqual(o.value, divisionId));
            return match && match.divisionColor != null && String(match.divisionColor).trim() !== ''
                ? String(match.divisionColor).trim()
                : null;
        })();
        const eventColorHex = TimetableCalendar.resolveEventDisplayHex(
            divisionColorPicklist || optionColor,
            storedColor
        );
        const rowKey = divisionId
            ? `${session.id}_${divisionId}`
            : String(session.id);
        return {
            id: session.id,
            rowKey,
            title: session.title,
            date: this.normalizeDateString(session.sessionDate),
            startTime: session.startTime,
            endTime: session.endTime,
            location: session.location,
            description: session.description,
            classRoom: session.classRoom,
            remark: session.remark,
            url: session.url,
            color: storedColor || 'blue',
            divisionColorPicklist,
            eventColorHex,
            divisionId: divisionId,
            divisionName: divisionName,
            divisionKey: divisionKey,
            courseId: session.courseId,
            courseName: session.courseName,
            batchWiseCourseId: session.batchWiseCourseId,
            courseActivity: session.courseActivity,
            sessionType: session.sessionType,
            facultyNames: facultyNames,
            leadFacultyNames: leadFacultyNames,
            supportFacultyNames: supportFacultyNames,
            selectedFacultyIds: selectedFacultyIds,
            leadFacultyId: leadFacultyId,
            leadFacultyIds: leadFacultyIds.length > 0 ? leadFacultyIds : [],
            isJointSession: session.isJointSession || false,
            isRecurring: false,
            scheduleType: session.scheduleType || null,
            // Session is completed when its date is before today (same as formula intent).
            isCompleted: this.isSessionCompletedByDate(session.sessionDate),
            // SE-502: Maps studentNames and selectedStudentIds from session DTO to event object
            studentNames: (session.studentNames && Array.isArray(session.studentNames)) ? session.studentNames : [],
            selectedStudentIds: (session.selectedStudentIds && Array.isArray(session.selectedStudentIds)) ? session.selectedStudentIds : [],
            // RSVP read-back (Target 1): cached Google Calendar attendee response counts.
            hasGoogleEvent: session.hasGoogleEvent === true,
            attendeesTotal: session.attendeesTotal != null ? Number(session.attendeesTotal) : 0,
            attendeesAccepted: session.attendeesAccepted != null ? Number(session.attendeesAccepted) : 0,
            attendeesDeclined: session.attendeesDeclined != null ? Number(session.attendeesDeclined) : 0,
            attendeesTentative: session.attendeesTentative != null ? Number(session.attendeesTentative) : 0,
            attendeesAwaiting: session.attendeesAwaiting != null ? Number(session.attendeesAwaiting) : 0
        };
    }

    isSessionCompletedByDate(sessionDate) {
          const normalized = this.normalizeDateString(sessionDate);
        if (!normalized) return false;
        const today = this.formatDateLocal(new Date());
        return normalized < today;
    }

    /** First non-null / non-blank string among arguments; otherwise null. */
    firstNonBlank(...values) {
        for (const v of values) {
            if (v != null && String(v).trim() !== '') {
                return String(v);
            }
        }
        return null;
    }

    /** Label for a combobox value by scanning option arrays in order (modal vs sidebar lists). */
    optionLabelByValue(value, ...optionLists) {
        if (value == null || String(value).trim() === '') {
            return '';
        }
        const str = String(value);
        for (const opts of optionLists) {
            if (!opts || !Array.isArray(opts)) {
                continue;
            }
            const match = opts.find((o) => o && String(o.value) === str);
            if (match && match.label) {
                return String(match.label);
            }
        }
        return '';
    }

    buildSessionPayload(sourceEvent = {}) {
        const fallbackDivisionId = this.isAllDivisionsSelected ? null : this.selectedDivision;
        const divisionId = sourceEvent.divisionId || this.modalDivisionId || fallbackDivisionId;
        const divisionIds = sourceEvent.divisionIds || null; // For multiple divisions
        const sessionDate = sourceEvent.date instanceof Date
            ? sourceEvent.date.toISOString().split('T')[0]
            : sourceEvent.date;
        
        // Check if we have at least one division (either single or multiple)
        if (!divisionId && (!divisionIds || divisionIds.length === 0)) {
            throw new Error('Please select at least one division before saving a session.');
        }
        if (!sourceEvent.title) {
            throw new Error('Session title is required.');
        }
        if (!sessionDate) {
            throw new Error('Session date is required.');
        }
        this.validateSessionDateNotInPast(sessionDate,sourceEvent.startTime);/*1017 */
        if (!sourceEvent.startTime || !sourceEvent.endTime) {
            throw new Error('Start time and end time are required.');
        }

        const termIdForValidation = this.firstNonBlank(sourceEvent.termId, this.modalTerm, this.selectedTerm);
        this.validateSessionDateWithinTermBounds(sessionDate, termIdForValidation);

        const colorSourceDivisionId = this.resolveColorSourceDivisionIdForPayload(sourceEvent, divisionId, divisionIds);

        const payload = {
            sessionId: sourceEvent.id || null,
            sessionName: sourceEvent.title,
            divisionId: divisionId, // Single division (for backward compatibility)
            divisionIds: divisionIds, // Multiple divisions
            programId: this.firstNonBlank(sourceEvent.programId, this.modalProgram, this.selectedProgram),
            batchId: this.firstNonBlank(sourceEvent.batchId, this.modalBatch, this.selectedBatch),
            academicYearId: this.firstNonBlank(sourceEvent.academicYearId, this.selectedBatchGroup),
            termId: this.firstNonBlank(sourceEvent.termId, this.modalTerm, this.selectedTerm),
            batchWiseCourseId: sourceEvent.batchWiseCourseId || null,
            courseId: this.firstNonBlank(sourceEvent.courseId, this.modalCourse, this.selectedCourse),
            sessionDate: sessionDate,
            startTime: this.combineDateAndTime(sessionDate, sourceEvent.startTime),
            endTime: this.combineDateAndTime(sessionDate, sourceEvent.endTime),
            numberOfSessions: sourceEvent.numberOfSessions || 1,
            description: sourceEvent.description || '',
            classRoom: sourceEvent.classRoom !== undefined ? sourceEvent.classRoom : '',
            remark: sourceEvent.remark !== undefined ? sourceEvent.remark : '',
            url: sourceEvent.url !== undefined ? sourceEvent.url : '',
            courseActivity: sourceEvent.courseActivity || null,
            // Session Type picklist (Joint Session / Combined Session). Prefer the value
            // carried on the event/row; fall back to the edit-modal selection.
            sessionType: (sourceEvent.sessionType !== undefined && sourceEvent.sessionType !== null && sourceEvent.sessionType !== '')
                ? sourceEvent.sessionType
                : (this.selectedSessionType || null),
            color: (sourceEvent.color && String(sourceEvent.color).startsWith('#')) ? String(sourceEvent.color) : null,
            colorSourceDivisionId,
            isJointSession: this.isJointSession || false,
            selectedFacultyIds: sourceEvent.selectedFacultyIds !== undefined
                ? this.normalizeFacultyIds(sourceEvent.selectedFacultyIds)
                : this.normalizeFacultyIds(this.selectedFacultyValue),
            selectedStudentIds: sourceEvent.selectedStudentIds || [],
            leadFacultyId: sourceEvent.leadFacultyId != null && sourceEvent.leadFacultyId !== ''
                ? sourceEvent.leadFacultyId
                : null,
            leadFacultyIds: (sourceEvent.leadFacultyIds && sourceEvent.leadFacultyIds.length > 0)
                ? sourceEvent.leadFacultyIds.filter(id => id != null && String(id).trim() !== '')
                : (sourceEvent.leadFacultyId != null && sourceEvent.leadFacultyId !== ''
                    ? [sourceEvent.leadFacultyId]
                    : null),
            proposedConflictContextJson: JSON.stringify(
                this.buildProposedConflictContextForPayload(sourceEvent, divisionId, divisionIds,sourceEvent.selectedAssignmentKeys)
            ),
            ignoreConflicts: sourceEvent.ignoreConflicts === true || this.pendingConflictOverride === true,
            sendNotifications: sourceEvent.sendNotifications !== false
        };
        return payload;
    }
    /*1017 - Start */
    validateSessionDateNotInPast(sessionDate,startTime) {
        if (!sessionDate) return;

        const today = new Date();
        today.setHours(0, 0, 0, 0);

        const selectedDate = new Date(sessionDate);
        selectedDate.setHours(0, 0, 0, 0);

        if (selectedDate < today) {
            throw new Error('Session date cannot be in the past.');
        }
        // Same-day sessions: the date alone can pass even though the chosen start time has already
    // elapsed (e.g. creating a 2 PM session when it's currently 4 PM). Guard against that too.
    if (selectedDate.getTime() === today.getTime() && startTime) {
        const normalizedTime = String(startTime).length === 5 ? `${startTime}:00` : startTime;
        const selectedDateTime = new Date(`${sessionDate}T${normalizedTime}`);
        if (!Number.isNaN(selectedDateTime.getTime()) && selectedDateTime < new Date()) {
            throw new Error('Cannot create session in past.');
        }
    }
    }
    /*1017 - End */
    /**
     * Display-only context for division conflict modal ("Your session"), built from current UI — no server queries.
     */
    buildProposedConflictContextForPayload(sourceEvent = {}, divisionId, divisionIds,assignmentKeys) {
        const courseRaw = this.firstNonBlank(sourceEvent.courseId, this.modalCourse, this.selectedCourse) || '';
        let courseName = '';
        if (courseRaw) {
            const str = String(courseRaw);
            const opts = [...(this.modalCourseOptions || []), ...(this.courseOptions || [])];
            const match = opts.find((o) => o && String(o.value) === str);
            if (match && match.label) {
                courseName = String(match.label);
            } else if (str.includes('|')) {
                courseName = str.split('|')[0] || str;
            } else {
                courseName = str;
            }
        }
       
        const divIds = [];
        if (divisionIds && Array.isArray(divisionIds) && divisionIds.length > 0) {
            divisionIds.forEach((id) => {
                if (id != null && String(id).trim() !== '') divIds.push(String(id));
            });
        } else if (divisionId != null && String(divisionId).trim() !== '') {
            divIds.push(String(divisionId));
        }
        const divisionNames = divIds
            .map((id) => { 
            const allDivisionOptions = [
            ...(this.divisionOptions || []),
            ...(this.modalDivisionOptions || [])];
            const m = allDivisionOptions.find(
            (o) => o && String(o.value).trim() === String(id).trim()
             );
             return m?.label || '';
            })
            .filter(Boolean)
            .join(', ');

        const programId = this.firstNonBlank(sourceEvent.programId, this.modalProgram, this.selectedProgram) || '';
        const batchId = this.firstNonBlank(sourceEvent.batchId, this.modalBatch, this.selectedBatch) || '';
        const batchGroupId = this.firstNonBlank(sourceEvent.academicYearId, this.selectedBatchGroup) || '';
        const termId = this.firstNonBlank(sourceEvent.termId, this.modalTerm, this.selectedTerm) || '';

        let programName = this.optionLabelByValue(programId, this.programOptions, this.modalProgramOptionsWithAll);
        if (!programName) {
            programName = this.selectedProgramLabel || '';
        }
        let batchName = this.optionLabelByValue(batchId, this.batchOptions, this.modalBatchOptionsWithAll);
        if (!batchName) {
            batchName = this.selectedBatchLabel || '';
        }
        let batchGroupName = this.optionLabelByValue(batchGroupId, this.batchGroupOptions);
        if (!batchGroupName) {
            batchGroupName = this.selectedBatchGroupLabel || '';
        }
        let termName = this.optionLabelByValue(termId, this.termOptions, this.modalTermOptionsWithAll);
        if (!termName) {
            termName = this.selectedTermLabel || '';
        }
       let resolvedKeys = [];
if (assignmentKeys != null && Array.isArray(assignmentKeys)) {
    resolvedKeys = assignmentKeys.map(k => String(k).trim()).filter(Boolean);
} else {
    const activeSession = (this.createSessionsList || [])[this.activeCreateSessionIndex];
    const activeKeys = activeSession ? (activeSession.selectedAssignmentKeys || []) : [];
    resolvedKeys = activeKeys.map(k => (k != null ? String(k).trim() : '')).filter(Boolean);
}

const mergedPrograms = resolvedKeys.length > 0
    ? (this.courseAssignments || [])
        .filter(a => {
            const key = a.assignmentKey != null ? String(a.assignmentKey).trim() : '';
            return key && resolvedKeys.includes(key);
        })
        .map(a => {
            const findLabel = (id, ...lists) => {
                if (!id) return '';
                for (const opts of lists) {
                    if (!Array.isArray(opts)) continue;
                    const match = opts.find(o => o && this.idsEqual(String(o.value), String(id)));
                    if (match && match.label) return String(match.label);
                }
                return '';
            };

            return {
                programName:
                    findLabel(a.programId, this.programOptions, this.modalProgramOptionsWithAll)
                    || a.programName
                    || '',

                batchName:
                    findLabel(a.batchId, this.batchOptions, this.modalBatchOptionsWithAll)
                    || a.batchName
                    || '',

                batchGroupName:
                    findLabel(a.batchGroupId, this.batchGroupOptions)
                    || a.batchGroupName
                    || '',

                termName:
                    findLabel(a.termId, this.termOptions, this.modalTermOptionsWithAll)
                    || a.termName
                    || ''
            };
        })
    : [];

console.log('mergedPrograms', JSON.stringify(mergedPrograms));

/* ===== ADD THIS BLOCK ===== */

if (mergedPrograms.length > 0) {
    const programSet = new Set(programName ? [programName] : []);
    const batchSet = new Set(batchName ? [batchName] : []);
    const batchGroupSet = new Set(batchGroupName ? [batchGroupName] : []);
    const termSet = new Set(termName ? [termName] : []);

    mergedPrograms.forEach(mp => {
        if (mp.programName) {
            programSet.add(mp.programName);
        }
        if (mp.batchName) {
            batchSet.add(mp.batchName);
        }
        if (mp.batchGroupName) {
            batchGroupSet.add(mp.batchGroupName);
        }
        if (mp.termName) {
            termSet.add(mp.termName);
        }
    });

    programName = [...programSet].join(', ');
    batchName = [...batchSet].join(', ');
    batchGroupName = [...batchGroupSet].join(', ');
    termName = [...termSet].join(', ');
}

/* ===== END BLOCK ===== */

      return {
            courseName,
            divisionNames,
            programName,
            batchName,
            batchGroupName,
            termName,
            mergedPrograms    // ← ADD THIS LINE
        };
    }
    
    /** Division that owns session tile color: explicit from UI, else single divisionId, else first merged id. */
    resolveColorSourceDivisionIdForPayload(sourceEvent, divisionId, divisionIds) {
        if (sourceEvent && sourceEvent.colorSourceDivisionId != null && String(sourceEvent.colorSourceDivisionId).trim() !== '') {
            return String(sourceEvent.colorSourceDivisionId).trim();
        }
        if (divisionId) return String(divisionId);
        if (divisionIds && divisionIds.length > 0) return String(divisionIds[0]);
        return null;
    }

    /** Edit / single-create modal: color follows the session row division, else payload division, else initiating context. */
    resolveColorSourceDivisionIdForModalSave(editingEvent, payloadSource) {
        if (editingEvent && editingEvent.divisionId) {
            return String(editingEvent.divisionId);
        }
        if (payloadSource && payloadSource.divisionId) {
            return String(payloadSource.divisionId);
        }
        if (this.isAllDivisionsSelected && this.modalDivisionId) {
            return String(this.modalDivisionId);
        }
        const ids = payloadSource && payloadSource.divisionIds;
        if (ids && ids.length > 0) {
            return String(ids[0]);
        }
        return null;
    }

    normalizeFacultyIds(facultyValue) {
        // Normalize faculty value to always be an array for backend
        // Use selectedFacultyValue which is the internal tracking variable
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

    // Add minutes to a time string (HH:mm or H:mm). Returns HH:mm. Used for batch session duration.
    addMinutesToTime(timeStr, minutes) {
        if (!timeStr || minutes == null || minutes < 0) return timeStr || '09:00';
        const parts = String(timeStr).trim().split(':');
        const h = parseInt(parts[0], 10) || 0;
        const m = (parts.length > 1 ? parseInt(parts[1], 10) : 0) || 0;
        const wholeMinutes = Math.round(parseFloat(minutes) || 0);
        const totalMinutes = h * 60 + m + wholeMinutes;
        const endH = Math.floor(totalMinutes / 60) % 24;
        const endM = totalMinutes % 60;
        return `${String(endH).padStart(2, '0')}:${String(endM).padStart(2, '0')}`;
    }

    // Default start/end time for create-session using batch session duration (e.g. 75 min). Fallback 09:00–10:00. Duration rounded to whole minutes.
    getDefaultCreateSessionTimes(afterEndTime = null) {
        const raw = (this.sessionDuration != null && this.sessionDuration > 0) ? this.sessionDuration : 60;
        const duration = Math.round(Number(raw));
        const startTime = afterEndTime || '09:00';
        const endTime = this.addMinutesToTime(startTime, duration);
        return { startTime, endTime };
    }

    persistSessionChanges(eventRecord) {
        let payload;
        try {
            payload = this.buildSessionPayload(eventRecord);
        } catch (error) {
            this.showToastMessage(error.message, 'error');
            return Promise.reject(error);
        }

        this.isSaving = true;
        return saveSession({ requestJson: JSON.stringify(payload) })
            .finally(() => {
                this.isSaving = false;
            });
    }

    ensureDivisionSelected() {
        if (!this.selectedDivision || (this.isAllDivisionsSelected && !this.modalDivisionId)) {
            this.showToastMessage('Please select a division before scheduling sessions', 'error');
            return false;
        }
        return true;
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

    /**
     * Handles save error: if server returned CALENDAR_CONFLICT, FACULTY_CONFLICT or
     * DIVISION_SESSION_CONFLICT with details, opens the unified conflict details modal only
     * (no toast, to avoid misleading duplicate message). Otherwise shows generic error toast.
     *
     * @param error The Apex error.
     * @param pendingEvent The event record whose save was rejected, passed by the drag/drop and
     *        resize paths. A conflict raised there must be re-submitted through that same path on
     *        override — the edit modal is not open, so re-running its save would send stale state.
     */
    handleSaveError(error, pendingEvent) {
        const msg = this.getErrorMessage(error);
        this.pendingOverrideEvent = pendingEvent || null;
        const conflictMode = pendingEvent ? 'persist' : (this.isCreateSessionsMode ? 'create' : 'edit');
        try {
            const data = JSON.parse(msg);
            // Reschedule availability re-check: the faculty is busy in Google at the new time.
            if (data && data.type === 'CALENDAR_CONFLICT' && Array.isArray(data.details) && data.details.length > 0) {
                this.calendarConflicts = data.details;
                this.facultyConflicts = [];
                this.sessionConflicts = [];
                this.showConflictsForBlockedSave(conflictMode);
                return;
            }
            if (data && data.type === 'FACULTY_CONFLICT' && Array.isArray(data.details) && data.details.length > 0) {
                this.facultyConflicts = data.details;
                this.calendarConflicts = [];
                this.showConflictsForBlockedSave(conflictMode);
                return;
            }
            if (data && data.type === 'DIVISION_SESSION_CONFLICT' && Array.isArray(data.details) && data.details.length > 0) {
                this.sessionConflicts = data.details;
                this.calendarConflicts = [];
                this.showConflictsForBlockedSave(conflictMode);
                return;
            }
            // Old server may still throw STUDENT_SESSION_CONFLICT; show friendly message and ask to deploy latest Apex
            if (data && data.type === 'STUDENT_SESSION_CONFLICT') {
                this.showToastMessage(
                    'One or more students have overlapping sessions. Session was not created. Deploy the latest TimetableSessionController to allow creating sessions with a warning.',
                    'error'
                );
                return;
            }
        } catch (_) {
            // not JSON or not conflict payload
        }
        this.showToastMessage(msg, 'error');
    }

    get formattedDateRange() {
        const options = { month: 'short', day: 'numeric' };
        
        if (this.currentView === 'day') {
            // Day view: show single date
            return this.currentDate.toLocaleDateString('en-US', {
                ...options,
                year: 'numeric',
                weekday: 'long'
            });
        } else if (this.currentView === 'week') {
            // Week view: show week range
            const startOfWeek = this.getStartOfWeek(this.currentDate);
            const endOfWeek = new Date(startOfWeek);
            endOfWeek.setDate(endOfWeek.getDate() + 6);
            
            const startStr = startOfWeek.toLocaleDateString('en-US', options);
            const endStr = endOfWeek.toLocaleDateString('en-US', { ...options, year: 'numeric' });
            
            return `${startStr} - ${endStr}`;
        } else if (this.currentView === 'month') {
            // Month view: show month and year
            return this.currentDate.toLocaleDateString('en-US', { 
                month: 'long', 
                year: 'numeric' 
            });
        }
        
        // Default to week view
        const startOfWeek = this.getStartOfWeek(this.currentDate);
        const endOfWeek = new Date(startOfWeek);
        endOfWeek.setDate(endOfWeek.getDate() + 6);
        
        const startStr = startOfWeek.toLocaleDateString('en-US', options);
        const endStr = endOfWeek.toLocaleDateString('en-US', { ...options, year: 'numeric' });
        
        return `${startStr} - ${endStr}`;
    }

    get weekDays() {
        const days = [];
        const today = new Date();
        today.setHours(0, 0, 0, 0);
        
        const dayNames = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
        let startDate;
        let numDays;
        
        if (this.currentView === 'day') {
            // Day view: show only the current date
            startDate = new Date(this.currentDate);
            startDate.setHours(0, 0, 0, 0);
            numDays = 1;
        } else if (this.currentView === 'week') {
            // Week view: show 7 days starting from start of week
            startDate = this.getStartOfWeek(this.currentDate);
            numDays = 7;
        } else if (this.currentView === 'month') {
            // Month view: handled by monthWeeks getter
            return [];
        } else {
            // Default to week view
            startDate = this.getStartOfWeek(this.currentDate);
            numDays = 7;
        }
        
        for (let i = 0; i < numDays; i++) {
            const date = new Date(startDate);
            date.setDate(date.getDate() + i);
            const dateStr = this.formatDateLocal(date);
            const isToday = date.getTime() === today.getTime();
            const isDropTarget = this.dropTargetDay === dateStr;
            
            const rawEvents = this.getEventsForDate(dateStr);
            const layout = this.calculateEventLayout(rawEvents);
            
            const dayEvents = rawEvents.map((event, index) => {
                const formattedEvent = this.formatEventForDisplay(event, dateStr);
                const eventLayout = layout[index];
                
                if (eventLayout && eventLayout.totalColumns > 1) {
                    // Apply layout positioning for overlapping events
                    const leftPercent = eventLayout.left;
                    const widthPercent = eventLayout.width;
                    // Extract top and height from existing style
                    const styleMatch = formattedEvent.style.match(/top:\s*(\d+)px;\s*height:\s*(\d+)px;/);
                    if (styleMatch) {
                        const top = styleMatch[1];
                        const height = styleMatch[2];
                        // Keep division/session tint (background-color / color). Rebuilding only
                        // position styles previously dropped the tint → overlapping tiles looked blue.
                        const tintMatch = formattedEvent.style.match(
                            /background-color:\s*[^;]+;\s*color:\s*[^;]+;?/i
                        );
                        const tintStyle = tintMatch ? ` ${tintMatch[0].trim()}` : '';
                        formattedEvent.style =
                            `top: ${top}px; height: ${height}px; left: ${leftPercent}%; width: calc(${widthPercent}% - 8px);${tintStyle}`;
                    }
                    formattedEvent.layoutColumn = eventLayout.column;
                    formattedEvent.totalColumns = eventLayout.totalColumns;
                    formattedEvent.eventClass += ' overlapping-event';
                }
                // If totalColumns is 1, use default full-width styling
                
                return formattedEvent;
            });
            
            days.push({
                key: dateStr,
                name: dayNames[date.getDay()],
                date: date.getDate(),
                isToday: isToday,
                events: dayEvents,
                headerClass: `day-header ${isToday ? 'today' : ''}`,
                dateClass: `day-date ${isToday ? 'today-date' : ''}`,
                columnClass: `day-column ${isToday ? 'today-column' : ''} ${isDropTarget ? 'drop-target' : ''}`,
                showDropIndicator: isDropTarget && this.dropTargetHour !== null,
                dropIndicatorStyle: this.getDropIndicatorStyle()
            });
        }
        
        return days;
    }

    get monthWeeks() {
        if (this.currentView !== 'month') {
            return [];
        }

        const year = this.currentDate.getFullYear();
        const month = this.currentDate.getMonth();
        const today = new Date();
        today.setHours(0, 0, 0, 0);
        
        const dayNames = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
        const weeks = [];
        
        // Get first day of month
        const firstDay = new Date(year, month, 1);
        const lastDay = new Date(year, month + 1, 0);
        
        // Get first day of the week that contains the first day of month
        const startDate = new Date(firstDay);
        const dayOfWeek = startDate.getDay();
        startDate.setDate(startDate.getDate() - dayOfWeek);
        
        // Get last day of the week that contains the last day of month
        const endDate = new Date(lastDay);
        const lastDayOfWeek = endDate.getDay();
        endDate.setDate(endDate.getDate() + (6 - lastDayOfWeek));
        
        // Generate all days in the month view (including days from previous/next month)
        let currentDate = new Date(startDate);
        let currentWeek = [];
        
        while (currentDate <= endDate) {
            const dateStr = this.formatDateLocal(currentDate);
            const isToday = currentDate.getTime() === today.getTime();
            const isCurrentMonth = currentDate.getMonth() === month;
            const isDropTarget = this.dropTargetDay === dateStr;
            
            // Get events for this day (formatted for month view - simpler format)
            const dayEvents = this.getEventsForDate(dateStr)
                .map(event => this.formatEventForMonthView(event, dateStr));
            const visibleEvents = dayEvents.slice(0, TimetableCalendar.MONTH_VIEW_VISIBLE_EVENT_LIMIT);
            const hiddenEvents = dayEvents.slice(TimetableCalendar.MONTH_VIEW_VISIBLE_EVENT_LIMIT);
            
            currentWeek.push({
                key: dateStr,
                name: dayNames[currentDate.getDay()],
                date: currentDate.getDate(),
                isToday: isToday,
                isCurrentMonth: isCurrentMonth,
                events: dayEvents,
                visibleEvents: visibleEvents,
                hiddenEvents: hiddenEvents,
                hasMoreEvents: hiddenEvents.length > 0,
                moreEventsCount: hiddenEvents.length,
                dateStr: dateStr,
                isDropTarget: isDropTarget,
                monthDayClass: `month-day ${isCurrentMonth ? 'current-month' : 'other-month'} ${isToday ? 'today' : ''}`,
                dateNumberClass: `month-date-number ${isToday ? 'today-date' : ''}`
            });
            
            // If we've filled a week (7 days), add it and start a new week
            if (currentWeek.length === 7) {
                weeks.push({
                    key: `week-${weeks.length}`,
                    days: [...currentWeek]
                });
                currentWeek = [];
            }
            
            currentDate.setDate(currentDate.getDate() + 1);
        }
        
        // Add the last week if it's not complete
        if (currentWeek.length > 0) {
            weeks.push({
                key: `week-${weeks.length}`,
                days: [...currentWeek]
            });
        }
        
        return weeks;
    }

    formatEventForMonthView(event, dateStr) {
        const startTime12 = this.formatTime12(event.startTime);
        const endTime12 = this.formatTime12(event.endTime);
        const divisionDisplayName = this.getDivisionDisplayName(event);
        const primaryFacultyName = this.getPrimaryFacultyText(event);
        
        const hex = event.eventColorHex;
        const tintStyle = hex ? TimetableCalendar.eventTintInlineStyle(hex) : undefined;
        return {
            ...event,
            timeRange: `${startTime12} - ${endTime12}`,
            eventClass: hex ? 'month-event event-division-tint' : `month-event event-${event.color || 'blue'}`,
            eventTileStyle: tintStyle,
            displayTitle: event.title || '',
            divisionDisplayName: divisionDisplayName,
            primaryFacultyName: primaryFacultyName,
            tooltipText: this.getEventTooltipText(event)
        };
    }

    get monthMoreEventsTitle() {
        if (!this.monthMoreEventsDate) return 'More sessions';
        const d = new Date(this.monthMoreEventsDate);
        const label = d.toLocaleDateString(undefined, {
            weekday: 'short',
            month: 'short',
            day: 'numeric',
            year: 'numeric'
        });
        return `Sessions on ${label}`;
    }

    getEventsForDate(dateStr) {
        // Get direct events for this date
        const directEvents = this.events.filter(event => event.date === dateStr);
        
        // Get recurring event instances for this date
        const recurringInstances = this.getRecurringInstancesForDate(dateStr);
        
        const combined = [...directEvents, ...recurringInstances];
        return this.sortEventsByStartTime(combined);
    }

    /** Sort events by start time (then end time) so display order is chronological */
    sortEventsByStartTime(events) {
        if (!events || events.length === 0) return events;
        return [...events].sort((a, b) => {
            const aStart = this.parseTimeToMinutes(a.startTime);
            const bStart = this.parseTimeToMinutes(b.startTime);
            if (aStart !== bStart) return aStart - bStart;
            const aEnd = this.parseTimeToMinutes(a.endTime);
            const bEnd = this.parseTimeToMinutes(b.endTime);
            return (aEnd || 0) - (bEnd || 0);
        });
    }

    parseTimeToMinutes(timeStr) {
        if (!timeStr) return 0;
        const parts = String(timeStr).trim().split(':');
        const h = parseInt(parts[0], 10) || 0;
        const m = parseInt(parts[1], 10) || 0;
        return h * 60 + m;
    }

    /** Strip seconds/ms so values match combobox options (avoids Lightning treating "22:30:00.000" like a native time max check). */
    normalizeToHHmm(timeStr) {
        if (timeStr == null || timeStr === '') return '';
        const raw = String(timeStr).trim();
        if (!raw) return '';
        const parts = raw.split(':');
        const h = parseInt(parts[0], 10);
        const m = parseInt(parts[1], 10);
        if (Number.isNaN(h) || Number.isNaN(m)) return raw;
        return `${String(h).padStart(2, '0')}:${String(m).padStart(2, '0')}`;
    }
    
    /* SE-1015--- COMMENTED OUT: no longer called anywhere after the changes above ---
    /** Max end time: 10 PM = 22:00 (sessions must not extend beyond this). */
   /**  get maxEndTimeMinutes() {
        return TimetableCalendar.DAY_END_HOUR * 60;
    } 

    /** Earliest allowed time: 9 AM (matches calendar grid). 
    get minStartTimeMinutes() {
        return TimetableCalendar.DAY_START_HOUR * 60;
    }

    /** Returns true if time is before 9:00 AM. Empty/invalid treated as valid for "no error". 
    isTimeBefore9AM(timeStr) {
        if (!timeStr || !String(timeStr).trim()) return false;
        const minutes = this.parseTimeToMinutes(String(timeStr).trim());
        return minutes < this.minStartTimeMinutes;
    }

    /** Returns true if time is after 10 PM (22:00). Empty/invalid treated as valid for "no error". 
    isTimeBeyond10PM(timeStr) {
        if (!timeStr || !String(timeStr).trim()) return false;
        const minutes = this.parseTimeToMinutes(String(timeStr).trim());
        return minutes > this.maxEndTimeMinutes;
    } 
    --- END COMMENTED OUT --- SE1015*/

    /** True if any session has start/end beyond 10 PM or end <= start or missing times. */
    get createSessionsHasTimeError() {
        const list = this.createSessionsList || [];
        return list.some(s => {
            const startM = this.parseTimeToMinutes(s.startTime);
            const endM = this.parseTimeToMinutes(s.endTime);
            if (!s.startTime || !s.endTime || !String(s.startTime).trim() || !String(s.endTime).trim()) return true;
         /* --- COMMENTED OUT: 9AM/10PM time-of-day restriction (no longer required) SE-1015---
              if (
              this.isTimeBefore9AM(s.startTime) ||
              this.isTimeBefore9AM(s.endTime) ||
               this.isTimeBeyond10PM(s.startTime) //||
                //this.isTimeBeyond10PM(s.endTime)
            ) {
                return true;
            }
          --- END COMMENTED OUT --- SE-1015 */    
            return endM <= startM;
        });
    }

    /** True when edit modal has end/start time beyond 10 PM or end <= start. */
    get isEditSessionTimeInvalid() {
        if (!this.eventStartTime || !this.eventEndTime) return false;
        const startStr = String(this.eventStartTime).trim();
        const endStr = String(this.eventEndTime).trim();
        if (!startStr || !endStr) return false;
      /* --- COMMENTED OUT: 9AM/10PM time-of-day restriction (no longer required) SE-1015---  
        if (
            this.isTimeBefore9AM(startStr) ||
            this.isTimeBefore9AM(endStr) ||
            this.isTimeBeyond10PM(startStr) ||
            this.isTimeBeyond10PM(endStr)
        ) {
            return true;
        }
          --- END COMMENTED OUT --- SE-1015*/
        return this.parseTimeToMinutes(endStr) <= this.parseTimeToMinutes(startStr);
    }

    getRecurringInstancesForDate(dateStr) {
        const instances = [];
        const targetDate = new Date(dateStr);
        const targetDayOfWeek = targetDate.getDay();
        
        this.events.forEach(event => {
            if (!event.isRecurring || event.date === dateStr) return;
            
            const eventDate = new Date(event.date);
            const endDate = event.recurringEndDate ? new Date(event.recurringEndDate) : null;
            
            // Skip if target date is before event start or after end date
            if (targetDate < eventDate) return;
            if (endDate && targetDate > endDate) return;
            
            let shouldShow = false;
            
            switch (event.recurringType) {
                case 'daily':
                    const daysDiff = Math.floor((targetDate - eventDate) / (1000 * 60 * 60 * 24));
                    shouldShow = daysDiff % event.recurringInterval === 0;
                    break;
                    
                case 'weekly':
                    const weeksDiff = Math.floor((targetDate - eventDate) / (1000 * 60 * 60 * 24 * 7));
                    const selectedDays = event.selectedWeekdays || [eventDate.getDay()];
                    shouldShow = weeksDiff % event.recurringInterval === 0 && selectedDays.includes(targetDayOfWeek);
                    break;
                    
                case 'monthly':
                    const monthsDiff = (targetDate.getFullYear() - eventDate.getFullYear()) * 12 + 
                                       (targetDate.getMonth() - eventDate.getMonth());
                    shouldShow = monthsDiff % event.recurringInterval === 0 && 
                                 targetDate.getDate() === eventDate.getDate();
                    break;
                    
                case 'yearly':
                    const yearsDiff = targetDate.getFullYear() - eventDate.getFullYear();
                    shouldShow = yearsDiff % event.recurringInterval === 0 && 
                                 targetDate.getMonth() === eventDate.getMonth() &&
                                 targetDate.getDate() === eventDate.getDate();
                    break;
            }
            
            if (shouldShow) {
                instances.push({
                    ...event,
                    id: `${event.id}-${dateStr}`,
                    date: dateStr,
                    parentEventId: event.id,
                    isRecurringInstance: true
                });
            }
        });
        
        return instances;
    }

    getDropIndicatorStyle() {
        if (this.dropTargetHour === null) return '';
        const top = (this.dropTargetHour - TimetableCalendar.DAY_START_HOUR) * TimetableCalendar.DAY_VIEW_HOUR_HEIGHT;
        return `top: ${top}px;`;
    }

    // Calculate layout for overlapping events
    calculateEventLayout(events) {
        if (!events || events.length === 0) return [];
        
        // Convert events to time-based format for overlap detection
        const eventTimes = events.map((event, index) => {
            const startHour = parseInt(event.startTime.split(':')[0], 10);
            const startMinute = parseInt(event.startTime.split(':')[1], 10);
            const endHour = parseInt(event.endTime.split(':')[0], 10);
            const endMinute = parseInt(event.endTime.split(':')[1], 10);
            
            const startMinutes = startHour * 60 + startMinute;
            const endMinutes = endHour * 60 + endMinute;
            
            return {
                ...event,
                originalIndex: index,
                startMinutes: startMinutes,
                endMinutes: endMinutes,
                column: -1
            };
        });
        
        // Sort by start time, then by end time
        eventTimes.sort((a, b) => {
            if (a.startMinutes !== b.startMinutes) {
                return a.startMinutes - b.startMinutes;
            }
            return a.endMinutes - b.endMinutes;
        });
        
        // Build overlap graph and assign columns
        const layout = new Array(events.length);
        
        eventTimes.forEach((event, idx) => {
            if (event.column !== -1) return; // Already assigned
            
            // Find all events that overlap with this event
            const overlappingEvents = [event];
            eventTimes.forEach((otherEvent, otherIdx) => {
                if (idx === otherIdx || otherEvent.column !== -1) return;
                
                // Check if events overlap
                const overlaps = !(event.endMinutes <= otherEvent.startMinutes || 
                                 otherEvent.endMinutes <= event.startMinutes);
                
                if (overlaps) {
                    overlappingEvents.push(otherEvent);
                }
            });
            
            // Assign columns to overlapping events
            if (overlappingEvents.length === 1) {
                // Single event - full width
                event.column = 0;
                layout[event.originalIndex] = {
                    column: 0,
                    totalColumns: 1,
                    left: 0,
                    width: 100
                };
            } else {
                // Multiple overlapping events - assign columns
                const columns = [];
                
                overlappingEvents.forEach(evt => {
                    // Find the first column where this event doesn't overlap with existing events
                    let assignedColumn = -1;
                    
                    for (let col = 0; col < columns.length; col++) {
                        const columnEvents = columns[col];
                        // Check if this event doesn't overlap with any event in this column
                        const canFit = columnEvents.every(colEvent => 
                            evt.endMinutes <= colEvent.startMinutes || 
                            colEvent.endMinutes <= evt.startMinutes
                        );
                        
                        if (canFit) {
                            assignedColumn = col;
                            break;
                        }
                    }
                    
                    // If no column available, create a new one
                    if (assignedColumn === -1) {
                        assignedColumn = columns.length;
                        columns.push([]);
                    }
                    
                    columns[assignedColumn].push(evt);
                    evt.column = assignedColumn;
                });
                
                // Calculate positions for each event
                const totalColumns = columns.length;
                overlappingEvents.forEach(evt => {
                    const width = 100 / totalColumns;
                    const left = (evt.column * width);
                    
                    layout[evt.originalIndex] = {
                        column: evt.column,
                        totalColumns: totalColumns,
                        left: left,
                        width: width
                    };
                });
            }
        });
        
        return layout;
    }

    formatEventForDisplay(event, dateStr) {
        const startHour = parseInt(event.startTime.split(':')[0], 10);
        const startMinute = parseInt(event.startTime.split(':')[1], 10);
        const endHour = parseInt(event.endTime.split(':')[0], 10);
        const endMinute = parseInt(event.endTime.split(':')[1], 10);
        
        if (isNaN(startHour) || isNaN(startMinute) || isNaN(endHour) || isNaN(endMinute)) {
            console.warn('Invalid time format for event:', event.startTime, event.endTime);
            const hx = event.eventColorHex;
            return {
                ...event,
                style: 'display: none;',
                eventClass: hx ? 'calendar-event event-division-tint' : 'calendar-event event-' + (event.color || 'blue'),
                timeRange: '—',
                tooltipText: ''
            };
        }
        
        // Calculate offset in minutes from DAY_START_HOUR
        const startOffset = (startHour - TimetableCalendar.DAY_START_HOUR) * 60 + startMinute;
        const duration = (endHour - startHour) * 60 + (endMinute - startMinute);
        const pxPerMin = TimetableCalendar.DAY_VIEW_HOUR_HEIGHT / 60;
        // Position events: scale by pxPerMin so rows fit time/title/course/room (4 lines)
        const top = startOffset * pxPerMin;
        const height = Math.max(duration * pxPerMin, 88);
        
        const startTime12 = this.formatTime12(event.startTime);
        const endTime12 = this.formatTime12(event.endTime);
        
        const isDragged =
            this.draggedEventId === event.id &&
            (!this.draggedEventDivisionId || this.idsEqual(event.divisionId, this.draggedEventDivisionId));
        
        let recurringLabel = '';
        if (event.isRecurring) {
            const typeLabels = {
                daily: 'Daily',
                weekly: 'Weekly',
                monthly: 'Monthly',
                yearly: 'Yearly'
            };
            recurringLabel = `Repeats ${typeLabels[event.recurringType] || 'Weekly'}`;
            if (event.recurringInterval > 1) {
                recurringLabel = `Every ${event.recurringInterval} ${event.recurringType.replace('ly', 's')}`;
            }
        }
        
        const hx = event.eventColorHex;
        const bg = hx ? TimetableCalendar.eventTintInlineStyle(hx) : '';
        return {
            ...event,
            style: `top: ${top}px; height: ${height}px;${bg ? ` ${bg}` : ''}`,
            eventClass: `calendar-event ${hx ? 'event-division-tint' : `event-${event.color || 'blue'}`} ${isDragged ? 'dragging' : ''}`,
            timeRange: `${startTime12} - ${endTime12}`,
            divisionDisplayName: this.getDivisionDisplayName(event),
            primaryFacultyName: this.getPrimaryFacultyText(event),
            recurringLabel: recurringLabel,
            tooltipText: this.getEventTooltipText(event)
        };
    }

    formatTime12(time24) {
        const [hours, minutes] = time24.split(':');
        const hour = parseInt(hours, 10);
        const hour12 = hour > 12 ? hour - 12 : hour === 0 ? 12 : hour;
        const ampm = hour >= 12 ? 'PM' : 'AM';
        return `${hour12}:${minutes} ${ampm}`;
    }

    getDivisionDisplayName(event) {
        if (event && event.divisionName && String(event.divisionName).trim()) {
            return String(event.divisionName).trim();
        }
        if (this.selectedDivisionLabel && String(this.selectedDivisionLabel).trim()) {
            return String(this.selectedDivisionLabel).trim();
        }
        return '—';
    }

    getPrimaryFacultyText(event) {
        const leadNames = (event && Array.isArray(event.leadFacultyNames)) ? event.leadFacultyNames : [];
        const cleanLead = leadNames.map(n => (n != null ? String(n).trim() : '')).filter(Boolean);
        if (cleanLead.length > 0) {
            return cleanLead.join(', ');
        }
        return '—';
    }

    // Session details for hover tooltip: Division first, then Course, Faculty, Support Faculty, Activity Type
    getEventTooltipText(event) {
        if (!event) return '';
        const division = (event.divisionName && String(event.divisionName).trim()) || '—';
        const course = (event.courseName && String(event.courseName).trim()) || '—';
        const faculty = (event.leadFacultyNames && Array.isArray(event.leadFacultyNames) && event.leadFacultyNames.length > 0)
            ? event.leadFacultyNames.join(', ')
            : '—';
        const supportFaculty = (event.supportFacultyNames && Array.isArray(event.supportFacultyNames) && event.supportFacultyNames.length > 0)
            ? event.supportFacultyNames.join(', ')
            : '—';
        const activity = (event.courseActivity && String(event.courseActivity).trim()) || '—';
        let text = `Division: ${division}\nCourse: ${course}\nFaculty: ${faculty}\nSupport Faculty: ${supportFaculty}\nActivity Type: ${activity}`;
        // RSVP read-back (Target 1): show attendee responses for sessions pushed to Google.
        if (event.hasGoogleEvent) {
            text += `\nResponses: ${event.attendeesAccepted || 0} yes, ${event.attendeesDeclined || 0} no, ${event.attendeesTentative || 0} maybe, ${event.attendeesAwaiting || 0} awaiting`;
        }
        return text;
    }

    /**
     * RSVP read-back (Target 1): fetch the latest Google Calendar attendee responses for a
     * session when its detail modal is opened, so the panel shows near real-time data.
     * Falls back silently to the cached roll-up counts if the live fetch fails.
     */
    loadAttendeeSummary(sessionId, selectedEvent) {
        this.attendeeSummary = null;
        this.attendeeMessage = '';
        // Only sessions that were pushed to Google Calendar have attendees to read back.
        if (!selectedEvent || selectedEvent.hasGoogleEvent !== true) {
            this.attendeeLoading = false;
            return;
        }
        this.attendeeLoading = true;
        refreshAttendees({ sessionId })
            .then((result) => {
                // Guard against a stale response if the user opened another session meanwhile.
                if (this.selectedEventId !== sessionId) {
                    return;
                }
                this.attendeeSummary = result;
                this.attendeeMessage = (result && result.message) ? result.message : '';
            })
            .catch((error) => {
                if (this.selectedEventId !== sessionId) {
                    return;
                }
                // eslint-disable-next-line no-console
                console.error('refreshAttendees failed', error);
                this.attendeeMessage = 'Could not load live responses; showing last synced data.';
            })
            .finally(() => {
                if (this.selectedEventId === sessionId) {
                    this.attendeeLoading = false;
                }
            });
    }

    /** RSVP read-back: whether to render the attendee panel in the edit modal. */
    get showAttendeePanel() {
        return this.attendeeLoading || this.attendeeSummary != null || (this.attendeeMessage && this.attendeeMessage.length > 0);
    }

    /** RSVP read-back: attendee rows decorated with a CSS class per response status. */
    get attendeeRows() {
        if (!this.attendeeSummary || !Array.isArray(this.attendeeSummary.attendees)) {
            return [];
        }
        return this.attendeeSummary.attendees.map((a, i) => {
            const status = a.status || 'No Response';
            let statusClass = 'rsvp-pill rsvp-awaiting';
            if (status === 'Accepted') {
                statusClass = 'rsvp-pill rsvp-accepted';
            } else if (status === 'Declined') {
                statusClass = 'rsvp-pill rsvp-declined';
            } else if (status === 'Tentative') {
                statusClass = 'rsvp-pill rsvp-tentative';
            }
            return {
                key: `${a.email || 'attendee'}-${i}`,
                email: a.email,
                status,
                statusClass,
                type: a.type,
                isOrganizer: a.isOrganizer === true
            };
        });
    }

    /**
     * Time options: 15-min intervals 9:00–22:00, 12h labels, value HH:mm.
     * Merges extra values (e.g. current start/end) when not on grid, if not past 10 PM.
     * Used by edit modal and create-session row (avoids native time input duplicate validation messages).
     */
    buildTimeSlotOptions(...extraTimeStrings) {
        const valueSet = new Set();
        const options = [];
        for (let h = TimetableCalendar.DAY_START_HOUR; h <= TimetableCalendar.DAY_END_HOUR; h++) {
            const minutesList = (h === TimetableCalendar.DAY_END_HOUR) ? [0] : [0, 15, 30, 45];
            for (const min of minutesList) {
                const value = `${String(h).padStart(2, '0')}:${String(min).padStart(2, '0')}`;
                valueSet.add(value);
                options.push({ label: this.formatTime12(value).toLowerCase(), value });
            }
        }
        for (const time of extraTimeStrings) {
            if (time == null) continue;
            const t = this.normalizeToHHmm(time);
            if (!t || valueSet.has(t)) continue;
             /* --- COMMENTED OUT: old guard blocked saved times after 10 PM SE-1015----
             if (!this.isTimeBeyond10PM(t)) {
                valueSet.add(t);
                options.push({ label: this.formatTime12(t).toLowerCase(), value: t });
             }
             --- END COMMENTED OUT --- */
            valueSet.add(t);
            options.push({ label: this.formatTime12(t).toLowerCase(), value: t });
            }
            options.sort((a, b) => a.value.localeCompare(b.value));
            return options;
        }

    // Time options for edit session modal
    get editSessionTimeOptions() {
        return this.buildTimeSlotOptions(this.eventStartTime, this.eventEndTime);
    }

    /**
     * First day of the visible week (Monday 00:00 local). Used for week view headers,
     * session date range, and navigation.
     */
    getStartOfWeek(date) {
        const d = new Date(date);
        d.setHours(0, 0, 0, 0);
        const day = d.getDay(); // 0 Sun … 6 Sat
        const daysSinceMonday = (day + 6) % 7; // Mon → 0, Sun → 6
        d.setDate(d.getDate() - daysSinceMonday);
        return d;
    }

    get showCurrentTime() {
        const now = this.currentTime || new Date();
        const startOfWeek = this.getStartOfWeek(this.currentDate);
        const endOfWeek = new Date(startOfWeek);
        endOfWeek.setDate(endOfWeek.getDate() + 7);
        
        return now >= startOfWeek && now < endOfWeek;
    }

    get currentTimeStyle() {
        const now = this.currentTime || new Date();
        const hours = now.getHours();
        const minutes = now.getMinutes();
        
        if (hours < TimetableCalendar.DAY_START_HOUR || hours > TimetableCalendar.DAY_END_HOUR) return 'display: none;';
        
        const pxPerMin = TimetableCalendar.DAY_VIEW_HOUR_HEIGHT / 60;
        const top = ((hours - TimetableCalendar.DAY_START_HOUR) * 60 + minutes) * pxPerMin;
        const dayOfWeek = now.getDay();
        // Week grid columns are Mon–Sun; JS Sunday=0 must map to column 6.
        const columnIndex =
            this.currentView === 'day' ? 0 : (dayOfWeek + 6) % 7;

        return `top: ${top}px; left: calc(60px + ${columnIndex} * ((100% - 60px) / 7));`;
    }

    get dayViewClass() {
        return `view-btn ${this.currentView === 'day' ? 'active' : ''}`;
    }

    get weekViewClass() {
        return `view-btn ${this.currentView === 'week' ? 'active' : ''}`;
    }

    get monthViewClass() {
        return `view-btn ${this.currentView === 'month' ? 'active' : ''}`;
    }

    get isWeekView() {
        return this.currentView === 'week';
    }

    get isDayView() {
        return this.currentView === 'day';
    }

    get dayViewLabel() {
        return this.isAllDivisionsSelected ? 'Day (Division)' : 'Day';
    }

    get isMonthView() {
        return this.currentView === 'month';
    }

    get dayNames() {
        return ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
    }

    // ---------- All Divisions: Week (Divisions rows, Days columns) ----------
    get weekMatrixDays() {
        const startOfWeek = this.getStartOfWeek(this.currentDate);
        const today = new Date();
        today.setHours(0, 0, 0, 0);
        const dayNames = ['SUN', 'MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT'];
        const days = [];
        for (let i = 0; i < 7; i++) {
            const d = new Date(startOfWeek);
            d.setDate(d.getDate() + i);
            d.setHours(0, 0, 0, 0);
            const dateStr = this.formatDateLocal(d);
            const isToday = d.getTime() === today.getTime();
            days.push({
                key: dateStr,
                name: dayNames[d.getDay()],
                date: d.getDate(),
                headerClass: `div-week-day-header ${isToday ? 'today' : ''}`
            });
        }
        return days;
    }

    get divisionsForMatrix() {
        const opts = (this.divisionOptions || [])
            .filter(o => o && o.value && o.value !== TimetableCalendar.ALL_DIVISIONS_VALUE)
            .map(o => ({
                value: String(o.value),
                label: o.label ? String(o.label) : String(o.value),
                divisionColor: (o.divisionColor && String(o.divisionColor).trim()) ? String(o.divisionColor).trim().toLowerCase() : null
            }));

        if (!this.isAllDivisionsSelected) {
            return opts.filter(o => o.value === String(this.selectedDivision));
        }

        // All Divisions: show only divisions for the selected term (from divisionOptions). Do not fall back to
        // divisions from events, so when the term has no divisions we show no rows (not batch/batch-group divisions).
        if (opts.length > 0) {
            return opts.sort((a, b) => (a.label || '').localeCompare(b.label || ''));
        }

        // Term has no divisions (or options not loaded): return empty so we don't show batch-level divisions A–H.
        return [];
    }

    /** Hour slots for week view left column: 9 AM to 10 PM (22:00). Label in 24h (09:00, 10:00, ...). */
    get weekViewHourSlots() {
        const slots = [];
        for (let h = TimetableCalendar.DAY_START_HOUR; h <= TimetableCalendar.DAY_END_HOUR; h++) {
            const label24 = `${String(h).padStart(2, '0')}:00`;
            slots.push({ hour: h, key: `h-${h}`, label: label24 });
        }
        return slots;
    }

    /** True if event's start time falls in the given hour (24h). */
    eventStartsInHour(event, hour) {
        if (!event || !event.startTime) return false;
        const parts = String(event.startTime).trim().split(':');
        const h = parseInt(parts[0], 10);
        return Number.isInteger(h) && h === hour;
    }

    /** Event duration in minutes from startTime/endTime (e.g. "09:00", "12:00" -> 180). */
    getEventDurationMinutes(event) {
        if (!event) return 0;
        const startM = this.parseTimeToMinutes(event.startTime);
        const endM = this.parseTimeToMinutes(event.endTime);
        return Math.max(0, (endM || 0) - (startM || 0));
    }

    /** Number of grid rows this event should span (row height = 60 min). */
    getEventSpanRows(event, rowHeightMinutes = 60) {
        const duration = this.getEventDurationMinutes(event);
        return Math.max(1, Math.ceil(duration / rowHeightMinutes));
    }

    /** Assign lane index to each event so overlapping events get different lanes. Returns [{ event, laneIndex, numLanes }]. */
    assignLanesForCellEvents(events) {
        if (!events || events.length === 0) return [];
        const withMinutes = events.map(e => ({
            event: e,
            startM: this.parseTimeToMinutes(e.startTime),
            endM: this.parseTimeToMinutes(e.endTime)
        }));
        const lanes = [];
        const result = [];
        for (const { event, startM, endM } of withMinutes) {
            let lane = 0;
            while (lane < lanes.length) {
                const hasOverlap = lanes[lane].some(placed => startM < placed.endM && endM > placed.startM);
                if (!hasOverlap) break;
                lane++;
            }
            if (lane >= lanes.length) lanes.push([]);
            lanes[lane].push({ startM, endM });
            result.push({ event, laneIndex: lane, numLanes: 0 });
        }
        const numLanes = lanes.length;
        result.forEach(r => { r.numLanes = numLanes; });
        return result;
    }

    /** Week view All Divisions: one row per time slot, no division column; each cell has events from all divisions. */
    get divisionWeekRows() {
        if (!this.isAllDivisionsSelected) {
            return [];
        }
        const days = this.weekMatrixDays;
        const events = Array.isArray(this.events) ? this.events : [];
        const hourSlots = this.weekViewHourSlots;

        // Lane width/position per day + start hour only (events that begin in this cell). Using all-day events
        // made numLanes the max concurrent sessions for the whole day, so a single session in a later hour
        // still got 1/N width from an earlier busy hour.
        const laneByDayHourAndEventKey = {};
        days.forEach(day => {
            hourSlots.forEach(hourObj => {
                const cellStartEvents = events.filter(
                    e => e.date === day.key && this.eventStartsInHour(e, hourObj.hour)
                );
                const withLanes = this.assignLanesForCellEvents(cellStartEvents);
                const hourKey = `${day.key}__h${hourObj.hour}`;
                laneByDayHourAndEventKey[hourKey] = {};
                withLanes.forEach(({ event: e, laneIndex, numLanes }) => {
                    const lk = e && e.rowKey ? e.rowKey : (e && e.id ? e.id : null);
                    if (lk) laneByDayHourAndEventKey[hourKey][lk] = { laneIndex, numLanes };
                });
            });
        });

        const rows = [];
        hourSlots.forEach((hourObj, hourIndex) => {
            const rowIndex = hourIndex + 1; // 1-based for CSS grid
            const rowHeightPx = 50;
            const cells = days.map((day, dayIndex) => {
                const matching = events.filter(e =>
                    e.date === day.key &&
                    this.eventStartsInHour(e, hourObj.hour)
                );
                const sorted = this.sortEventsByStartTime(matching);
                const hourKey = `${day.key}__h${hourObj.hour}`;
                const cellEvents = sorted.map(e => {
                    const laneKey = e.rowKey || e.id;
                    const laneInfo =
                        (laneByDayHourAndEventKey[hourKey] && laneByDayHourAndEventKey[hourKey][laneKey]) ||
                        { laneIndex: 0, numLanes: 1 };
                    const div = this.getDivisionForEvent(e);
                    const startMinutes = this.parseTimeToMinutes(e.startTime);
                    const endMinutes = this.parseTimeToMinutes(e.endTime);
                    const hourStartMinutes = hourObj.hour * 60;
                    const offsetMinutes = Math.max(0, startMinutes - hourStartMinutes);
                    const durationMinutes = Math.max(1, endMinutes - startMinutes);
                    const topOffsetPx = (offsetMinutes / 60) * rowHeightPx;
                    const explicitHeightPx = (durationMinutes / 60) * rowHeightPx;
                    const spanRows = Math.max(1, Math.ceil((offsetMinutes + durationMinutes) / 60));
                    return this.formatEventForDivisionCell(e, div || { value: e.divisionId, label: e.divisionName || 'Unknown', divisionColor: null }, {
                        spanRows,
                        laneIndex: laneInfo.laneIndex,
                        numLanes: laneInfo.numLanes,
                        rowHeightPx,
                        topOffsetPx,
                        explicitHeightPx
                    });
                });
                const hasSpanningEvent = matching.some(e => this.getEventSpanRows(e, 60) > 1);
                const hasAnyEvent = matching.length > 0;
                const cellClass = `divisions-week-cell divisions-week-cell-clickable${(hasSpanningEvent || hasAnyEvent) ? ' divisions-week-cell-has-spanning-event' : ''}`;
                return {
                    key: `t-${hourObj.hour}-${day.key}`,
                    dateStr: day.key,
                    events: cellEvents,
                    cellGridStyle: `grid-column: ${2 + dayIndex}; grid-row: ${rowIndex};`,
                    cellClass
                };
            });
            rows.push({
                key: `hour-${hourObj.hour}`,
                hour: hourObj.hour,
                timeLabel: hourObj.label,
                rowIndex,
                cells,
                timeGridStyle: `grid-column: 1; grid-row: ${rowIndex};`
            });
        });
        return rows;
    }

    /** No division name blocks: left column is timings only. */
    get divisionWeekNameBlocks() {
        return [];
    }

    get divisionsWeekGridBodyStyle() {
        if (!this.isAllDivisionsSelected || !this.divisionWeekRows.length) {
            return '';
        }
        const totalRows = this.divisionWeekRows.length;
        const rowHeightPx = 50;
        const totalHeightPx = totalRows * rowHeightPx;
        return `--divisions-week-rows: ${totalRows}; --divisions-week-row-height: ${rowHeightPx}px; grid-template-rows: repeat(${totalRows}, ${rowHeightPx}px); grid-auto-rows: ${rowHeightPx}px; grid-template-columns: var(--divisions-week-columns); min-height: ${totalHeightPx}px;`;
    }

    /** Week view grouped by division: division name shown once, with time rows to the right. */
    get divisionWeekRowGroups() {
        if (!this.isAllDivisionsSelected) {
            return [];
        }
        const flatRows = this.divisionWeekRows;
        const hourCount = this.weekViewHourSlots.length;
        const groups = [];
        for (let i = 0; i < flatRows.length; i += hourCount) {
            const chunk = flatRows.slice(i, i + hourCount);
            if (chunk.length === 0) continue;
            const first = chunk[0];
            const rowsWithFirst = chunk.map((row, idx) => ({
                ...row,
                isFirst: idx === 0
            }));
            groups.push({
                key: first.divisionId,
                divisionId: first.divisionId,
                divisionName: first.divisionName,
                rowCount: chunk.length,
                rows: rowsWithFirst
            });
        }
        return groups;
    }

    formatEventForDivisionCell(event, division, opts = {}) {
        const startTime12 = this.formatTime12(event.startTime);
        const divisionName = (division && division.label) ? String(division.label) : (event.divisionName || 'Unknown');
        const divisionLabel = divisionName;
        const primaryFacultyName = this.getPrimaryFacultyText(event);
        const hex = TimetableCalendar.divisionPicklistToHex(division && division.divisionColor)
            || event.eventColorHex;
        const { spanRows = 1, laneIndex = 0, numLanes = 1, rowHeightPx = 50, topOffsetPx = 0, explicitHeightPx = null } = opts;
        const heightPx = explicitHeightPx != null ? explicitHeightPx : (spanRows * rowHeightPx);
        const widthPct = numLanes > 0 ? (100 / numLanes) : 100;
        const leftPct = numLanes > 0 ? (laneIndex * (100 / numLanes)) : 0;
        const bg = hex ? TimetableCalendar.eventTintInlineStyle(hex) : '';
        const eventStyle = `position:absolute; top:${topOffsetPx}px; left:${leftPct}%; width:${widthPct}%; height:${heightPx}px; box-sizing:border-box; overflow:hidden;${bg ? ` ${bg}` : ''}`;
        const token = String(event.color || 'blue').toLowerCase();
        const safeToken = token === 'gray' ? 'grey' : token;
        const divIdForDom = (division && division.value) ? division.value : event.divisionId;
        return {
            key: event.rowKey || `${event.id}-${division ? division.value : ''}`,
            id: event.id,
            divisionId: divIdForDom,
            title: event.title,
            divisionLabel: divisionLabel,
            courseName: event.courseName || '',
            primaryFacultyName: primaryFacultyName,
            timeLabel: startTime12,
            eventClass: `division-cell-event ${hex ? 'event-division-tint' : `event-${safeToken}`}`,
            eventStyle: eventStyle,
            tooltipText: this.getEventTooltipText(event)
        };
    }

    doesEventMatchDivision(event, division) {
        if (!event || !division) return false;
        const optValue = division.value ? String(division.value) : '';
        const optLabel = division.label ? String(division.label) : '';
        const evId = event.divisionId ? String(event.divisionId) : '';
        const evName = event.divisionName ? String(event.divisionName) : '';
        const evKey = event.divisionKey ? String(event.divisionKey) : (evId || evName);
        const eventHasId = !!(evId || (evKey && /^[a-zA-Z0-9]{15,18}$/.test(evKey)));

        // When both have Ids, require Id match so two divisions with same name (e.g. two "A"s) don't match each other's events.
        if (optValue && eventHasId) {
            if (optValue === evId || optValue === evKey) return true;
            return false;
        }
        // Some orgs use option.value as Division Id, others as Division Name.
        return (optValue && evKey && optValue === evKey) ||
            (optValue && evId && optValue === evId) ||
            (optValue && evName && optValue === evName) ||
            (optLabel && evName && optLabel === evName) ||
            (optLabel && evKey && optLabel === evKey);
    }

    /** Find division option for an event. Prefer Id match so same-named divisions (e.g. two "A"s) get correct color. */
    getDivisionForEvent(event) {
        if (!event || !this.divisionsForMatrix || this.divisionsForMatrix.length === 0) return null;
        const evId = event.divisionId ? String(event.divisionId) : '';
        const evKey = event.divisionKey ? String(event.divisionKey) : evId;
        const byId = this.divisionsForMatrix.find(d => d.value && (d.value === evId || d.value === evKey));
        if (byId) return byId;
        return this.divisionsForMatrix.find(d => this.doesEventMatchDivision(event, d)) || null;
    }

    // ---------- All Divisions: Day (Divisions rows, Time columns) ----------
    get divisionDayHours() {
        const hours = [];
        for (let hour = TimetableCalendar.DAY_START_HOUR; hour <= TimetableCalendar.DAY_END_HOUR; hour++) {
            hours.push({
                key: `h-${hour}`,
                hour,
                label: `${hour}:00`
            });
        }
        return hours;
    }

    get dayDivisionDateStr() {
        return this.formatDateLocal(this.currentDate);
    }

    get divisionsDayWrapperStyle() {
        const n = (this.divisionDayTimelineRows || []).length;
        const hoursCount = (TimetableCalendar.DAY_END_HOUR - TimetableCalendar.DAY_START_HOUR + 1);
        const colWidthPx = 170;
        const minWidthPx = Math.max(1, hoursCount) * colWidthPx;
        return `--divisions-row-count: ${Math.max(1, n)}; --divisions-hour-count: ${Math.max(1, hoursCount)}; --divisions-hours-min-width: ${minWidthPx}px;`;
    }

    get timeGridWrapperStyle() {
        const hoursCount = (TimetableCalendar.DAY_END_HOUR - TimetableCalendar.DAY_START_HOUR + 1);
        const minHeightPx = Math.max(1, hoursCount) * TimetableCalendar.DAY_VIEW_HOUR_HEIGHT;
        return `--time-grid-min-height: ${minHeightPx}px;`;
    }

    get divisionDayTimelineRows() {
        if (!this.isAllDivisionsSelected || !this.isDayView) {
            return [];
        }

        const dateStr = this.dayDivisionDateStr;
        const events = (Array.isArray(this.events) ? this.events : []).filter(e => e.date === dateStr);

        const hourStart = TimetableCalendar.DAY_START_HOUR;
        const hourEnd = TimetableCalendar.DAY_END_HOUR;
        const hourWidth = 130; // px per hour - wider so time/title/course fit without truncation
        const baseStartMinutes = hourStart * 60;
        const totalWidth = (hourEnd - hourStart + 1) * hourWidth;
        const eventHeight = 80;
        const laneGap = 6;

        return this.divisionsForMatrix.map(div => {
            const divKey = String(div.value);
            const divEvents = events.filter(e => this.doesEventMatchDivision(e, div));

            const positioned = this.positionEventsOnTimeline(divEvents, {
                baseStartMinutes,
                totalWidth,
                hourWidth,
                eventHeight,
                laneGap,
                hourStart,
                hourEnd,
                divisionColor: div.divisionColor || null,
                divisionName: div.label || ''
            });

            return {
                divisionId: divKey,
                divisionName: div.label,
                rowStyle: `height: ${Math.max(80, positioned.rowHeight)}px;`,
                events: positioned.events
            };
        });
    }

    _isSyncingDivisionsDayScroll = false;

    handleDivisionsDayScrollAreaScroll(event) {
        if (this._isSyncingDivisionsDayScroll) return;
        const scrollTop = event && event.target ? event.target.scrollTop : 0;
        const fixedCol = this.template.querySelector('.divisions-day-fixed-col');
        if (!fixedCol) return;
        this._isSyncingDivisionsDayScroll = true;
        fixedCol.scrollTop = scrollTop;
        this._isSyncingDivisionsDayScroll = false;
    }

    handleDivisionsDayFixedColScroll(event) {
        if (this._isSyncingDivisionsDayScroll) return;
        const scrollTop = event && event.target ? event.target.scrollTop : 0;
        const scrollArea = this.template.querySelector('.divisions-day-scroll-area');
        if (!scrollArea) return;
        this._isSyncingDivisionsDayScroll = true;
        scrollArea.scrollTop = scrollTop;
        this._isSyncingDivisionsDayScroll = false;
    }

    positionEventsOnTimeline(events, cfg) {
        const parsed = (events || [])
            .map(e => {
                const [sh, sm] = (e.startTime || '00:00').split(':').map(n => parseInt(n, 10));
                const [eh, em] = (e.endTime || '00:00').split(':').map(n => parseInt(n, 10));
                const startMinutes = (sh * 60) + (sm || 0);
                const endMinutes = (eh * 60) + (em || 0);
                return { ...e, startMinutes, endMinutes };
            })
            .filter(e => Number.isFinite(e.startMinutes) && Number.isFinite(e.endMinutes) && e.endMinutes > e.startMinutes)
            .sort((a, b) => a.startMinutes - b.startMinutes || a.endMinutes - b.endMinutes);

        // Greedy lane assignment
        const laneEnds = [];
        const placed = [];
        for (const e of parsed) {
            let lane = laneEnds.findIndex(end => e.startMinutes >= end);
            if (lane === -1) {
                lane = laneEnds.length;
                laneEnds.push(e.endMinutes);
            } else {
                laneEnds[lane] = e.endMinutes;
            }
            placed.push({ ...e, lane });
        }

        const totalLanes = Math.max(1, laneEnds.length);
        const rowHeight = (totalLanes * (cfg.eventHeight + cfg.laneGap)) + 12;

        // Use percentage for left/width so tile always matches hour column width regardless of timeline pixel size
        const totalMinutes = ((cfg.hourEnd - cfg.hourStart + 1) * 60);
        const timelineEvents = placed.map(e => {
            const startOffsetMinutes = e.startMinutes - cfg.baseStartMinutes;
            const durationMinutes = e.endMinutes - e.startMinutes;
            const leftPercent = Math.max(0, (startOffsetMinutes / totalMinutes) * 100);
            const widthPercent = Math.min(100 - leftPercent, (durationMinutes / totalMinutes) * 100);
            const topPx = 6 + (e.lane * (cfg.eventHeight + cfg.laneGap));

            const divisionName = (cfg.divisionName && String(cfg.divisionName).trim()) || (e.divisionName || '');
            const divisionLabel = divisionName ? `Division - ${divisionName}` : '';
            const primaryFacultyName = this.getPrimaryFacultyText(e);
            const hex = TimetableCalendar.divisionPicklistToHex(cfg.divisionColor) || e.eventColorHex;
            const tok = String(e.color || 'blue').toLowerCase();
            const safeTok = tok === 'gray' ? 'grey' : tok;
            const bg = hex ? TimetableCalendar.eventTintInlineStyle(hex) : '';
            return {
                key: e.rowKey || `${e.id}-${e.divisionId}`,
                id: e.id,
                divisionId: e.divisionId,
                title: e.title,
                divisionLabel: divisionLabel,
                courseName: e.courseName || '',
                primaryFacultyName: primaryFacultyName,
                timeLabel: `${this.formatTime12(e.startTime)} – ${this.formatTime12(e.endTime)}`,
                eventClass: `division-timeline-event ${hex ? 'event-division-tint' : `event-${safeTok}`}`,
                style: `left:${leftPercent}%; width:${widthPercent}%; top:${topPx}px; height:${cfg.eventHeight}px;${bg ? ` ${bg}` : ''}`,
                tooltipText: this.getEventTooltipText(e)
            };
        });

        return { rowHeight, events: timelineEvents };
    }

    get showNoSessionsMessage() {
        // Show message when filters are applied but no events found
        // TODO: Update this logic based on actual event data
        return this.events.length === 0 && (this.selectedProgram || this.selectedBatch || this.selectedDivision);
    }

    get semesterInfo() {
        // TODO: Get semester info based on selected filters
        // For now, return a placeholder
        if (this.selectedBatchGroup || this.selectedTerm) {
            return '';
        }
        return null;
    }

    get modalTitle() {
        return this.isEditMode ? 'Edit Session' : 'Add New Session';
    }

    get toastClass() {
        return `toast toast-${this.toastType}`;
    }

    get dayColumnsClass() {
        return this.currentView === 'day' 
            ? 'day-columns day-view-columns' 
            : 'day-columns';
    }
    
    get allAssignmentsSelected() {
        if (!this.courseAssignments || this.courseAssignments.length === 0) {
            return false;
        }
        return this.courseAssignments.every(option => 
            this.selectedAssignments.includes(option.assignmentKey)
        );
    }
    
    handleSelectAllAssignments(event) {
        const isChecked = event.target.checked;
        
        if (isChecked) {
            // Select all
            this.selectedAssignments = this.courseAssignments.map(option => option.assignmentKey);
        } else {
            // Deselect all
            this.selectedAssignments = [];
        }
        
        // Update isSelected for each assignment
        this.updateAssignmentSelection();
    }

    // Recurring event options
    get recurringTypes() {
        return [
            { value: 'daily', label: 'Daily', buttonClass: `recurring-type-btn ${this.recurringType === 'daily' ? 'active' : ''}` },
            { value: 'weekly', label: 'Weekly', buttonClass: `recurring-type-btn ${this.recurringType === 'weekly' ? 'active' : ''}` },
            { value: 'monthly', label: 'Monthly', buttonClass: `recurring-type-btn ${this.recurringType === 'monthly' ? 'active' : ''}` },
            { value: 'yearly', label: 'Yearly', buttonClass: `recurring-type-btn ${this.recurringType === 'yearly' ? 'active' : ''}` }
        ];
    }

    get showWeekdaySelector() {
        return this.recurringType === 'weekly';
    }

    get weekdayOptions() {
        const days = [
            { value: 0, short: 'S', full: 'Sunday' },
            { value: 1, short: 'M', full: 'Monday' },
            { value: 2, short: 'T', full: 'Tuesday' },
            { value: 3, short: 'W', full: 'Wednesday' },
            { value: 4, short: 'T', full: 'Thursday' },
            { value: 5, short: 'F', full: 'Friday' },
            { value: 6, short: 'S', full: 'Saturday' }
        ];
        
        return days.map(day => ({
            ...day,
            buttonClass: `weekday-btn ${this.selectedWeekdays.includes(day.value) ? 'selected' : ''}`
        }));
    }

    get intervalLabel() {
        const labels = {
            daily: 'day(s)',
            weekly: 'week(s)',
            monthly: 'month(s)',
            yearly: 'year(s)'
        };
        return labels[this.recurringType] || 'week(s)';
    }

    // Navigation handlers
    handlePreviousWeek() {
        const newDate = new Date(this.currentDate);
        if (this.currentView === 'day') {
            newDate.setDate(newDate.getDate() - 1);
        } else if (this.currentView === 'week') {
            newDate.setDate(newDate.getDate() - 7);
        } else if (this.currentView === 'month') {
            newDate.setMonth(newDate.getMonth() - 1);
        }
        this.currentDate = newDate;
        this.requestAutoScroll();
    }

    handleNextWeek() {
        const newDate = new Date(this.currentDate);
        if (this.currentView === 'day') {
            newDate.setDate(newDate.getDate() + 1);
        } else if (this.currentView === 'week') {
            newDate.setDate(newDate.getDate() + 7);
        } else if (this.currentView === 'month') {
            newDate.setMonth(newDate.getMonth() + 1);
        }
        this.currentDate = newDate;
        this.requestAutoScroll();
    }

    handleToday() {
        this.currentDate = new Date();
        this.requestAutoScroll();
    }

    handleDayView() {
        this.currentView = 'day';
        this.requestAutoScroll();
    }

    handleWeekView() {
        this.currentView = 'week';
        this.requestAutoScroll();
    }

    handleMonthView() {
        this.currentView = 'month';
    }

    requestAutoScroll() {
        // Defer until after DOM renders updated hour-cells/events
        this.pendingAutoScroll = true;
    }

    getAutoScrollKey() {
        const dateStr = this.formatDateLocal(this.currentDate);
        const div = this.selectedDivision ? String(this.selectedDivision) : '';
        const view = this.currentView ? String(this.currentView) : '';
        return `${div}::${view}::${dateStr}`;
    }

    getAutoScrollTop(gridContainer) {
        const hourHeight = TimetableCalendar.DAY_VIEW_HOUR_HEIGHT;
        const baseStartMinutes = TimetableCalendar.DAY_START_HOUR * 60;
        const paddingPx = Math.round(hourHeight * 2); // show ~2 hours above earliest session when possible

        const { startDate, endDate } = this.getCurrentViewDateRange();
        const events = Array.isArray(this.events) ? this.events : [];

        const visibleEvents = events.filter(e => {
            if (!e || !e.date) return false;
            if (this.currentView === 'day') return e.date === startDate;
            // week view: inclusive date range
            return e.date >= startDate && e.date <= endDate;
        });

        let minStartMinutes = null;
        for (const e of visibleEvents) {
            if (!e.startTime) continue;
            const parts = String(e.startTime).split(':');
            const h = parseInt(parts[0], 10);
            const m = parseInt(parts[1], 10);
            if (!Number.isFinite(h) || !Number.isFinite(m)) continue;
            const mins = (h * 60) + m;
            if (minStartMinutes == null || mins < minStartMinutes) minStartMinutes = mins;
        }

        // Default scroll target: 09:00 if there are no sessions
        const targetMinutes = (minStartMinutes != null) ? minStartMinutes : (9 * 60);
        const rawTopPx = Math.max(0, targetMinutes - baseStartMinutes) * (hourHeight / 60); // px
        const desiredTopPx = Math.max(0, rawTopPx - paddingPx);

        const maxScroll = Math.max(
            0,
            (gridContainer.scrollHeight || 0) - (gridContainer.clientHeight || 0)
        );
        return Math.min(maxScroll, desiredTopPx);
    }

    /** Publish is only disabled while a publish request is in flight (no draft-in-view or division checks). */
    get isPublishDisabled() {
        return this.isPublishingSessions;
    }

    handlePublishSessions() {
        const range = this.getCurrentViewDateRange();
        this.publishFromDate = range.startDate || '';
        this.publishToDate = range.endDate || '';
        this.showPublishModal = true;
    }

    handleClosePublishModal() {
        if (this.isPublishingSessions) {
            return;
        }
        this.showPublishModal = false;
    }

    get isPlainNotifyPrompt() {
        return !this.isPublishNotifyPrompt && !this.isRepublishNotifyPrompt;
    }

    /**
     * Asks whether to notify, and resolves to the user's answer (null when they close the prompt).
     *
     * Every save path asks this AFTER its conflict checks, so one user action reaches it once.
     * The guard covers the remaining way to stack two copies of the question: a double-click that
     * enters the save twice. The second attempt aborts rather than replacing the first attempt's
     * resolver, which would leave the first save hanging forever.
     */
    promptSendFacultyNotifications(isPublish, isRepublish) {
        if (this.showFacultyNotifyModal) {
            return Promise.resolve(null); // duplicate attempt: the first one owns the prompt
        }
        this.isPublishNotifyPrompt = isPublish === true;
        this.isRepublishNotifyPrompt = isPublish !== true && isRepublish === true;
        this.showFacultyNotifyModal = true;
        return new Promise((resolve) => {
            this.facultyNotifyResolve = resolve;
        });
    }

    handleFacultyNotifyYes() {
        this.showFacultyNotifyModal = false;
        if (this.facultyNotifyResolve) {
            this.facultyNotifyResolve(true);
            this.facultyNotifyResolve = null;
        }
    }

    handleFacultyNotifyNo() {
        this.showFacultyNotifyModal = false;
        if (this.facultyNotifyResolve) {
            this.facultyNotifyResolve(false);
            this.facultyNotifyResolve = null;
        }
    }

    /** Closing via the X cancels the save entirely (no decision was made). */
    handleFacultyNotifyClose() {
        this.showFacultyNotifyModal = false;
        if (this.facultyNotifyResolve) {
            this.facultyNotifyResolve(null);
            this.facultyNotifyResolve = null;
        }
    }

    handlePublishFromDateChange(event) {
        this.publishFromDate = event.target.value || '';
    }

    handlePublishToDateChange(event) {
        this.publishToDate = event.target.value || '';
    }

    async handleConfirmPublishSessions() {
        const from = (this.publishFromDate || '').trim();
        const to = (this.publishToDate || '').trim();
        if (!from || !to) {
            this.showToastMessage('From Date and To Date are required.', 'error');
            return;
        }
        if (from > to) {
            this.showToastMessage('From Date cannot be after To Date.', 'error');
            return;
        }
        if (!this.selectedDivision) {
            this.showToastMessage('Please select a division before publishing sessions', 'error');
            return;
        }

        const startDateStr = new Date(from + 'T12:00:00').toLocaleDateString('en-US', {
            month: 'short',
            day: 'numeric',
            year: 'numeric'
        });
        const endDateStr = new Date(to + 'T12:00:00').toLocaleDateString('en-US', {
            month: 'short',
            day: 'numeric',
            year: 'numeric'
        });

        // ADD THIS
        const scheduleTypes = [];

        if (this.filterScheduleTypeDraft) {
        scheduleTypes.push('Draft');
        }

        if (this.filterScheduleTypePublished) {
        scheduleTypes.push('Published');
        }

        const sendNotifications = await this.promptSendFacultyNotifications(true);
        if (sendNotifications === null) {
            return;
        }

        const filterPayload = {
            divisionId: this.isAllDivisionsSelected ? null : (this.selectedDivision || null),
            divisionIds: this.isAllDivisionsSelected ? this.allDivisionIds : null,
            startDate: from,
            endDate: to,
            scheduleTypes: scheduleTypes,
            sendNotifications
        };

        this.isPublishingSessions = true;
        publishSessions({ filterJson: JSON.stringify(filterPayload) })
            .then((result) => {
                const n = Number(result) || 0;
           
                  if (n > 0) {
                    this.showToastMessage(
                        `Successfully published ${n} eligible session(s) from ${startDateStr} to ${endDateStr}.`,
                        'success'
                    );
                }/*else {
                    this.showToastMessage('In the selected date range all sessions are already published.', 'warning');
                }  */
                    else {
                        if (this.filterScheduleTypePublished && this.filterScheduleTypeDraft) {
                        this.showToastMessage(
                        'In the selected date range all sessions are already published.', // Scenario 3 edge: Published + Draft both selected but no future drafts remain.This happens when the user selected BOTH Published and Draft, and every Draft in range turned out to already be published/in the past
                         'warning'                                                        // WHY (Scenario 3 edge case): n === 0 here means Apex didn't throw an error(so none of the 4 hard-stop scenarios fired) but also didn't update anything.
                        );
                        } else {                                                        // WHY: if Draft/Published weren't both selected, n === 0 just means the chosen filter+date range genuinely has nothing to publish — keep the original generic message for that case.
                        this.showToastMessage('No sessions to publish in the selected date range.', 'warning');
                        }
                    }   
                 
                
                    this.sessionsRefreshKey = Date.now();
                    if (this.wiredSessionsResult) {
                    return refreshApex(this.wiredSessionsResult);
                }
            })
            .catch((error) => {
                this.showToastMessage(this.getErrorMessage(error), 'error');
            })
            .finally(() => {
                this.isPublishingSessions = false;
                this.showPublishModal = false;
            });
    }

    getCurrentViewDateRange() {
        let startDate;
        let endDate;
        
        if (this.currentView === 'day') {
            // Day view: single date
            startDate = new Date(this.currentDate);
            startDate.setHours(0, 0, 0, 0);
            endDate = new Date(this.currentDate);
            endDate.setHours(23, 59, 59, 999);
        } else if (this.currentView === 'week') {
            // Week view: 7 days starting from start of week
            startDate = this.getStartOfWeek(this.currentDate);
            endDate = new Date(startDate);
            endDate.setDate(endDate.getDate() + 6);
            endDate.setHours(23, 59, 59, 999);
        } else if (this.currentView === 'month') {
            // Month view: entire month
            const year = this.currentDate.getFullYear();
            const month = this.currentDate.getMonth();
            startDate = new Date(year, month, 1);
            startDate.setHours(0, 0, 0, 0);
            endDate = new Date(year, month + 1, 0); // Last day of month
            endDate.setHours(23, 59, 59, 999);
        } else {
            // Default to week view
            startDate = this.getStartOfWeek(this.currentDate);
            endDate = new Date(startDate);
            endDate.setDate(endDate.getDate() + 6);
            endDate.setHours(23, 59, 59, 999);
        }
        
        // Convert to YYYY-MM-DD in local timezone
        return {
            startDate: this.formatDateLocal(startDate),
            endDate: this.formatDateLocal(endDate)
        };
    }

    // Event handlers
    handleAddEvent() {
        if (!this.ensureDivisionSelected()) {
            return;
        }
        this.isEditMode = false;
        this.selectedEventId = null;
        this.eventDate = new Date().toISOString().split('T')[0];
        this.initializeCreateSessionsModal();
        this.resetEventForm();
        this.showModal = true;
    }

    handleMonthDayClick(event) {
        const dayElement = event.currentTarget;
        const dateStr = dayElement.getAttribute('data-day');
        if (dateStr) {
            // Switch to day view for the clicked date
            this.currentDate = new Date(dateStr);
            this.currentView = 'day';
        }
    }

    handleMonthMoreClick(event) {
        event.stopPropagation();
        const dateStr = event.currentTarget?.dataset?.day;
        if (!dateStr) return;
        const allEvents = this.getEventsForDate(dateStr)
            .map(ev => this.formatEventForMonthView(ev, dateStr));
        this.monthMoreEventsDate = dateStr;
        this.monthMoreEventsList = allEvents;
        this.showMonthMoreEventsModal = true;
    }

    handleCloseMonthMoreEvents() {
        this.showMonthMoreEventsModal = false;
        this.monthMoreEventsDate = '';
        this.monthMoreEventsList = [];
    }

    handleCellClick(event, overrideHour, overrideDay) {
        if (this.isDragging) return;
        if (!this.ensureDivisionSelected()) return;
        // When called from All Divisions slot click, use explicitly passed hour/day so start time reflects clicked slot
        const hour = overrideHour != null ? String(overrideHour) : (event.currentTarget && event.currentTarget.dataset ? event.currentTarget.dataset.hour : null);
        const day = overrideDay != null ? overrideDay : (event.currentTarget && event.currentTarget.dataset ? event.currentTarget.dataset.day : null);
        if (!hour || !day) return;

        this.isEditMode = false;
        this.selectedEventId = null;
        this.eventDate = day;
        this.eventClassRoom = '';
        this.eventRemark = '';
        this.eventUrl = '';
        this.eventStartTime = `${hour.toString().padStart(2, '0')}:00`;
        
        let endTime = '';
        if (this.sessionDuration && this.sessionDuration > 0) {
            const startHour = parseInt(hour, 10);
            const totalStartMinutes = startHour * 60;
            const durationMinutes = Math.round(Number(this.sessionDuration));
            const totalEndMinutes = totalStartMinutes + durationMinutes;
            const endHour = Math.floor(totalEndMinutes / 60);
            const endMinutes = totalEndMinutes % 60;
            endTime = `${endHour.toString().padStart(2, '0')}:${endMinutes.toString().padStart(2, '0')}`;
        } else {
            endTime = `${(parseInt(hour, 10) + 1).toString().padStart(2, '0')}:00`;
        }
        this.eventEndTime = endTime;
        
        this.initializeCreateSessionsModal();
        if (this.createSessionsList && this.createSessionsList.length > 0) {
            this.createSessionsList = [
                {
                    ...this.createSessionsList[0],
                    date: day,
                    startTime: this.eventStartTime,
                    endTime: endTime
                },
                ...this.createSessionsList.slice(1)
            ];
        }
        this.showModal = true;
    }

    handleEventClick(event) {
        if (this.isDragging) return;
        
        event.stopPropagation();
        const eventId = event.currentTarget.dataset.id;
        // Division of the tile: per-row data-division-id (multi–Session_Division sessions) or row [data-division] (day view)
        const fromEventEl =
            event.currentTarget.dataset && event.currentTarget.dataset.divisionId
                ? event.currentTarget.dataset.divisionId
                : null;
        const divisionCell = event.currentTarget.closest && event.currentTarget.closest('[data-division]');
        const fromRow =
            divisionCell && divisionCell.dataset && divisionCell.dataset.division
                ? divisionCell.dataset.division
                : null;
        this.clickedTileDivisionId = fromEventEl || fromRow || null;

        // Handle recurring instance - get parent event
        const actualEventId = eventId.includes('-') ? eventId.split('-')[0] : eventId;
        const selectedEvent = this.findEventRowForSession(actualEventId, this.clickedTileDivisionId);
        
        if (selectedEvent) {
            this.isEditMode = true;
            this.selectedEventId = actualEventId;
            // RSVP read-back (Target 1): pull the latest Google Calendar responses live.
            this.loadAttendeeSummary(actualEventId, selectedEvent);
            this.eventTitle = selectedEvent.title || '';
            this.eventDate = selectedEvent.date || '';
            this.eventStartTime = selectedEvent.startTime || '09:00';
            this.eventEndTime = selectedEvent.endTime || '10:00';
            this.eventLocation = selectedEvent.location || '';
            this.eventDescription = selectedEvent.description || '';
            this.eventClassRoom = selectedEvent.classRoom || '';
            this.eventRemark = selectedEvent.remark || '';
            this.eventUrl = selectedEvent.url || '';
            this.selectedCourseActivity = selectedEvent.courseActivity || '';
            this.selectedSessionType = selectedEvent.sessionType || '';
            //SE-502
            // SE-502: Added studentNames, editEnrolledStudentOptions,
            // editEnrolledSelectedIds, editStudentDivisionMap mapping
            // when edit session modal opens
            this.studentNames = (selectedEvent.studentNames && selectedEvent.studentNames.length > 0) ? selectedEvent.studentNames : [];
            // Build edit eligible student checkbox options
            const rawIds = (selectedEvent.selectedStudentIds && selectedEvent.selectedStudentIds.length > 0) ? selectedEvent.selectedStudentIds : [];
            this.editEnrolledStudentOptions = [...new Set(this.studentNames)].map((name, i) => ({
            label: name,
            value: rawIds[i] || name
            }));
            this.editEnrolledSelectedIds = this.editEnrolledStudentOptions.map(o => o.value);
            this.editStudentDivisionMap = {};
            const mainDivId = this.clickedTileDivisionId || 'main';
            this.editStudentDivisionMap[mainDivId] = this.editEnrolledStudentOptions.map(o => o.value);
            //End SE-502
            this.isRecurring = selectedEvent.isRecurring || false;
            this.recurringType = selectedEvent.recurringType || 'weekly';
            this.recurringInterval = selectedEvent.recurringInterval || 1;
            this.recurringEndDate = selectedEvent.recurringEndDate || '';
            this.selectedWeekdays = selectedEvent.selectedWeekdays || [new Date(selectedEvent.date).getDay()];
            this.isJointSession = this.isCourseActivityJointSession(this.selectedCourseActivity) || selectedEvent.isJointSession || false;

            const courseName = selectedEvent.courseName || '';
            const openEditModal = () => {
                // Store faculty names from the event (getSessions returns these from Session_Faculty__c); so edit pills show names even if faculty was removed from Instructor__c for that course
                const ids = selectedEvent.selectedFacultyIds && Array.isArray(selectedEvent.selectedFacultyIds) ? selectedEvent.selectedFacultyIds : [];
                const names = selectedEvent.facultyNames && Array.isArray(selectedEvent.facultyNames) ? selectedEvent.facultyNames : [];
                this.editModalFacultyNameList = ids.map((id, i) => ({ id: String(id).trim(), name: (names[i] != null && names[i] !== undefined) ? String(names[i]).trim() : '' }));
                // Always clear and reload existing session divisions so reopened modal shows latest data (e.g. after Remove + Save)
                this.existingSessionDivisions = [];
                // Find the matching course option value (format: "courseName|learningCourseId")
                if (courseName) {
                    const matchingOption = this.courseOptions.find(opt => opt.value && opt.value.startsWith(courseName + '|'));
                    this.selectedCourse = matchingOption ? matchingOption.value : courseName;
                    if (this.selectedCourse && matchingOption) {
                        this.selectedCourseDepartmentName = matchingOption.departmentName || '';
                    } else {
                        this.selectedCourseDepartmentName = '';
                    }
                    if (this.selectedCourse) {
                        this.loadCourseAssignments();
                    }
                } else {
                    this.selectedCourse = '';
                    this.selectedCourseDepartmentName = '';
                }
                this.loadExistingSessionDivisions(actualEventId);
                if (actualEventId) {
                    this.editLeadFacultyIds = (selectedEvent.leadFacultyIds && selectedEvent.leadFacultyIds.length > 0)
                        ? [...selectedEvent.leadFacultyIds]
                        : (selectedEvent.leadFacultyId ? [selectedEvent.leadFacultyId] : []);
                    this.loadExistingSessionFaculties(actualEventId);
                } else {
                    this.selectedFacultyValue = [];
                    this.editLeadFacultyIds = [];
                }
                this.editFacultyComboboxValue = '';
                if (this.selectedCourse) {
                    this.loadFacultyForCourse();
                }
                if (this.selectedBatchAllowsMultiProgram && this.selectedCourse) {
                    this.loadEditAddCourseAssignments();
                } else {
                    this.editAddCourseAssignments = [];
                    this.editAddSelectedKeys = [];
                }
                this.showModal = true;
            };

            // When "All Divisions" is selected, courseOptions is empty; load courses for this session's division first
            if (this.isAllDivisionsSelected && selectedEvent.divisionId) {
                getCoursesForDivision({ divisionId: selectedEvent.divisionId })
                    .then(result => {
                        this.courseOptions = (result || []).map(option => ({
                            label: option.label,
                            value: option.value,
                            departmentName: option.departmentName || null
                        }));
                        openEditModal();
                    })
                    .catch(err => {
                        console.error('Error loading courses for edit:', err);
                        this.courseOptions = [];
                        openEditModal();
                    });
            } else {
                openEditModal();
            }
        }
    }

    // Mouse hover handlers for events (also drives custom tooltip)
    handleEventMouseEnter(event) {
        event.stopPropagation();
        const eventElement = event.currentTarget;
        // Remove title attribute to prevent native browser tooltip
        if (eventElement.hasAttribute('title')) {
            eventElement.removeAttribute('title');
        }
        eventElement.classList.add('event-hover');
        const eventId = eventElement.dataset.id;
        const divisionIdAttr =
            eventElement.dataset && eventElement.dataset.divisionId
                ? eventElement.dataset.divisionId
                : null;
        if (eventId) {
            const actualEventId = eventId.includes('-') ? eventId.split('-')[0] : eventId;
            const ev = this.findEventRowForSession(actualEventId, divisionIdAttr);
            if (ev) {
                const divisionName = (ev.divisionName && String(ev.divisionName).trim()) || '—';
                const course = (ev.courseName && String(ev.courseName).trim()) || '—';
                const facultyStr = (ev.leadFacultyNames && Array.isArray(ev.leadFacultyNames) && ev.leadFacultyNames.length > 0)
                    ? ev.leadFacultyNames.join(', ')
                    : '—';
                const supportFacultyStr = (ev.supportFacultyNames && Array.isArray(ev.supportFacultyNames) && ev.supportFacultyNames.length > 0)
                    ? ev.supportFacultyNames.join(', ')
                    : '—';
                const activity = (ev.courseActivity && String(ev.courseActivity).trim()) || '—';
                const classRoom = (ev.classRoom && String(ev.classRoom).trim()) || '—';
                this.hoveredEventTooltip = { divisionName, courseName: course, facultyStr, supportFacultyStr, courseActivity: activity, classRoom };
                this.tooltipPosition = { x: event.clientX, y: event.clientY + 14 };
            }
        }
    }

    handleEventMouseLeave(event) {
        event.stopPropagation();
        const eventElement = event.currentTarget;
        eventElement.classList.remove('event-hover');
        // Clear tooltip when leaving the event element
        this.hoveredEventTooltip = null;
    }

    get sessionHoverTooltipStyle() {
        const x = this.tooltipPosition && this.tooltipPosition.x != null ? this.tooltipPosition.x : 0;
        const y = this.tooltipPosition && this.tooltipPosition.y != null ? this.tooltipPosition.y : 0;
        const tooltipWidth = 280;
        const gap = 12;
        const win = typeof window !== 'undefined' ? window : { innerWidth: 9999 };
        const showOnLeft = x + tooltipWidth + gap > win.innerWidth;
        const left = showOnLeft ? Math.max(gap, x - tooltipWidth - gap) : x;
        return `left: ${left}px; top: ${y}px;`;
    }

    get showSessionHoverTooltip() {
        return this.hoveredEventTooltip != null;
    }

    // Drag and Drop handlers
    handleDragStart(event) {
        if (!this.canDragEvents) {
            event.preventDefault();
            return;
        }
        const eventId = event.currentTarget.dataset.id;
        const divFromDom =
            event.currentTarget.dataset && event.currentTarget.dataset.divisionId
                ? event.currentTarget.dataset.divisionId
                : null;
        const actualEventId = eventId.includes('-') ? eventId.split('-')[0] : eventId;
        const draggedEvent = this.findEventRowForSession(actualEventId, divFromDom);
        
        if (draggedEvent) {
            this.isDragging = true;
            this.draggedEventId = eventId;
            this.draggedEventDivisionId = divFromDom;
            this.draggedEventTitle = draggedEvent.title;
            
            // Set drag data
            event.dataTransfer.setData('text/plain', eventId);
            event.dataTransfer.effectAllowed = 'move';
            
            // Create custom drag image
            const dragGhost = document.createElement('div');
            dragGhost.className = 'drag-ghost-element';
            dragGhost.textContent = draggedEvent.title;
            dragGhost.style.cssText = 'position: absolute; top: -1000px; background: #6366f1; color: white; padding: 8px 16px; border-radius: 8px; font-weight: 600; font-size: 13px; box-shadow: 0 4px 12px rgba(0,0,0,0.15);';
            document.body.appendChild(dragGhost);
            event.dataTransfer.setDragImage(dragGhost, 0, 0);
            
            setTimeout(() => {
                document.body.removeChild(dragGhost);
            }, 0);
        }
    }

    handleDragEnd() {
        this.isDragging = false;
        this.draggedEventId = null;
        this.draggedEventDivisionId = null;
        this.draggedEventTitle = '';
        this.dropTargetDay = null;
        this.dropTargetHour = null;
    }

    handleDragOver(event) {
        if (!this.canDragEvents) {
            return;
        }
        event.preventDefault();
        event.dataTransfer.dropEffect = 'move';
        
        const dayColumn = event.currentTarget;
        this.dropTargetDay = dayColumn.dataset.day;
    }

    handleDragLeave(event) {
        const dayColumn = event.currentTarget;
        const relatedTarget = event.relatedTarget;
        
        if (!dayColumn.contains(relatedTarget)) {
            if (this.dropTargetDay === dayColumn.dataset.day) {
                this.dropTargetDay = null;
                this.dropTargetHour = null;
            }
        }
    }

    handleCellDragOver(event) {
        if (!this.canDragEvents) {
            return;
        }
        event.preventDefault();
        const hour = parseInt(event.currentTarget.dataset.hour, 10);
        this.dropTargetHour = hour;
    }

    handleCellDrop(event) {
        if (!this.canDragEvents) {
            return;
        }
        event.preventDefault();
        this.handleDrop(event);
    }

    handleDrop(event) {
        if (!this.canDragEvents) {
            return;
        }
        event.preventDefault();
        
        const eventId = event.dataTransfer.getData('text/plain');
        const targetDay = event.currentTarget.dataset.day || this.dropTargetDay;
        const targetHour = this.dropTargetHour;
        
        if (!eventId || !targetDay) return;
        
        const actualEventId = eventId.includes('-') ? eventId.split('-')[0] : eventId;
        const divId = this.draggedEventDivisionId;
        const eventIndex = this.events.findIndex(e => {
            if (!e) return false;
            const idMatch = e.id === eventId || e.id === actualEventId;
            if (!idMatch) return false;
            if (!divId) return true;
            return this.idsEqual(e.divisionId, divId);
        });
        
        if (eventIndex !== -1) {
            const originalEvent = this.events[eventIndex];
            const startParts = (originalEvent.startTime || '09:00').split(':');
            const endParts = (originalEvent.endTime || '10:00').split(':');
            const startH = parseInt(startParts[0], 10) || 0;
            const startM = (startParts.length > 1 ? parseInt(startParts[1], 10) : 0) || 0;
            const endH = parseInt(endParts[0], 10) || 0;
            const endM = (endParts.length > 1 ? parseInt(endParts[1], 10) : 0) || 0;
            const durationMinutes = (endH * 60 + endM) - (startH * 60 + startM);
            const safeDurationMinutes = Math.max(1, durationMinutes);

            const newStartHour = (targetHour !== null && targetHour !== undefined)
                ? (parseInt(targetHour, 10) || startH)
                : startH;
            const newStartTime = `${String(newStartHour).padStart(2, '0')}:${String(startM).padStart(2, '0')}`;
            const newEndTime = this.addMinutesToTime(newStartTime, safeDurationMinutes);

            const updatedEvent = {
                ...originalEvent,
                date: targetDay,
                startTime: newStartTime,
                endTime: newEndTime,
                selectedFacultyIds: Array.isArray(originalEvent.selectedFacultyIds)
                    ? [...originalEvent.selectedFacultyIds]
                    : (originalEvent.selectedFacultyIds ? [originalEvent.selectedFacultyIds] : [])
            };

            this.events = [
                ...this.events.slice(0, eventIndex),
                updatedEvent,
                ...this.events.slice(eventIndex + 1)
            ];

            this.persistSessionChanges(updatedEvent)
                .then(() => {
                    this.showToastMessage(`"${originalEvent.title}" moved to ${this.formatDateForDisplay(targetDay)}`, 'success');
                    if (this.wiredSessionsResult) {
                        return refreshApex(this.wiredSessionsResult);
                    }
                })
                .catch(error => {
                    console.error('Error updating session via drag/drop:', error);
                    this.handleSaveError(error, updatedEvent);
                    // Refresh the wired sessions data on error to restore correct state
                    if (this.wiredSessionsResult) {
                        return refreshApex(this.wiredSessionsResult);
                    }
                });
        }
        
        this.handleDragEnd();
    }

    // Resize handlers
    handleResizeStart(event) {
        event.preventDefault();
        event.stopPropagation();
        
        const eventId = event.currentTarget.dataset.id;
        const divFromDom =
            (event.currentTarget.dataset && event.currentTarget.dataset.divisionId) ||
            (event.currentTarget.parentElement &&
                event.currentTarget.parentElement.dataset &&
                event.currentTarget.parentElement.dataset.divisionId) ||
            null;
        const actualEventId = eventId.includes('-') ? eventId.split('-')[0] : eventId;
        this.isResizing = true;
        this.resizingEventId = eventId;
        this.draggedEventDivisionId = divFromDom;
        
        const handleMouseMove = (e) => {
            if (!this.isResizing) return;
            
            const gridContainer = this.template.querySelector('.time-grid-container');
            const rect = gridContainer.getBoundingClientRect();
            const scrollTop = gridContainer.scrollTop;
            const y = e.clientY - rect.top + scrollTop;
            
            const hourHeight = TimetableCalendar.DAY_VIEW_HOUR_HEIGHT;
            const startHour = TimetableCalendar.DAY_START_HOUR;
            const endHour = TimetableCalendar.DAY_END_HOUR;
            const newHour = Math.max(startHour + 1, Math.min(endHour, Math.round(y / hourHeight) + startHour));
            
            const eventIndex = this.events.findIndex(ev => {
                if (!ev || ev.id !== actualEventId) return false;
                if (!this.draggedEventDivisionId) return true;
                return this.idsEqual(ev.divisionId, this.draggedEventDivisionId);
            });
            
            if (eventIndex !== -1) {
                const startHour = parseInt(this.events[eventIndex].startTime.split(':')[0], 10);
                if (newHour > startHour) {
                    this.events = [
                        ...this.events.slice(0, eventIndex),
                        {
                            ...this.events[eventIndex],
                            endTime: `${newHour.toString().padStart(2, '0')}:00`
                        },
                        ...this.events.slice(eventIndex + 1)
                    ];
                }
            }
        };
        
        const handleMouseUp = () => {
            this.isResizing = false;
            this.resizingEventId = null;
            const divisionForResize = this.draggedEventDivisionId;
            document.removeEventListener('mousemove', handleMouseMove);
            document.removeEventListener('mouseup', handleMouseUp);

            const updatedEvent = this.findEventRowForSession(actualEventId, divisionForResize);
            this.draggedEventDivisionId = null;
            if (updatedEvent) {
                this.persistSessionChanges(updatedEvent)
                    .then(() => {
                        this.showToastMessage(`"${updatedEvent.title}" duration updated`, 'success');
                        // Refresh the wired sessions data
                        if (this.wiredSessionsResult) {
                            return refreshApex(this.wiredSessionsResult);
                        }
                    })
                    .catch(error => {
                        console.error('Error updating session after resize:', error);
                        this.handleSaveError(error, updatedEvent);
                        // Refresh the wired sessions data on error to restore correct state
                        if (this.wiredSessionsResult) {
                            return refreshApex(this.wiredSessionsResult);
                        }
                    });
            }
        };
        
        document.addEventListener('mousemove', handleMouseMove);
        document.addEventListener('mouseup', handleMouseUp);
    }

    formatDateForDisplay(dateStr) {
        const date = new Date(dateStr);
        return date.toLocaleDateString('en-US', { weekday: 'short', month: 'short', day: 'numeric' });
    }

    handleCloseModal() {
        this.showModal = false;
        this.isEditMode = false;
        this.selectedEventId = null;
        this.clickedTileDivisionId = null;
        this.modalDivisionId = null;
        this.resetEventForm();
        this.resetCreateSessionsModal();
    }
    
    initializeCreateSessionsModal() {
        const today = this.formatDateLocal(new Date());
        this.modalProgram = this.selectedProgram || '';
        this.modalBatch = this.selectedBatch || '';
        this.modalTerm = this.selectedTerm || '';
        this.modalCourse = this.selectedCourse || '';
        this.modalBatchOptions = [...(this.batchOptions || [])];
        this.modalTermOptions = [...(this.termOptions || [])];
        // Use sidebar courseOptions when a single division is selected; when "All Divisions" + clicked a cell, load courses for that division
        const effectiveDivisionId = this.isAllDivisionsSelected ? this.modalDivisionId : this.selectedDivision;
        if (effectiveDivisionId) {
            if (!this.isAllDivisionsSelected && (this.courseOptions || []).length > 0) {
                this.modalCourseOptions = [...this.courseOptions];
            } else {
                this.modalCourseOptions = [];
                getCoursesForDivision({ divisionId: effectiveDivisionId })
                    .then(result => {
                        this.modalCourseOptions = Array.isArray(result) ? result.map(o => ({
                            label: o.label,
                            value: o.value,
                            departmentName: o.departmentName || null
                        })) : [];
                    })
                    .catch(() => {
                        this.modalCourseOptions = [];
                    });
            }
        } else {
            this.modalCourseOptions = [...(this.courseOptions || [])];
        }
        this.createSessionsSaveAttempted = false;
        const { startTime: defaultStart, endTime: defaultEnd } = this.getDefaultCreateSessionTimes();
        this.createSessionsList = [{
            id: 'create-' + Date.now() + '-' + Math.random().toString(36).substr(2, 9),
            title: '',
            date: today,
            startTime: defaultStart,
            endTime: defaultEnd,
            facultyIds: [],
            leadFacultyIds: [],
            leadFacultyId: undefined,
            facultyComboboxValue: '',
            selectedAssignmentKeys: [],
            courseActivity: '',
            classRoom: '',
            remark: '',
            url: ''
    
        }];
        this.activeCreateSessionIndex = 0;
        this.facultyConflicts = [];
        if (this.modalCourse) {
            this.loadCourseAssignmentsForCreateModal();
        }
        if (this.modalCourse && this.facultyOptions.length === 0) {
            this.loadFacultyForCourse();
        }
        this.loadFacultyConflicts();
    }

    /** Division ids for one create-sessions row (course assignment keys + sidebar / all-divisions). */
    getCreateSessionDivisionIdsForRow(session) {
        const divisionId = this.isAllDivisionsSelected
            ? (this.modalDivisionId || null)
            : this.selectedDivision;
        const divisionIds = this.isAllDivisionsSelected
            ? (this.modalDivisionId ? null : this.allDivisionIds)
            : null;
        const assignmentKeys = (session.selectedAssignmentKeys || []).map((k) => (k != null ? String(k).trim() : '')).filter(Boolean);
        const list = [];
        if (assignmentKeys.length > 0 && this.courseAssignments && this.courseAssignments.length > 0) {
            this.courseAssignments.forEach((a) => {
                const key = a.assignmentKey != null ? String(a.assignmentKey).trim() : '';
                if (!key || !assignmentKeys.includes(key)) return;
                const divId = this.getAssignmentDivisionId(a);
                if (divId) list.push(divId);
            });
        }
        if (list.length === 0 && divisionId) list.push(divisionId);
        if (list.length === 0 && divisionIds && divisionIds.length > 0) list.push(...divisionIds);
        if (divisionId && !list.includes(divisionId)) list.push(divisionId);
        return list;
    }
    
    resetCreateSessionsModal() {
        this.createSessionsList = [];
        this.activeCreateSessionIndex = 0;
        this.createSessionsSaveAttempted = false;
        this.facultyConflicts = [];
        this.sessionConflicts = [];
        this.calendarConflicts = [];
        this.showConflictsModal = false;
        this.pendingConflictOverride = false;
        this.conflictOverrideSaveMode = null;
        this.modalProgram = '';
        this.modalBatch = '';
        this.modalTerm = '';
        this.modalCourse = '';
        this.modalBatchOptions = [];
        this.modalTermOptions = [];
        this.modalCourseOptions = [];
    }
    
    loadCourseAssignmentsForCreateModal() {
        if (this.selectedBatch && !this.selectedBatchAllowsMultiProgram) {
            this.courseAssignments = [];
            this.showCourseAssignments = false;
            return;
        }
        const courseValue = this.modalCourse;
        const parts = courseValue.split('|');
        const learningCourseId = parts.length > 1 ? parts[1] : null;
        if (!learningCourseId) {
            this.courseAssignments = [];
            this.showCourseAssignments = false;
            return;
        }
        // Pass full context so server excludes the "already selected" row.
        // Division: when "All Divisions" is selected we opened from a div tile → use modalDivisionId; else use selectedDivision.
        const currentDivisionId = this.isAllDivisionsSelected
            ? (this.modalDivisionId || null)
            : (this.selectedDivision !== TimetableCalendar.ALL_DIVISIONS_VALUE ? this.selectedDivision : null);
        const currentProgramId = this.modalProgram || this.selectedProgram || null;
        const currentBatchId = this.selectedBatch || null;
        const currentBatchGroupId = this.selectedBatchGroup || null;
        const currentTermId = this.selectedTerm || null;
        // DEBUG: compare what we send to Apex
        console.debug('[loadCourseAssignmentsForCreateModal] Sending context:', {
            learningCourseId,
            currentDivisionId,
            currentProgramId,
            currentBatchId,
            currentBatchGroupId,
            currentTermId,
            isAllDivisionsSelected: this.isAllDivisionsSelected,
            modalDivisionId: this.modalDivisionId,
            selectedDivision: this.selectedDivision
        });
        getCourseAssignments({
            learningCourseId,
            currentDivisionId,
            currentProgramId,
            currentBatchId,
            currentBatchGroupId,
            currentTermId
        })
            .then(result => {
                const assignments = Array.isArray(result) ? result : [];
                this.courseAssignments = assignments.map((option, index) => {
                    const div0 = option.divisions && option.divisions[0];
                    const divisionId = div0 ? (div0.divisionId || div0.id || '') : '';
                    const divisionName = div0 ? (div0.divisionName || div0.name || '') : '';
                    return {
                        ...option,
                        assignmentKey: this.getAssignmentKey(option, index),
                        isSelected: false,
                        divisionName: divisionName,
                        divisionId: divisionId
                    };
                });
                this.showCourseAssignments = this.courseAssignments.length > 0;
            })
            .catch(() => {
                this.courseAssignments = [];
                this.showCourseAssignments = false;
            });
    }
    
    handleModalProgramChange(event) {
        this.modalProgram = event.detail.value || '';
        this.modalBatch = '';
        this.modalTerm = '';
        this.modalCourse = '';
        this.modalBatchOptions = [];
        this.modalTermOptions = [];
        this.modalCourseOptions = [];
        this.courseAssignments = [];
        this.showCourseAssignments = false;
        if (this.modalProgram) {
            getBatchesForProgram({ programId: this.modalProgram })
                .then(result => {
                    this.modalBatchOptions = (result || []).map(o => ({
                        label: o.label,
                        value: o.value,
                        sessionDuration: o.sessionDuration || null
                    }));
                })
                .catch(() => { this.modalBatchOptions = []; });
        }
    }
    
    handleModalBatchChange(event) {
        this.modalBatch = event.detail.value || '';
        this.modalTerm = '';
        this.modalCourse = '';
        this.modalTermOptions = [];
        this.modalCourseOptions = [];
        this.courseAssignments = [];
        this.showCourseAssignments = false;
        if (this.modalBatch) {
            getBatchGroupsForBatch({ batchId: this.modalBatch })
                .then(result => {
                    const batchGroups = result || [];
                    if (batchGroups.length > 0) {
                        return getTermsForBatchGroup({ batchGroupId: batchGroups[0].value });
                    }
                    return [];
                })
                .then(result => {
                    this.modalTermOptions = Array.isArray(result)
                        ? result.map(o => ({
                              label: o.label,
                              value: o.value,
                              termStartDate: o.termStartDate || null,
                              termEndDate: o.termEndDate || null
                          }))
                        : [];
                })
                .catch(() => { this.modalTermOptions = []; });
        }
    }
    
    handleModalTermChange(event) {
        this.modalTerm = event.detail.value || '';
        this.modalCourse = '';
        this.modalCourseOptions = [];
        this.courseAssignments = [];
        this.showCourseAssignments = false;
        if (this.modalTerm) {
            getDivisionsForTerms({ termIds: [this.modalTerm] })
                .then(result => {
                    const divisions = result || [];
                    if (divisions.length > 0) {
                        return getCoursesForDivision({ divisionId: divisions[0].value });
                    }
                    return [];
                })
                .then(result => {
                    this.modalCourseOptions = Array.isArray(result) ? result.map(o => ({
                        label: o.label,
                        value: o.value,
                        departmentName: o.departmentName || null
                    })) : [];
                })
                .catch(() => { this.modalCourseOptions = []; });
        }
    }

    /** Create Sessions modal (All Divisions): user selects division from dropdown; load courses for that division. */
    handleCreateModalDivisionChange(event) {
        const divisionId = event.detail.value || null;
        this.modalDivisionId = divisionId;
        this.modalCourse = '';
        this.modalCourseOptions = [];
        this.courseAssignments = [];
        this.showCourseAssignments = false;
        if (divisionId) {
            getCoursesForDivision({ divisionId: divisionId })
                .then(result => {
                    this.modalCourseOptions = Array.isArray(result) ? result.map(o => ({
                        label: o.label,
                        value: o.value,
                        departmentName: o.departmentName || null
                    })) : [];
                })
                .catch(() => { this.modalCourseOptions = []; });
        }
    }
    
    handleModalCourseChange(event) {
        this.modalCourse = event.detail.value || '';
        this.courseAssignments = [];
        this.showCourseAssignments = false;
        // When course changes, clear faculty from all sessions so user picks faculty for the new course (avoids showing raw ID)
        if (this.createSessionsList && this.createSessionsList.length > 0) {
            this.createSessionsList = this.createSessionsList.map(s => ({
                ...s,
                facultyIds: [],
                leadFacultyIds: [],
                leadFacultyId: undefined,
                facultyComboboxValue: ''
            }));
        }
        if (this.modalCourse) {
            this.loadCourseAssignmentsForCreateModal();
            const divisionId = this.getDivisionIdForFacultyQuery();
            getFacultyForCourse({ courseId: this.modalCourse, divisionId: divisionId || undefined })
                .then(result => {
                    this.facultyOptions = Array.isArray(result) ? result : [];
                })
                .catch(() => { this.facultyOptions = []; });
        } else {
            this.facultyOptions = [];
        }
         // Clear students when course changes in create modal
         // SE-502: Added student clearing and reloading when course changes in create modal
        this.eligibleStudentOptions = [];
        this.selectedStudentIds = [];
        this.studentDivisionMap = {};
        const idx = this.activeCreateSessionIndex;
        if (idx != null && this.createSessionsList && this.createSessionsList[idx]) {
            const u = [...this.createSessionsList];
            u[idx] = {
                ...u[idx],
                selectedStudentIds: [],
                selectedAssignmentKeys: []
            };
            this.createSessionsList = u;

            // If Make Up Exam is already selected, reload students for new course
            if (u[idx].courseActivity === 'Make Up Exam' && this.selectedDivision) {
                const courseValue = this.modalCourse || '';
                const courseParts = courseValue.split('|');
                const courseId = courseParts.length > 1 ? courseParts[1] : null;
                const divisionId = this.selectedDivision;

                getEligibleMakeupStudents({ divisionId, courseId })
                    .then(result => {
                        this.eligibleStudentOptions = result.map(s => ({
                            label: s.studentName,
                            value: s.studentId
                        }));
                        // Track main division students
                        this.studentDivisionMap = {};
                        this.studentDivisionMap[divisionId] = result.map(s => s.studentId);
                    })
                    .catch(error => {
                        console.error('Error reloading students on course change', error);
                        this.eligibleStudentOptions = [];
                    });
            }
        }
    }
    
    handleAddCreateSession() {
        const today = this.formatDateLocal(new Date());
        const list = this.createSessionsList || [];
        const lastSession = list.length > 0 ? list[list.length - 1] : null;
        const nextDate = lastSession && lastSession.date
            ? this.getNextWeekdayDate(lastSession.date)
            : (this.eventDate || today);
        const startTime = (lastSession && lastSession.startTime) ? lastSession.startTime : '09:00';
        const endTime = (lastSession && lastSession.endTime) ? lastSession.endTime : '10:00';
        this.createSessionsList = [...list, {
            id: 'create-' + Date.now() + '-' + Math.random().toString(36).substr(2, 9),
            title: '',
            date: nextDate,
            startTime: startTime,
            endTime: endTime,
            facultyIds: [],
            leadFacultyIds: [],
            leadFacultyId: undefined,
            facultyComboboxValue: '',
            selectedAssignmentKeys: [],
            courseActivity: '',
            classRoom: '',
            remark: '',
            url: ''
        }];
        this.activeCreateSessionIndex = this.createSessionsList.length - 1;
        this.loadFacultyConflicts();
    }
    
    handleRemoveCreateSession(event) {
        event.preventDefault();
        event.stopPropagation();
        const rawIndex = event.currentTarget.dataset.index;
        const index = typeof rawIndex === 'string' || typeof rawIndex === 'number'
            ? parseInt(String(rawIndex), 10) : NaN;
        if (Number.isNaN(index) || index < 0 || index >= (this.createSessionsList || []).length) {
            return;
        }
        if (this.createSessionsList.length <= 1) return;
        const updated = (this.createSessionsList || []).filter((_, i) => i !== index);
        this.createSessionsList = [...updated];
        if (this.activeCreateSessionIndex >= this.createSessionsList.length) {
            this.activeCreateSessionIndex = Math.max(0, this.createSessionsList.length - 1);
        } else if (this.activeCreateSessionIndex === index) {
            this.activeCreateSessionIndex = Math.max(0, index - 1);
        } else if (this.activeCreateSessionIndex > index) {
            this.activeCreateSessionIndex = this.activeCreateSessionIndex - 1;
        }
        this.loadFacultyConflicts();
    }
    
    handleSelectCreateSession(event) {
        const index = parseInt(event.currentTarget.dataset.index, 10);
        this.activeCreateSessionIndex = index;
    }
    
    handleCreateSessionFieldChange(event) {
        const index = parseInt(event.currentTarget.dataset.index, 10);
        if (Number.isNaN(index) || index < 0) return;
        const field = event.currentTarget.dataset.field;
        // lightning-input uses event.detail; native uses event.target.value
        const value = (event.detail && event.detail.value !== undefined)
            ? event.detail.value
            : (event.target && event.target.value !== undefined ? event.target.value : null);
        const updated = [...this.createSessionsList];
        if (!updated[index]) return;
        updated[index] = { ...updated[index], [field]: value };
        // SE-502: Added student loading for Make Up Exam activity —
        // loads eligible students from main division and already-checked programs
        if (field === 'courseActivity') {
        if (value === 'Make Up Exam') {
           console.log('Session Data:', JSON.stringify(updated[index]));
           console.log('Division Id:', updated[index].divisionId);
           const courseValue = this.selectedCourse || '';
           const courseParts = courseValue.split('|');
           const courseId = courseParts.length > 1 ? courseParts[1] : null;
           getEligibleMakeupStudents({
           divisionId: this.selectedDivision,
           courseId: courseId
            })
            .then(result => {
                this.eligibleStudentOptions = result.map(student => ({
                label: student.studentName,
                value: student.studentId
                }));

                this.selectedStudentIds = [];
                this.studentDivisionMap[this.selectedDivision] = result.map(s => s.studentId);
                this.createSessionsList = [...updated];
            // Also load students for already checked programs
            const session = updated[index];
            const checkedKeys = session.selectedAssignmentKeys || [];
            if (checkedKeys.length > 0) {
                const courseValue = this.selectedCourse || '';
                const courseParts = courseValue.split('|');
                const courseId = courseParts.length > 1 ? courseParts[1] : null;

                checkedKeys.forEach(assignmentKey => {
                const assignment = (this.courseAssignments || []).find(
                a => a.assignmentKey != null && String(a.assignmentKey).trim() === String(assignmentKey).trim()
                );
                const divisionId = assignment ? this.getAssignmentDivisionId(assignment) : null;
                    if (!divisionId || divisionId === this.selectedDivision) return;
                        getEligibleMakeupStudents({ divisionId, courseId })
                        .then(res => {
                        const newStudents = (res || []).map(s => ({
                        label: s.studentName,
                        value: s.studentId
                        }));
                    this.studentDivisionMap[divisionId] = newStudents.map(s => s.value);
                    const existing = this.eligibleStudentOptions || [];
                    const existingValues = new Set(existing.map(o => o.value));
                    const toAdd = newStudents.filter(s => !existingValues.has(s.value));
                    this.eligibleStudentOptions = [...existing, ...toAdd];
                })
                .catch(error => {
                    console.error('Error loading students for checked program', divisionId, error);
                });
                });
                }
            })

        } else {

            updated[index].eligibleStudents = [];
            updated[index].selectedStudentIds = [];
            this.eligibleStudentOptions = [];   // ← ADD THIS
            this.selectedStudentIds = [];       // ← ADD THIS

            this.createSessionsList = [...updated];
        }
        }
            
     // When Course Activity changes to non-Joint, restrict to single lead only; preserve support faculty
   if (field === 'courseActivity' && !this.isCourseActivityJointSession(value)) {
            const session = updated[index];
            const leadFacultyIds = session.leadFacultyIds || [];
            const existingLeadId = session.leadFacultyId || (leadFacultyIds.length > 0 ? leadFacultyIds[0] : '');
            const leadId = existingLeadId || '';
            const allFacultyIds = session.facultyIds || [];
            const supportIds = allFacultyIds.filter(id => !leadFacultyIds.some(lid => this.idsEqual(lid, id)));
            const facultyIdsWithSupport = leadId ? [leadId, ...supportIds] : supportIds;
            updated[index] = {
                ...session,
                leadFacultyIds: leadId ? [leadId] : [],
                facultyIds: facultyIdsWithSupport.length > 0 ? facultyIdsWithSupport : (leadId ? [leadId] : []),
                leadFacultyId: leadId || undefined
            };
        }
        // When user changes start time, auto-update end time: use batch duration if set, else 60 minutes
        const startValue = value != null ? String(value).trim() : '';
        if (field === 'startTime' && startValue) {
            const raw = (this.sessionDuration != null && this.sessionDuration > 0) ? this.sessionDuration : 60;
            const durationMinutes = Math.round(Number(raw));
            updated[index].endTime = this.addMinutesToTime(startValue, durationMinutes);
        }
        this.createSessionsList = updated;
        this.loadFacultyConflicts();
    }

    // SE-502: Stores selected student IDs per session in createSessionsList
    handleStudentSelection(event) {
    const index = parseInt(event.target.dataset.index, 10);

    if (Number.isNaN(index)) {
        return;
    }

    const updated = [...this.createSessionsList];

    updated[index].selectedStudentIds = event.detail.value;

    this.createSessionsList = [...updated];
}

   isMultiFacultySession(sessionType) {
    return sessionType === 'Joint Session' ||
           sessionType === 'Combined Session';
    }

    get hasEligibleStudents() {
    return this.eligibleStudentOptions &&
           this.eligibleStudentOptions.length > 0;
}
    // SE-502: Returns true if all eligible students are selected (drives select-all checkbox state)
    get allStudentsSelected() {
    const session = this.createSessionsList && this.createSessionsList[this.activeCreateSessionIndex];
    if (!session || !this.eligibleStudentOptions || this.eligibleStudentOptions.length === 0) return false;
    const selected = session.selectedStudentIds || [];
    return this.eligibleStudentOptions.every(o => selected.includes(o.value));
    }
    
    // SE-502: Selects or deselects all eligible students in create session
    handleSelectAllStudents(event) {
    const isChecked = event.target.checked;
    const index = parseInt(event.target.dataset.index, 10);
    if (Number.isNaN(index)) return;
    const updated = [...this.createSessionsList];
    updated[index] = {
        ...updated[index],
        selectedStudentIds: isChecked ? this.eligibleStudentOptions.map(o => o.value) : []
    };
    this.createSessionsList = updated;
    this.selectedStudentIds = isChecked ? this.eligibleStudentOptions.map(o => o.value) : [];
}
    
    handleCreateSessionLeadFacultyChange(event) {
        const index = parseInt(event.currentTarget.dataset.index, 10);
        const value = event.detail.value || '';
        
        if (Number.isNaN(index) || index < 0) return;
        const updated = [...this.createSessionsList];
        const session = updated[index];
        if (!session) return;
        const isMulti = this.isMultiFacultySession(session.sessionType);
       
        const facultyIds = session.facultyIds || [];
        const leadFacultyIds = (session.leadFacultyIds && session.leadFacultyIds.length > 0)
            ? session.leadFacultyIds
            : (session.leadFacultyId ? [session.leadFacultyId] : []);
        const supportIds = (session.facultyIds || []).filter(id =>
            !leadFacultyIds.some(lid => this.idsEqual(lid, id))
        );
        if (isMulti) {
            // Joint Session: Faculty can be multiple — add to leadFacultyIds
            if (leadFacultyIds.some(lid => this.idsEqual(lid, value))) return;
            const newLeadIds = [...leadFacultyIds, value];
            updated[index] = {
                ...session,
                leadFacultyIds: newLeadIds,
                leadFacultyId: newLeadIds[0],
                facultyIds: [...newLeadIds, ...supportIds],
                facultyComboboxValue: ''
            };
        } else {
            // Non-Joint: Faculty is single — preserve support faculty when changing lead
            updated[index] = {
                ...session,
                leadFacultyIds: value ? [value] : [],
                leadFacultyId: value || undefined,
                facultyIds: value ? [value, ...supportIds] : supportIds,
                facultyComboboxValue: ''
            };
        }
        this.createSessionsList = updated;
        this.loadFacultyConflicts();
        this.resetCreateSessionFacultyCombobox(index);
    }

    handleCreateSessionSupportFacultyAdd(event) {
        const index = parseInt(event.currentTarget.dataset.index, 10);
        const value = event.detail.value;
        if (!value) return;
        const updated = [...this.createSessionsList];
        const session = updated[index];
        if (!session) return;
        const facultyIds = session.facultyIds || [];
        if (facultyIds.some(fid => this.idsEqual(fid, value))) return;
        const leadFacultyIds = (session.leadFacultyIds && session.leadFacultyIds.length > 0)
            ? session.leadFacultyIds
            : (session.leadFacultyId ? [session.leadFacultyId] : []);
        const supportIds = (session.facultyIds || []).filter(id =>
            !leadFacultyIds.some(lid => this.idsEqual(lid, id))
        );
        const newSupportIds = [...supportIds, value];
        updated[index] = {
            ...session,
            facultyIds: [...leadFacultyIds, ...newSupportIds],
            facultyComboboxValue: ''
        };
        this.createSessionsList = updated;
        this.loadFacultyConflicts();
        this.resetCreateSessionFacultyCombobox(index);
    }

    handleCreateSessionAddFaculty(event) {
        const index = parseInt(event.currentTarget.dataset.index, 10);
        const value = event.detail.value;
        if (!value) return;
        const session = (this.createSessionsList || [])[index];
        const isJoint = session && this.isCourseActivityJointSession(session.courseActivity);
        if (isJoint) {
            this.handleCreateSessionSupportFacultyAdd(event);
            return;
        }
        this.handleCreateSessionLeadFacultyChange(event);
    }
    
    handleCreateSessionRemoveFaculty(event) {
        event.stopPropagation();
        const sessionIndex = parseInt(event.currentTarget.dataset.sessionIndex, 10);
        const facultyValue = event.currentTarget.dataset.faculty;
        const updated = [...this.createSessionsList];
        const session = updated[sessionIndex];
        if (!session) return;
        const leadFacultyIds = (session.leadFacultyIds && session.leadFacultyIds.length > 0)
            ? session.leadFacultyIds
            : (session.leadFacultyId ? [session.leadFacultyId] : []);
        const supportIds = (session.facultyIds || []).filter(id =>
            !leadFacultyIds.some(lid => this.idsEqual(lid, id))
        );
        const isFromLead = leadFacultyIds.some(lid => this.idsEqual(lid, facultyValue));
        let newLeadFacultyIds = leadFacultyIds;
        let newFacultyIds = (session.facultyIds || []).filter(id => !this.idsEqual(id, facultyValue));
        if (isFromLead) {
            newLeadFacultyIds = leadFacultyIds.filter(id => !this.idsEqual(id, facultyValue));
            newFacultyIds = [...newLeadFacultyIds, ...supportIds];
        }
        updated[sessionIndex] = {
            ...session,
            leadFacultyIds: newLeadFacultyIds,
            leadFacultyId: newLeadFacultyIds.length > 0 ? newLeadFacultyIds[0] : undefined,
            facultyIds: newFacultyIds,
            facultyComboboxValue: ''
        };
        this.createSessionsList = updated;
        this.loadFacultyConflicts();
        this.resetCreateSessionFacultyCombobox(sessionIndex);
    }
    
    /** Hard reset for create session faculty combobox so removed faculty can be re-selected. */
    resetCreateSessionFacultyCombobox(sessionIndex) {
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        setTimeout(() => {
            try {
                // Find combobox by data-index attribute to ensure we get the correct one
                const combos = this.template.querySelectorAll('.faculty-selector lightning-combobox[data-index]');
                combos.forEach(combo => {
                    const idx = parseInt(combo.getAttribute('data-index'), 10);
                    if (idx === sessionIndex) {
                        combo.value = null;
                    }
                });
            } catch (e) {
                // Non-critical; ignore
            }
        }, 0);
    }
    
    handleCreateSessionProgramToggle(event) {
        const rawKey = event.currentTarget.dataset.assignmentKey;
        const assignmentKey = rawKey != null ? String(rawKey).trim() : '';
        if (!assignmentKey) return;
        const isChecked = event.target.checked;
        const session = this.createSessionsList[this.activeCreateSessionIndex];
        if (!session) return;
        let keys = [...(session.selectedAssignmentKeys || [])];
        if (isChecked) {
            if (!keys.includes(assignmentKey)) keys.push(assignmentKey);
        } else {
            keys = keys.filter(k => k != null && String(k).trim() !== assignmentKey);
        }
        const updated = [...this.createSessionsList];
        updated[this.activeCreateSessionIndex] = { ...session, selectedAssignmentKeys: keys };
        this.createSessionsList = updated;

        // SE-502: Added division tracking — loads/removes students
        // for checked/unchecked programs using studentDivisionMap
        // Load/remove students only for THIS program's division
        if (session.courseActivity === 'Make Up Exam') {
        const assignment = (this.courseAssignments || []).find(
            a => a.assignmentKey != null && String(a.assignmentKey).trim() === assignmentKey
        );
        const divisionId = assignment ? this.getAssignmentDivisionId(assignment) : null;
        if (!divisionId) return;

        const courseValue = this.selectedCourse || '';
        const courseParts = courseValue.split('|');
        const courseId = courseParts.length > 1 ? courseParts[1] : null;

        if (isChecked) {
            getEligibleMakeupStudents({ divisionId, courseId })
                .then(result => {
                    const newStudents = (result || []).map(s => ({
                        label: s.studentName,
                        value: s.studentId
                    }));
                    this.studentDivisionMap[divisionId] = newStudents.map(s => s.value);  // ← ADD THIS
                    const existing = this.eligibleStudentOptions || [];
                    const existingValues = new Set(existing.map(o => o.value));
                    const toAdd = newStudents.filter(s => !existingValues.has(s.value));
                    this.eligibleStudentOptions = [...existing, ...toAdd];
                })
                .catch(error => {
                    console.error('Error fetching students for division', divisionId, error);
                });
        }else {
        // Only remove students EXCLUSIVE to this division
        const removedIds = this.studentDivisionMap[divisionId] || [];
        delete this.studentDivisionMap[divisionId];

        const stillNeededIds = new Set(
            Object.values(this.studentDivisionMap).flat()
        );

        const toRemove = new Set(removedIds.filter(id => !stillNeededIds.has(id)));

        this.eligibleStudentOptions = (this.eligibleStudentOptions || [])
            .filter(o => !toRemove.has(o.value));

        const currentSession = this.createSessionsList[this.activeCreateSessionIndex];
        if (currentSession) {
            const u = [...this.createSessionsList];
            u[this.activeCreateSessionIndex] = {
                ...currentSession,
                selectedStudentIds: (currentSession.selectedStudentIds || [])
                    .filter(id => !toRemove.has(id))
            };
            this.createSessionsList = u;
        }
    } 
}

}
    
    handleSelectAllCreateSessionPrograms(event) {
        const isChecked = event.target.checked;
        const session = this.createSessionsList[this.activeCreateSessionIndex];
        if (!session || !this.courseAssignments || this.courseAssignments.length === 0) return;
        const filtered = this.courseAssignments.filter(a => !this.isAssignmentCurrentContext(a));
        const keys = isChecked ? filtered.map(a => a.assignmentKey) : [];
        const updated = [...this.createSessionsList];
        updated[this.activeCreateSessionIndex] = { ...session, selectedAssignmentKeys: keys };
        this.createSessionsList = updated;
}

    loadFacultyConflicts() {
        if (!this.createSessionsList || this.createSessionsList.length === 0) {
            this.facultyConflicts = [];
            return;
        }
        const validSessions = this.createSessionsList.filter(s =>
            s.date && s.startTime && s.endTime && (s.facultyIds || []).length > 0
        );
        if (validSessions.length === 0) {
            this.facultyConflicts = [];
            return;
        }
        const payload = [];
        for (const s of validSessions) {
            let sessionDate = s.date;
            if (sessionDate instanceof Date) {
                sessionDate = sessionDate.toISOString().split('T')[0];
            } else if (typeof sessionDate === 'string' && sessionDate.includes('T')) {
                sessionDate = sessionDate.split('T')[0];
            }
            if (!sessionDate || !s.startTime || !s.endTime) continue;
            // Send local date + time (not ISO/UTC) so conflict details show "Your session" in user's timezone
            const dArr = this.getCreateSessionDivisionIdsForRow(s);
            const dOne = dArr.length === 1 ? dArr[0] : null;
            payload.push({
                sessionName: s.title || 'Session',
                sessionDate,
                startTime: s.startTime,
                endTime: s.endTime,
                selectedFacultyIds: Array.isArray(s.facultyIds) ? s.facultyIds : [],
                proposedContext: this.buildProposedConflictContextForPayload(
                    {
                        courseId: this.modalCourse,
                        programId: this.modalProgram || this.selectedProgram,
                        batchId: this.modalBatch || this.selectedBatch,
                        academicYearId: this.selectedBatchGroup,
                        termId: this.modalTerm || this.selectedTerm
                    },
                    dOne,
                    dArr.length > 1 ? dArr : dOne ? [dOne] : [],
                    s.selectedAssignmentKeys || []   // ← ADD THIS
                )
            });
        }
        if (payload.length === 0) {
            this.facultyConflicts = [];
            return;
        }
        getFacultyConflictsForSessions({ sessionsJson: JSON.stringify(payload) })
            .then((result) => {
                this.facultyConflicts = Array.isArray(result) ? result : [];
            })
            .catch((error) => {
                this.facultyConflicts = [];
            });
    }

    handleOpenConflictsModal() {
        if (!this.conflictOverrideSaveMode) {
            this.conflictOverrideSaveMode = this.isCreateSessionsMode ? 'create' : 'edit';
        }
        this.showConflictsModal = true;
    }

    handleCloseConflictsModal() {
        this.showConflictsModal = false;
        this.pendingConflictOverride = false;
        this.conflictOverrideSaveMode = null;
        this.pendingOverrideEvent = null;
    }

    /**
     * Opens the conflict details modal for a save that was refused, either by the client precheck
     * or by the org, remembering which save path "Submit anyway" has to re-run.
     *
     * @param mode Which save path to re-run on override: 'create' | 'edit' | 'persist'.
     */
    showConflictsForBlockedSave(mode) {
        this.conflictOverrideSaveMode = mode;
        this.showConflictsModal = true;
    }

    /**
     * Whether the form moves this session to a different date or time than the one saved in the
     * org. Only then is a Google availability read worth its callout — the same condition the org
     * applies in TimetableSessionController.isRescheduleNeedingCalendarCheck, so the client and
     * the server agree on when a reschedule is a reschedule.
     *
     * @param editingEvent The session row as loaded from the org; null when creating.
     * @return True when the date, the start time or the end time differs.
     */
    hasTimingChangedFromSavedSession(editingEvent) {
        if (!editingEvent) {
            return false; // a create: the screen has already checked availability
        }
        const savedDate = this.normalizeDateString(editingEvent.date);
        const formDate = this.normalizeDateString(this.eventDate);
        return savedDate !== formDate
            || editingEvent.startTime !== this.eventStartTime
            || editingEvent.endTime !== this.eventEndTime;
    }

    /**
     * User chose to create/update despite conflicts: re-run the matching save path with override.
     */
    handleConflictSubmitAnyway() {
        this.pendingConflictOverride = true;
        this.showConflictsModal = false;
        const mode = this.conflictOverrideSaveMode || (this.isCreateSessionsMode ? 'create' : 'edit');
        this.conflictOverrideSaveMode = null;
        if (mode === 'create') {
            this.handleCreateSessionsSave();
        } else if (mode === 'persist' && this.pendingOverrideEvent) {
            this.retryPersistWithOverride();
        } else {
            this.handleSaveEvent();
        }
    }

    /**
     * Re-saves a drag/drop or resize reschedule that a conflict blocked, now with the override,
     * and puts the timetable back in step with whatever the org ended up storing.
     */
    retryPersistWithOverride() {
        const eventToRetry = { ...this.pendingOverrideEvent, ignoreConflicts: true };
        this.pendingOverrideEvent = null;
        this.persistSessionChanges(eventToRetry)
            .then(() => {
                this.pendingConflictOverride = false;
                this.showToastMessage(`"${eventToRetry.title}" rescheduled.`, 'success');
                this.sessionsRefreshKey = Date.now();
                if (this.wiredSessionsResult) {
                    return refreshApex(this.wiredSessionsResult);
                }
                return Promise.resolve();
            })
            .catch((error) => {
                this.pendingConflictOverride = false;
                this.handleSaveError(error);
                if (this.wiredSessionsResult) {
                    return refreshApex(this.wiredSessionsResult);
                }
                return Promise.resolve();
            });
    }

    handleCloseStudentConflictsModal() {
        this.showStudentConflictsModal = false;
    }
    
    async handleCreateSessionsSave() {
        this.createSessionsSaveAttempted = true;
        if (!this.modalCourse || !String(this.modalCourse).trim()) {
            this.showToastMessage('Course is required.', 'error');
            return;
        }
        if (!this.createSessionsList || this.createSessionsList.length === 0) {
            this.showToastMessage('Add at least one session.', 'error');
            return;
        }
        if (this.createSessionsHasNoLeadFaculty) {
            this.showToastMessage('At least one Faculty (lead) is required for each session. Support faculty alone is not enough.', 'error');
            return;
        }
        const sessionIndex = this.createSessionsList.findIndex(s => {
            const titleOk = s.title && String(s.title).trim();
            const facultyOk = (s.facultyIds || []).length > 0;
            const dateOk = s.date && String(s.date).trim();
            const startOk = s.startTime && String(s.startTime).trim();
            const endOk = s.endTime && String(s.endTime).trim();
            return !titleOk || !facultyOk || !dateOk || !startOk || !endOk;
        });
        if (sessionIndex >= 0) {
            const session = this.createSessionsList[sessionIndex];
            const num = sessionIndex + 1;
            if (!session.title || !String(session.title).trim()) {
                this.showToastMessage(`Session Title is required for Session ${num}.`, 'error');
                return;
            }
            if (!(session.facultyIds || []).length) {
                this.showToastMessage(`Faculty is required for Session ${num}.`, 'error');
                return;
            }
            if (!this.sessionHasLeadFaculty(session)) {
                this.showToastMessage(`At least one Faculty (lead) is required for Session ${num}. Support faculty alone is not enough.`, 'error');
                return;
            }
            if (!session.date || !String(session.date).trim()) {
                this.showToastMessage(`Date is required for Session ${num}.`, 'error');
                return;
            }
            if (!session.startTime || !String(session.startTime).trim()) {
                this.showToastMessage(`Start Time is required for Session ${num}.`, 'error');
                return;
            }
            if (!session.endTime || !String(session.endTime).trim()) {
                this.showToastMessage(`End Time is required for Session ${num}.`, 'error');
                return;
            }
        }
        const valid = this.createSessionsList.filter(s => s.date && s.startTime && s.endTime);
        if (valid.length === 0) {
            this.showToastMessage('Add at least one session with date and times', 'error');
            return;
        }
        // Capture override after validation so early returns above never leave a sticky flag.
        const ignoreConflicts = this.pendingConflictOverride === true;
        this.pendingConflictOverride = false;
        this.isSaving = true;
        const promises = [];
        const divisionId = this.isAllDivisionsSelected
            ? (this.modalDivisionId || null)
            : this.selectedDivision;

        const initiatingDivisionIdForColor = (() => {
            if (this.isAllDivisionsSelected && this.modalDivisionId) {
                return String(this.modalDivisionId);
            }
            if (!this.isAllDivisionsSelected && this.selectedDivision && this.selectedDivision !== TimetableCalendar.ALL_DIVISIONS_VALUE) {
                return String(this.selectedDivision);
            }
            return divisionId ? String(divisionId) : null;
        })();

        // Merge sessions that have same date, time, and faculty into one session with combined divisions
        // so we never create multiple Session__c records at the same time for the same faculty
        const mergedSessions = [];
        const seen = new Set();
        for (const session of this.createSessionsList) {
            if (!session.date || !session.startTime || !session.endTime) continue;
            const facultyKey = [...(session.facultyIds || [])].sort().join(',');
            const slotKey = `${session.date}|${session.startTime}|${session.endTime}|${facultyKey}`;
            const divIds = this.getCreateSessionDivisionIdsForRow(session);
            if (divIds.length === 0) {
                this.showToastMessage('Please select a division in the sidebar or select programs to merge for each session.', 'error');
                this.isSaving = false;
                return;
            }
            if (seen.has(slotKey)) {
                const existing = mergedSessions.find(m => m.slotKey === slotKey);
                if (existing) {
                    const combined = [...new Set([...existing.divisionIds, ...divIds])];
                    existing.divisionIds = combined;
                    existing.title = existing.title || session.title || 'Session';
                }
                continue;
            }
            seen.add(slotKey);
            mergedSessions.push({
                slotKey,
                title: session.title || 'Session',
                date: session.date,
                startTime: session.startTime,
                endTime: session.endTime,
                divisionIds: [...new Set(divIds)],
                colorSourceDivisionId: initiatingDivisionIdForColor,
                courseActivity: session.courseActivity || null,
                sessionType: session.sessionType || null,
                selectedStudentIds: session.selectedStudentIds || [], 
                facultyIds: session.facultyIds || [],
                leadFacultyId: session.leadFacultyId || null,
                leadFacultyIds: (session.leadFacultyIds && session.leadFacultyIds.length > 0) ? session.leadFacultyIds : (session.leadFacultyId ? [session.leadFacultyId] : []),
                classRoom: session.classRoom || '',
                remark: session.remark || '',
                selectedStudentIds: session.selectedStudentIds || [], // SE-502: Passes selectedStudentIds in save payload for Make Up Exam
                url: session.url || '',
                selectedAssignmentKeys: session.selectedAssignmentKeys || []  // ← ADD THIS
            });
        }

        if (mergedSessions.length === 0) {
            this.showToastMessage('No valid sessions to create.', 'error');
            this.isSaving = false;
            return;
        }

        for (const session of mergedSessions) {
            let sessionDate = session.date;
            if (sessionDate instanceof Date) {
                sessionDate = sessionDate.toISOString().split('T')[0];
            } else if (typeof sessionDate === 'string' && sessionDate.includes('T')) {
                sessionDate = sessionDate.split('T')[0];
            }
            try {
                this.validateSessionDateWithinTermBounds(sessionDate, this.selectedTerm);
            } catch (e) {
                this.showToastMessage(e.message || 'Session date is outside the selected term.', 'error');
                this.isSaving = false;
                return;
            }
        }

        // Pre-check faculty and division/session conflicts for ALL sessions before saving any
        const facultyPayload = [];
        const divisionPayload = [];
        for (const session of mergedSessions) {
            let sessionDate = session.date;
            if (sessionDate instanceof Date) {
                sessionDate = sessionDate.toISOString().split('T')[0];
            } else if (typeof sessionDate === 'string' && sessionDate.includes('T')) {
                sessionDate = sessionDate.split('T')[0];
            }
            if (!sessionDate || !session.startTime || !session.endTime) continue;
            const dArr = Array.isArray(session.divisionIds) ? session.divisionIds : [];
            const dOne = dArr.length === 1 ? dArr[0] : null;
            // Send local date + time (not ISO/UTC) so server shows "Your session" in user's timezone (e.g. 2:00 PM not 8:30 AM)
            facultyPayload.push({
                sessionName: session.title || 'Session',
                sessionDate,
                startTime: session.startTime,
                endTime: session.endTime,
                selectedFacultyIds: Array.isArray(session.facultyIds) ? session.facultyIds : [],
                proposedContext: this.buildProposedConflictContextForPayload(
                    {
                        courseId: session.courseId || this.modalCourse,
                        programId: this.modalProgram || this.selectedProgram,
                        batchId: this.modalBatch || this.selectedBatch,
                        academicYearId: this.selectedBatchGroup,
                        termId: this.modalTerm || this.selectedTerm
                    },
                    dOne,
                
                    dArr.length > 1 ? dArr : dOne ? [dOne] : [],
                    session.selectedAssignmentKeys || [] // ← ADD THIS
                )
            });
            divisionPayload.push({
                sessionName: session.title || 'Session',
                sessionDate,
                startTime: session.startTime,
                endTime: session.endTime,
                divisionIds: dArr,
                proposedContext: this.buildProposedConflictContextForPayload(
                    {
                        courseId: session.courseId || this.modalCourse,
                        programId: this.modalProgram || this.selectedProgram,
                        batchId: this.modalBatch || this.selectedBatch,
                        academicYearId: this.selectedBatchGroup,
                        termId: this.modalTerm || this.selectedTerm
                    },
                    dOne,
                    dArr.length > 1 ? dArr : dOne ? [dOne] : [],
                    session.selectedAssignmentKeys || []
                )
            });
        }
        try {
            // After user confirmed via Submit, skip precheck and proceed to save with ignoreConflicts.
            if (!ignoreConflicts) {
                const [facultyConflictsResult, sessionConflictsResult, calendarConflictsResult] = await Promise.all([
                    getFacultyConflictsForSessions({ sessionsJson: JSON.stringify(facultyPayload) }),
                    getDivisionSessionConflictsForSessions({ sessionsJson: JSON.stringify(divisionPayload) }),
                    getFacultyCalendarConflictsForSessions({ sessionsJson: JSON.stringify(facultyPayload) })
                ]);
                const hasFacultyConflicts = Array.isArray(facultyConflictsResult) && facultyConflictsResult.length > 0;
                const hasSessionConflicts = Array.isArray(sessionConflictsResult) && sessionConflictsResult.length > 0;
                const hasCalendarConflicts = Array.isArray(calendarConflictsResult) && calendarConflictsResult.length > 0;
                if (hasFacultyConflicts || hasSessionConflicts || hasCalendarConflicts) {
                    this.facultyConflicts = hasFacultyConflicts ? facultyConflictsResult : [];
                    this.sessionConflicts = hasSessionConflicts ? sessionConflictsResult : [];
                    this.calendarConflicts = hasCalendarConflicts ? calendarConflictsResult : [];
                    this.showConflictsForBlockedSave('create');
                    this.isSaving = false;
                    return;
                }
            }
        } catch (conflictCheckError) {
            console.error('Conflict check failed:', conflictCheckError);
            this.isSaving = false;
            this.showToastMessage('Unable to verify conflicts. Please try again.', 'error');
            return;
        }

        const sendNotifications = await this.promptSendFacultyNotifications();
        if (sendNotifications === null) {
            this.isSaving = false;
            return;
        }

        for (const session of mergedSessions) {
            const divisionIdsForSession = session.divisionIds;
            const payload = {
                id: null,
                title: session.title,
                date: session.date,
                startTime: session.startTime,
                endTime: session.endTime,
                divisionId: divisionIdsForSession.length === 1 ? divisionIdsForSession[0] : null,
                divisionIds: divisionIdsForSession.length > 1 ? divisionIdsForSession : null,
            programId: this.modalProgram || this.selectedProgram || null,
            batchId: this.modalBatch || this.selectedBatch || null,
            academicYearId: this.selectedBatchGroup || null,
            termId: this.modalTerm || this.selectedTerm || null,
            courseId: this.modalCourse || this.selectedCourse || null,
                batchWiseCourseId: null,
                numberOfSessions: 1,
                colorSourceDivisionId: session.colorSourceDivisionId || null,
                courseActivity: session.courseActivity,
                sessionType: session.sessionType || null,
                selectedFacultyIds: session.facultyIds,
                leadFacultyId: session.leadFacultyId || null,
                leadFacultyIds: (session.leadFacultyIds && session.leadFacultyIds.length > 0) ? session.leadFacultyIds : null,
                classRoom: session.classRoom || '',
                remark: session.remark || '',
                url: session.url || '',
                selectedStudentIds: session.selectedStudentIds || [],  //SE-502
                ignoreConflicts,
                sendNotifications
            };
            let sessionPayload;
            try {
                sessionPayload = this.buildSessionPayload(payload);
            } catch (e) {
                this.showToastMessage(e.message || 'Invalid session', 'error');
                this.isSaving = false;
                return;
                
            }
            promises.push(saveSession({ requestJson: JSON.stringify(sessionPayload) }));
        }
        Promise.all(promises)
            .then((results) => {
                const withWarning = Array.isArray(results) && results.some(r => r && (r.warningMessage || (r.warningDetails && r.warningDetails.length > 0)));
                const n = promises.length;
                const sessionWord = n === 1 ? 'session' : 'sessions';
                const successMessage = withWarning
                    ? `${n} ${sessionWord} created. Some students have overlapping schedules.`
                    : `${n} ${sessionWord} created successfully.`;
                this.showToastMessage(successMessage, withWarning ? 'warning' : 'success');
                // Ensure subsequent filter toggles (e.g. Draft only) do not reuse stale cached data.
                this.sessionsRefreshKey = Date.now();
                if (this.wiredSessionsResult) {
                    return refreshApex(this.wiredSessionsResult);
                }
                return Promise.resolve();
            })
            .then(() => {
                this.handleCloseModal();
            })
            .catch(error => {
                this.handleSaveError(error);
            })
            .finally(() => {
                this.isSaving = false;
            });
    }

    handleModalClick(event) {
        event.stopPropagation();
    }

    resetEventForm() {
        this.eventTitle = '';
        this.eventDate = '';
        this.eventStartTime = '09:00';
        this.eventEndTime = '10:00';
        this.eventLocation = '';
        this.eventDescription = '';
        this.eventClassRoom = '';
        this.eventRemark = '';
        this.eventUrl = '';
        this.selectedCourse = '';
        this.selectedCourseActivity = '';
        this.selectedSessionType = '';
        this.courseAssignments = [];
        this.selectedAssignments = [];
        this.showCourseAssignments = false;
        this.editModalFacultyNameList = [];
        this.existingSessionDivisions = [];
        this.editAddCourseAssignments = [];
        this.editAddSelectedKeys = [];
        this.isRecurring = false;
        this.recurringType = 'weekly';
        this.recurringInterval = 1;
        this.recurringEndDate = '';
        this.selectedWeekdays = [1];
        this.isJointSession = false;
        this.selectedFacultyValue = [];
        this.editFacultyComboboxValue = '';
        this.facultyOptions = [];
        this.selectedCourseDepartmentName = '';
        this.modalDivisionId = null;
        // SE-502: Clear all Make Up Exam student tracking on modal reset
        this.studentNames = [];
        this.editEnrolledStudentOptions = [];
        this.editEnrolledSelectedIds = [];
        this.editStudentDivisionMap = {};
        //SE-502
    }

    // SE-502: Returns true if all edit session students are selected
    get allEditStudentsSelected() {
    if (!this.editEnrolledStudentOptions || this.editEnrolledStudentOptions.length === 0) return false;
    return this.editEnrolledStudentOptions.every(o => this.editEnrolledSelectedIds.includes(o.value));
    }
    
    // SE-502: Selects or deselects all eligible students in edit session
    handleSelectAllEditStudents(event) {
    const isChecked = event.target.checked;
    this.editEnrolledSelectedIds = isChecked ? this.editEnrolledStudentOptions.map(o => o.value) : [];
    }
    
    // SE-502: Stores selected student IDs in edit session
    handleEligibleStudentEditSelection(event) {
    this.editEnrolledSelectedIds = event.detail.value;
    }

    handleAllDivisionsSlotClick(event) {
        event.stopPropagation();
        const hour = event.currentTarget.dataset.hour;
        const day = event.currentTarget.dataset.day;
        const divisionId = event.currentTarget.dataset.division;
        if (!hour || !day || !divisionId) return;
        this.modalDivisionId = divisionId;
        // Pass clicked hour/day explicitly so start time is always correct (event.currentTarget can be unreliable when delegating)
        this.handleCellClick(event, hour, day);
    }

    handleAllDivisionsWeekCellClick(event) {
        if (this.isDragging) return;
        // Only handle click on the cell itself, not on an event inside (events use handleEventClick with stopPropagation)
        if (event.target.closest('[data-id]')) return;
        event.stopPropagation();
        const day = event.currentTarget.dataset.day;
        const hour = event.currentTarget.dataset.hour;
        // Time-only grid: no per-cell division; default to first division so user can create a session
        const divisionId = event.currentTarget.dataset.division ||
            (this.divisionsForMatrix && this.divisionsForMatrix[0] && this.divisionsForMatrix[0].value) || null;
        if (!day) return;
        this.modalDivisionId = divisionId;
        this.isEditMode = false;
        this.selectedEventId = null;
        this.eventDate = day;
        this.eventClassRoom = '';
        this.eventRemark = '';
        this.eventUrl = '';
        // Use clicked row's hour (e.g. 14 for 2pm) so start time reflects the slot; fallback to 9am if missing
        const startHour = (hour != null && hour !== '') ? parseInt(String(hour), 10) : 9;
        const hourPadded = String(startHour).padStart(2, '0');
        this.eventStartTime = `${hourPadded}:00`;
        let endTime = '';
        if (this.sessionDuration && this.sessionDuration > 0) {
            const totalStartMinutes = startHour * 60;
            const durationMinutes = Math.round(Number(this.sessionDuration));
            const totalEndMinutes = totalStartMinutes + durationMinutes;
            const endHour = Math.floor(totalEndMinutes / 60);
            const endMinutes = totalEndMinutes % 60;
            endTime = `${endHour.toString().padStart(2, '0')}:${endMinutes.toString().padStart(2, '0')}`;
        } else {
            endTime = `${String(startHour + 1).padStart(2, '0')}:00`;
        }
        this.eventEndTime = endTime;
        this.initializeCreateSessionsModal();
        if (this.createSessionsList && this.createSessionsList.length > 0) {
            this.createSessionsList = [
                {
                    ...this.createSessionsList[0],
                    date: day,
                    startTime: this.eventStartTime,
                    endTime: this.eventEndTime
                },
                ...this.createSessionsList.slice(1)
            ];
        }
        this.showModal = true;
    }

    // Form change handlers
    handleTitleChange(event) {
        this.eventTitle = event.target.value;
    }

    handleDateChange(event) {
        this.eventDate = event.target.value;
        // Update default weekday based on selected date
        if (this.eventDate) {
            const dayOfWeek = new Date(this.eventDate).getDay();
            if (!this.selectedWeekdays.includes(dayOfWeek)) {
                this.selectedWeekdays = [dayOfWeek];
            }
        }
        this.loadFacultyConflicts();  //1002
    }

    /** Opens the date picker when user clicks anywhere on the date box (edit and create session). */
    handleDateBoxClick(event) {
        const target = event.target;
        if (target && target.tagName === 'INPUT' && target.type === 'date' && typeof target.showPicker === 'function') {
            target.showPicker();
            return;
        }
        let lightningInput = target && target.tagName === 'LIGHTNING-INPUT' ? target : null;
        if (!lightningInput) {
            const container = event.currentTarget;
            lightningInput = container && container.querySelector ? container.querySelector('lightning-input') : null;
        }
        if (lightningInput && lightningInput.shadowRoot) {
            const input = lightningInput.shadowRoot.querySelector('input[type="date"]');
            if (input && typeof input.showPicker === 'function') {
                input.showPicker();
            }
        }
        this.loadFacultyConflicts();  //1002
    }

    handleStartTimeChange(event) {
        // lightning-combobox uses event.detail.value; native input uses event.target.value
        const value = (event.detail && event.detail.value !== undefined)
            ? event.detail.value
            : (event.target && event.target.value != null ? event.target.value : '');
        if (value === '' || value == null) return;
        const valueStr = String(value).trim();
        this.eventStartTime = valueStr;
        // Auto-update end time: use batch duration if set (rounded to whole minutes), otherwise default 60 minutes
        const raw = (this.sessionDuration != null && this.sessionDuration > 0) ? this.sessionDuration : 60;
        const durationMinutes = Math.round(Number(raw));
        this.eventEndTime = this.addMinutesToTime(valueStr, durationMinutes);
        this.loadFacultyConflicts();  //1002
    }

    handleEndTimeChange(event) {
        const value = (event.detail && event.detail.value !== undefined)
            ? event.detail.value
            : (event.target && event.target.value != null ? event.target.value : '');
        if (value !== '' && value != null) this.eventEndTime = String(value).trim();
        this.loadFacultyConflicts();  //1002
    }

    handleClassRoomChange(event) {
        this.eventClassRoom = (event.detail && event.detail.value !== undefined) ? (event.detail.value || '') : '';
    }

    handleRemarkChange(event) {
        this.eventRemark = (event.detail && event.detail.value !== undefined) ? (event.detail.value || '') : '';
    }

    handleUrlChange(event) {
        this.eventUrl = (event.detail && event.detail.value !== undefined) ? (event.detail.value || '') : '';
    }

    handleLocationChange(event) {
        this.eventLocation = event.target.value;
    }

    handleDescriptionChange(event) {
        this.eventDescription = event.target.value;
    }

    // Recurring event handlers
    handleRecurringToggle(event) {
        this.isRecurring = event.target.checked;
        if (this.isRecurring && !this.recurringEndDate) {
            // Default end date to 3 months from event date
            const endDate = new Date(this.eventDate || new Date());
            endDate.setMonth(endDate.getMonth() + 3);
            this.recurringEndDate = endDate.toISOString().split('T')[0];
        }
    }

    handleRecurringTypeChange(event) {
        this.recurringType = event.currentTarget.dataset.value;
    }

    handleWeekdayToggle(event) {
        const dayValue = parseInt(event.currentTarget.dataset.value, 10);
        
        if (this.selectedWeekdays.includes(dayValue)) {
            if (this.selectedWeekdays.length > 1) {
                this.selectedWeekdays = this.selectedWeekdays.filter(d => d !== dayValue);
            }
        } else {
            this.selectedWeekdays = [...this.selectedWeekdays, dayValue];
        }
    }

    handleIntervalChange(event) {
        this.recurringInterval = Math.max(1, parseInt(event.target.value, 10) || 1);
    }

    handleRecurringEndDateChange(event) {
        this.recurringEndDate = event.target.value;
    }

    /**
     * Save / Republish from the edit modal. Thin re-entrancy guard around the save itself: the
     * button stays enabled until isSaving is set, which only happens after the notification prompt
     * and the conflict precheck, so a double-click used to start the save twice and ask the user
     * the Yes/No question twice. The flag is cleared in a finally, so a rejected or abandoned
     * save can never leave the button wedged.
     */
    async handleSaveEvent() {
        if (this.saveEventInFlight) {
            return; // the first click owns this save
        }
        this.saveEventInFlight = true;
        try {
            await this.performSaveEvent();
        } finally {
            this.saveEventInFlight = false;
        }
    }

    async performSaveEvent() { /*1002 - added async key word*/
        if (this.isEditSessionReadOnly) {
            this.showToastMessage('This session is completed and read-only. Attendance can still be viewed.', 'error');
            return;
        }
        if (!this.eventTitle || !this.eventDate || !this.eventStartTime || !this.eventEndTime) {
            this.showToastMessage('Please fill in all required fields', 'error');
            return;
        }

        const facultyIds = this.normalizeFacultyIds(this.selectedFacultyValue);
        if (!facultyIds || facultyIds.length === 0) {
            this.showToastMessage('Faculty is required.', 'error');
            return;
        }

        if (this.eventStartTime >= this.eventEndTime) {
            this.showToastMessage('End time must be after start time', 'error');
            return;
        }

        const editingEvent = this.isEditMode && this.selectedEventId
            ? this.findEventRowForSession(this.selectedEventId, this.clickedTileDivisionId)
            : null;

        const payloadSource = {
            id: this.isEditMode ? this.selectedEventId : null,
            title: this.eventTitle,
            date: this.eventDate,
            startTime: this.eventStartTime,
            endTime: this.eventEndTime,
            description: this.eventDescription,
            classRoom: this.eventClassRoom || '',
            remark: this.eventRemark || '',
            url: this.eventUrl || '',
            divisionId: this.isAllDivisionsSelected ? this.modalDivisionId : this.selectedDivision,
            programId: this.modalProgram || this.selectedProgram || null,
            batchId: this.modalBatch || this.selectedBatch || null,
            academicYearId: this.selectedBatchGroup || null,
            termId: this.modalTerm || this.selectedTerm || null,
            courseId: this.modalCourse || this.selectedCourse || null,
            batchWiseCourseId: null,
            courseActivity: this.selectedCourseActivity || null,
            sessionType: this.selectedSessionType || null,
            numberOfSessions: 1
        };

        if (editingEvent) {
            payloadSource.divisionId = editingEvent.divisionId || payloadSource.divisionId;
            const existingDivisionIds = (this.existingSessionDivisions || []).map(d => d.divisionId).filter(Boolean);
            const addSelected = (this.editAddCourseAssignments || []).filter(a =>
                (this.editAddSelectedKeys || []).includes(String((a.assignmentKey != null ? a.assignmentKey : '')).trim())
            );
            const addDivisionIds = addSelected.map(a => this.getAssignmentDivisionId(a)).filter(Boolean);
            const combinedDivisionIds = [...new Set([...existingDivisionIds, ...addDivisionIds])];
            if (combinedDivisionIds.length > 1) {
                payloadSource.divisionIds = combinedDivisionIds;
            } else if (combinedDivisionIds.length === 1) {
                payloadSource.divisionId = payloadSource.divisionId || combinedDivisionIds[0];
            } else if (existingDivisionIds.length === 1) {
                payloadSource.divisionId = payloadSource.divisionId || existingDivisionIds[0];
            }
            // If course hasn't changed, use original courseId (ID), otherwise use selected course name
            // The backend's resolveLookupId can handle both IDs and names
            if (this.selectedCourse && editingEvent.courseName && this.selectedCourse === editingEvent.courseName) {
                // Course hasn't changed, use original ID
                payloadSource.courseId = editingEvent.courseId || payloadSource.courseId;
            } else {
                // Course changed or new selection, use course name (backend will resolve)
                payloadSource.courseId = this.modalCourse || this.selectedCourse || null;
            }
            payloadSource.batchWiseCourseId = editingEvent.batchWiseCourseId || null;
            // Use form value so the user's Course Activity change is saved (event value is stale from when modal opened)
            payloadSource.courseActivity = (this.selectedCourseActivity !== undefined && this.selectedCourseActivity !== null)
                ? this.selectedCourseActivity
                : (editingEvent.courseActivity || null);
            // Use form value so the user's Session Type change is saved (event value is stale from when modal opened)
            payloadSource.sessionType = (this.selectedSessionType !== undefined && this.selectedSessionType !== null && this.selectedSessionType !== '')
                ? this.selectedSessionType
                : (editingEvent.sessionType || null);
            payloadSource.classRoom = this.eventClassRoom !== undefined ? this.eventClassRoom : (editingEvent.classRoom || '');
            payloadSource.remark = this.eventRemark !== undefined ? this.eventRemark : (editingEvent.remark || '');
            payloadSource.url = this.eventUrl !== undefined ? this.eventUrl : (editingEvent.url || '');
            // Explicitly pass faculty from the edit form so add/remove faculty is saved (leadFacultyIds so all leads get Faculty_Type__c = 'Lead')
            payloadSource.selectedFacultyIds = this.normalizeFacultyIds(this.selectedFacultyValue);
            payloadSource.leadFacultyId = this.editLeadFacultyId || null;
            payloadSource.leadFacultyIds = (this.editLeadFacultyIds && this.editLeadFacultyIds.length > 0)
                ? [...this.editLeadFacultyIds]
                : null;
        } else {
            payloadSource.courseActivity = this.selectedCourseActivity || null;
        }

        payloadSource.colorSourceDivisionId = this.resolveColorSourceDivisionIdForModalSave(editingEvent, payloadSource);

        // Check if we have selected course assignments
        if (this.showCourseAssignments && this.selectedAssignments.length > 0) {
            // This branch saves without a precheck, so the notification question is asked here.
            const sendNotifications = await this.promptSendFacultyNotifications(false, this.isRepublishSave);
            if (sendNotifications === null) {
                return;
            }
            payloadSource.sendNotifications = sendNotifications;
            // Create one session with multiple divisions
            this.createSessionWithMultipleDivisions(payloadSource);
        } else {
            // Single session creation (existing logic)
            let sessionPayload;
            try {
                sessionPayload = this.buildSessionPayload(payloadSource);
            } catch (error) {
                this.showToastMessage(error.message, 'error');
                return;
            }
            /*1002 Start*/
            // ======================================
            // PRE-CHECK CONFLICTS BEFORE SAVE
            // ======================================

            const facultyPayload = [{
                sessionId: sessionPayload.sessionId,
                sessionName: sessionPayload.sessionName,
                sessionDate: sessionPayload.sessionDate,
                startTime: this.eventStartTime,
                endTime: this.eventEndTime,
                selectedFacultyIds: sessionPayload.selectedFacultyIds || [],
                proposedContext: this.buildProposedConflictContextForPayload(
                    payloadSource,
                    sessionPayload.divisionId,
                    sessionPayload.divisionIds
                )
            }];

            const divisionPayload = [{
                sessionId: sessionPayload.sessionId,
                sessionName: sessionPayload.sessionName,
                sessionDate: sessionPayload.sessionDate,
                startTime: this.eventStartTime,
                endTime: this.eventEndTime,
                divisionIds:
                    sessionPayload.divisionIds ||
                    (sessionPayload.divisionId
                        ? [sessionPayload.divisionId]
                        : []),
                proposedContext: this.buildProposedConflictContextForPayload(
                    payloadSource,
                    sessionPayload.divisionId,
                    sessionPayload.divisionIds
                )
            }];

            try {
                if (!this.pendingConflictOverride) {
                    // The Google read is the expensive one (a callout per faculty), and the org only
                    // spends it when the timing actually moved. Match that here so editing a
                    // classroom or a remark on a published session costs nothing extra.
                    const checkCalendar = this.hasTimingChangedFromSavedSession(editingEvent);

                    const [
                        facultyConflictsResult,
                        sessionConflictsResult,
                        calendarConflictsResult
                    ] = await Promise.all([

                        getFacultyConflictsForSessions({
                            sessionsJson: JSON.stringify(facultyPayload)
                        }),

                        getDivisionSessionConflictsForSessions({
                            sessionsJson: JSON.stringify(divisionPayload)
                        }),

                        checkCalendar
                            ? getFacultyCalendarConflictsForSessions({
                                sessionsJson: JSON.stringify(facultyPayload)
                            })
                            : Promise.resolve([])

                    ]);

                    const hasFacultyConflicts =
                        Array.isArray(facultyConflictsResult)
                        && facultyConflictsResult.length > 0;

                    const hasSessionConflicts =
                        Array.isArray(sessionConflictsResult)
                        && sessionConflictsResult.length > 0;

                    const hasCalendarConflicts =
                        Array.isArray(calendarConflictsResult)
                        && calendarConflictsResult.length > 0;

                    if (hasFacultyConflicts || hasSessionConflicts || hasCalendarConflicts) {

                        this.facultyConflicts =
                            hasFacultyConflicts
                                ? facultyConflictsResult
                                : [];

                        this.sessionConflicts =
                            hasSessionConflicts
                                ? sessionConflictsResult
                                : [];

                        this.calendarConflicts =
                            hasCalendarConflicts
                                ? calendarConflictsResult
                                : [];

                        this.showConflictsForBlockedSave('edit');

                        return;
                    }
                }

            } catch (conflictError) {

                console.error(
                    'Conflict precheck failed',
                    conflictError
                );

                this.pendingConflictOverride = false;
                this.showToastMessage(
                    'Unable to validate conflicts.',
                    'error'
                );

                return;
            }
            /*1002 End*/
            // Asked last, once every conflict is known: the user is never made to decide about
            // notifications for a save that is about to be refused, and the override retry — which
            // skips the precheck above — reaches this same single prompt.
            const sendNotifications = await this.promptSendFacultyNotifications(false, this.isRepublishSave);
            if (sendNotifications === null) {
                this.pendingConflictOverride = false;
                return;
            }
            sessionPayload.sendNotifications = sendNotifications;

            sessionPayload.ignoreConflicts = this.pendingConflictOverride === true;
            this.pendingConflictOverride = false;
            this.isSaving = true;
            saveSession({ requestJson: JSON.stringify(sessionPayload) })
                .then((data) => {
                    const result = data && typeof data === 'object' ? data : { sessionId: data };
                    const hasStudentOverlap = result.warningMessage || (result.warningDetails && result.warningDetails.length > 0);
                    const successMessage = hasStudentOverlap
                        ? (this.isEditMode ? 'Session updated.' : 'Session created.')
                            + ' Note: Some students have overlapping schedules.'
                        : (this.isEditMode ? 'Session updated successfully.' : 'Session created successfully.');
                    this.showToastMessage(successMessage, hasStudentOverlap ? 'warning' : 'success');
                    this.sessionsRefreshKey = Date.now();
                    if (this.wiredSessionsResult) {
                        return refreshApex(this.wiredSessionsResult);
                    }
                    return Promise.resolve();
                })
                .then(() => {
                    return new Promise(resolve => setTimeout(resolve, 100));
                })
                .then(() => {
                    this.handleCloseModal();
                })
                .catch(error => {
                    this.handleSaveError(error);
                })
                .finally(() => {
                    this.isSaving = false;
                });
        }
    }
    
    createSessionWithMultipleDivisions(basePayload) {
        if (!this.selectedAssignments || this.selectedAssignments.length === 0) {
            this.showToastMessage('Please select at least one assignment', 'error');
            return;
        }
        
        // Get selected assignments
        const selectedOptions = this.courseAssignments.filter(option => 
            this.selectedAssignments.includes(option.assignmentKey)
        );
        
        if (selectedOptions.length === 0) {
            this.showToastMessage('Please select at least one assignment', 'error');
            return;
        }
        
        // Collect all division IDs from selected assignments
        const divisionIds = new Set(); // Use Set to avoid duplicates
        
        // When "All Divisions" + user clicked a division tile, use only that division; otherwise use sidebar selection
        if (this.isAllDivisionsSelected && this.modalDivisionId) {
            divisionIds.add(this.modalDivisionId);
        } else if (this.selectedDivision && this.selectedDivision !== TimetableCalendar.ALL_DIVISIONS_VALUE) {
            divisionIds.add(this.selectedDivision);
        }
        
        // Add division IDs from selected assignments in the table
        for (const option of selectedOptions) {
            if (option.divisionId) {
                divisionIds.add(option.divisionId);
            }
        }
        
        // Convert Set to Array
        const divisionIdsArray = Array.from(divisionIds);
        
        if (divisionIdsArray.length === 0) {
            this.showToastMessage('No valid divisions found', 'error');
            return;
        }
        
        // Build payload with multiple division IDs
        const payload = {
            ...basePayload,
            divisionIds: divisionIdsArray, // Pass array of division IDs
            courseId: this.modalCourse || this.selectedCourse || null
        };
        
        let sessionPayload;
        try {
            sessionPayload = this.buildSessionPayload(payload);
            // divisionIds is already included in buildSessionPayload
        } catch (error) {
            this.showToastMessage(error.message, 'error');
            return;
        }
        
        // Save one session with multiple divisions
        this.isSaving = true;
        saveSession({ requestJson: JSON.stringify(sessionPayload) })
            .then((data) => {
                const result = data && typeof data === 'object' ? data : { sessionId: data };
                const hasStudentOverlap = result.warningMessage || (result.warningDetails && result.warningDetails.length > 0);
                const divCount = divisionIdsArray.length;
                const divWord = divCount === 1 ? 'division' : 'divisions';
                const successMessage = hasStudentOverlap
                    ? (this.isEditMode ? 'Session updated' : 'Session created')
                        + ` with ${divCount} ${divWord}. Note: Some students have overlapping schedules.`
                    : (this.isEditMode
                        ? `Session updated successfully with ${divCount} ${divWord}.`
                        : `Session created successfully with ${divCount} ${divWord}.`);
                this.showToastMessage(successMessage, hasStudentOverlap ? 'warning' : 'success');
                this.sessionsRefreshKey = Date.now();
                if (this.wiredSessionsResult) {
                    return refreshApex(this.wiredSessionsResult);
                }
                return Promise.resolve();
            })
            .then(() => new Promise(resolve => setTimeout(resolve, 100)))
            .then(() => {
                this.handleCloseModal();
            })
            .catch(error => {
                this.handleSaveError(error);
            })
            .finally(() => {
                this.isSaving = false;
            });
    }

    handleDeleteEvent() {
        if (this.isEditSessionReadOnly) {
            this.showToastMessage('This session is completed and read-only. Attendance can still be viewed.', 'error');
            return;
        }
        if (!this.selectedEventId) {
            return;
        }

        // Edit modal "Cancel" -> mark the whole session as Cancelled (not delete)
        const eventToCancel = this.findEventRowForSession(this.selectedEventId, this.clickedTileDivisionId);
        this.isLoading = true;
        cancelSession({ sessionId: this.selectedEventId })
            .then(() => {
                let dateLabel = '';
                if (eventToCancel && eventToCancel.date) {
                    const d = new Date(eventToCancel.date + 'T12:00:00');
                    dateLabel = isNaN(d.getTime()) ? '' : d.toLocaleDateString('en-US', { month: 'short', day: 'numeric', year: 'numeric' });
                }
                const message = dateLabel ? `Session on ${dateLabel} is cancelled` : 'Session is cancelled';
                this.showToastMessage(message, 'success');
                this.sessionsRefreshKey = Date.now();
                if (this.wiredSessionsResult) {
                    return refreshApex(this.wiredSessionsResult);
                }
                return Promise.resolve();
            })
            .then(() => new Promise(resolve => setTimeout(resolve, 100)))
            .then(() => {
                this.handleCloseModal();
            })
            .catch(error => {
                this.showToastMessage(this.getErrorMessage(error), 'error');
            })
            .finally(() => {
                this.isLoading = false;
            });
    }

    handleEditAddAssignmentToggle(event) {
        const key = (event.currentTarget.dataset && event.currentTarget.dataset.assignmentKey) || '';
        if (!key) return;
        const isChecked = event.currentTarget.checked;  // ← ADD THIS SE-502
        const keys = [...(this.editAddSelectedKeys || [])];
        const idx = keys.indexOf(key);
        if (event.currentTarget.checked) {
            if (idx === -1) keys.push(key);
        } else {
            if (idx !== -1) keys.splice(idx, 1);
        }
        this.editAddSelectedKeys = keys;

        // SE-502: Added student load/remove logic with editStudentDivisionMap
        // tracking for checked/unchecked programs in edit session
        if (this.selectedCourseActivity === 'Make Up Exam') {
        const assignment = (this.editAddCourseAssignments || []).find(
            a => a.assignmentKey != null && String(a.assignmentKey).trim() === key
        );
        const divisionId = assignment ? this.getAssignmentDivisionId(assignment) : null;
        if (!divisionId) return;

        const courseValue = this.selectedCourse || '';
        const courseParts = courseValue.split('|');
        const courseId = courseParts.length > 1 ? courseParts[1] : null;

        if (isChecked) {
            getEligibleMakeupStudents({ divisionId, courseId })
                .then(result => {
                    const newStudents = (result || []).map(s => ({
                        label: s.studentName,
                        value: s.studentId
                    }));
                    this.editStudentDivisionMap[divisionId] = newStudents.map(s => s.value);
                    const existing = this.editEnrolledStudentOptions || [];
                    const existingValues = new Set(existing.map(o => o.value));
                    const toAdd = newStudents.filter(s => !existingValues.has(s.value));
                    this.editEnrolledStudentOptions = [...existing, ...toAdd];
                })
                .catch(error => {
                    console.error('Error fetching students for edit division', divisionId, error);
                });
        } else {
            const removedIds = this.editStudentDivisionMap[divisionId] || [];
            delete this.editStudentDivisionMap[divisionId];
            const stillNeededIds = new Set(Object.values(this.editStudentDivisionMap).flat());
            const toRemove = new Set(removedIds.filter(id => !stillNeededIds.has(id)));
            this.editEnrolledStudentOptions = (this.editEnrolledStudentOptions || [])
                .filter(o => !toRemove.has(o.value));
            this.editEnrolledSelectedIds = (this.editEnrolledSelectedIds || [])
                .filter(id => !toRemove.has(id));
        }
    }
    }
    

    handleViewAttendance() {
        
      /*  if (!this.selectedEventId) return;
        const divisionId =
            (this.clickedTileDivisionId && String(this.clickedTileDivisionId).trim()) ||
            (!this.isAllDivisionsSelected && this.selectedDivision ? String(this.selectedDivision).trim() : '');
        let url = `/lightning/cmp/c__sessionAttendanceManager?c__sessionId=${encodeURIComponent(this.selectedEventId)}`;
        if (divisionId) {
            url += `&c__divisionId=${encodeURIComponent(divisionId)}`;
        }
        window.open(url, '_blank');*/
         if (!this.selectedEventId) return;

    const editingEvent = this.findEventRowForSession(this.selectedEventId, this.clickedTileDivisionId);
    if (editingEvent) {
        const scheduleType = editingEvent.scheduleType
            ? String(editingEvent.scheduleType).toLowerCase()
            : '';

        // Draft session — not allowed
        if (scheduleType === 'draft') {
            this.showToastMessage(
                'View Attendance is not available for Draft sessions.',
                'warning'
            );
            return;
        }

        const dateStr = this.normalizeDateString(editingEvent.date);
        const today = this.formatDateLocal(new Date());

        if (dateStr > today) {
            // Future published session
            this.showToastMessage(
                'You can update the attendance once the session is completed.',
                'warning'
            );
            return;
        }

        if (dateStr === today) {
            // Today's session — check if end time has passed
            const endTime = editingEvent.endTime ? String(editingEvent.endTime).trim() : '';
            if (endTime) {
                const now = new Date();
                const currentMinutes = now.getHours() * 60 + now.getMinutes();
                const [endHH, endMM] = endTime.split(':').map(Number);
                const endMinutes = endHH * 60 + endMM;
                if (currentMinutes < endMinutes) {
                    this.showToastMessage(
                        'You can update the attendance once the session is completed.',
                        'warning'
                    );
                    return;
                }
            }
        }
        // Past date, or today after end time — open attendance
    }

    const divisionId =
        (this.clickedTileDivisionId && String(this.clickedTileDivisionId).trim()) ||
        (!this.isAllDivisionsSelected && this.selectedDivision ? String(this.selectedDivision).trim() : '');
    let url = `/lightning/cmp/c__sessionAttendanceManager?c__sessionId=${encodeURIComponent(this.selectedEventId)}`;
    if (divisionId) {
        url += `&c__divisionId=${encodeURIComponent(divisionId)}`;
    }
    window.open(url, '_blank');

    }

    handleRemoveSessionDivision(event) {
        const divisionIdToRemove = event.currentTarget && event.currentTarget.dataset && event.currentTarget.dataset.divisionId;
        if (!divisionIdToRemove || !this.selectedEventId) return;
        this.isLoading = true;
        deleteSession({ sessionId: this.selectedEventId, divisionIdToRemove: divisionIdToRemove })
            .then((newSessionId) => {
                this.showToastMessage('Division removed from session.', 'success');
                this.sessionsRefreshKey = Date.now();
                if (newSessionId) {
                    this.selectedEventId = newSessionId;
                    this.existingSessionDivisions = (this.existingSessionDivisions || []).filter(d => {
                        const divId = (d && d.divisionId) ? String(d.divisionId).trim() : '';
                        return !this.idsEqual(divId, divisionIdToRemove);
                    });
                    this.existingSessionDivisions = [...this.existingSessionDivisions];
                }
                return Promise.resolve(newSessionId);
            })
            .then((newSessionId) => {
                if (this.wiredSessionsResult) {
                    return refreshApex(this.wiredSessionsResult).then(() => newSessionId);
                }
                return Promise.resolve(newSessionId);
            })
            .then((newSessionId) => {
                if (newSessionId == null) this.handleCloseModal();
                return newSessionId;
            })
            .catch(err => {
                this.showToastMessage(this.getErrorMessage(err), 'error');
            })
            .finally(() => {
                this.isLoading = false;
            });
    }

    // Toast notification
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