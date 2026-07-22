// applicationService.js
export function validateMinMaxDate(fieldMeta, value) {
    if (!value) return null;
    if (!fieldMeta?.min && !fieldMeta?.max) return null;

    const normalizeDateOnly = (input) => {
        if (!input) return null;

        const str = String(input).trim();
        const match = str.match(/^(\d{4}-\d{2}-\d{2})/);
        if (!match) return null;

        const normalized = match[1];
        const parsed = new Date(`${normalized}T00:00:00`);
        if (isNaN(parsed.getTime())) return null;

        return normalized;
    };

    const d = normalizeDateOnly(value);
    if (!d) return null;

    if (fieldMeta.min) {
        const min = normalizeDateOnly(fieldMeta.min);
        if (min && d < min) {
            return {
                code: 'MIN_DATE',
                message: `${fieldMeta.label} must be ≥ ${fieldMeta.min}`
            };
        }
    }

    if (fieldMeta.max) {
        const max = normalizeDateOnly(fieldMeta.max);
        if (max && d > max) {
            return {
                code: 'MAX_DATE',
                message: `${fieldMeta.label} must be ≤ ${fieldMeta.max}`
            };
        }
    }

    return null;
}


// applicationService.js
export function buildErrorSummary(errors, metadata = {}) {
    let msg = `Not so quick. Resolve issues in below mentioned sections\n`;

    Object.keys(errors || {}).forEach(section => {
        let errorCount = 0;
        const block = errors[section];

        if (block && typeof block === 'object') {
            let hasSubSection = false;

            Object.keys(block).forEach(k => {
                const v = block[k];
                if (v && typeof v === 'object') {
                    hasSubSection = true;
                    const nonEmpty = Object.values(v)
                        .filter(x => typeof x === 'object'
                            ? Object.keys(x).length > 0
                            : !!x);
                    errorCount += nonEmpty.length;
                }
            });

            if (!hasSubSection) {
                errorCount = Object.keys(block).length;
            }
        }

        if (errorCount > 0) {
            console.log('errMsg errorCount', errorCount);
            console.log('errMsg section', section);
            const label = metadata?.[section]?.title || section;
            msg += `* section ${label.toUpperCase()} has ${errorCount} unresolved issue${errorCount > 1 ? 's' : ''}\n`;
        }
    });

    return msg;
}

//convert to title case
export function convertToTitleCase(str = '') {
    return str.toLowerCase().replace(
        /(^|\s|-|')\w/g,
        char => char.toUpperCase()
    );
}

const DEFAULT_MAX = 99999;
const DEFAULT_STEP = 1;

export function resolveMax(value) {
    if (value !== undefined && value !== null && value !== '') {
        return Number(value);
    }
    return DEFAULT_MAX;
}

export function resolveStep(value) {
    if (value !== undefined && value !== null && value !== '') {
        return Number(value);
    }
    return DEFAULT_STEP;
}

export function getStepMessage(fieldMeta) {

    const step = resolveStep(fieldMeta.step);
    const label = fieldMeta.label || fieldMeta.api;

    if (step === 1) {
        return `${label} must be a whole number`;
    }

    const decimals = step.toString().split('.')[1]?.length || 0;

    return `${label} can have up to ${decimals} decimal place${decimals > 1 ? 's' : ''}`;
}

export function validateNumber(fieldMeta, value) {

    if (fieldMeta?.readOnly) return null;

    if (value === null || value === '' || value === undefined) {
        return null;
    }

    const num = Number(value);
    if (isNaN(num)) return null;

    const step = resolveStep(fieldMeta.step);

    if (step) {
        const decimalsAllowed = step.toString().split('.')[1]?.length || 0;

        const valueStr = String(value);
        const decimalsEntered = (valueStr.split('.')[1] || '').length;

        if (decimalsEntered > decimalsAllowed) {
            return getStepMessage(fieldMeta);
        }
    }

    const min = fieldMeta.min;
    if (min != null && num < Number(min)) {
        return fieldMeta.messageWhenRangeUnderflow 
            || `${fieldMeta.label || fieldMeta.api} must be at least ${min}`;
    }

    const max = resolveMax(fieldMeta.max);

    if (max != null && num > max) {
        return `${fieldMeta.label || fieldMeta.api} cannot exceed ${max}`;
    }

    return null;
}

export function getValueByPath(data, path) {
    return path.split('.').reduce(
        (obj, key) => obj?.[key],
        data
    );
}

export function isFieldVisible(field, data) {
    if (!field) return true;

    if (field.visible === false) {
        return false;
    }

    const visibleWhen = field.visibleWhen;

    if (!visibleWhen) {
        return true;
    }

    return Object.entries(visibleWhen).every(([path, expected]) => {
        const actual = getValueByPath(data, path);

        if (expected === '__notNull') {
            return actual !== null && actual !== undefined;
        }

        if (expected === '__notEmpty') {
            return actual !== null &&
                actual !== undefined &&
                actual !== '';
        }

        if (Array.isArray(actual)) {
            return actual.includes(expected);
        }

        return actual === expected;
    });
}

function getWordCount(text) {

    if (!text) {
        return 0;
    }

    return text
        .trim()
        .split(/\s+/)
        .filter(Boolean)
        .length;
}

export function validateTextConstraints(fieldMeta, value) {

    if (
        value === null ||
        value === undefined ||
        value === ''
    ) {
        return null;
    }

    const text = String(value).trim();

    if (
        fieldMeta.maxlength &&
        text.length > Number(fieldMeta.maxlength)
    ) {
        return `${fieldMeta.label} cannot exceed ${fieldMeta.maxlength} characters. Current: ${text.length}`;
    }

    const wordCount = getWordCount(text);

    if (
        fieldMeta.minWords &&
        wordCount < Number(fieldMeta.minWords)
    ) {
        console.log('value came '+JSON.stringify(value));
        console.log('text counted: '+JSON.stringify(text));
        return `${fieldMeta.label} requires at least ${fieldMeta.minWords} words. Current: ${wordCount}`;
    }

    if (
        fieldMeta.maxWords &&
        wordCount > Number(fieldMeta.maxWords)
    ) {
        console.log('text counted: '+JSON.stringify(text));
        return `${fieldMeta.label} cannot exceed ${fieldMeta.maxWords} words. Current: ${wordCount}`;
    }

    return null;
}