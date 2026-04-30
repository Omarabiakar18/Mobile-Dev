import type { Response } from 'express';

/** Wraps a payload in `{ data: ... }` for the uniform response shape. */
export function ok<T>(res: Response, data: T, status = 200) {
  res.status(status).json({ data });
}
