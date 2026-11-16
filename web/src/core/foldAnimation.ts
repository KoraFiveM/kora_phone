// Folding hides the real display straight away, so copy it first: the top half of the copy rides on the
// half that swings down and the bottom half stays lit under it, until the phone is shut.
const reduced = () => matchMedia('(prefers-reduced-motion: reduce)').matches;

function layer(phone: HTMLElement, screen: HTMLElement, className: string, copyClass: string): HTMLDivElement {
  const el = document.createElement('div'); el.className = className; el.setAttribute('aria-hidden', 'true');
  const copy = screen.cloneNode(true) as HTMLElement; copy.removeAttribute('inert'); copy.classList.add(copyClass);
  el.appendChild(copy); phone.appendChild(el);
  return el;
}

export function snapshotForFold(phone: HTMLElement | null, screen: HTMLElement | null): void {
  if (!phone || !screen || reduced()) return;
  const face = document.createElement('div'); face.className = 'fold-face'; face.setAttribute('aria-hidden', 'true');
  face.appendChild(layer(phone, screen, 'fold-face-inner', 'fold-copy-top')); phone.appendChild(face);
  const made = [layer(phone, screen, 'fold-rest', 'fold-copy-bottom'), face];
  window.setTimeout(() => made.forEach(el => el.remove()), 600);
}

export function snapshotForUnfold(phone: HTMLElement | null, screen: HTMLElement | null): void {
  if (!phone || !screen || reduced()) return;
  const face = layer(phone, screen, 'unfold-face', 'unfold-copy-top');
  const rest = layer(phone, screen, 'unfold-rest', 'unfold-copy-bottom');
  window.setTimeout(() => { face.remove(); rest.remove(); }, 800);
}
