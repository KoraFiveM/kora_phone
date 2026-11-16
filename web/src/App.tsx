import './handset-shells.css';
import './scheme.css';
import './handset-standard.css';
import { Phone } from './core/Phone';
import { PhoneStoreProvider } from './core/PhoneStore';

/** Root component. The theme stylesheets are imported here and in main.tsx (style.css, surfaces.css, social.css). */
export default function App() {
  return <PhoneStoreProvider><Phone /></PhoneStoreProvider>;
}
