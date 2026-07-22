import { LightningElement, api } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { CloseActionScreenEvent } from 'lightning/actions';
import distributeStudentsByTerm from '@salesforce/apex/StudentDivisionDistributor.distributeStudentsByTerm';
import validateDistribution from '@salesforce/apex/StudentDivisionDistributor.validateDistribution';
import getDivisionNames from '@salesforce/apex/StudentDivisionDistributor.getDivisionNames';
import getDivisionsForTerm from '@salesforce/apex/StudentDivisionDistributor.getDivisionsForTerm';

export default class StudentDivisionDistribution extends LightningElement {
  @api recordId; // AcademicTerm Id from quick action context

  isLoading = false;
  errorMessage = '';
  successMessage = '';
  validationMessage = '';
  validationAlertType = 'info';
  showResults = false;
  divisionStatsList = [];

  

  handleDistribute() {
  
    if (!this.recordId) {
      this.showError('Please select an Academic Term record.');
      return;
    }

    this.isLoading = true;
    this.clearMessages();
    this.showResults = false;

    distributeStudentsByTerm({ termId: this.recordId })
      .then((result) => {
        this.isLoading = false;
        if (result.success) {
          this.successMessage = result.message;
          this.processDistributionResults(result.divisionStats);
          this.showToast('Success', result.message, 'success');
        } else {
          this.errorMessage = result.message;
          this.showToast('Error', result.message, 'error');
        }
      })
      .catch((error) => {
        this.isLoading = false;
        this.errorMessage = 'Error: ' + (error.body?.message || error.message);
        this.showToast('Error', this.errorMessage, 'error');
        console.error('Error distributing students:', error);
      });
  }

  async handleValidate() {
    if (!this.recordId) {
      this.showError('Please select an Academic Term record.');
      return;
    }

    this.isLoading = true;
    this.clearMessages();
    this.showResults = false;

    try {
      const result = await validateDistribution({ termId: this.recordId });
      this.isLoading = false;
      this.validationMessage = result.message;
      this.validationAlertType = result.isValid ? 'success' : 'warning';
      
      // Convert validation result to display format
      await this.processValidationResults(result);
      
      this.showToast(
        result.isValid ? 'Validation Passed' : 'Validation Failed',
        result.message,
        result.isValid ? 'success' : 'warning'
      );
    } catch (error) {
      this.isLoading = false;
      this.errorMessage = 'Error: ' + (error.body?.message || error.message);
      this.showToast('Error', this.errorMessage, 'error');
      console.error('Error validating distribution:', error);
    }
  }

  processDistributionResults(divisionStatsMap) {
    if (!divisionStatsMap || Object.keys(divisionStatsMap).length === 0) {
      return;
    }

    this.divisionStatsList = Object.keys(divisionStatsMap).map((divisionId) => {
      const stat = divisionStatsMap[divisionId];
      return {
        divisionId: divisionId,
        divisionName: stat.divisionName || 'N/A',
        totalStudents: stat.totalStudents || 0,
        maleCount: stat.maleCount || 0,
        femaleCount: stat.femaleCount || 0,
        technicalCount: stat.technicalCount || 0,
        nonTechnicalCount: stat.nonTechnicalCount || 0,
        avgWorkExperience: this.formatDecimal(stat.avgWorkExperience),
        avgMaleWorkExperience: this.formatDecimal(stat.avgMaleWorkExperience),
        avgFemaleWorkExperience: this.formatDecimal(stat.avgFemaleWorkExperience)
      };
    });

    // Sort by division name
    this.divisionStatsList.sort((a, b) => {
      return a.divisionName.localeCompare(b.divisionName);
    });

    this.showResults = true;
  }

  async processValidationResults(validationResult) {
    const statsList = [];
    const maleCounts = validationResult.maleCounts || {};
    const femaleCounts = validationResult.femaleCounts || {};
    const technicalCounts = validationResult.technicalCounts || {};
    const nonTechnicalCounts = validationResult.nonTechnicalCounts || {};
    const maleAvgWorkExp = validationResult.maleAvgWorkExperience || {};
    const femaleAvgWorkExp = validationResult.femaleAvgWorkExperience || {};

    // Get all unique division IDs from count maps
    let allDivisionIds = Array.from(new Set([
      ...Object.keys(maleCounts),
      ...Object.keys(femaleCounts),
      ...Object.keys(technicalCounts),
      ...Object.keys(nonTechnicalCounts)
    ]));

    // If no division IDs found in maps (all zeros), get them from the term
    if (allDivisionIds.length === 0 && this.recordId) {
      try {
        const divisionIds = await getDivisionsForTerm({ termId: this.recordId });
        allDivisionIds = divisionIds || [];
      } catch (error) {
        console.error('Error fetching divisions for term:', error);
      }
    }

    // Fetch division names
    let divisionNameMap = {};
    if (allDivisionIds.length > 0) {
      try {
        divisionNameMap = await getDivisionNames({ divisionIds: allDivisionIds });
      } catch (error) {
        console.error('Error fetching division names:', error);
      }
    }

    allDivisionIds.forEach((divisionId) => {
      const divisionName = divisionNameMap[divisionId] || 'Division ' + divisionId.substring(0, 8) + '...';
      statsList.push({
        divisionId: divisionId,
        divisionName: divisionName,
        totalStudents: (maleCounts[divisionId] || 0) + (femaleCounts[divisionId] || 0),
        maleCount: maleCounts[divisionId] || 0,
        femaleCount: femaleCounts[divisionId] || 0,
        technicalCount: technicalCounts[divisionId] || 0,
        nonTechnicalCount: nonTechnicalCounts[divisionId] || 0,
        avgWorkExperience: 'N/A',
        avgMaleWorkExperience: this.formatDecimal(maleAvgWorkExp[divisionId]),
        avgFemaleWorkExperience: this.formatDecimal(femaleAvgWorkExp[divisionId])
      });
    });

    // Sort by division name
    statsList.sort((a, b) => {
      return a.divisionName.localeCompare(b.divisionName);
    });

    this.divisionStatsList = statsList;
    this.showResults = statsList.length > 0;
  }

  formatDecimal(value) {
    if (value === null || value === undefined) {
      return '0.00';
    }
    return parseFloat(value).toFixed(2);
  }

  clearMessages() {
    this.errorMessage = '';
    this.successMessage = '';
    this.validationMessage = '';
  }

  handleCloseError() {
    this.errorMessage = '';
  }

  handleCloseSuccess() {
    this.successMessage = '';
  }

  handleCloseValidation() {
    this.validationMessage = '';
  }

  showError(message) {
    this.errorMessage = message;
    this.showToast('Error', message, 'error');
  }

  showToast(title, message, variant) {
    const evt = new ShowToastEvent({
      title: title,
      message: message,
      variant: variant,
      mode: 'dismissable'
    });
    this.dispatchEvent(evt);
  }

  handleClose() {
    this.dispatchEvent(new CloseActionScreenEvent());
  }
}