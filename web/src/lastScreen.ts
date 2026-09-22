// Remembers the last screen across phone close/reopen and page reloads.
export const recall = (key: string): string | null => { try { return localStorage.getItem(`qbphone:${key}`); } catch { return null; } };
export const remember = (key: string, value: string) => { try { localStorage.setItem(`qbphone:${key}`, value); } catch { /* storage blocked: start from home */ } };
// A crashing screen must not be restored on the next open, or the phone would crash on every load.
addEventListener('error', () => remember('app', 'home'));
