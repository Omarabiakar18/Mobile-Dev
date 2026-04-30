import express from 'express';
import cors from 'cors';
import pinoHttp from 'pino-http';
import rateLimit from 'express-rate-limit';

import { env } from './config/env';
import { logger } from './lib/logger';
import { prisma } from './lib/prisma';
import { errorHandler, notFoundHandler } from './middleware/error';

import { authRouter } from './modules/auth/auth.routes';
import { usersRouter } from './modules/users/users.routes';
import { carsRouter } from './modules/cars/cars.routes';

async function main() {
  const app = express();

  app.use(cors());
  app.use(express.json({ limit: '2mb' }));
  app.use(express.urlencoded({ extended: true }));
  app.use(pinoHttp({ logger }));

  // Health check
  app.get('/health', (_req, res) => {
    res.json({ data: { status: 'ok', uptime: process.uptime() } });
  });

  // Rate-limit auth endpoints (login bruteforce / register spam)
  const authLimiter = rateLimit({
    windowMs: 60 * 1000,
    limit: 10,
    standardHeaders: 'draft-7',
    legacyHeaders: false,
    skip: (req) => req.path === '/me' || req.path === '/refresh',
  });

  app.use('/auth', authLimiter, authRouter);
  app.use('/users', usersRouter);
  app.use('/cars', carsRouter);

  // TODO(phase 2): mount fuel, maintenance, documents, reminders routes
  // TODO(phase 4): mount ocr routes
  // TODO(phase 5): mount gas-stations routes

  // 404 + error handlers (must come last)
  app.use(notFoundHandler);
  app.use(errorHandler);

  const server = app.listen(env.PORT, () => {
    logger.info(`Garage backend listening on http://localhost:${env.PORT}`);
  });

  // Graceful shutdown
  const shutdown = async (signal: string) => {
    logger.info(`Received ${signal}, shutting down...`);
    server.close(() => logger.info('HTTP server closed'));
    await prisma.$disconnect();
    process.exit(0);
  };
  process.on('SIGINT', () => shutdown('SIGINT'));
  process.on('SIGTERM', () => shutdown('SIGTERM'));
}

main().catch((err) => {
  logger.error({ err }, 'Fatal startup error');
  process.exit(1);
});
