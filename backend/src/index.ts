import express from 'express';
import cors from 'cors';
import pinoHttp from 'pino-http';

import { env } from './config/env';
import { logger } from './lib/logger';
import { prisma } from './lib/prisma';
import { errorHandler, notFoundHandler } from './middleware/error';

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

  // TODO(phase 1): mount auth routes
  // TODO(phase 1): mount users routes
  // TODO(phase 1): mount cars routes
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
