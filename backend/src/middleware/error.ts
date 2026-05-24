import type { ErrorRequestHandler, Request, Response, NextFunction } from 'express';
import multer from 'multer';
import { ZodError } from 'zod';
import { HttpError } from '../lib/errors';
import { logger } from '../lib/logger';

export const errorHandler: ErrorRequestHandler = (
  err: unknown,
  _req: Request,
  res: Response,
  // eslint-disable-next-line @typescript-eslint/no-unused-vars
  _next: NextFunction,
) => {
  if (err instanceof ZodError) {
    res.status(400).json({
      error: {
        code: 'VALIDATION_ERROR',
        message: 'Invalid input',
        details: err.flatten(),
      },
    });
    return;
  }

  // Multer errors: surface a clean 4xx with the right code so the client can
  // show the user a friendly message ("file too large") instead of a 500.
  if (err instanceof multer.MulterError) {
    const map: Record<string, { status: number; code: string; message: string }> = {
      LIMIT_FILE_SIZE: {
        status: 413,
        code: 'FILE_TOO_LARGE',
        message: 'File is too large for this endpoint.',
      },
      LIMIT_UNEXPECTED_FILE: {
        status: 400,
        code: 'UNEXPECTED_FILE_FIELD',
        message: `Unexpected file field "${err.field ?? 'unknown'}".`,
      },
      LIMIT_FILE_COUNT: {
        status: 400,
        code: 'TOO_MANY_FILES',
        message: 'Too many files in this upload.',
      },
    };
    const m = map[err.code] ?? {
      status: 400,
      code: err.code,
      message: err.message,
    };
    res.status(m.status).json({
      error: { code: m.code, message: m.message, ...(err.field ? { details: { field: err.field } } : {}) },
    });
    return;
  }

  if (err instanceof HttpError) {
    res.status(err.status).json({
      error: {
        code: err.code,
        message: err.message,
        ...(err.details !== undefined ? { details: err.details } : {}),
      },
    });
    return;
  }

  logger.error({ err }, 'Unhandled error');
  res.status(500).json({
    error: {
      code: 'INTERNAL_ERROR',
      message: 'Something went wrong',
    },
  });
};

export const notFoundHandler = (_req: Request, res: Response) => {
  res.status(404).json({
    error: {
      code: 'NOT_FOUND',
      message: 'Route not found',
    },
  });
};
