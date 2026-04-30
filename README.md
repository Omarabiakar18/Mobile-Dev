# Garage — Smart Car Companion App

University final project · Mobile Development · Antonine University.
Flutter (iOS) + Node.js/TypeScript backend.

See [GARAGE_PROJECT_SPEC.md](./GARAGE_PROJECT_SPEC.md) for the locked design.

---

## Quick start

### Prerequisites
- Node.js 20+ (LTS)
- Docker + docker-compose
- Flutter (3.x) with iOS toolchain (Xcode)
- A free Apple Developer account (for sideloading to your iPhone via Xcode)

### 1. Backend

```bash
cd backend
cp .env.example .env
npm install
npx prisma migrate dev --name init
npm run db:seed
npm run dev
```

Server listens on `http://localhost:3000`. Health check: `http://localhost:3000/health`.

### 2. Database (alternative — full docker-compose)

From the project root:

```bash
docker-compose up -d postgres minio
# then in backend/:
npx prisma migrate dev
npm run db:seed
npm run dev
```

### 3. Mobile app

```bash
cd mobile
flutter pub get
open ios/Runner.xcworkspace        # one-time: configure signing in Xcode
flutter run                         # runs on connected iPhone / simulator
```

The Flutter app expects the backend at `http://localhost:3000` by default. For running on a real iPhone over USB, point it at your Mac's LAN IP (configurable in `mobile/lib/core/api/base_url.dart`).

---

## Project layout

```
.
├── GARAGE_PROJECT_SPEC.md   ← single source of truth for the design
├── docker-compose.yml       ← Postgres + MinIO + backend
├── backend/                 ← Express + TypeScript + Prisma
└── mobile/                  ← Flutter (iOS first)
```

---

## Demo mode

Set `DEMO_MODE=true` in `backend/.env` to make the OCR endpoint return hardcoded fields instead of calling Google Cloud Vision. **Always run the live demo with this on** — it removes any dependency on a working internet connection or the Vision API being up.

---

## Development phases

Tracking the phased plan from [GARAGE_PROJECT_SPEC.md §11](./GARAGE_PROJECT_SPEC.md#11-phasing--14-weeks-155-hours-total):

- [ ] **Phase 1** — Foundation (auth, scaffolds, cars CRUD)
- [ ] **Phase 2** — Core CRUD (fuel, maintenance, documents)
- [ ] **Phase 3** — Smart math (predictive fill-up, service reminder dates)
- [ ] **Phase 4** — Receipt OCR
- [ ] **Phase 5** — Notifications + geofencing
- [ ] **Phase 6** — Polish + demo prep
