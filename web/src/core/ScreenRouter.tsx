import { Suspense } from 'react';
import { PageHeader } from '../components';
import { appDefinition } from './appRegistry';
import { FoldInbox } from './FoldInbox';
import { usePhoneStore } from './storeContext';

/** The open app: its page header (unless it draws its own), the app screen and, unfolded, the message list. */
export function ScreenRouter() {
  const { state, actions, view } = usePhoneStore();
  const { app, target, device } = state;
  const definition = appDefinition(app);
  if (!device) return null;
  const Screen = definition?.component;
  const social = definition?.fullBleed === true;
  const expanded = view.fold && !state.folded && app === 'messages';
  return <>
    {!social && <PageHeader title={definition?.copy.label || ''} subtitle={definition?.copy.subtitle} back={() => actions.navigate('home')} />}
    <div className={`handset-app-layout ${expanded ? 'expanded-messages' : ''}`}>
      {expanded && <FoldInbox />}
      <main className={`app-content ${social ? 'app-content-social' : ''}`} key={`${device.id}-${app}-${target}`}>
        {/* Heavy apps load on first open; the fallback matches the in-app loading line. */}
        <Suspense fallback={<p className="loading" role="status">Connecting<span>···</span></p>}>{Screen && <Screen target={target} />}</Suspense>
      </main>
    </div>
  </>;
}
