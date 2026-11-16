import { ArrowUpRight, Bell, Check, LockKeyhole, MessageCircle, Moon, Settings as SettingsIcon, SlidersHorizontal, Sun } from 'lucide-react';
import { api } from '../../api';
import { DotClock } from '../../components';
import { mergeOrder } from '../../homeReorder';
import type { AppId } from '../../types';
import { AppIcon } from '../AppIcon';
import { canLaunch, defaultDock, homeGridIds } from '../appRegistry';
import { senderName } from '../NotificationShade';
import { usePhoneStore } from '../storeContext';
import { useHomeReorder } from './useHomeReorder';

/** Icons per page: the unfolded tablet fits more. */
const pageSizeOf = (wide: boolean) => wide ? 16 : 12;

export function HomeScreen() {
  const { state, dispatch, actions, view } = usePhoneStore();
  const { device, notifications } = state;
  const { data, date, time, model, fold, quiet } = view;
  const { navigate } = actions;

  const gridIds = mergeOrder(data.settings.appOrder, homeGridIds(device));
  const dockIds = mergeOrder(data.settings.dockOrder, defaultDock(device));
  // Server turns this off with Config.HomeScreen.allowReorder; the preview and older servers leave it on.
  const reorderAllowed = device?.homeReorder !== false;
  const reorder = useHomeReorder({ grid: gridIds, dock: dockIds }, reorderAllowed);
  const { editing, dragId, overId } = reorder;

  const pageSize = pageSizeOf(fold && !state.folded);
  const pageCount = Math.max(1, Math.ceil(gridIds.length / pageSize));
  const visiblePage = Math.min(state.home.page, pageCount - 1);
  const unread = (id: AppId) => notifications.filter(n => n.app === id).reduce((total, n) => total + (n.count ?? 1), 0);
  const weather = canLaunch('weather', device);

  const toggleQuiet = () => {
    if (quiet && !data.settings.dnd) { actions.notify(`Quiet hours are on until ${data.settings.dndTo}. Change them in Settings.`); return; }
    const settings = { ...data.settings, dnd: !data.settings.dnd };
    actions.updateData({ ...data, settings });
    void actions.run(async () => { actions.updateData(await api('settings', settings)); });
  };
  const icon = (id: AppId, dock: boolean) => <AppIcon key={id} id={id} dock={dock} badge={unread(id)} editing={editing} dragging={dragId === id} over={overId === id} onClick={() => reorder.iconClick(id)} onPointerDown={e => reorder.beginPress(e, id, dock ? 'dock' : 'grid')} />;
  const note = notifications[0];

  return <main className="home-screen"><div className="home-top"><span className="eyebrow">{date.toLocaleDateString('en-GB', { weekday: 'short', day: '2-digit', month: 'short' }).toUpperCase()}</span><div>{reorderAllowed && <button className={`icon-button ${editing ? 'active' : ''}`} aria-label={editing ? 'Done arranging apps' : 'Arrange apps'} onClick={() => reorder.setEditing(!editing)}>{editing ? <Check size={17} /> : <SlidersHorizontal size={16} />}</button>}<button className={`icon-button ${quiet ? 'active' : ''}`} aria-label={quiet ? 'Turn off Do Not Disturb' : 'Turn on Do Not Disturb'} aria-pressed={quiet} onClick={toggleQuiet}><Moon size={16} /></button><button className="icon-button" aria-label="Notifications" onClick={() => dispatch({ type: 'patch', patch: { showNotifications: !state.showNotifications } })}><Bell size={17} />{notifications.length > 0 && <i className="notification-dot" />}</button><button className="icon-button" aria-label="Lock phone" onClick={actions.lock}><LockKeyhole size={16} /></button></div></div><div className={`handset-clock ${model === 'standard' ? 'nothing-clock' : ''}`} aria-label={model === 'standard' ? undefined : time}>{model === 'standard' ? <DotClock value={time} /> : time}</div><div className="home-widgets"><button className="city-widget" onClick={() => navigate(weather ? 'weather' : 'gps')}><Sun size={31} strokeWidth={1.2} /><div><strong>Los Santos</strong><span>{weather ? 'Your day, at a glance' : 'Find your way'}</span></div><ArrowUpRight size={14} /></button><button className="settings-widget" aria-label="Open Settings" onClick={() => navigate('settings')}><SettingsIcon size={25} strokeWidth={1.3} /><span>Make it yours</span></button></div><div className="home-section"><span>EVERYTHING, IN REACH.</span><span>( 01 )</span></div><div className="app-grid">{gridIds.slice(visiblePage * pageSize, visiblePage * pageSize + pageSize).map(id => icon(id, false))}</div>{editing && <div className="home-edit-hint"><span>Press and drag to rearrange</span><button onClick={() => reorder.setEditing(false)}>Done</button></div>}<button className="home-note" onClick={() => navigate(note?.app || 'messages')}><span className="note-symbol"><MessageCircle size={21} strokeWidth={1.5} /></span><span><strong>{(note && senderName(data, note)) || 'A little closer.'}</strong><small>{note?.body || 'Good conversations start with hello.'}</small></span><ArrowUpRight size={16} /></button><div className="home-page-dots">{Array.from({ length: pageCount }, (_, i) => <button key={i} data-home-page={i} aria-label={`App page ${i + 1}`} aria-current={visiblePage === i ? 'page' : undefined} onClick={() => dispatch({ type: 'home', patch: { page: i } })}><i /></button>)}</div><nav className="dock" aria-label="Favorite apps">{dockIds.map(id => icon(id, true))}</nav></main>;
}
