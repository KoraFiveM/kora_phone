export const themes = [
  { id: 'kora_core', label: 'QBCore', dark: true, color: '#17140f', chip: 'linear-gradient(135deg, #17140f 58%, #d86b59 58%)' },
  { id: 'light', label: 'Light', dark: false, color: '#efefef' },
  { id: 'dark', label: 'Dark', dark: true, color: '#242424' },
  { id: 'ocean', label: 'Ocean', dark: true, color: '#123449' },
  { id: 'forest', label: 'Forest', dark: true, color: '#183b2c' },
  { id: 'amethyst', label: 'Amethyst', dark: true, color: '#352345' },
  { id: 'ember', label: 'Ember', dark: true, color: '#482a20' },
] as const;
export type Theme = typeof themes[number]['id'];
export const isDarkTheme = (id?: Theme) => themes.find(theme => theme.id === id)?.dark ?? false;
// The small colour chip can differ from the theme's solid colour (QBCore shows its accent as a two-tone chip).
export const themeChip = (theme: typeof themes[number]) => 'chip' in theme ? theme.chip : theme.color;

export type HandsetModel = 'standard' | 'flip' | 'fold';
export const handsetIconStyle = (model:HandsetModel, stored?:'circle'|'squircle'|'outline'|'solid') => model==='standard' ? 'circle' : stored || (model==='flip' ? 'squircle' : 'outline');
export const handsetIdentity = (model: HandsetModel) => ({
  standard: { name: 'Orchard One', os: 'Nothing-inspired OS', subtitle: 'Quiet by design. Yours in every detail.' },
  flip: { name: 'Circuit Flip', os: 'Circuit OS', subtitle: 'A little character. A more personal everyday.' },
  fold: { name: 'Atlas Fold', os: 'Atlas OS', subtitle: 'More room for what matters.' },
})[model];

type Palette = { bg:string; surface:string; field:string; ink:string; muted:string; line:string; accent:string; actionInk:string; wallpaper:string };
const dark:Palette={bg:'#101214',surface:'#1a1d20',field:'#24282c',ink:'#eef0f2',muted:'#a7afb6',line:'#394047',accent:'#e3e9ee',actionInk:'#171b1e',wallpaper:'#15191d'};
const light:Palette={bg:'#f5f6f8',surface:'#ffffff',field:'#edf0f4',ink:'#202731',muted:'#5c6978',line:'#d7dde5',accent:'#344761',actionInk:'#ffffff',wallpaper:'#e8edf3'};
const flip:Record<string,Palette>={
  dark, light,
  ocean:{bg:'#f1f7fc',surface:'#ffffff',field:'#dfecf6',ink:'#203a50',muted:'#536f87',line:'#c9dce9',accent:'#376c98',actionInk:'#fff',wallpaper:'radial-gradient(ellipse at top right,#c1e1f8,transparent 65%),#e8f2fa'},
  forest:{bg:'#f1f7f3',surface:'#ffffff',field:'#e0eee5',ink:'#253d30',muted:'#5b7464',line:'#cbded1',accent:'#386c50',actionInk:'#fff',wallpaper:'radial-gradient(ellipse at top right,#c4e3cf,transparent 65%),#e8f2ec'},
  amethyst:{bg:'#f6f2fa',surface:'#ffffff',field:'#eae1f2',ink:'#3d2e4e',muted:'#736180',line:'#ded2e8',accent:'#73528d',actionInk:'#fff',wallpaper:'radial-gradient(ellipse at top right,#ead1eb,transparent 65%),#e9e2f2'},
  ember:{bg:'#fcf4f0',surface:'#ffffff',field:'#f4e3d9',ink:'#4c3328',muted:'#836759',line:'#e8d5c8',accent:'#995e41',actionInk:'#fff',wallpaper:'radial-gradient(ellipse at top right,#f6d4bb,transparent 65%),#f6e9e0'},
};
const fold:Record<string,Palette>={
  dark, light,
  ocean:{bg:'#101d28',surface:'#192b39',field:'#21394b',ink:'#e3edf5',muted:'#a0b9cc',line:'#365368',accent:'#b9dced',actionInk:'#163142',wallpaper:'radial-gradient(ellipse at top left,#37687a66,transparent 65%),#102739'},
  forest:{bg:'#12231d',surface:'#1b3228',field:'#254435',ink:'#e6f0e8',muted:'#a7c0af',line:'#3c5c48',accent:'#bcdfc6',actionInk:'#183522',wallpaper:'radial-gradient(ellipse at top left,#47735b66,transparent 65%),#142b20'},
  amethyst:{bg:'#211b2b',surface:'#30273e',field:'#403450',ink:'#eee7f5',muted:'#bfb0d0',line:'#574767',accent:'#dbcaee',actionInk:'#30223e',wallpaper:'radial-gradient(ellipse at top left,#72558a66,transparent 65%),#251b34'},
  ember:{bg:'#2a1c16',surface:'#3b2921',field:'#4c372c',ink:'#f2e8df',muted:'#c8b2a0',line:'#674d3d',accent:'#eecbb1',actionInk:'#3b271b',wallpaper:'radial-gradient(ellipse at top left,#97613f55,transparent 65%),#302016'},
};

