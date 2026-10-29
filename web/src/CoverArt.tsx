import { useId, useState } from 'react';
import { imageUrl } from './Images';
import { QB_MARK_PATH } from './LockLogo';
import type { Settings } from './types';

// Original vector scenes for the flip phone's folded back panel. Drawn for this project, so there
// are no third-party images to license or download. They are composed for the panel's real shape
// (portrait, 300x340): the focal element sits in the top band (between the camera lenses and the
// label) or the bottom band (below "Put away"), and the middle stays simple because the display
// covers it with dark glass.
export const PHONE_CASES = [
  { id: 'default', label: 'Default' },
  { id: 'nightdrive', label: 'Night drive' },
  { id: 'citypop', label: 'City pop' },
  { id: 'sakura', label: 'Sakura' },
  { id: 'touge', label: 'Touge' },
  { id: 'garage', label: 'Garage' },
  { id: 'qbcore', label: 'QBCore' },
  { id: 'arcade', label: 'Arcade' },
  { id: 'space', label: 'Deep space' },
  { id: 'palms', label: 'Palms' },
  { id: 'skyline', label: 'Skyline' },
  { id: 'custom', label: 'My photo' },
] as const;
export type PhoneCase = typeof PHONE_CASES[number]['id'];
type Scene = Exclude<PhoneCase, 'default' | 'custom'>;

const CITY_BACK: [number, number, number][] = [[0, 34, 150], [30, 26, 190], [52, 30, 140], [86, 28, 205], [110, 34, 165], [140, 26, 125], [162, 36, 195], [196, 28, 160], [220, 32, 215], [248, 26, 145], [270, 34, 180]];
const CITY_FRONT: [number, number, number][] = [[-6, 40, 108], [30, 30, 134], [58, 44, 96], [98, 32, 148], [126, 40, 114], [162, 30, 130], [188, 44, 102], [228, 34, 140], [258, 44, 112]];
const PETALS: [number, number, number][] = [[24, 130, 20], [276, 96, -30], [16, 210, 40], [284, 176, 10], [30, 268, -20], [270, 250, 35], [150, 310, -10], [92, 322, 25], [230, 318, 15], [60, 36, 30], [244, 30, -25]];
const STARS: [number, number, number][] = [[18, 20, 1.2], [46, 84, 1], [122, 16, 1.4], [176, 28, 1], [214, 12, 1.2], [246, 78, 1], [284, 40, 1.4], [70, 10, 1], [200, 84, 1]];

// Space Invaders-style sprite: each string is a row, 1 = lit pixel.
const INVADER = ['00100000100', '00010001000', '00111111100', '01101110110', '11111111111', '10111111101', '10100000101', '00011011000'];
const RAIN: [number, number][] = [[14, 20], [52, 60], [88, 8], [126, 44], [166, 24], [204, 70], [240, 14], [276, 52], [30, 110], [104, 98], [190, 120], [262, 104], [70, 150], [150, 142], [226, 158]];
const MORE_STARS: [number, number, number][] = [...STARS, [30, 150, 1], [90, 190, 1.2], [260, 140, 1], [140, 120, 1], [222, 176, 1.2], [60, 240, 1], [280, 230, 1.4], [16, 300, 1], [120, 270, 1]];

