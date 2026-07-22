import { LightningElement, api, track } from 'lwc';
import getStudentsForBatch from '@salesforce/apex/EnrollStudentController.getStudentsForBatch';
import saveSelectedStudents from '@salesforce/apex/EnrollStudentController.saveSelectedStudents';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { CloseActionScreenEvent } from 'lightning/actions';

export default class BatchEnrolStudent extends LightningElement {
    _recordId;

    @api
    set recordId(value) {
        this._recordId = value;
        if (value) {
            this.loadStudents();
        }
    }
    get recordId() {
        return this._recordId;
    }

    @track students = [];          // filtered list shown in UI
    @track allStudents = [];       // full list from Apex
    @track selectedStudents = [];  // currently selected
    @track searchKey = '';         // bound to search input
    @track batchIntake = null;    // Batch intake limit
    @track currentMemberCount = 0; // Current number of members in batch
    originalSelectedIds = new Set();
    @track programmeIntake;
    @track currentProgrammeCount;

    async loadStudents() {
        try {
            const data = await getStudentsForBatch({ batchId: this._recordId });
            this.processStudentData(data);
        } catch (error) {
            console.error('Error fetching students:', error);
            this.dispatchEvent(new ShowToastEvent({
                title: 'Error',
                message: error?.body?.message || 'Failed to load students.',
                variant: 'error'
            }));
        }
    }

    processStudentData(data) {
        if (!data) return;

        this.batchIntake = data.batchIntake;
        this.currentMemberCount = data.currentMemberCount || 0;
        this.originalSelectedIds = new Set();
        this.programmeIntake = data.programmeIntake;
        this.currentProgrammeCount = data.currentProgrammeCount||0;

        if (!data.students) {
            data.students = [];
        }

        const availableSlots = this.batchIntake != null
            ? this.batchIntake - this.currentMemberCount
            : null;

        let selectedCount = 0;
        const limitedStudents = data.students.map((student) => {
            let shouldSelect = student.Selected;
            if (shouldSelect && availableSlots != null && selectedCount >= availableSlots) {
                shouldSelect = false;
            }
            if (shouldSelect) {
                selectedCount++;
                this.originalSelectedIds.add(student.Id);
            }
            return { ...student, Selected: shouldSelect };
        });

        this.allStudents = limitedStudents.map((student, index) => ({
            rowId: student.Id,
            rowNumber: index + 1,
            studentName: student.studentName,
            status: student.Status,
            selected: student.Selected
        }));

        this.applySearchFilter();
        this.updateSelectedStudents();
    }

    // 🔹 Handle search input
    handleSearchChange(event) {
        this.searchKey = event.target.value;
        this.applySearchFilter();
    }

    // 🔹 Apply search filter (only by studentName)
    applySearchFilter() {
        if (!this.searchKey || this.searchKey.trim() === '') {
            this.students = [...this.allStudents];
        } else {
            const searchLower = this.searchKey.toLowerCase().trim();
            this.students = this.allStudents.filter(stu =>
                stu.studentName && stu.studentName.toLowerCase().includes(searchLower)
            );

            // Update row numbers for filtered results
            this.students = this.students.map((stu, index) => ({
                ...stu,
                rowNumber: index + 1
            }));
        }
    }

    // Handle checkbox selection
    handleCheckboxChange(event) {
        const studentId = event.target.dataset.studentId;
        const isChecked = event.target.checked;
        
        // If checking a student, validate batch intake limit
        if (isChecked && this.batchIntake != null) {
            // Count students that will be newly enrolled (selected but not originally selected)
            // Excluding the one being checked
            const willBeNewlyEnrolled = this.allStudents.filter(
                s => s.selected && s.rowId !== studentId && !this.originalSelectedIds.has(s.rowId)
            ).length;
            
            // Check if the student was originally selected
            const wasOriginallySelected = this.originalSelectedIds.has(studentId);
            
            // If checking a new student (not originally selected), validate against available slots
            if (!wasOriginallySelected) {
                const availableSlots = this.batchIntake - this.currentMemberCount;
                const newSelectedCount = willBeNewlyEnrolled + 1;
                
                // Check if selecting this student would exceed available slots
                if (newSelectedCount > availableSlots) {
    let errorMessage;

    if (availableSlots <= 0) {
        errorMessage = `Cannot assign more students. Batch intake is ${this.batchIntake} and ${this.currentMemberCount} student(s) are already enrolled.`;
    } else {
        errorMessage = `Cannot select more than ${availableSlots} student(s). Batch intake is ${this.batchIntake} and ${this.currentMemberCount} student(s) are already enrolled.`;
    }

    this.dispatchEvent(new ShowToastEvent({
        title: 'Error',
        message: errorMessage,
        variant: 'error'
    }));

    event.target.checked = false;
    return;
}
            }
        }

        const updateStudent = (stu) => {
            if (stu.rowId === studentId) {
                return {
                    ...stu,
                    selected: isChecked,
                    status: isChecked ? 'Applied' : 'Withdrawn'
                };
            }
            return stu;
        };

        this.students = this.students.map(updateStudent);
        this.allStudents = this.allStudents.map(updateStudent);

        this.updateSelectedStudents();
    }

