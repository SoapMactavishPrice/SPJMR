import { LightningElement, api, wire } from 'lwc';
import getUserInfo from '@salesforce/apex/StudentProfileDashboardController.getUserInfo';
import programInfo from '@salesforce/apex/StudentProfileDashboardController.programInfo';
import getDivisionEnrollmentTable from '@salesforce/apex/StudentProfileDashboardController.getDivisionEnrollmentTable';
import profileDummy from '@salesforce/resourceUrl/Profile_Dummy';
import { NavigationMixin } from 'lightning/navigation';

const NA_LABEL = 'N/A';

export default class Spjimr_programDetails extends NavigationMixin(LightningElement){
    selectedMenuItem = 'programDetails';
    profileDummyIcon = profileDummy;
    isSidebarOpen = true;

    selectedTermValue;

    student = {
        name: '',
        email: '',
        gender: '',
        dob: '',
        rollNumber: '',
        mobile: '',
        previousQualification: '',
        graduationYear: '',
        marks: '',
        term: '',
        address: '',
        termOptions: [],
        courseCount: {},
        currentTermId: null
    };
    divisionRows = [];

    program = {
        name: '',
        code: '',
        duration: ''
    };
    calendarUrl;

    connectedCallback() {
        this[NavigationMixin.GenerateUrl]({
            type: 'comm__namedPage',
            attributes: {
                name: 'Attendance_and_Schedule__c'
            }
        }).then(url => {
            this.calendarUrl = url;
        });
    }



    get isStudentDetailsSection() {
        return this.selectedMenuItem === 'programDetails';
    }
    get mainContentClass() {
        return this.isSidebarOpen ? 'main-content main-content-with-sidebar' : 'main-content main-content-full';
    }



    @wire(getUserInfo)
    wiredUserInfo({ data, error }) {
        if (data) {
            console.log('student data::', JSON.stringify(data));
            this.mapUserInfo(data);
        } else if (error) {
            console.error('User info error:', error);
        }
    }

    @wire(programInfo)
    wiredProgramInfo({ data, error }) {
        if (data) {
            console.log('program data:',data);
            this.mapProgramInfo(data);
        } else if (error) {
            console.error('Program info error:', error);
        }
    }

    @wire(getDivisionEnrollmentTable, { currentTermId: '$student.currentTermId' })
    wiredDivisionTable({ data, error }) {
        if (data) {
            this.divisionRows = data;
        } else if (error) {
            this.divisionRows = [];
        }
    }

    formatNA(value) {
        if (value === null || value === undefined) {
            return NA_LABEL;
        }
        const s = String(value).trim();
        return s.length ? s : NA_LABEL;
    }

    get displayProgramName() {
        return this.formatNA(this.program?.name);
    }
    get displayProgramCode() {
        return this.formatNA(this.program?.code);
    }
    get displayProgramDuration() {
        return this.formatNA(this.program?.duration);
    }
    get displayStudentTerm() {
        return this.formatNA(this.student?.term);
    }

    get courseCountText() {
    const labelMap = {
        Core: {
            singular: 'Core',
            plural: 'Cores'
        },
        Elective: {
            singular: 'Elective',
            plural: 'Electives'
        },
        Specialisation: {
            singular: 'Specialisation',
            plural: 'Specialisations'
        }
    };

    if (!this.student?.courseCount) {
        return NA_LABEL;
    }

    const text = Object.keys(labelMap)
        .filter((key) => this.student.courseCount[key])
        .map((key) => {
            const count = this.student.courseCount[key];

            const label =
                count > 1
                    ? labelMap[key].plural
                    : labelMap[key].singular;

            return `${count} ${label}`;
        })
        .join(', ');

    const t = (text || '').trim();
    return t.length ? t : NA_LABEL;
}


    mapUserInfo(result) {
        // 1️⃣ Sort options safely
        const sortedOptions = [...(result.termOptions || [])].sort((a, b) =>
            a.label.localeCompare(b.label, undefined, { numeric: true })
        );

        // 2️⃣ Map student data (USE sortedOptions)
        this.student = {
            name: result.fullName ?? '',
            code: result.programCode ?? '',
            email: result.email ?? '',
            gender: result.gender ?? '',
            dob: result.dateOfBirth ?? '',
            rollNumber: result.rollNumber ?? '',
            mobile: result.mobileNumber ?? '',
            previousQualification: result.prevQualification ?? '',
            graduationYear: result.graduationYear ?? '',
            marks: result.marks ?? '',
            term: result.term ?? '',
            address: result.address ?? '',
            termOptions: sortedOptions,
            courseCount: result.courseCount ?? {},
            currentTermId: result.currentTermId ?? null
        };

        // 3️⃣ Robust default selection (normalize)
        const normalizedCurrentTerm = (this.student.term || '')
            .replace(/\s+/g, '')
            .toLowerCase();

        const currentTermOption = sortedOptions.find(opt =>
            opt.label.replace(/\s+/g, '').toLowerCase() === normalizedCurrentTerm
        );

        if (currentTermOption) {
            this.selectedTermValue = currentTermOption.value;
        }

        console.log('this.student::', JSON.stringify(this.student));
    }


    mapProgramInfo(result) {
    const durationValue = result.Duration_to_Complete__c ?? '';
    const calendarValue = result.Programme_Duration__c ?? '';

    this.program = {
        name: result.Name ?? '',
        code: result.Program_Code__c ?? '',
        duration: durationValue && calendarValue  ? `${durationValue} ${calendarValue}` : durationValue
    };

    console.log('this.program::', JSON.stringify(this.program));
}
    handleTermChange(event) {
    const value = event.detail.value;
    if (value === this.selectedTermValue) {
        return;
    }
    this.selectedTermValue = value;
    if (!value) {
        return;
    }
    this[NavigationMixin.Navigate]({
        type: 'comm__namedPage',
        attributes: {
            name: 'term_detail__c'
        },
        state: {
            termId: value
        }
    });
}

}