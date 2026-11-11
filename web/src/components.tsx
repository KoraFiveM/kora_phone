import type { ReactNode } from 'react';
import { ArrowLeft, ArrowUpRight, Plus } from 'lucide-react';
const glyphs: Record<string, string[]> = {
  '0': ['01110', '11011', '11011', '11011', '11011', '11011', '01110'],
  '1': ['00110', '01110', '00110', '00110', '00110', '00110', '01111'],
  '2': ['01110', '11011', '00011', '00110', '01100', '11000', '11111'],
  '3': ['11110', '00011', '00011', '01110', '00011', '00011', '11110'],
  '4': ['00011', '00111', '01111', '11011', '11111', '00011', '00011'],
  '5': ['11111', '11000', '11000', '11110', '00011', '11011', '01110'],
  '6': ['01110', '11000', '11000', '11110', '11011', '11011', '01110'],
  '7': ['11111', '00011', '00110', '00110', '01100', '01100', '01100'],
  '8': ['01110', '11011', '11011', '01110', '11011', '11011', '01110'],
  '9': ['01110', '11011', '11011', '01111', '00011', '00011', '01110'],
  ':': ['00000', '00100', '00100', '00000', '00100', '00100', '00000'],
};
export function DotClock({ value }: { value: string }) {
  return <svg className="dot-clock" viewBox={`0 0 ${value.length * 36 - 6} 42`} role="img" aria-label={value}>
    {[...value].flatMap((letter, index) => (glyphs[letter] || glyphs['0']).flatMap((row, y) => [...row].map((pixel, x) => pixel === '1' ? <circle key={`${index}-${y}-${x}`} cx={index * 36 + x * 6 + 3} cy={y * 6 + 3} r="2.1" fill="currentColor" /> : null)))}
  </svg>;
}
export function PageHeader({ title, subtitle, back, action }: { title: string; subtitle?: string; back?: () => void; action?: ReactNode }) {
  return <header className="page-header"><div className="page-top"><button className="icon-button" aria-label="Back" onClick={back}><ArrowLeft size={20} /></button><span className="eyebrow">THREE / OS</span>{action || <span className="header-spacer" />}</div><h1>{title}</h1>{subtitle && <p>{subtitle}</p>}</header>;
}
export function Empty({ title, detail }: { title: string; detail: string }) { return <div className="empty"><span className="empty-mark">( — )</span><h3>{title}</h3><p>{detail}</p></div>; }
export function AddButton({ onClick, label = 'Add' }: { onClick: () => void; label?: string }) { return <button className="icon-button" aria-label={label} onClick={onClick}><Plus size={21} /></button>; }
export function Row({ title, detail, icon, onClick, end }: { title: string; detail?: string; icon?: ReactNode; onClick?: () => void; end?: ReactNode }) {
  const content = <>{icon && <span className="row-icon">{icon}</span>}<span className="row-copy"><strong>{title}</strong>{detail && <small>{detail}</small>}</span>{end || (onClick && <ArrowUpRight size={17} />)}</>;
  return onClick ? <button className="row" onClick={onClick}>{content}</button> : <div className="row">{content}</div>;
}
export const money = (value: number) => new Intl.NumberFormat('en-US', { style: 'currency', currency: 'USD', maximumFractionDigits: 0 }).format(value);
export const dateLabel = (value: string) => { const date = new Date(value); return Number.isNaN(date.getTime()) ? value : date.toLocaleDateString('en-GB', { month: 'short', day: 'numeric' }); };
export function calculate(expression: string): string {
  // A small arithmetic parser, never eval or Function on user input.
  const tokens = expression.match(/(?:\d+(?:\.\d*)?|\.\d+)|[+\-×÷*/]/g);
  if (!tokens || tokens.join('') !== expression.replace(/\s/g, '')) throw new Error('Enter a valid calculation');
  let i = 0;
  const number = (): number => { let sign = 1; if (tokens[i] === '-') { sign = -1; i++; } else if (tokens[i] === '+') i++; const token = tokens[i++]; if (!token || !/^(\d|\.)/.test(token)) throw new Error('Incomplete calculation'); return sign * Number(token); };
  const term = (): number => { let value = number(); while (['*', '/', '×', '÷'].includes(tokens[i])) { const op = tokens[i++]; const right = number(); value = op === '*' || op === '×' ? value * right : value / right; } return value; };
  let value = term();
  while (i < tokens.length) { const op = tokens[i++]; if (op !== '+' && op !== '-') throw new Error('Invalid operator'); const right = term(); value = op === '+' ? value + right : value - right; }
  if (!Number.isFinite(value)) throw new Error('Cannot divide by zero');
  return String(Number(value.toPrecision(12)));
}
