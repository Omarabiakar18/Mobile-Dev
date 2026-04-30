import path from 'node:path';
import express from 'express';
import cors from 'cors';
import pinoHttp from 'pino-http';

import { env } from './config/env';
import { logger } from './lib/logger';
import { prisma } from './lib/prisma';
import { errorHandler, notFoundHandler } from './middleware/error';

import { authRouter } from './modules/auth/auth.routes';
import { usersRouter } from './modules/users/users.routes';
import { carsRouter } from './modules/cars/cars.routes';
import { carScopedFuelRouter, fuelByIdRouter } from './modules/fuel/fuel.routes';
import {
  carScopedMaintenanceRouter,
  maintenanceByIdRouter,
} from './modules/maintenance/maintenance.routes';
import { carScopedDocsRouter, docsByIdRouter } from './modules/documents/documents.routes';
import {
  carScopedRemindersRouter,
  remindersByIdRouter,
} from './modules/reminders/reminders.routes';
import { startAvgKmPerDayCron } from './jobs/avg-km-per-day.cron';

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

  // Auth routes carry their own per-route rate limiters (see auth.routes.ts).
  app.use('/auth', authRouter);
  app.use('/users', usersRouter);
  app.use('/cars', carsRouter);

  // Phase 2: car-scoped sub-resources. Order matters — these must come AFTER
  // `/cars` so the cars router doesn't intercept e.g. `/cars/:id/fuel`.
  app.use('/cars/:carId', carScopedFuelRouter);
  app.use('/cars/:carId/maintenance', carScopedMaintenanceRouter);
  app.use('/cars/:carId/documents', carScopedDocsRouter);
  app.use('/cars/:carId/reminders', carScopedRemindersRouter);

  // Phase 2: by-id routes
  app.use('/fuel', fuelByIdRouter);
  app.use('/maintenance', maintenanceByIdRouter);
  app.use('/documents', docsByIdRouter);
  app.use('/reminders', remindersByIdRouter);

  // Static file serving for uploads (maintenance photos, document files).
  app.use(
    '/uploads',
    express.static(path.resolve(env.UPLOADS_DIR), { fallthrough: false, maxAge: '7d' }),
  );

  // TODO(phase 4): mount ocr routes
  // TODO(phase 5): mount gas-stations routes

  // 404 + error handlers (must come last)
  app.use(notFoundHandler);
  app.use(errorHandler);

  const server = app.listen(env.PORT, () => {
    logger.info(`Garage backend listening on http://localhost:${env.PORT}`);
  });

  // Phase 3: nightly recompute of stale avgKmPerDay values (spec §6.2).
  const avgKmCron = startAvgKmPerDayCron();

  // Graceful shutdown
  const shutdown = async (signal: string) => {
    logger.info(`Received ${signal}, shutting down...`);
    avgKmCron.stop();
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
