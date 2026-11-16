import { useEffect, useRef, useState } from 'react';
import type { CSSProperties, PointerEvent as ReactPointerEvent } from 'react';
import { isDemo, isEmbed, isPreview } from '../api';
import { usePhoneStore } from './storeContext';

interface DragState { x: number; y: number; width: number; height: number; left: number; top: number; nextX: number; nextY: number; frame: number }

/** Scaling the handset to the window, and dragging it around the game screen by its status bar. */
export function usePhoneStage() {
  const { state, view } = usePhoneStore();
  const { data, flip, fold } = view;
  const unfoldedFold = fold && !state.folded;
  const [viewport, setViewport] = useState({ width: window.innerWidth, height: window.innerHeight });
  const [position, setPosition] = useState<{ x: number; y: number } | null>(null);
  const stage = useRef<HTMLDivElement>(null);
  // left/top: where the drag started; nextX/nextY: the latest clamped target; frame: the pending animation frame.
  // The stage follows the pointer through a CSS transform so React only re-renders on start and release.
  const drag = useRef<DragState | null>(null);

  useEffect(() => {
    const resize = () => setViewport({ width: window.innerWidth, height: window.innerHeight });
    window.addEventListener('resize', resize);
    return () => window.removeEventListener('resize', resize);
  }, []);

  const height = flip ? 820 : 780;
  const width = unfoldedFold ? 690 : 370;
  const margin = isDemo ? 64 : isPreview ? (viewport.width > 760 ? 180 : 150) : 40;
  const scale = isEmbed
    ? Math.min(viewport.width / width, viewport.height / height)
    : Math.min(data.settings.scale, (viewport.height - margin) / height, (viewport.width - (isDemo ? 20 : 28)) / width);

  // Keep a dragged phone on screen when the window or the handset shrinks.
  useEffect(() => {
    if (isPreview) return;
    const scaledWidth = width * scale; const scaledHeight = height * scale;
    setPosition(current => {
      if (!current) return current;
      const next = { x: Math.min(current.x, Math.max(0, viewport.width - scaledWidth)), y: Math.min(current.y, Math.max(0, viewport.height - scaledHeight)) };
      return next.x === current.x && next.y === current.y ? current : next;
    });
  }, [height, width, scale, viewport.height, viewport.width]);

  const handlers = {
    onPointerDown: (event: ReactPointerEvent<HTMLDivElement>) => {
      if (isPreview || event.button !== 0 || !stage.current) return;
      const bounds = stage.current.getBoundingClientRect();
      drag.current = { x: event.clientX - bounds.left, y: event.clientY - bounds.top, width: bounds.width, height: bounds.height, left: bounds.left, top: bounds.top, nextX: bounds.left, nextY: bounds.top, frame: 0 };
      setPosition({ x: bounds.left, y: bounds.top });
      event.currentTarget.setPointerCapture(event.pointerId);
    },
    onPointerMove: (event: ReactPointerEvent<HTMLDivElement>) => {
      const current = drag.current;
      if (!current) return;
      current.nextX = Math.max(0, Math.min(event.clientX - current.x, viewport.width - current.width));
      current.nextY = Math.max(0, Math.min(event.clientY - current.y, viewport.height - current.height));
      if (current.frame) return;
      current.frame = requestAnimationFrame(() => {
        current.frame = 0;
        if (stage.current) stage.current.style.transform = `translate(${current.nextX - current.left}px, ${current.nextY - current.top}px)`;
      });
    },
    onPointerUp: () => stop(),
    onPointerCancel: () => stop(),
  };
  function stop() {
    const current = drag.current;
    drag.current = null;
    if (!current) return;
    if (current.frame) cancelAnimationFrame(current.frame);
    if (stage.current) stage.current.style.transform = '';
    setPosition({ x: current.nextX, y: current.nextY });
  }

  const stageStyle: CSSProperties | undefined = !isPreview && position ? { left: position.x, top: position.y, right: 'auto', bottom: 'auto' } : undefined;
  return { stage, stageStyle, width, height, scale, handlers };
}
