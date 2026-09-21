export const themes = [
  { id: 'light', label: 'Light', dark: false, color: '#efefef' },
  { id: 'dark', label: 'Dark', dark: true, color: '#242424' },
  { id: 'ocean', label: 'Ocean', dark: true, color: '#123449' },
  { id: 'forest', label: 'Forest', dark: true, color: '#183b2c' },
  { id: 'amethyst', label: 'Amethyst', dark: true, color: '#352345' },
  { id: 'ember', label: 'Ember', dark: true, color: '#482a20' },
  { id: 'qbcore', label: 'QBCore', dark: true, color: '#17140f', chip: 'linear-gradient(135deg, #17140f 58%, #d86b59 58%)' },
] as const;
export type Theme = typeof themes[number]['id'];
export const isDarkTheme = (id?: Theme) => themes.find(theme => theme.id === id)?.dark ?? false;
// The small colour chip can differ from the theme's solid colour (QBCore shows its accent as a two-tone chip).
export const themeChip = (theme: typeof themes[number]) => 'chip' in theme ? theme.chip : theme.color;
