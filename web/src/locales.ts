import type { AppId } from './types';
type AppCopy = Record<Exclude<AppId, 'home'>, { label: string; subtitle: string }>;
const en: AppCopy = {
  custom: { label: 'Community app', subtitle: 'Made for your server.' },
  store: { label: 'App Store', subtitle: 'A little more you.' },
};
export const appCopy = (id: AppId) => id === 'home' ? { label: 'Home', subtitle: '' } : en[id];
