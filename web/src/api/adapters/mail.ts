import type { MailItem } from '../../types';
import type { RawMail } from '../raw';
import { isFlag } from '../raw';
import { stamp } from './common';

export const mapMail = (x: RawMail): MailItem => ({
    id: x.id,
    peer: String(x.peer),
    subject: x.subject,
    body: x.body,
    created_at: stamp(x.createdAt),
    unread: isFlag(x.unread),
});
