import { useState } from 'react';
import { calculate } from '../../components';

export function CalculatorScreen() {
  const [expression, setExpression] = useState(''); const [error, setError] = useState('');
  const press = (key: string) => { setError(''); if (key === 'AC') setExpression(''); else if (key === '⌫') setExpression(v => v.slice(0, -1)); else if (key === '=') { try { setExpression(calculate(expression)); } catch (e) { setError((e as Error).message); } } else setExpression(v => (v + key).slice(0, 60)); };
  return <div className="calculator"><div className="calc-display"><small>{error || 'A LITTLE CLARITY'}</small><output aria-live="polite">{expression || '0'}</output></div><div className="calc-keys">{['AC', '⌫', '÷', '×', '7', '8', '9', '-', '4', '5', '6', '+', '1', '2', '3', '=', '0', '.'].map(key => <button key={key} className={`${key === '=' ? 'equals' : ''} ${key === '0' ? 'zero' : ''}`} onClick={() => press(key)}>{key}</button>)}</div></div>;
}
