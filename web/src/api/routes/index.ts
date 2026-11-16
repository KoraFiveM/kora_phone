import type { Handlers } from '../routeTypes';
import { communityRoutes } from './community';
import { deviceRoutes } from './device';
import { messagingRoutes } from './messaging';
import { serviceRoutes } from './services';

/** Action name -> handler. `Handlers` makes TypeScript fail the build if any action is missing. */
export const handlers: Handlers = { ...deviceRoutes, ...messagingRoutes, ...communityRoutes, ...serviceRoutes };
