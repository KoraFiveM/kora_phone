import { Check, X } from 'lucide-react';
import type { DeviceData, Notification } from '../types';
import { NotificationIcon } from './AppIcon';
import { usePhoneStore } from './storeContext';

const clock = (at: number) => new Date(at).toLocaleTimeString('en-GB', { hour: '2-digit', minute: '2-digit' });

/** Shared by the shade and the home-screen note: who a notification is from, using the contact name when there is one. */
export const senderName = (data: DeviceData, notification: Notification) => data.contacts.find(c => c.number === notification.title)?.name ?? notification.title;

function NotificationCard({ notification, data }: { notification: Notification; data: DeviceData }) {
  return <><NotificationIcon id={notification.app} /><span><strong>{senderName(data, notification)}</strong><small>{notification.body}</small></span>{notification.count && notification.count > 1 && <b className="notification-count">{notification.count}</b>}{notification.at && <time>{clock(notification.at)}</time>}</>;
}

export function NotificationShade() {
  const { state, dispatch, actions, view } = usePhoneStore();
  const { notifications, earlier } = state;
  const { data } = view;
  const close = () => dispatch({ type: 'patch', patch: { showNotifications: false } });
  return <div className="notification-shade"><div className="section-heading"><h3>Notifications</h3><span className="shade-actions">{notifications.length > 0 && <button className="text-button" onClick={() => actions.markRead(notifications)}>Clear all</button>}<button className="icon-button" aria-label="Close notifications" onClick={close}><X size={18} /></button></span></div>
    {notifications.length ? notifications.map((notification, i) => <button key={i} className="notification-card" onClick={() => { actions.navigate(notification.app); actions.markRead([notification]); }}><NotificationCard notification={notification} data={data} /></button>) : <div className="notifications-empty"><Check size={27} /><h3>All caught up.</h3><p>A little quiet looks good on you.</p></div>}
    {earlier.length > 0 && <><div className="section-heading earlier-heading"><h3>Earlier</h3><button className="text-button" onClick={() => dispatch({ type: 'patch', patch: { earlier: [] } })}>Clear history</button></div>{earlier.map((notification, i) => <button key={i} className="notification-card is-earlier" onClick={() => actions.navigate(notification.app)}><NotificationCard notification={notification} data={data} /></button>)}</>}
  </div>;
}
