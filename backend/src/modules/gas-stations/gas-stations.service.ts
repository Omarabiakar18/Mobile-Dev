import type { GasStation } from '@prisma/client';

import { prisma } from '../../lib/prisma';

/** Mean Earth radius in kilometers (WGS-84 spherical approximation). */
const EARTH_RADIUS_KM = 6371;

/**
 * Default cap on results returned from `findNearby`. iOS caps geofences at
 * 20 regions per app, so 20 is plenty — the Flutter side will never need
 * more, and clamping here keeps payloads small.
 */
const DEFAULT_NEARBY_LIMIT = 20;

function toRadians(deg: number): number {
  return (deg * Math.PI) / 180;
}

/**
 * Great-circle distance between two `(lat, lng)` points in kilometers.
 *
 * Spherical-Earth approximation (sufficient at city-scale; the error vs.
 * the WGS-84 ellipsoid is well under 0.5% over the distances we care about).
 * Exported so the verification script can hit it directly without a DB.
 */
export function haversineKm(
  latA: number,
  lngA: number,
  latB: number,
  lngB: number,
): number {
  const dLat = toRadians(latB - latA);
  const dLng = toRadians(lngB - lngA);
  const a =
    Math.sin(dLat / 2) ** 2 +
    Math.cos(toRadians(latA)) *
      Math.cos(toRadians(latB)) *
      Math.sin(dLng / 2) ** 2;
  const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
  return EARTH_RADIUS_KM * c;
}

/** Annotated GasStation row with the computed distance from the query origin. */
export type GasStationWithDistance = GasStation & { distanceKm: number };

/**
 * Returns the gas stations within `radiusKm` of `(lat, lng)`, sorted by
 * distance ascending. We pull every row (the seed table is ~10–100 rows for
 * the lifetime of the app — Postgres geo extensions would be overkill) and
 * filter in memory.
 *
 * The result is capped at `limit` (default 20) — see `DEFAULT_NEARBY_LIMIT`.
 */
export async function findNearby(
  lat: number,
  lng: number,
  radiusKm: number,
  limit: number = DEFAULT_NEARBY_LIMIT,
): Promise<GasStationWithDistance[]> {
  const all = await prisma.gasStation.findMany();

  const annotated: GasStationWithDistance[] = all
    .map((s) => ({
      ...s,
      distanceKm: haversineKm(lat, lng, s.latitude, s.longitude),
    }))
    .filter((s) => s.distanceKm <= radiusKm)
    .sort((a, b) => a.distanceKm - b.distanceKm);

  return annotated.slice(0, limit);
}

/** Useful for an admin/debug screen — not currently exposed via HTTP. */
export function listAll() {
  return prisma.gasStation.findMany({ orderBy: { name: 'asc' } });
}
