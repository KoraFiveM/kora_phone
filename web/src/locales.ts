import type { AppId } from './types';
type AppCopy = Record<Exclude<AppId, 'home'>, { label: string; subtitle: string }>;
const en: AppCopy = {
  custom: { label: 'Community app', subtitle: 'Made for your server.' },
  store: { label: 'App Store', subtitle: 'A little more you.' },
  social: { label: 'Pulse', subtitle: 'The city, in conversation.' },
  gps: { label: 'Maps', subtitle: 'Find your own way.' },
  flash: { label: 'Flash', subtitle: 'Your city, in short clips.' },
  music: { label: 'Sound', subtitle: 'Something to listen to.' },
  clock: { label: 'Clock', subtitle: 'Right on time.' },
  camera: { label: 'Camera', subtitle: 'See something. Keep it.' },
  settings: { label: 'Settings', subtitle: 'Unmistakably yours.' },
};
export const appCopy = (id: AppId) => id === 'home' ? { label: 'Home', subtitle: '' } : en[id];