function Scene({ id }: { id: Scene }) {
  const g = `c${useId().replace(/:/g, '')}`;
  switch (id) {
    case 'nightdrive': return <>
      <defs>
        <linearGradient id={`${g}s`} x1="0" y1="0" x2="0" y2="1"><stop offset="0" stopColor="#12062e" /><stop offset=".55" stopColor="#5b1a7a" /><stop offset="1" stopColor="#ff4f8b" /></linearGradient>
        <linearGradient id={`${g}u`} x1="0" y1="0" x2="0" y2="1"><stop offset="0" stopColor="#ffd166" /><stop offset="1" stopColor="#ff4f8b" /></linearGradient>
        <clipPath id={`${g}c`}><rect x="0" y="0" width="300" height="206" /></clipPath>
      </defs>
      <rect width="300" height="340" fill={`url(#${g}s)`} />
      {STARS.map(([x, y, r]) => <circle key={`${x}${y}`} cx={x} cy={y} r={r} fill="#fff" opacity=".8" />)}
      <g clipPath={`url(#${g}c)`}><circle cx="150" cy="150" r="64" fill={`url(#${g}u)`} />{[150, 164, 176, 186, 194, 201].map((y, i) => <rect key={y} x="80" y={y} width="140" height={1.6 + i * 1} fill="#4a1466" />)}</g>
      <rect y="206" width="300" height="134" fill="#0d0620" />
      <polygon points="145,206 155,206 296,340 4,340" fill="#170a30" />
      {[-150, -100, -50, 0, 50, 100, 150].map(dx => <line key={dx} x1="150" y1="206" x2={150 + dx * 1.6} y2="340" stroke="#ff4f8b" strokeOpacity=".45" strokeWidth=".8" />)}
      {[216, 230, 250, 278, 316].map(y => <line key={y} x1="0" y1={y} x2="300" y2={y} stroke="#ff4f8b" strokeOpacity=".35" strokeWidth=".8" />)}
      <path d="M108 342 L112 318 Q118 304 133 302 L167 302 Q182 304 188 318 L192 342 Z" fill="#0a0414" />
      <path d="M122 318 Q126 309 136 308 L164 308 Q174 309 178 318 Z" fill="#2a1450" />
      <ellipse cx="124" cy="326" rx="15" ry="6" fill="#ff2d55" opacity=".28" /><ellipse cx="176" cy="326" rx="15" ry="6" fill="#ff2d55" opacity=".28" />
      <rect x="112" y="322" width="21" height="5" rx="2" fill="#ff2d55" /><rect x="167" y="322" width="21" height="5" rx="2" fill="#ff2d55" />
    </>;
    case 'citypop': return <>
      <defs>
        <linearGradient id={`${g}s`} x1="0" y1="0" x2="0" y2="1"><stop offset="0" stopColor="#f0708f" /><stop offset=".5" stopColor="#ff9c8a" /><stop offset="1" stopColor="#ffd9a8" /></linearGradient>
        <radialGradient id={`${g}h`}><stop offset="0" stopColor="#fff3c4" stopOpacity=".7" /><stop offset="1" stopColor="#fff3c4" stopOpacity="0" /></radialGradient>
      </defs>
      <rect width="300" height="340" fill={`url(#${g}s)`} />
      <circle cx="150" cy="54" r="52" fill={`url(#${g}h)`} /><circle cx="150" cy="54" r="27" fill="#fff3c4" />
      <path d="M196 16 q5 -6 10 0 q5 -6 10 0 M214 30 q4 -5 8 0 q4 -5 8 0 M262 22 q5 -6 10 0 q5 -6 10 0" fill="none" stroke="#7a4b8a" strokeWidth="1.6" strokeLinecap="round" />
      {CITY_BACK.map(([x, w, h]) => <rect key={`b${x}`} x={x} y={340 - h} width={w} height={h} fill="#7a5aa6" opacity=".78" />)}
      {CITY_FRONT.map(([x, w, h]) => <g key={`f${x}`}><rect x={x} y={340 - h} width={w} height={h} fill="#2a1d45" />{Array.from({ length: Math.floor(h / 22) }, (_, r) => <rect key={r} x={x + 7 + ((r * 11) % Math.max(8, w - 18))} y={340 - h + 10 + r * 20} width="5" height="7" fill="#ffd166" opacity={r % 3 === 0 ? 0.25 : 0.9} />)}</g>)}
    </>;
    case 'sakura': return <>
      <defs>
        <linearGradient id={`${g}s`} x1="0" y1="0" x2="0" y2="1"><stop offset="0" stopColor="#0c1432" /><stop offset="1" stopColor="#3a3382" /></linearGradient>
        <radialGradient id={`${g}m`}><stop offset="0" stopColor="#fdf6e3" stopOpacity=".9" /><stop offset="1" stopColor="#fdf6e3" stopOpacity="0" /></radialGradient>
      </defs>
      <rect width="300" height="340" fill={`url(#${g}s)`} />
      {STARS.map(([x, y, r]) => <circle key={`${x}${y}`} cx={x} cy={y} r={r} fill="#fff" opacity=".7" />)}
      <circle cx="150" cy="52" r="52" fill={`url(#${g}m)`} opacity=".6" /><circle cx="150" cy="52" r="25" fill="#fdf6e3" />
      <path d="M312 318 C 262 300, 214 322, 158 326 S 64 340, -10 328" fill="none" stroke="#231433" strokeWidth="6" strokeLinecap="round" />
      <path d="M232 312 C 240 292, 252 280, 266 272 M120 328 C 108 312, 96 304, 84 300 M40 334 C 30 322, 18 316, 6 314" fill="none" stroke="#231433" strokeWidth="3" strokeLinecap="round" />
      {[[270, 270], [258, 282], [236, 308], [212, 314], [188, 320], [160, 326], [132, 328], [104, 322], [84, 300], [90, 312], [62, 334], [36, 334], [8, 314], [20, 320], [282, 262]].map(([x, y], i) => <g key={i}><circle cx={x} cy={y} r={6 + (i % 3)} fill="#ffb7d5" /><circle cx={x - 2} cy={y - 2} r="2" fill="#ffe3ee" /></g>)}
      {PETALS.map(([x, y, r]) => <ellipse key={`${x}${y}`} cx={x} cy={y} rx="4" ry="2.4" fill="#ffc8de" opacity=".85" transform={`rotate(${r} ${x} ${y})`} />)}
    </>;
    case 'touge': return <>
      <defs>
        <linearGradient id={`${g}s`} x1="0" y1="0" x2="0" y2="1"><stop offset="0" stopColor="#2b1055" /><stop offset=".4" stopColor="#8a6bbf" /><stop offset=".62" stopColor="#ffb37b" /><stop offset="1" stopColor="#ffb37b" /></linearGradient>
        <radialGradient id={`${g}h`}><stop offset="0" stopColor="#fff7d6" /><stop offset="1" stopColor="#fff7d6" stopOpacity="0" /></radialGradient>
      </defs>
      <rect width="300" height="340" fill={`url(#${g}s)`} />
      <circle cx="150" cy="80" r="34" fill="#ffd9a0" opacity=".35" /><circle cx="150" cy="78" r="26" fill="#fff0c8" />
      <polygon points="0,86 30,58 62,76 104,42 146,84 152,84 196,46 240,74 272,54 300,82 300,340 0,340" fill="#4b3f8f" />
      <polygon points="0,140 60,104 116,132 178,100 240,130 300,108 300,340 0,340" fill="#241a56" />
      <polygon points="0,196 74,166 146,190 216,160 300,184 300,340 0,340" fill="#120c30" />
      <path d="M152 348 C 84 312, 218 276, 140 240 S 178 200, 164 172" fill="none" stroke="#0a0720" strokeWidth="40" strokeLinecap="round" />
      <path d="M152 348 C 84 312, 218 276, 140 240 S 178 200, 164 172" fill="none" stroke="#ffd166" strokeWidth="1.8" strokeDasharray="7 8" />
      <circle cx="140" cy="322" r="18" fill={`url(#${g}h)`} opacity=".8" /><circle cx="158" cy="324" r="18" fill={`url(#${g}h)`} opacity=".8" />
      <circle cx="141" cy="322" r="3" fill="#fffbe8" /><circle cx="157" cy="324" r="3" fill="#fffbe8" />
    </>;
    case 'garage': return <>
      <defs>
        <linearGradient id={`${g}w`} x1="0" y1="0" x2="0" y2="1"><stop offset="0" stopColor="#1b1b22" /><stop offset="1" stopColor="#08080b" /></linearGradient>
        <linearGradient id={`${g}l`} x1="0" y1="0" x2="0" y2="1"><stop offset="0" stopColor="#fff" stopOpacity=".55" /><stop offset="1" stopColor="#fff" stopOpacity="0" /></linearGradient>
      </defs>
      <rect width="300" height="340" fill={`url(#${g}w)`} />
      <polygon points="122,0 178,0 244,306 56,306" fill={`url(#${g}l)`} />
      <rect x="110" y="0" width="80" height="7" fill="#3a3a44" />
      <rect x="4" y="30" width="12" height="270" rx="6" fill="#ff3b5c" opacity=".22" /><rect x="8" y="34" width="5" height="262" rx="2.5" fill="#ff3b5c" />
      <rect x="284" y="30" width="12" height="270" rx="6" fill="#3bd6ff" opacity=".2" /><rect x="287" y="34" width="5" height="262" rx="2.5" fill="#3bd6ff" />
      <rect y="306" width="300" height="34" fill="#101015" />
      <line x1="0" y1="318" x2="300" y2="318" stroke="#23232c" strokeWidth="1" />
      <ellipse cx="150" cy="316" rx="120" ry="7" fill="#000" opacity=".5" />
      <path d="M60 300 L78 286 Q100 270 135 268 L175 268 Q205 270 222 286 L245 292 Q252 296 252 304 L252 310 L52 310 L52 304 Q52 300 60 300 Z" fill="#0b0b10" stroke="#34343f" strokeWidth="1.2" />
      <path d="M92 286 Q108 274 136 272 L172 272 Q194 274 206 286 Z" fill="#20202b" />
      <circle cx="96" cy="310" r="14" fill="#050507" stroke="#3a3a48" strokeWidth="2" /><circle cx="96" cy="310" r="6" fill="#20202b" />
      <circle cx="208" cy="310" r="14" fill="#050507" stroke="#3a3a48" strokeWidth="2" /><circle cx="208" cy="310" r="6" fill="#20202b" />
      <rect x="240" y="294" width="10" height="4" rx="2" fill="#fff" opacity=".9" />
    </>;
    case 'arcade': return <>
      <defs><linearGradient id={`${g}s`} x1="0" y1="0" x2="0" y2="1"><stop offset="0" stopColor="#0a0620" /><stop offset=".6" stopColor="#25105a" /><stop offset="1" stopColor="#4a1a8a" /></linearGradient></defs>
      <rect width="300" height="340" fill={`url(#${g}s)`} />
      {MORE_STARS.slice(0, 12).map(([x, y, r]) => <circle key={`${x}${y}`} cx={x} cy={y} r={r} fill="#fff" opacity=".6" />)}
      {[[24, '#ff4f9a'], [244, '#b6ff3b']].map(([x, color]) => <g key={String(x)} fill={String(color)}>{INVADER.flatMap((row, r) => [...row].map((cell, c) => cell === '1' ? <rect key={`${r}-${c}`} x={Number(x) + c * 2.6} y={300 + r * 2.6} width="2.4" height="2.4" /> : null))}</g>)}
      <polygon points="150,250 20,340 280,340" fill="#170a3a" />
      {[-120, -80, -40, 0, 40, 80, 120].map(dx => <line key={dx} x1="150" y1="250" x2={150 + dx * 2.2} y2="340" stroke="#3bf0ff" strokeOpacity=".5" strokeWidth=".9" />)}
      {[262, 276, 296, 322].map(y => <line key={y} x1="0" y1={y} x2="300" y2={y} stroke="#3bf0ff" strokeOpacity=".4" strokeWidth=".9" />)}
      <g fill="#b6ff3b"><rect x="141" y="300" width="18" height="8" /><rect x="135" y="308" width="30" height="8" /><rect x="147" y="292" width="6" height="8" /></g>
    </>;
    case 'space': return <>
      <defs>
        <linearGradient id={`${g}s`} x1="0" y1="0" x2="0" y2="1"><stop offset="0" stopColor="#04051a" /><stop offset="1" stopColor="#1b0d47" /></linearGradient>
        <radialGradient id={`${g}p`} cx=".35" cy=".3" r="1"><stop offset="0" stopColor="#ffc38a" /><stop offset=".5" stopColor="#e2557a" /><stop offset="1" stopColor="#4b1a6b" /></radialGradient>
        <clipPath id={`${g}c`}><circle cx="208" cy="350" r="118" /></clipPath>
      </defs>
      <rect width="300" height="340" fill={`url(#${g}s)`} />
      {MORE_STARS.map(([x, y, r]) => <circle key={`${x}${y}`} cx={x} cy={y} r={r} fill="#fff" opacity=".85" />)}
      <circle cx="130" cy="38" r="13" fill="#d8d3ec" /><circle cx="125" cy="34" r="3.6" fill="#b3add0" /><circle cx="136" cy="43" r="2.6" fill="#b3add0" />
      <line x1="250" y1="24" x2="196" y2="46" stroke="#fff" strokeWidth="1.4" strokeLinecap="round" opacity=".7" />
      <circle cx="208" cy="350" r="118" fill={`url(#${g}p)`} />
      <g clipPath={`url(#${g}c)`} opacity=".35">{[262, 282, 302, 322].map((y, i) => <rect key={y} x="80" y={y} width="260" height={6 + i * 2} fill="#4b1a6b" />)}</g>
      <ellipse cx="208" cy="350" rx="172" ry="34" fill="none" stroke="#f4d3ff" strokeWidth="5" opacity=".6" transform="rotate(-14 208 350)" />
    </>;
    case 'palms': return <>
      <defs>
        <linearGradient id={`${g}s`} x1="0" y1="0" x2="0" y2="1"><stop offset="0" stopColor="#2b1055" /><stop offset=".45" stopColor="#d8467a" /><stop offset=".78" stopColor="#ff9a5c" /><stop offset="1" stopColor="#ffd27a" /></linearGradient>
        <clipPath id={`${g}c`}><circle cx="130" cy="42" r="15" /></clipPath>
      </defs>
      <rect width="300" height="340" fill={`url(#${g}s)`} />
      <circle cx="130" cy="42" r="15" fill="#fff0b8" />
      <g clipPath={`url(#${g}c)`}>{[40, 46, 51].map((y, i) => <rect key={y} x="112" y={y} width="36" height={1.4 + i * .8} fill="#d8467a" />)}</g>
      <rect y="290" width="300" height="50" fill="#1d0b3a" />
      {[[300, 90, 210], [312, 110, 190], [326, 70, 230]].map(([y, x1, x2]) => <line key={y} x1={x1} y1={y} x2={x2} y2={y} stroke="#ffb37b" strokeOpacity=".55" strokeWidth="1.6" strokeLinecap="round" />)}
      {[[34, 1, 232], [268, -1, 224]].map(([x, dir, top]) => <g key={x} fill="none" stroke="#120624" strokeLinecap="round">
        <path d={`M${x} 340 Q${x + dir * 10} 290 ${x + dir * 6} ${top}`} strokeWidth="6" />
        {[[-44, 8], [-30, -20], [0, -30], [30, -20], [44, 8]].map(([ex, ey]) => <path key={ex} d={`M${x + dir * 6} ${top} Q${x + dir * 6 + ex / 2} ${top + Math.min(ey, 0) - 14} ${x + dir * 6 + ex} ${top + ey}`} strokeWidth="4.5" />)}
      </g>)}
    </>;
    case 'skyline': return <>
      <defs>
        <linearGradient id={`${g}s`} x1="0" y1="0" x2="0" y2="1"><stop offset="0" stopColor="#070b1c" /><stop offset=".7" stopColor="#1a2c52" /><stop offset="1" stopColor="#ff8a3d" /></linearGradient>
        <radialGradient id={`${g}h`}><stop offset="0" stopColor="#e9fbff" /><stop offset=".4" stopColor="#7fe6ff" stopOpacity=".7" /><stop offset="1" stopColor="#7fe6ff" stopOpacity="0" /></radialGradient>
      </defs>
      <rect width="300" height="340" fill={`url(#${g}s)`} />
      {CITY_BACK.map(([x, w, h]) => <rect key={x} x={x} y={296 - h} width={w} height={h} fill="#0d1530" opacity=".85" />)}
      {RAIN.map(([x, y], i) => <line key={i} x1={x} y1={y} x2={x - 6} y2={y + 22} stroke="#bfe9ff" strokeOpacity=".4" strokeWidth="1" />)}
      <rect y="296" width="300" height="44" fill="#0a0d18" />
      <ellipse cx="150" cy="322" rx="110" ry="9" fill="#7fe6ff" opacity=".18" />
      <circle cx="98" cy="312" r="30" fill={`url(#${g}h)`} /><circle cx="202" cy="312" r="30" fill={`url(#${g}h)`} />
      <path d="M62 340 L66 310 Q72 296 96 292 L204 292 Q228 296 234 310 L238 340 Z" fill="#0b0e18" stroke="#2c3550" strokeWidth="1.2" />
      <path d="M92 292 Q104 272 132 268 L168 268 Q196 272 208 292 Z" fill="#141a2c" />
      <circle cx="98" cy="312" r="11" fill="#f2fdff" /><circle cx="202" cy="312" r="11" fill="#f2fdff" />
      <rect x="130" y="318" width="40" height="12" rx="3" fill="#05070d" /><rect x="140" y="322" width="20" height="6" rx="1.5" fill="#dfe6f2" />
    </>;
    case 'qbcore': return <>
      <defs><radialGradient id={`${g}r`} cx=".85" cy="0" r="1.1"><stop offset="0" stopColor="#8f3220" stopOpacity=".75" /><stop offset="1" stopColor="#8f3220" stopOpacity="0" /></radialGradient></defs>
      <rect width="300" height="340" fill="#17140f" />
      <rect width="300" height="340" fill={`url(#${g}r)`} />
      <path d={QB_MARK_PATH} transform="translate(112 118) scale(.26) translate(-0.53 -0.56)" fill="#d86b59" opacity=".1" />
      <path d={QB_MARK_PATH} transform="translate(105 18) scale(.088) translate(-0.53 -0.56)" fill="#d86b59" opacity=".9" />
    </>;
  }
}

