import afProgramDetailsContainerGmp from 'c/afProgramDetailsContainerGmp';
import afBasicDetailsContainerGmp from 'c/afBasicDetailsContainerGmp';
import afAcademicDetailsContainerGmp from 'c/afAcademicDetailsContainerGmp';
import afCompetitiveExamDetailsContainerGmp from 'c/afCompetitiveExamDetailsContainerGmp';
import afWorkExperienceContainerGmp from 'c/afWorkExperienceContainerGmp';
import afProfileInformationContainerGmp from 'c/afProfileInformationContainerGmp';
import afTermsAndConditionsContainerGmp from 'c/afTermsAndConditionsContainerGmp';

import afBasicDetailsContainerPgpm from 'c/afBasicDetailsContainerPgpm';
import afProgramDetailsContainerPgpm from 'c/afProgramDetailsContainerPgpm';
import afAcademicDetailsContainerPgpm from 'c/afAcademicDetailsContainerPgpm';
import afWorkExperienceContainerPgpm from 'c/afWorkExperienceContainerPgpm';
import afCompetitiveExamDetailsContainerPgpm from 'c/afCompetitiveExamDetailsContainerPgpm';
import afOtherInformationContainerPgpm from 'c/afOtherInformationContainerPgpm';
import afUploadDocumentsContainerPgpm from 'c/afUploadDocumentsContainerPgpm';
import afDeclarationContainerPgpm from 'c/afDeclarationContainerPgpm';

import afProgramDetailsContainerPgdm from 'c/afProgramDetailsContainerPgdm';
import afBasicDetailsContainerPgdm from 'c/afBasicDetailsContainerPgdm';
import afAcademicDetailsContainerPgdm from 'c/afAcademicDetailsContainerPgdm';
import afWorkExperienceContainerPgdm from 'c/afWorkExperienceContainerPgdm';
import afCompetitiveExamDetailsContainerPgdm from 'c/afCompetitiveExamDetailsContainerPgdm';
import afDeclarationContainerPgdm from 'c/afDeclarationContainerPgdm';

export const COMPONENT_REGISTRY = {
    afProgramDetailsContainerGmp,
    afBasicDetailsContainerGmp,
    afAcademicDetailsContainerGmp,
    afCompetitiveExamDetailsContainerGmp,
    afWorkExperienceContainerGmp,
    afProfileInformationContainerGmp,
    afTermsAndConditionsContainerGmp,

    afBasicDetailsContainerPgpm,
    afProgramDetailsContainerPgpm,
    afAcademicDetailsContainerPgpm,
    afWorkExperienceContainerPgpm,
    afCompetitiveExamDetailsContainerPgpm,
    afOtherInformationContainerPgpm,
    afUploadDocumentsContainerPgpm,
    afDeclarationContainerPgpm,

    afProgramDetailsContainerPgdm,
    afBasicDetailsContainerPgdm,
    afAcademicDetailsContainerPgdm,
    afWorkExperienceContainerPgdm,
    afCompetitiveExamDetailsContainerPgdm,
    afDeclarationContainerPgdm,
};

export const DEFAULT_ICON_STATES = {
    selected:
        '<svg width="80" height="80" viewBox="0 0 80 80"><circle cx="40" cy="40" r="36" fill="#E8DDF7" stroke="#4B2E83" stroke-width="4"/><rect x="26" y="22" width="28" height="36" rx="4" stroke="#4B2E83" stroke-width="4" fill="none"/><line x1="30" y1="32" x2="50" y2="32" stroke="#4B2E83" stroke-width="3"/><line x1="30" y1="40" x2="50" y2="40" stroke="#4B2E83" stroke-width="3"/></svg>',
    completed:
        '<svg width="80" height="80" viewBox="0 0 80 80"><circle cx="40" cy="40" r="36" fill="#4B2E83"/><rect x="26" y="22" width="28" height="36" rx="4" stroke="white" stroke-width="3" fill="none"/><line x1="30" y1="32" x2="50" y2="32" stroke="white" stroke-width="3"/><line x1="30" y1="40" x2="50" y2="40" stroke="white" stroke-width="3"/><circle cx="60" cy="60" r="9" fill="#4CAF50"/><polyline points="56,60 59,63 65,56" stroke="white" stroke-width="3" fill="none" stroke-linecap="round"/></svg>',
    pending:
        '<svg width="80" height="80" viewBox="0 0 80 80"><circle cx="40" cy="40" r="36" stroke="#B9AFCF" stroke-width="3" fill="none"/><rect x="26" y="22" width="28" height="36" rx="4" stroke="#4B2E83" stroke-width="3" fill="none"/><line x1="30" y1="32" x2="50" y2="32" stroke="#4B2E83" stroke-width="3"/><line x1="30" y1="40" x2="50" y2="40" stroke="#4B2E83" stroke-width="3"/></svg>'
};

