import type { Contact, Photo } from '../../types';
import type { RawContact, RawMedia } from '../raw';
import { isFlag } from '../raw';
import { kindOf } from './common';

export const mapPhoto = (x: RawMedia): Photo => ({
    id: String(x.id),
    url: String(x.publicUrl),
    created_at: Number(x.createdAt || 0),
    kind: kindOf(x.mimeType, x.publicUrl),
});

export const mapContact = (c: RawContact): Contact => ({
    id: Number(c.id),
    name: String(c.displayName || ''),
    number: String(c.phoneNumber || ''),
    photo: c.photo,
    favorite: isFlag(c.isFavorite),
});