/** A case scene at any size (used for the folded back panel and the settings thumbnails). */
export function CoverScene({ id }: { id: Scene }) {
  return <svg viewBox="0 0 300 340" preserveAspectRatio="xMidYMid slice" aria-hidden="true" focusable="false"><Scene id={id} /></svg>;
}

// Own <img> (not PhotoImage): PhotoImage falls back to a person icon, which would fill the whole panel.
// A link that is not a valid https URL, or that fails to load, simply shows nothing.
function CoverPhoto({ src }: { src: string }) {
  const [failed, setFailed] = useState('');
  return imageUrl(src) && src !== failed ? <img src={src} alt="" referrerPolicy="no-referrer" onError={() => setFailed(src)} /> : null;
}

/** The layer behind the folded cover's controls: a scene or the user's photo. */
export function CoverBackdrop({ settings }: { settings: Pick<Settings, 'phoneCase' | 'phoneCaseUrl'> }) {
  const id = settings.phoneCase ?? 'default';
  if (id === 'default') return null;
  if (id === 'custom') return settings.phoneCaseUrl ? <div className="cover-art" data-scene="custom"><CoverPhoto src={settings.phoneCaseUrl} /></div> : null;
  return <div className="cover-art" data-scene={id}><CoverScene id={id} /></div>;
}
