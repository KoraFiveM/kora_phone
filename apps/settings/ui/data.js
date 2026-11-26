// Static choices the Settings screens offer. The server accepts exactly the same ids (shared/validation.lua).
export const WALLPAPERS = [
    { id: 'kora_core', label: 'Signature', swatch: 'linear-gradient(160deg, hsl(var(--primary) / 45%), hsl(var(--background)))' },
    { id: 'orbit', label: 'Orbit', swatch: 'radial-gradient(circle at 28% 35%, hsl(var(--armour) / 55%) 0 14%, transparent 14.5%), radial-gradient(circle at 76% 70%, hsl(var(--warning) / 55%) 0 22%, transparent 22.5%), hsl(var(--foreground))' },
    { id: 'plain', label: 'Plain', swatch: 'hsl(var(--muted))' },
    { id: 'midnight', label: 'Midnight', swatch: 'linear-gradient(155deg, hsl(var(--armour) / 45%), hsl(var(--background)))' },
    { id: 'slate', label: 'Slate', swatch: 'linear-gradient(145deg, hsl(var(--foreground)), color-mix(in srgb, hsl(var(--foreground)) 45%, hsl(var(--background))))' },
    { id: 'ember', label: 'Ember', swatch: 'radial-gradient(ellipse at bottom right, hsl(var(--warning) / 60%), hsl(var(--background)) 75%)' },
    { id: 'custom', label: 'Your photo', swatch: 'repeating-linear-gradient(45deg, hsl(var(--muted-foreground)) 0 6px, hsl(var(--muted)) 6px 12px)' },
];

export const PHONE_CASES = [
    ['default', 'Default'], ['nightdrive', 'Night drive'], ['citypop', 'City pop'], ['sakura', 'Sakura'], ['touge', 'Touge'], ['garage', 'Garage'],
    ['kora_core', 'QBCore'], ['arcade', 'Arcade'], ['space', 'Deep space'], ['palms', 'Palms'], ['skyline', 'Skyline'], ['custom', 'My photo'],
];

export const ICON_STYLES = [['circle', 'Circle'], ['squircle', 'Rounded'], ['outline', 'Outline'], ['solid', 'Solid']];

export const APPEARANCES = [['dark', 'Dark'], ['light', 'Light']];
// Only 'light' is light. Dark covers the default 'kora_core' and every retired palette id.
export const appearanceOf = theme => (theme === 'light' ? 'light' : 'dark');

export const IDENTITY = {
    standard: { name: 'Orchard One', os: 'Kora OS', subtitle: 'Quiet by design. Yours in every detail.' },
    flip: { name: 'Circuit Flip', os: 'Circuit OS', subtitle: 'A little character. A more personal everyday.' },
    fold: { name: 'Atlas Fold', os: 'Atlas OS', subtitle: 'More room for what matters.' },
};

export const iconStyleOf = (model, stored) => model === 'standard' ? 'circle' : stored || (model === 'flip' ? 'squircle' : 'outline');

// Do Not Disturb: on all the time, or inside a daily window that may cross midnight (22:00 to 07:00).
const minutes = time => { const m = /^(\d\d):(\d\d)$/.exec(time || ''); return m ? Number(m[1]) * 60 + Number(m[2]) : -1; };
export function isQuiet(settings, now = new Date()) {
    if (settings.dnd === true) return true;
    const from = minutes(settings.dndFrom), to = minutes(settings.dndTo), at = now.getHours() * 60 + now.getMinutes();
    if (from < 0 || to < 0 || from === to) return false;
    return from < to ? at >= from && at < to : at >= from || at < to;
}

export const HANDSET_NAMES = { standard: 'Orchard One', flip: 'Circuit Flip', fold: 'Atlas Fold' };
export const ITEM_NAMES = { phone_standard: 'Orchard One', phone_flip: 'Circuit Flip', phone_fold: 'Atlas Fold', phone_sim: 'Mobile SIM' };
