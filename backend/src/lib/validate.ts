import type { Request, Response, NextFunction, RequestHandler } from 'express';
import { ZodError, type ZodType } from 'zod';

/**
 * Express middleware that parses and validates `req.body` against a Zod schema,
 * replacing it with the parsed (typed) value on success. Throws ZodError on
 * failure — the error middleware turns that into a 400 response.
 *
 *   router.post('/register', validateBody(registerSchema), handler);
 */
export function validateBody<T>(schema: ZodType<T>): RequestHandler {
  return (req: Request, _res: Response, next: NextFunction) => {
    const parsed = schema.parse(req.body);
    req.body = parsed;
    next();
  };
}

export function validateQuery<T>(schema: ZodType<T>): RequestHandler {
  return (req: Request, _res: Response, next: NextFunction) => {
    const parsed = schema.parse(req.query);
    (req as unknown as { validatedQuery: T }).validatedQuery = parsed;
    next();
  };
}

export { ZodError };
