import { LightningElement, track } from 'lwc';

export default class PreferencePicker extends LightningElement {
    @track selectedLevel = '';
    @track selectedGrade = '';
    levelOptions = [{ label: 'MBA', value: 'MBA' }];
    gradeOptions = [];
    @track subjects = null;
    @track majorPreference = null;
    @track minorPreference = null;

    data = {
        MBA: {
            Term3: {
                Finance: [
                    { name: 'Corporate Finance', credits: 4 },
                    { name: 'Investment Analysis', credits: 3 }
                ],
                Marketing: [
                    { name: 'Digital Marketing', credits: 2 },
                    { name: 'Brand Management', credits: 4 }
                ],
                HR: [
                    { name: 'Organizational Behavior', credits: 3 },
                    { name: 'Talent Management', credits: 5 }
                ]
            }
        }
    };

    handleLevelChange(event) {
        this.selectedLevel = event.target.value;
        if (this.selectedLevel) {
            this.gradeOptions = Object.keys(this.data[this.selectedLevel]).map(
                grade => ({ label: grade, value: grade })
            );
        }
        this.resetSelection();
    }

    handleGradeChange(event) {
        this.selectedGrade = event.target.value;
        if (this.selectedLevel && this.selectedGrade) {
            const subjectsData = this.data[this.selectedLevel][this.selectedGrade];
            this.subjects = Object.keys(subjectsData).map(category => ({
                category,
                subjects: subjectsData[category].map(subject => ({
                    ...subject,
                    rowClass: '' // Initialize rowClass
                }))
            }));
            this.resetPreferences();
        }
    }

    handleCheckboxChange() {
        const selectedSubjects = this.template.querySelectorAll(
            'input[type="checkbox"]:checked'
        );
        const creditTotals = {};

        selectedSubjects.forEach(checkbox => {
            const category = checkbox.dataset.category;
            const credits = parseInt(checkbox.dataset.credits, 10);
            creditTotals[category] = (creditTotals[category] || 0) + credits;
        });

        const sortedCategories = Object.keys(creditTotals).sort(
            (a, b) => creditTotals[b] - creditTotals[a]
        );

        this.majorPreference = sortedCategories[0] || null;
        this.minorPreference = sortedCategories[1] || null;

        // Update rowClass for each subject
        this.subjects = this.subjects.map(subjectCategory => ({
            ...subjectCategory,
            subjects: subjectCategory.subjects.map(subject => {
                if (subjectCategory.category === this.majorPreference) {
                    return { ...subject, rowClass: 'highlight-major' };
                } else if (subjectCategory.category === this.minorPreference) {
                    return { ...subject, rowClass: 'highlight-minor' };
                }
                return { ...subject, rowClass: '' };
            })
        }));
    }

    resetSelection() {
        this.selectedGrade = '';
        this.subjects = null;
        this.resetPreferences();
    }

    resetPreferences() {
        this.majorPreference = null;
        this.minorPreference = null;
    }
}