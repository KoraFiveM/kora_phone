import type { MailAcceptResult, MailItem, SystemActivity } from '../../types';
import type { RawActivity, RawMail, RawMailAccept } from '../raw';
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

export const mapSystemMail = (x: RawMail): MailItem => ({
    id: x.id,
    peer: String(x.peer),
    subject: x.subject,
    body: x.body,
    hasAction: isFlag(x.hasAction),
    created_at: stamp(x.createdAt),
    unread: isFlag(x.unread),
});

export const mapActivity = (x: RawActivity): SystemActivity => ({
    ...(x as unknown as SystemActivity),
    created_at: stamp(x.createdAt),
});

export const mapMailAccept = (x: RawMailAccept | undefined): MailAcceptResult => ({
    accepted: isFlag(x?.accepted),
    dispatched: isFlag(x?.dispatched),
});
