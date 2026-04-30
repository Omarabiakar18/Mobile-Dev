import type { Request, Response, NextFunction, RequestHandler } from 'express';

/**
 * Wraps an async route handler so thrown/rejected errors are forwarded to
 * Express's error middleware via next(err) instead of crashing the process.
 */
export const asyncHandler =
  <TReq extends Request = Request>(
    fn: (req: TReq, res: Response, next: NextFunction) => Promise<unknown>,
  ): RequestHandler =>
  (req, res, next) => {
    Promise.resolve(fn(req as TReq, res, next)).catch(next);
  };
