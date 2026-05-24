import { z } from 'zod';

/**
 * Query schema for `GET /gas-stations?lat=&lng=&radiusKm=`. The Flutter
 * geofence registrar hits this on app launch with the device's current
 * coordinates, then takes the result and feeds it into `geofence_service`
 * to register CLCircularRegions (iOS caps at 20 — see spec §8).
 *
 * Values come in as URL query strings, so every field is `z.coerce.number()`.
 * We cap `radiusKm` at 50 because anything wider than that returns stations
 * the user could never plausibly drive past in a single trip.
 */
/**
 * `limit` ceiling is 20 because the iOS CLCircularRegion API itself caps at
 * 20 active regions per app — beyond that the OS silently drops registrations.
 * The mobile geofence wrapper usually passes 10. Default mirrors the same
 * ceiling so an absent `limit` doesn't accidentally return all rows.
 */
export const nearbyQuerySchema = z
  .object({
    lat: z.coerce.number().min(-90).max(90),
    lng: z.coerce.number().min(-180).max(180),
    radiusKm: z.coerce.number().positive().max(50).default(10),
    limit: z.coerce.number().int().positive().max(20).default(20),
  })
  .strict();

export type NearbyQueryInput = z.infer<typeof nearbyQuerySchema>;