export function resolveHandsetTheme(model:HandsetModel, stored?:Theme) {
  if (!themes.some(theme=>theme.id===stored)) stored=undefined;
  const id:Theme=model==='standard' ? stored==='light' ? 'light' : 'dark'
    : !stored || stored==='kora_core' ? model==='flip' ? 'amethyst' : 'ocean' : stored;
  const palette:Palette=model==='standard'
    ? id==='light' ? {...light,bg:'#f5f5f5',field:'#f0f0f0',ink:'#1a1a1a',muted:'#666666',line:'#cccccc',accent:'#1a1a1a',wallpaper:'#f5f5f5'}
      : {...dark,bg:'#000000',surface:'#111111',field:'#1a1a1a',ink:'#e8e8e8',muted:'#999999',line:'#333333',accent:'#e8e8e8',actionInk:'#000000',wallpaper:'#000000'}
    : (model==='flip' ? flip : fold)[id] || dark;
  const labels:Record<string,string>=model==='standard' ? {dark:'Dark',light:'Light'} : model==='flip'
    ? {dark:'Graphite',light:'Porcelain',ocean:'Sky',forest:'Sage',amethyst:'Lilac',ember:'Apricot'}
    : {dark:'Graphite',light:'Platinum',ocean:'Midnight',forest:'Evergreen',amethyst:'Dusk',ember:'Copper'};
  return {...palette,id,label:labels[id] || 'Graphite',dark:model==='standard' ? id!=='light' : model==='fold' ? id!=='light' : id==='dark',color:palette.wallpaper};
}

export const themeOptions = (model:HandsetModel) => themes
  .filter(theme=>theme.id!=='kora_core' && (model!=='standard' || theme.id==='dark' || theme.id==='light'))
  .map(theme=>resolveHandsetTheme(model,theme.id));

export function handsetThemeTokens(palette:ReturnType<typeof resolveHandsetTheme>, wallpaper?:string) {
  const lightScene=wallpaper==='orbit' || wallpaper==='slate';
  const darkScene=wallpaper==='midnight' || wallpaper==='ember' || wallpaper==='custom';
  return {
    '--ui-bg':palette.bg,'--ui-surface':palette.surface,'--ui-field':palette.field,
    '--ui-ink':palette.ink,'--ui-muted':palette.muted,'--ui-line':palette.line,
    '--ui-action':palette.accent,'--ui-action-ink':palette.actionInk,'--ui-accent':palette.accent,
    '--handset-wallpaper':palette.wallpaper,
    '--wp-ink':lightScene?'#20252a':darkScene?'#f5f5f5':palette.ink,
    '--wp-ink-muted':lightScene?'#535e69':darkScene?'#c4c4c4':palette.muted,
    colorScheme:palette.dark ? 'dark' : 'light',
  };
}
