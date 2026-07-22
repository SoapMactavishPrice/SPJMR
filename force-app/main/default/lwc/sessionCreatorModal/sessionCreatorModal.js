import { LightningElement, api, track } from 'lwc';

export default class SessionCreatorModal extends LightningElement {
    @api isOpen = false;
    
    // Context information passed from parent
    @api contextInfo = {
        programName: 'Post Graduate Programme in Management',
        batchName: 'PGPM Class of 2025',
        termName: 'Term 1',
        courseName: 'Management Course',
        selectedDate: null
    };

    @track selectedSessionIndex = 0;
    
    // Sessions data
    @track sessions = [];

    // Faculty options
    facultyOptions = [
        { label: 'Dr. John Miller', value: 'miller' },
        { label: 'Prof. Sarah Smith', value: 'smith' },
        { label: 'Dr. Michael Johnson', value: 'johnson' },
        { label: 'Prof. Emily Wilson', value: 'wilson' },
        { label: 'Dr. Carlos Hernandez', value: 'hernandez' },
        { label: 'Prof. Lisa Anderson', value: 'anderson' },
        { label: 'Dr. Robert Taylor', value: 'taylor' }
    ];

    // Available programs for merging (where the course is already running)
    @track programsForMerge = [
        { 
            id: 'prog-1', 
            programName: 'GMP Demo (Jan 2026)', 
            batchName: 'Batch 1', 
            batchGroup: 'BG1', 
            division: 'DIV-0231', 
            term: 'Term 1'
        },
        { 
            id: 'prog-2', 
            programName: 'Executive MBA', 
            batchName: 'Batch 2024', 
            batchGroup: 'BG2', 
            division: 'DIV-0232', 
            term: 'Term 1'
        },
        { 
            id: 'prog-3', 
            programName: 'MBA Finance', 
            batchName: 'Batch 2025', 
            batchGroup: 'BG1', 
            division: 'DIV-0233', 
            term: 'Term 2'
        },
        { 
            id: 'prog-4', 
            programName: 'MBA Marketing', 
            batchName: 'Batch 2025', 
            batchGroup: 'BG2', 
            division: 'DIV-0234', 
            term: 'Term 1'
        },
        { 
            id: 'prog-5', 
            programName: 'MBA Operations', 
            batchName: 'Batch 2024', 
            batchGroup: 'BG1', 
            division: 'DIV-0235', 
            term: 'Term 2'
        },
        { 
            id: 'prog-6', 
            programName: 'Post Graduate Programme (PGPM)', 
            batchName: 'Batch 2025', 
            batchGroup: 'BG3', 
            division: 'DIV-0236', 
            term: 'Term 1'
        }
    ];

    connectedCallback() {
        this.initializeSessions();
    }

    @api
    open(contextData) {
        if (contextData) {
            this.contextInfo = { ...this.contextInfo, ...contextData };
        }
        this.initializeSessions();
        this.isOpen = true;
    }

    @api
    close() {
        this.isOpen = false;
        this.dispatchEvent(new CustomEvent('close'));
    }

    initializeSessions() {
        const today = this.contextInfo.selectedDate || this.formatDateString(new Date());
        this.sessions = [{
            id: this.generateId(),
            title: '',
            date: today,
            startTime: '09:00',
            endTime: '10:00',
            faculty: [],
            selectedPrograms: []
        }];
        this.selectedSessionIndex = 0;
    }

    // Getters
    get hasSelectedSession() {
        return this.selectedSessionIndex !== null && this.selectedSessionIndex >= 0;
    }

    get selectedSessionDisplayNumber() {
        return this.selectedSessionIndex !== null ? this.selectedSessionIndex + 1 : '';
    }

    get sessionsWithIndex() {
        const canDeleteAny = this.sessions.length > 1;
        return this.sessions.map((session, index) => ({
            ...session,
            index: index,
            displayNumber: index + 1,
            isSelected: this.selectedSessionIndex === index,
            cardClass: this.selectedSessionIndex === index 
                ? 'session-card selected' 
                : 'session-card',
            canDelete: canDeleteAny,
            programCount: session.selectedPrograms ? session.selectedPrograms.length : 0,
            facultyPills: session.faculty.map(f => ({
                value: f,
                label: this.getFacultyLabel(f)
            })),
            availableFacultyOptions: this.facultyOptions.filter(
                fo => !session.faculty.includes(fo.value)
            )
        }));
    }

    get availablePrograms() {
        if (!this.hasSelectedSession) return [];
        
        const session = this.sessions[this.selectedSessionIndex];
        const selectedIds = session.selectedPrograms || [];
        
        return this.programsForMerge.map(program => ({
            ...program,
            isSelected: selectedIds.includes(program.id),
            rowClass: selectedIds.includes(program.id) ? 'program-row selected' : 'program-row'
        }));
    }

    get allProgramsSelected() {
        if (!this.hasSelectedSession) return false;
        const session = this.sessions[this.selectedSessionIndex];
        return session.selectedPrograms && 
               session.selectedPrograms.length === this.programsForMerge.length;
    }

    get totalSessions() {
        return this.sessions.length;
    }

