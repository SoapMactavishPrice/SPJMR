import { LightningElement, api, track, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { CurrentPageReference } from 'lightning/navigation';
import getExistingCourses from '@salesforce/apex/DivisionCourseAssignmentController.getExistingCourses';
import assignCourses from '@salesforce/apex/DivisionCourseAssignmentController.assignCourses';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { CloseActionScreenEvent } from 'lightning/actions';

export default class AssignDivisionCourses extends NavigationMixin(LightningElement) {

    _recordId;
    divisionId;

    @api
    get recordId() {
        return this._recordId;
    }
    set recordId(value) {
        this._recordId = value;
        if (value && !this.divisionId) {
            this.divisionId = value;
            this.tryLoadCourses();
        }
    }

    @track courses = [];
    @track allCourses = [];
    @track selectedCourses = [];
    @track searchKey = '';
    @track initialSelectedCourseIds = new Set();

    // ✅ ADDED
    @track isSpecialisationDivision = false;

    isElective = false;
    message = '';
    isLoading = false;

    @wire(CurrentPageReference)
    wiredPageRef(currentPageReference) {
        if (!currentPageReference) return;
        const fromState = currentPageReference.state?.recordId;
        const fromAttributes = currentPageReference.attributes?.recordId;
        const id = fromState || fromAttributes || this._recordId;
        if (id && id !== this.divisionId) {
            this.divisionId = id;
            this.tryLoadCourses();
        }
    }

    connectedCallback() {
        if (this._recordId && !this.divisionId) {
            this.divisionId = this._recordId;
        }
        this.tryLoadCourses();
    }

    tryLoadCourses() {
        if (this.divisionId) {
            this.loadCourses();
        } else {
            this.isLoading = false;
            this.message = 'Loading division context…';
        }
    }

    loadCourses() {
        if (!this.divisionId) {
            this.isLoading = false;
            this.message = 'Division record context is missing.';
            return;
        }

        this.isLoading = true;

        getExistingCourses({ divisionId: this.divisionId })
            .then((coursesResult) => {

                const rawList = Array.isArray(coursesResult) ? coursesResult : [];
                console.log('rawlist::',rawList);

                // ✅ ADDED: Detect Specialisation Division
                if (rawList.length > 0) {
                    const firstCourse = rawList[0].course;
                    console.log('firscouse::',firstCourse);

                    this.isSpecialisationDivision =
                        firstCourse?.Course_Type__c === 'Specialisation' ||
                        firstCourse?.SPJIMR_Specialisation__c != null;
                }

                const hasCourses = rawList.length > 0;
                this.isElective = hasCourses;
                this.message = hasCourses ? '' : 'No courses found';

                this.initialSelectedCourseIds = new Set();

                const validWrappers = rawList.filter((wrapper) =>
                    wrapper && wrapper.course && wrapper.course.Id
                );

                this.allCourses = validWrappers.map((wrapper, index) => {

                    const course = wrapper.course;
                    const courseId = course.Id;
                    const isSelected = wrapper.isSelected === true;
                    const divisionCourseId = wrapper.divisionCourseId;

                    if (isSelected && divisionCourseId) {
                        this.initialSelectedCourseIds.add(courseId);
                    }

                    return {
                        ...course,
                        courseId: courseId,
                        courseName: course.Learning_Course__r?.Name || '—',
                        courseCode: course.Learning_Course__r?.CourseNumber || '—',
                        rowId: courseId,
                        rowNumber: index + 1,
                        selected: isSelected,
                        isMultiTerm: course.Is_Multi_Term__c === true,
                        courseType: course.Course_Type__c || '—',
                        specialisation: course.SPJIMR_Specialisation__r?.Specialisation_Name__r?.Name || '—',
                        isDisabled: !isSelected,
                        programCourseId: courseId,
                        divisionCourseId: divisionCourseId
                    };
                });

                this.applySearchFilter();
                this.updateSelectedCourses();
                this.isLoading = false;
            })
            .catch((error) => {
                this.allCourses = [];
                this.courses = [];
                this.message = 'Failed to load courses';
                this.isLoading = false;

                this.showToast(
                    'Error',
                    error.body?.message || error.message,
                    'error'
                );
            });
    }

    handleSearchChange(event) {
        this.searchKey = event.target.value;
        this.applySearchFilter();
    }

    applySearchFilter() {
        if (!this.searchKey || this.searchKey.trim() === '') {
            this.courses = [...this.allCourses];
        } else {
            const searchLower = this.searchKey.toLowerCase().trim();
            this.courses = this.allCourses.filter((course) =>
                (course.courseName && course.courseName.toLowerCase().includes(searchLower)) ||
                (course.courseNumber && course.courseNumber.toLowerCase().includes(searchLower))
            );
        }
    }

    handleCheckboxChange(event) {
        const courseId = event.currentTarget.dataset.courseId;
        const selected = event.target.checked;

        const updateCourse = (course) => {
            if (course.rowId === courseId) {
                return { ...course, selected };
            }
            return course;
        };

        this.courses = this.courses.map(updateCourse);
        this.allCourses = this.allCourses.map(updateCourse);
        this.updateSelectedCourses();
    }

    updateSelectedCourses() {
        this.selectedCourses = this.allCourses.filter((course) => course.selected);
    }

    get hasSelectedCourses() {
        return this.selectedCourses.length > 0;
    }

    get selectedCount() {
        return this.selectedCourses.length;
    }

    get isSaveDisabled() {
        return this.allCourses.length === 0;
    }

    get isVisible() {
        return this.allCourses.length > 0;
    }

   handleSave() {
    const courseIds = this.selectedCourses.map(c => c.courseId);

    if (courseIds.length === 0) {
        this.showToast('Error', 'Please select at least one course', 'error');
        return;
    }

    this.isLoading = true;

    assignCourses({
        divisionId: this.divisionId,
        courseIds: courseIds,
        divisionCourseIdsToDelete: null
    })
    .then(() => {
        this.showToast('Success', 'Courses assigned successfully', 'success');

        // ✅ STEP 1: Close the modal (VERY IMPORTANT)
        this.dispatchEvent(new CloseActionScreenEvent());

        // ✅ STEP 2: Refresh full page after closing
        setTimeout(() => {
            window.location.reload();
        }, 800); // small delay ensures modal closes first
    })
    .catch((error) => {
        this.showToast(
            'Error',
            error.body?.message || error.message,
            'error'
        );
    })
    .finally(() => {
        this.isLoading = false;
    });
}
    handleCancel() {
        this.dispatchEvent(new CloseActionScreenEvent());
    }

    showToast(title, message, variant) {
        this.dispatchEvent(
            new ShowToastEvent({
                title,
                message,
                variant
            })
        );
    }
}