import type { Scheme, ThemePayload } from './protocol';

/** kora_theme custom properties forwarded to apps (see kora_theme docs/tokens.md). */
export const THEME_VARS: readonly string[] = [
    'background', 'foreground', 'card', 'card-foreground', 'popover', 'popover-foreground',
    'secondary', 'secondary-foreground', 'muted', 'muted-foreground', 'accent', 'accent-foreground',
    'surface', 'surface-raised', 'surface-hover', 'surface-panel', 'secondary-text',
    'border', 'border-strong', 'input', 'control-border', 'control-border-hover',
    'primary', 'primary-foreground', 'ring', 'focus-ring', 'selection',
    'brand-hover', 'brand-pressed', 'brand-soft', 'brand-border',
    'success', 'success-soft', 'success-border', 'success-foreground',
    'warning', 'warning-soft', 'warning-border', 'warning-foreground',
    'destructive', 'destructive-soft', 'destructive-border', 'destructive-foreground',
    'danger', 'info', 'info-soft', 'info-border', 'info-foreground',
    'font-sans', 'font-heading', 'font-mono',
    'space', 'space-1', 'space-2', 'space-3', 'space-4', 'space-6',
    'radius-sm', 'radius', 'radius-lg', 'radius-full',
    'shadow-low', 'shadow-floating', 'shadow-modal',
    'duration-fast', 'duration-popover', 'duration-dialog', 'ease-entry',
].map(name => `--${name}`);

export type StyleReader = (name: string) => string;

/** Resolve every theme variable that has a value. Colour tokens are HSL triplets, e.g. "84 100% 50%". */
export function collectThemeVars(read: StyleReader, names: readonly string[] = THEME_VARS): Record<string, string> {
    const vars: Record<string, string> = {};
    for (const name of names) {
        const value = read(name).trim();
        if (value) vars[name] = value;
    }
    return vars;
}

/** Light/dark is derived from the --background lightness (HSL triplet); dark when unknown. */
export function schemeFromVars(vars: Record<string, string>): Scheme {
    const match = /^\s*[\d.]+(?:deg)?[\s,]+[\d.]+%[\s,]+([\d.]+)%/.exec(vars['--background'] ?? '');
    return match && Number(match[1]) > 50 ? 'light' : 'dark';
}

export function buildTheme(read: StyleReader): ThemePayload {
    const vars = collectThemeVars(read);
    return { vars, scheme: schemeFromVars(vars) };
}

export const sameTheme = (a: ThemePayload | null, b: ThemePayload): boolean => {
    if (!a || a.scheme !== b.scheme) return false;
    const keys = Object.keys(b.vars);
    return keys.length === Object.keys(a.vars).length && keys.every(key => a.vars[key] === b.vars[key]);
};
