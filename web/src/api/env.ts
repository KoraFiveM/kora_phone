import { isDemo } from '../mock';

declare global { interface Window { GetParentResourceName?: () => string } }

const query = new URLSearchParams(window.location?.search);
const demoParam = query.get('demo');

// mock.ts owns isDemo (import cycle), so it is only re-exported here.
export { isDemo };
export const isEmbed = isDemo && query.get('embed') === 'screen';
export const demoModel = (['standard', 'flip', 'fold'] as const).find(value => value === demoParam) ?? 'fold';
/** True in the browser preview, where requests are answered by mock.ts instead of the game. */
export const isPreview = isDemo || !window.GetParentResourceName;
export const requestId = (): string => crypto.randomUUID();
