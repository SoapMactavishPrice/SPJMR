import { LightningElement, api, track } from 'lwc';
import distribute from '@salesforce/apex/StudentDivisionDistributorV2.distribute';
import validate from '@salesforce/apex/StudentDivisionDistributorV2.validateDistribution';
import modal from "@salesforce/resourceUrl/custommodalcss";
import { loadStyle } from 'lightning/platformResourceLoader';

export default class StudentDivisionManager extends LightningElement {
    @api recordId;
    @track rows;
    @track message;
    @track warnings = [];
    @track isValid = true;

    columns = [
        { label: 'Division', fieldName: 'divisionName' },
        { label: 'Total', fieldName: 'total', type: 'number' },
        { label: 'Male', fieldName: 'male', type: 'number' },
        { label: 'Female', fieldName: 'female', type: 'number' },
        { label: 'Tech', fieldName: 'tech', type: 'number' },
        { label: 'Non-Tech', fieldName: 'nonTech', type: 'number' },
        { label: 'Avg Male Exp', fieldName: 'avgMaleExp', type: 'number', cellAttributes: { alignment: 'left' } },
        { label: 'Avg Female Exp', fieldName: 'avgFemaleExp', type: 'number', cellAttributes: { alignment: 'left' } },
        {
            label: 'Specialisations',
            fieldName: 'specialisations',
            typeAttributes: {
                class: 'slds-line-clamp',
                text: { fieldName: 'specialisations' },
            },
            wrapText: true,
            type: 'text',
            cellAttributes: { class: 'specialisation-cell' },
            initialWidth: 300
        }
    ];

    connectedCallback() {
        loadStyle(this, modal);
    }

    handleDistribute() {
        distribute({ termId: this.recordId })
            .then(() => {
                this.message = 'Students distributed successfully';
                this.handleValidate();
            })
            .catch(e => {
                this.message = e.body?.message || e.message || 'Error distributing students';
            });
    }

    handleValidate() {
        validate({ termId: this.recordId })
            .then(res => {
                // Store validation status and warnings
                this.isValid = res.isValid || false;
                this.warnings = res.warnings || [];

                // Format the data to match column field names
                if (res.divisions && Array.isArray(res.divisions)) {
                    // Collect all specialisation names to create dynamic columns if needed
                    const allSpecialisations = new Set();
                    res.divisions.forEach(div => {
                        if (div.specialisationCounts) {
                            Object.keys(div.specialisationCounts).forEach(spec => {
                                allSpecialisations.add(spec);
                            });
                        }
                    });

                    // Format specialisation counts as a readable string
                    this.rows = res.divisions.map(div => {
                        let specString = '';
                        if (div.specialisationCounts && Object.keys(div.specialisationCounts).length > 0) {
                            specString = Object.entries(div.specialisationCounts)
                                .map(([name, count]) => `${name}: ${count}`)
                                .join(', ');
                        } else {
                            specString = 'None';
                        }

                        return {
                            divisionId: div.divisionId,
                            divisionName: div.divisionName,
                            total: div.total || 0,
                            male: div.male || 0,
                            female: div.female || 0,
                            tech: div.tech || 0,
                            nonTech: div.nonTech || 0,
                            avgMaleExp: div.avgMaleExp ? parseFloat(div.avgMaleExp).toFixed(2) : '0.00',
                            avgFemaleExp: div.avgFemaleExp ? parseFloat(div.avgFemaleExp).toFixed(2) : '0.00',
                            specialisations: specString
                        };
                    });
                } else {
                    this.rows = [];
                }
                this.message = res.message || '';
            })
            .catch(e => {
                this.message = e.body?.message || e.message || 'Error validating distribution';
                this.rows = [];
                this.warnings = [];
                this.isValid = false;
            });
    }
}