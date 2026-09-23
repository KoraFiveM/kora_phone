import type { AppId } from './types';
type AppCopy = Record<Exclude<AppId, 'home'>, { label: string; subtitle: string }>;
const en: AppCopy = {
  custom: { label: 'Community app', subtitle: 'Made for your server.' },
  store: { label: 'App Store', subtitle: 'A little more you.' },
  banking: { label: 'Wallet', subtitle: 'A little peace of mind.' },
  social: { label: 'Pulse', subtitle: 'The city, in conversation.' },
  gallery: { label: 'Gallery', subtitle: 'The moments you keep.' },
  classifieds: { label: 'Market', subtitle: 'Good things. New beginnings.' },
  gps: { label: 'Maps', subtitle: 'Find your own way.' },
  services: { label: 'Work', subtitle: 'Your role. Your shift.' },
  notes: { label: 'Notes', subtitle: 'Room for a thought.' },
  mail: { label: 'Mail', subtitle: 'A little more to say.' },
  weather: { label: 'Weather', subtitle: 'Look on the bright side.' },
  calculator: { label: 'Calculator', subtitle: 'It all adds up.' },
  property: { label: 'Home', subtitle: 'Your corner of the city.' },
  vehicles: { label: 'Garage', subtitle: 'Make your next move.' },
  flash: { label: 'Flash', subtitle: 'Your city, in short clips.' },
  music: { label: 'Sound', subtitle: 'Something to listen to.' },
  clock: { label: 'Clock', subtitle: 'Right on time.' },
  phone: { label: 'Phone', subtitle: 'A voice on the other end.' },
  messages: { label: 'Messages', subtitle: 'Stay a little closer.' },
  contacts: { label: 'Contacts', subtitle: 'Good people. One place.' },
  camera: { label: 'Camera', subtitle: 'See something. Keep it.' },
  settings: { label: 'Settings', subtitle: 'Unmistakably yours.' },
  moderation: { label: 'Moderation', subtitle: 'Keep the city civil.' },
};
export const appCopy = (id: AppId) => id === 'home' ? { label: 'Home', subtitle: '' } : en[id];