    get totalProgramsMerged() {
        let total = 0;
        this.sessions.forEach(session => {
            total += (session.selectedPrograms || []).length;
        });
        return total;
    }

    // Helper methods
    generateId() {
        return 'session-' + Date.now() + '-' + Math.random().toString(36).substr(2, 9);
    }

    formatDateString(date) {
        const year = date.getFullYear();
        const month = String(date.getMonth() + 1).padStart(2, '0');
        const day = String(date.getDate()).padStart(2, '0');
        return `${year}-${month}-${day}`;
    }

    getFacultyLabel(value) {
        const faculty = this.facultyOptions.find(f => f.value === value);
        return faculty ? faculty.label : value;
    }

    // Event handlers
    handleClose() {
        this.close();
    }

    stopPropagation(event) {
        event.stopPropagation();
    }

    handleSelectSession(event) {
        const index = parseInt(event.currentTarget.dataset.index, 10);
        this.selectedSessionIndex = index;
    }

    handleAddSession() {
        const today = this.formatDateString(new Date());
        const newSession = {
            id: this.generateId(),
            title: '',
            date: today,
            startTime: '09:00',
            endTime: '10:00',
            faculty: [],
            selectedPrograms: []
        };
        this.sessions = [...this.sessions, newSession];
        this.selectedSessionIndex = this.sessions.length - 1;
    }

    handleDeleteSession(event) {
        event.stopPropagation();
        const index = parseInt(event.currentTarget.dataset.index, 10);
        
        if (this.sessions.length <= 1) {
            // Don't delete if it's the last session
            return;
        }
        
        this.sessions = this.sessions.filter((_, i) => i !== index);
        
        // Adjust selected index
        if (this.selectedSessionIndex >= this.sessions.length) {
            this.selectedSessionIndex = this.sessions.length - 1;
        } else if (this.selectedSessionIndex === index) {
            this.selectedSessionIndex = Math.max(0, index - 1);
        }
    }

    handleFieldChange(event) {
        const index = parseInt(event.currentTarget.dataset.index, 10);
        const field = event.currentTarget.dataset.field;
        const value = event.detail ? event.detail.value : event.target.value;
        
        const updatedSessions = [...this.sessions];
        updatedSessions[index] = {
            ...updatedSessions[index],
            [field]: value
        };
        this.sessions = updatedSessions;
    }

    handleAddFaculty(event) {
        const index = parseInt(event.currentTarget.dataset.index, 10);
        const value = event.detail.value;
        
        if (!value) return;
        
        const updatedSessions = [...this.sessions];
        const session = updatedSessions[index];
        
        if (!session.faculty.includes(value)) {
            updatedSessions[index] = {
                ...session,
                faculty: [...session.faculty, value]
            };
            this.sessions = updatedSessions;
        }
        
        // Reset combobox
        event.target.value = '';
    }

    handleRemoveFaculty(event) {
        event.stopPropagation();
        const sessionIndex = parseInt(event.currentTarget.dataset.sessionIndex, 10);
        const facultyValue = event.currentTarget.dataset.faculty;
        
        const updatedSessions = [...this.sessions];
        updatedSessions[sessionIndex] = {
            ...updatedSessions[sessionIndex],
            faculty: updatedSessions[sessionIndex].faculty.filter(f => f !== facultyValue)
        };
        this.sessions = updatedSessions;
    }

    handleProgramToggle(event) {
        const programId = event.currentTarget.dataset.programId;
        const isChecked = event.target.checked;
        
        if (!this.hasSelectedSession) return;
        
        const updatedSessions = [...this.sessions];
        const session = updatedSessions[this.selectedSessionIndex];
        let selectedPrograms = session.selectedPrograms ? [...session.selectedPrograms] : [];
        
        if (isChecked) {
            if (!selectedPrograms.includes(programId)) {
                selectedPrograms.push(programId);
            }
        } else {
            selectedPrograms = selectedPrograms.filter(id => id !== programId);
        }
        
        updatedSessions[this.selectedSessionIndex] = {
            ...session,
            selectedPrograms
        };
        this.sessions = updatedSessions;
    }

    handleSelectAllPrograms(event) {
        const isChecked = event.target.checked;
        
        if (!this.hasSelectedSession) return;
        
        const updatedSessions = [...this.sessions];
        const session = updatedSessions[this.selectedSessionIndex];
        
        updatedSessions[this.selectedSessionIndex] = {
            ...session,
            selectedPrograms: isChecked 
                ? this.programsForMerge.map(p => p.id) 
                : []
        };
        this.sessions = updatedSessions;
    }

    handleSave() {
        // Validate sessions
        const validSessions = this.sessions.filter(session => {
            return session.date && session.startTime && session.endTime;
        });
        
        if (validSessions.length === 0) {
            // Show error - at least one valid session required
            return;
        }
        
        // Dispatch save event with session data
        const eventDetail = {
            sessions: this.sessions.map(session => ({
                ...session,
                contextInfo: this.contextInfo
            }))
        };
        
        this.dispatchEvent(new CustomEvent('save', {
            detail: eventDetail
        }));
        
        this.close();
    }
}