import type { Call } from '../../types';
import type { RawCall } from '../raw';

export const mapCall = (v: RawCall): Call => ({
    id: String(v.id),
    status: (v.status === 'rejected' ? 'declined' : v.status) as Call['status'],
    number: String(v.remoteNumber || ''),
    direction: v.direction || 'outgoing',
    deviceId: 'kora_phone',
});

