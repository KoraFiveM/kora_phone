import { HandsetPanel } from '../apps/handset/HandsetPanel';
import { SettingsScreen } from '../apps/settings/Settings';
import { usePhoneStore } from './storeContext';

/** Settings embeds the handset panel, which needs the preview model switch and a handset reload from the shell. */
export function SettingsHost() {
  const { actions, view } = usePhoneStore();
  return <SettingsScreen handsetPanel={panel => <HandsetPanel view={panel} onReload={actions.reloadHandset} previewModel={view.model} onPreviewModel={actions.choosePreviewModel} />} />;
}
