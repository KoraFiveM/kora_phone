// A small arithmetic parser. Never eval or Function on user input.
export function calculate(expression) {
    const tokens = expression.match(/(?:\d+(?:\.\d*)?|\.\d+)|[+\-×÷*/]/g);
    if (!tokens || tokens.join('') !== expression.replace(/\s/g, '')) throw new Error('Enter a valid calculation');
    let i = 0;
    const number = () => {
        let sign = 1;
        if (tokens[i] === '-') { sign = -1; i++; } else if (tokens[i] === '+') i++;
        const token = tokens[i++];
        if (!token || !/^(\d|\.)/.test(token)) throw new Error('Incomplete calculation');
        return sign * Number(token);
    };
    const term = () => {
        let value = number();
        while (['*', '/', '×', '÷'].includes(tokens[i])) {
            const op = tokens[i++];
            const right = number();
            value = op === '*' || op === '×' ? value * right : value / right;
        }
        return value;
    };
    let value = term();
    while (i < tokens.length) {
        const op = tokens[i++];
        if (op !== '+' && op !== '-') throw new Error('Invalid operator');
        const right = term();
        value = op === '+' ? value + right : value - right;
    }
    if (!Number.isFinite(value)) throw new Error('Cannot divide by zero');
    return String(Number(value.toPrecision(12)));
}
