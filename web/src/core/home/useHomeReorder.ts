import { sdkIdOf } from '../runtimeApps';
import { useCallback, useEffect, useRef } from 'react';
import type { PointerEvent as ReactPointerEvent } from 'react';
import { api } from '../../api';
import { LONG_PRESS_MS, MOVE_TOLERANCE, moveItem } from '../../homeReorder';
import type { AppId, DeviceData } from '../../types';
import { usePhoneStore } from '../storeContext';

type Zone = 'grid' | 'dock';

/**
 * Arranging the home screen. Pointer events instead of HTML5 drag-and-drop (unreliable in CEF): press and
 * hold an icon to start arranging, or press one straight away while arranging. Hovering a page dot turns the page.
 */
export function useHomeReorder(orders: { grid: AppId[]; dock: AppId[] }, allowed: boolean) {
  const { state, dispatch, actions, view } = usePhoneStore();
  const { editing, dragId, overId } = state.home;
  const { data } = view;
  const suppressClick = useRef(false);
  const dragCleanup = useRef<(() => void) | null>(null);
  const home = useCallback((patch: Partial<typeof state.home>) => dispatch({ type: 'home', patch }), [dispatch]);

  const saveOrder = (patch: Partial<DeviceData['settings']>) => {
    const settings = { ...data.settings, ...patch };
    actions.updateData({ ...data, settings });
    void (async () => { try { actions.updateData(await api('settings', settings)); } catch (e) { actions.notify(e instanceof Error ? e.message : 'Could not save the app order'); } })();
  };
  const reorder = (zone: Zone, from: AppId, to: AppId) => {
    const current = zone === 'dock' ? orders.dock : orders.grid;
    const next = moveItem(current, from, to);
    if (next.join() !== current.join()) saveOrder(zone === 'dock' ? { dockOrder: next } : { appOrder: next });
  };

  const beginPress = (e: ReactPointerEvent<HTMLButtonElement>, id: AppId, zone: Zone) => {
    if (!allowed || e.button !== 0 || dragCleanup.current) return;
    const startX = e.clientX, startY = e.clientY;
    let active = false, over: AppId | null = null, timer: number | undefined;
    const activate = (byLongPress: boolean) => { active = true; if (byLongPress) suppressClick.current = true; home({ editing: true, dragId: id, overId: null }); };
    const move = (ev: PointerEvent) => {
      const travelled = Math.hypot(ev.clientX - startX, ev.clientY - startY) > MOVE_TOLERANCE;
      if (!active) { if (travelled) end(false); return; }
      ev.preventDefault();
      if (travelled) suppressClick.current = true;
      const hit = document.elementFromPoint(ev.clientX, ev.clientY);
      const dot = hit?.closest<HTMLElement>('[data-home-page]');
      if (dot && zone === 'grid') home({ page: Number(dot.dataset.homePage) });
      const icon = hit?.closest<HTMLElement>('[data-app-id]');
      const next = icon && icon.dataset.zone === zone && icon.dataset.appId !== id ? icon.dataset.appId as AppId : null;
      if (next !== over) { over = next; home({ overId: next }); }
    };
    const up = () => end(true);
    const cancel = () => end(false);
    const end = (drop: boolean) => {
      window.clearTimeout(timer);
      window.removeEventListener('pointermove', move);
      window.removeEventListener('pointerup', up);
      window.removeEventListener('pointercancel', cancel);
      dragCleanup.current = null;
      if (active) { if (drop && over) reorder(zone, id, over); home({ dragId: null, overId: null }); }
      window.setTimeout(() => { suppressClick.current = false; }, 60);
    };
    window.addEventListener('pointermove', move, { passive: false });
    window.addEventListener('pointerup', up);
    window.addEventListener('pointercancel', cancel);
    dragCleanup.current = () => end(false);
    if (editing) activate(false); else timer = window.setTimeout(() => activate(true), LONG_PRESS_MS);
  };

  const iconClick = (id: AppId) => {
    if (suppressClick.current) { suppressClick.current = false; return; }
    if (editing) { home({ editing: false }); return; }
    const sdkId = sdkIdOf(id);
    if (sdkId) actions.navigate('custom', sdkId); else actions.navigate(id);
  };
  useEffect(() => () => dragCleanup.current?.(), []);
  useEffect(() => { if (!allowed) home({ editing: false, dragId: null, overId: null }); }, [allowed, home]);

  return { editing, dragId, overId, beginPress, iconClick, setEditing: (value: boolean) => home({ editing: value, dragId: null, overId: null }) };
}
