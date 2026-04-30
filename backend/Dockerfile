# syntax=docker/dockerfile:1
FROM node:20-alpine AS base
WORKDIR /app

# Install deps
COPY package*.json ./
COPY prisma ./prisma
RUN npm ci
RUN npx prisma generate

# Copy source
COPY tsconfig.json ./
COPY src ./src

# Build
RUN npm run build

# --- runtime ---
FROM node:20-alpine
WORKDIR /app
ENV NODE_ENV=production

COPY --from=base /app/node_modules ./node_modules
COPY --from=base /app/dist ./dist
COPY --from=base /app/prisma ./prisma
COPY --from=base /app/package.json ./package.json

# uploads dir mounted as a volume in compose; ensure it exists
RUN mkdir -p /app/uploads

EXPOSE 3000
CMD ["node", "dist/index.js"]
