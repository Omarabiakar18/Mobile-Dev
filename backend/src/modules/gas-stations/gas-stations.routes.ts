import { Router } from 'express';

import { asyncHandler } from '../../lib/asyncHandler';
import { ok } from '../../lib/respond';
import { validateQuery } from '../../lib/validate';
import { requireAuth } from '../../middleware/auth';

import * as gasStationsService from './gas-stations.service';
import { nearbyQuerySchema, type NearbyQueryInput } from './gas-stations.schemas';

export const gasStationsRouter = Router();

gasStationsRouter.use(requireAuth);

/**
 * `GET /gas-stations?lat=&lng=&radiusKm=` — nearest stations to the device,
 * sorted by distance, capped server-side at 20 (well under iOS's CLCircular
 * region cap). The Flutter geofence registrar uses this on app launch.
 *
 * Echoes back the `origin` and `radiusKm` so the client can render the
 * "nearby stations within 10 km of you" header without re-deriving anything.
 */
gasStationsRouter.get(
  '/',
  validateQuery(nearbyQuerySchema),
  asyncHandler(async (req, res) => {
    const { lat, lng, radiusKm } = (
      req as unknown as { validatedQuery: NearbyQueryInput }
    ).validatedQuery;

    const stations = await gasStationsService.findNearby(lat, lng, radiusKm);
    ok(res, {
      stations,
      origin: { lat, lng },
      radiusKm,
    });
  }),
);
