import type { JobData, MapBlip, Property, Vehicle, Weather, WalletCard } from '../../types';
import { items } from '../adapters/common';
import { mapBank } from '../adapters/bank';
import type { RawBalance, RawTransaction } from '../raw';
import type { HandlerSet, Routes } from '../routeTypes';
import { server } from '../transport';

export const serviceRoutes: HandlerSet<
    'bank' | 'transfer' | 'job' | 'setDuty' | 'jobAction' | 'property' | 'services' | 'vehicles' | 'weather'
    | 'waypoint' | 'wallet' | 'showWallet' | 'myLocation' | 'mapBlips'
> = {
    bank: async () => {
        const [balance, history] = await Promise.all([
            server<RawBalance>('bank:getData'),
            server<{ items?: RawTransaction[] }>('bank:getTransactions', { limit: 50 }),
        ]);
        return mapBank(balance, items(history));
    },
    transfer: async (p, { id }) => {
        const result = await server<{ transaction?: { status?: string } }>('bank:transfer', { to: p.recipient, amount: p.amount, clientRequestId: id });
        return { status: result.transaction?.status || 'completed' };
    },
    job: () => server<JobData>('jobs:getData'),
    setDuty: p => server<JobData>('jobs:setDuty', { onDuty: p.onDuty }),
    jobAction: p => server<{ completed: boolean }>('jobs:runAction', { action: p.action }),
    property: () => server<Property[]>('property:list'),
    services: async () => [],
    vehicles: () => server<Vehicle[]>('garage:list'),
    weather: () => server<Weather>('weather:get'),
    waypoint: async p => { await server('waypoint', { x: p.x, y: p.y }); return true; },
    wallet: () => server<WalletCard>('wallet:get'),
    showWallet: () => server<{ shown: boolean }>('wallet:show'),
    myLocation: () => server<Routes['myLocation']['out']>('location:mine'),
    mapBlips: () => server<MapBlip[]>('map:blips'),
};
