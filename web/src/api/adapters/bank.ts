import type { Bank } from '../../types';
import type { RawBalance, RawTransaction } from '../raw';
import { stamp } from './common';

export function mapBank(balance: RawBalance, transactions: RawTransaction[]): Bank {
    const account = String(balance.number || balance.account);
    return {
        balance: balance.balance,
        account,
        name: balance.holder || 'Personal',
        history: transactions.map(x => {
            const incoming = x.direction === 'incoming';
            const peer = String(x.peer || 'Phone transfer');
            return {
                id: String(x.id),
                citizenid: incoming ? peer : account,
                recipient: incoming ? account : peer,
                amount: Number(x.amount),
                status: x.status,
                created_at: stamp(x.createdAt),
            };
        }),
    };
}
