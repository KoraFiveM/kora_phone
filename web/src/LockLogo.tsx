const mark = [
  '110000011',
  '111000011',
  '111100011',
  '110110011',
  '110011011',
  '110001111',
  '110000111',
  '110000011',
];

// The QBCore glyph from https://qbcore.org/icon.svg (filled from the kora_theme primary), embedded so it scales and needs no
// image request. Shown on the lock screen when the QBCore theme is selected.
export const QB_MARK_PATH = 'M697.41,211.72c-64.8-64.81-165.54-72.3-238.67-22.51V.56H376.5V279.32l-31.26-38.59a190.31,190.31,0,0,0-23.8-29c-73.3-73.3-192.56-73.3-265.85,0A188,188,0,0,0,294.26,500.08V695.44H376.5V410l31.31,38.65a190.12,190.12,0,0,0,23.75,28.95A188,188,0,1,0,697.41,211.72ZM263.28,419.41A105.71,105.71,0,1,1,262,268.68h0c.42.4.85.78,1.25,1.19a105.83,105.83,0,0,1,0,149.54Zm376,0A105.84,105.84,0,0,1,491,420.6c-.42-.4-.85-.78-1.25-1.19a105.74,105.74,0,1,1,149.54,0Z';

/** The QBCore glyph on its own, for small spots such as the status bar and home header. */
export function QbMark({ size = 12 }: { size?: number }) {
  return <svg className="qb-mark" viewBox="0 0 700 696" width={size} height={size} aria-hidden="true"><path d={QB_MARK_PATH} transform="translate(-0.53 -0.56)" /></svg>;
}

/** A crisp, local animated mark; no image download or GIF decoding required. */
export function LockLogo({ brand = 'nothing' }: { brand?: 'nothing' | 'qbcore' }) {
  const qb = brand === 'qbcore';
  return <div className="lock-brand">
    <svg className="lock-logo" viewBox="0 0 240 240" role="img" aria-label={qb ? 'QBCore logo' : 'Nothing Phone animated logo'}>
      <circle className="logo-track" cx="120" cy="120" r="100" />
      <circle className="logo-inner-track" cx="120" cy="120" r="84" />
      <g className="logo-orbit">
        <path className="logo-arc" d="M 120 20 A 100 100 0 0 1 220 120" />
        <circle className="logo-satellite" cx="120" cy="20" r="4" />
      </g>
      {qb
        ? <path className="logo-qbmark" d={QB_MARK_PATH} transform="translate(72.5 72.8) scale(0.1357) translate(-0.53 -0.56)" />
        : <>
          <g className="logo-mark">{mark.flatMap((row, y) => [...row].map((dot, x) => dot === '1' ? <circle key={`${x}-${y}`} cx={76 + x * 10} cy={81 + y * 10} r="3.2" /> : null))}</g>
          <circle className="logo-period" cx="173" cy="151" r="5" />
        </>}
      <path className="logo-ticks" d="M120 8v5 M120 227v5 M8 120h5 M227 120h5" />
    </svg>
    <span className="lock-brand-label">{qb ? 'QBCORE / PHONE' : 'NOTHING / PHONE'}</span>
  </div>;
}
