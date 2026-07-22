import { LightningElement } from 'lwc';
import updateEvalScoreExport from '@salesforce/apex/InterviewController.updateEvalScoreExport';
import getHighestCriteriaCount from '@salesforce/apex/InterviewController.getHighestCriteriaCount';

export default class AdUpdateEvalScore_Export extends LightningElement {

    exportContactData() {

        let headers = [
            'Application Number',
            'Applicant Name',
            'Program',
            'Round',
            'Evaluated By'
        ];

        let orderedCriteria = [];

        getHighestCriteriaCount()
            .then(result => {

                const criteriaKeys = Object.keys(result)
                    .filter(k => k.startsWith('criteria'))
                    .sort((a, b) => {
                        const aNum = parseInt(a.match(/\d+/)?.[0] || 0, 10);
                        const bNum = parseInt(b.match(/\d+/)?.[0] || 0, 10);
                        return aNum - bNum;
                    });

                const seen = new Set();

                criteriaKeys.forEach(k => {
                    const label = result[k];
                    if (label && !seen.has(label)) {
                        seen.add(label);
                        orderedCriteria.push(label);
                        headers.push(label);
                    }
                });

                headers.push('Round Score');

                return updateEvalScoreExport();
            })

            .then(result => {

                const applicationMap = {};

                result.forEach(evaluation => {
                    const appNo = evaluation.ApplicationNumber__c;
                    if (!appNo) return;

                    if (!applicationMap[appNo]) {
                        applicationMap[appNo] = [];
                    }
                    applicationMap[appNo].push(evaluation);
                });

                let doc = '<table>';
                doc += `
                    <style>
                        table, th, td {
                            border: 1px solid black;
                            border-collapse: collapse;
                        }
                    </style>
                `;

                doc += '<tr>';
                headers.forEach(h => {
                    doc += `<th>${h}</th>`;
                });
                doc += '</tr>';

                Object.keys(applicationMap).forEach(appNo => {

                    const evaluations = applicationMap[appNo]
                        .sort((a, b) => (a.Round__c || 0) - (b.Round__c || 0));

                    evaluations.forEach(evaluation => {

                        doc += '<tr>';

                        doc += `<td>${appNo}</td>`;
                        doc += `<td>${evaluation.Applicant_Name__c ?? ''}</td>`;
                        doc += `<td>${evaluation.Program__c ?? ''}</td>`;
                        doc += `<td>${evaluation.Round__c ?? ''}</td>`;
                        doc += `<td>${evaluation.Employee__r?.Name ?? ''}</td>`;

                        const scoreMap = {};
                        (evaluation.Individual_Criteria_Results__r || []).forEach(item => {
                            scoreMap[item.Criteria_Description__c] = item.Score__c;
                        });

                        orderedCriteria.forEach(criteria => {
                            const score = scoreMap[criteria];
                            if (score !== undefined && score !== null) {
                                doc += `<td>${score}</td>`;
                            } else {
                                doc += `<td style="background-color:#e0e0e0;">N/A</td>`;
                            }
                        });

                        doc += `<td>${evaluation.Total_Score__c ?? ''}</td>`;
                        doc += '</tr>';
                    });
                });

                doc += '</table>';

                const element =
                    'data:application/vnd.ms-excel,' + encodeURIComponent(doc);

                const downloadElement = document.createElement('a');
                downloadElement.href = element;
                downloadElement.target = '_self';
                downloadElement.download = 'Contact_Data.xls';
                document.body.appendChild(downloadElement);
                downloadElement.click();
            })

            .catch(error => {
                console.error('Error:', JSON.stringify(error));
            });
    }
}