const PAYMENT_STEP_TEMPLATE = {
    name: 'payment',
    label: 'Payment',
    stageValue: 'Payment',
    componentName: null,
    allowDirectClick: false,
    isPaymentStep: true,
    iconKey: 'payment'
};

export function getComponentCtor(componentName) {
    return COMPONENT_REGISTRY[componentName];
}

export function buildFormMetadataRequests(programCode) {
    return [
        {
            metadataName: 'Application_Form_Definition__mdt',
            fields: [
                'DeveloperName',
                'QualifiedApiName',
                'Program_Code__c',
                'Form_Key__c',
                'Is_Active__c',
                'Is_Default__c',
                'Needs_Payment__c'
            ],
            filters: [
                { field: 'Program_Code__c', operator: '=', value: programCode },
                { field: 'Is_Active__c', operator: '=', value: true }
            ]
        },
        {
            metadataName: 'Application_Form_Step__mdt',
            fields: [
                'DeveloperName',
                'Form_Definition__r.QualifiedApiName',
                'Step_Key__c',
                'Step_Label__c',
                'Stage_Value__c',
                'Sequence__c',
                'Component_Name__c',
                'Allow_Direct_Click__c',
                'Icon_Key__c',
                'Is_Active__c'
            ],
            filters: [{ field: 'Is_Active__c', operator: '=', value: true }]
        }
    ];
}

export function normalizeApplicationFormMetadata(programCode, formKey, metadataResponse) {
    if (!programCode || !metadataResponse) {
        return null;
    }

    const normalizedFormKey = (formKey || 'A').trim() || 'A';
    const definitions = metadataResponse.Application_Form_Definition__mdt || [];
    const selectedDefinition =
        definitions.find((definition) => definition.Form_Key__c === normalizedFormKey) ||
        definitions.find((definition) => definition.Is_Default__c === true);

    if (!selectedDefinition) {
        return null;
    }

    const definitionQualifiedApiName = selectedDefinition.QualifiedApiName || selectedDefinition.DeveloperName;
    const rawSteps = (metadataResponse.Application_Form_Step__mdt || [])
        .filter((step) => step['Form_Definition__r.QualifiedApiName'] === definitionQualifiedApiName)
        .sort((left, right) => {
            const leftSequence = Number(left.Sequence__c || 0);
            const rightSequence = Number(right.Sequence__c || 0);
            if (leftSequence !== rightSequence) {
                return leftSequence - rightSequence;
            }
            return (left.DeveloperName || '').localeCompare(right.DeveloperName || '');
        });

    const config = {
        programCode,
        formKey: selectedDefinition.Form_Key__c,
        needsPayment: selectedDefinition.Needs_Payment__c === true,
        stageToStepMap: {},
        steps: rawSteps.map((step) => ({
            name: step.Step_Key__c,
            label: step.Step_Label__c,
            stageValue: step.Stage_Value__c,
            sequence: Number(step.Sequence__c || 0),
            componentName: step.Component_Name__c,
            allowDirectClick: step.Allow_Direct_Click__c === true,
            isPaymentStep: false,
            iconKey: step.Icon_Key__c
        }))
    };

    let lastSequence = config.steps.reduce((maxSequence, step) => Math.max(maxSequence, step.sequence), 0);
    config.steps.forEach((step) => {
        if (step.stageValue) {
            config.stageToStepMap[step.stageValue] = step.name;
        }
    });

    if (config.needsPayment) {
        const paymentStep = {
            ...PAYMENT_STEP_TEMPLATE,
            sequence: lastSequence + 1
        };
        config.steps.push(paymentStep);
        config.stageToStepMap[paymentStep.stageValue] = paymentStep.name;
        lastSequence = paymentStep.sequence;
    }

    return config;
}