// Do Not Disturb: on all the time, or inside a daily window that may cross midnight (22:00 to 07:00).
export interface Quiet { dnd?: boolean; dndFrom?: string; dndTo?: string }
const minutes = (time?: string) => { const m = /^(\d\d):(\d\d)$/.exec(time ?? ''); return m ? Number(m[1]) * 60 + Number(m[2]) : -1; };
export function isQuiet(settings: Quiet, now = new Date()): boolean {
  if (settings.dnd === true) return true;
  const from = minutes(settings.dndFrom), to = minutes(settings.dndTo), at = now.getHours() * 60 + now.getMinutes();
  if (from < 0 || to < 0 || from === to) return false;
  return from < to ? at >= from && at < to : at >= from || at < to;
}
