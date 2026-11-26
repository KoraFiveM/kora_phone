import type { Weather } from '../../types';
import type { HandlerSet, Routes } from '../routeTypes';
import { server } from '../transport';

export const serviceRoutes: HandlerSet<'weather' | 'waypoint' | 'myLocation'> = {
    weather: () => server<Weather>('weather:get'),
    waypoint: async p => { await server('waypoint', { x: p.x, y: p.y }); return true; },
    myLocation: () => server<Routes['myLocation']['out']>('location:mine'),
};
