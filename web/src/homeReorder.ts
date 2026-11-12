// Home-screen icon arranging. FiveM NUI (CEF) does not reliably deliver HTML5 drag events, so the
// arranging UI uses pointer events; these helpers hold the list logic and are kept free of DOM and
// React imports so tests/home-reorder.test.js can run them directly.

export const LONG_PRESS_MS = 450;
export const MOVE_TOLERANCE = 8;

/** Saved order first (unknown and repeated ids dropped), then anything new in its default position order. */
export function mergeOrder<T extends string>(saved: readonly T[] | undefined, available: readonly T[]): T[] {
  const seen = new Set<T>();
  const out: T[] = [];
  for (const id of saved ?? []) if (available.includes(id) && !seen.has(id)) { seen.add(id); out.push(id); }
  for (const id of available) if (!seen.has(id)) { seen.add(id); out.push(id); }
  return out;
}

/** Moves `from` into the slot currently held by `to`. Returns the same list when nothing can move. */
export function moveItem<T>(list: readonly T[], from: T, to: T): T[] {
  const source = list.indexOf(from);
  const target = list.indexOf(to);
  if (from === to || source < 0 || target < 0) return [...list];
  const next = [...list];
  next.splice(source, 1);
  next.splice(target, 0, from);
  return next;
}
