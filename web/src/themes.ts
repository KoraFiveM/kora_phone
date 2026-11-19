/**
 * Handset identity and appearance.
 *
 * kora_theme owns every colour, font and shape (see scheme.css). A handset only defines structure: its shell,
 * layout and icon style. The one colour choice a player keeps is the appearance, dark or light.
 */

// Ids the server accepts for settings.theme (shared/validation.lua SETTINGS_THEMES). Saved phones may still carry
// the retired palette ids; they are valid and simply resolve to an appearance.
export const THEME_IDS = ['kora_core', 'light', 'dark', 'ocean', 'forest', 'amethyst', 'ember'] as const;
export type Theme = typeof THEME_IDS[number];

export type Appearance = 'dark' | 'light';
export const appearanceOptions: ReadonlyArray<{ id: Appearance; label: string }> = [
  { id: 'dark', label: 'Dark' },
  { id: 'light', label: 'Light' },
];
// Only 'light' is light. Dark covers the default 'kora_core' and every retired palette id.
export const appearanceOf = (theme?: string): Appearance => (theme === 'light' ? 'light' : 'dark');
export const appearanceLabel = (appearance: Appearance) => appearanceOptions.find(option => option.id === appearance)!.label;

export type HandsetModel = 'standard' | 'flip' | 'fold';
export const handsetIconStyle = (model: HandsetModel, stored?: 'circle' | 'squircle' | 'outline' | 'solid') => model === 'standard' ? 'circle' : stored || (model === 'flip' ? 'squircle' : 'outline');
export const handsetIdentity = (model: HandsetModel) => ({
  standard: { name: 'Orchard One', os: 'Kora OS', subtitle: 'Quiet by design. Yours in every detail.' },
  flip: { name: 'Circuit Flip', os: 'Circuit OS', subtitle: 'A little character. A more personal everyday.' },
  fold: { name: 'Atlas Fold', os: 'Atlas OS', subtitle: 'More room for what matters.' },
})[model];
