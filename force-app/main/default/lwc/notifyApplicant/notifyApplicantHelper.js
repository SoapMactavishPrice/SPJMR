export function formatError(error) {
    return error?.body?.message || 'Unknown error';
}