    // 🔹 Update selected students
    updateSelectedStudents() {
        this.selectedStudents = this.allStudents.filter(stu => stu.selected);
    }

    get hasSelectedStudents() {
        return this.selectedStudents.length > 0;
    }

     get programmeRemaining() {
    const intake = this.programmeIntake || 0;
    const count = this.currentProgrammeCount || 0;

    const remaining = intake - count;
    return remaining > 0 ? remaining : 0;
}

    get selectedCount() {
        return this.selectedStudents.length;
    }

    get availableSlots() {
        if (this.batchIntake == null) {
            return null;
        }
        return this.batchIntake - this.currentMemberCount;
    }

    get hasStudentsToEnroll() {
        return this.allStudents && this.allStudents.length > 0;
    }

    // Save handler
    async handleSave() {
        // Get selected students (all students shown are not enrolled, so selected = to be enrolled)
        const selectedStudents = this.allStudents.filter(stu => stu.selected);
        
        // If no students selected, show message
        if (selectedStudents.length === 0) {
            this.dispatchEvent(new ShowToastEvent({
                title: 'Info',
                message: 'Please select at least one student to enroll.',
                variant: 'info'
            }));
            return;
        }
        
        // Calculate students to add (selected) and withdraw (originally selected but now unselected)
        // Note: All students shown are not enrolled, so selected students need to be enrolled
        const studentsToAdd = selectedStudents;
        const studentsToWithdraw = this.allStudents.filter(
            stu => !stu.selected && this.originalSelectedIds.has(stu.rowId)
        );
        
        // Since all students shown are not enrolled, if any are selected, they need enrollment
        // The Apex controller will handle checking for duplicates, so we can proceed to save

        const selectedIds = this.allStudents
            .filter(stu => stu.selected)
            .map(stu => stu.rowId);

        // Validate batch intake before saving
        if (this.batchIntake != null) {
            // Calculate total after save: current count - withdrawn + newly added
            const totalAfterSave = this.currentMemberCount - studentsToWithdraw.length + studentsToAdd.length;
            
            if (totalAfterSave > this.batchIntake) {
                const availableSlots = this.batchIntake - this.currentMemberCount + studentsToWithdraw.length;
                let errorMessage;

                if (availableSlots <= 0) {
                    errorMessage = `Cannot assign more students. Batch intake is ${this.batchIntake} and ${this.currentMemberCount} student(s) are already enrolled.`;
                } else {
                    errorMessage = `Cannot save. You can only select ${availableSlots} more student(s). Batch intake is ${this.batchIntake} and ${this.currentMemberCount} student(s) are already enrolled.`;
                }
                
                this.dispatchEvent(new ShowToastEvent({
                    title: 'Error',
                    message: errorMessage,
                    variant: 'error'
                }));
                return;
            }
        }

        const unselectedIds = studentsToWithdraw.map(stu => stu.rowId);

        try {
            await saveSelectedStudents({
                batchId: this.recordId,
                selectedStudentIds: selectedIds,
                unselectedStudentIdsToWithdraw: unselectedIds
            });

            this.dispatchEvent(new ShowToastEvent({
                title: 'Success',
                message: 'Enrollment updates saved.',
                variant: 'success'
            }));

            await this.loadStudents();

            // Close modal first
            this.dispatchEvent(new CloseActionScreenEvent());
            
            // Refresh page after small delay
            setTimeout(() => {
                window.location.reload();
            }, 500);
        } catch (error) {
            this.dispatchEvent(new ShowToastEvent({
                title: 'Error',
                message: error?.body?.message || 'An error occurred while saving.',
                variant: 'error'
            }));
        }
    }

    handleCancel() {
        this.dispatchEvent(new CloseActionScreenEvent());
    }
}