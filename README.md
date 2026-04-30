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

### 1. Database (Postgres in Docker)

From the project root:

```bash
# Start Docker Desktop first if it isn't running
docker-compose up -d postgres minio
```

This brings up Postgres on `localhost:5432` (user `garage`, password `garage`, db `garage`) and MinIO on `localhost:9000`.

### 2. Backend

```bash
cd backend
cp .env.example .env                 # then fill in GEMINI_API_KEY when you have one
npm install
npx prisma migrate dev --name init   # creates the schema in Postgres
npm run dev
```

Server listens on `http://localhost:3000`. Health check: `http://localhost:3000/health`.

> **Demo / dev shortcut:** set `DEMO_MODE=true` in `.env` to skip Google Vision and the LLM (returns hardcoded receipt fields and template strings). Always run the live demo with this on.

### 3. Mobile app

```bash
cd mobile
flutter pub get
open ios/Runner.xcworkspace        # one-time: configure signing in Xcode
flutter run                         # runs on connected iPhone / simulator
```

The Flutter app expects the backend at `http://localhost:3000` by default. For running on a real iPhone over USB:

```bash
ipconfig getifaddr en0              # gets your Mac's LAN IP (e.g. 192.168.1.42)
flutter run --dart-define=API_BASE_URL=http://192.168.1.42:3000
```

### 4. Phase 1 — what works today

- `POST /auth/register`, `/auth/login`, `/auth/refresh`, `/auth/logout`, `GET /auth/me`
- `PATCH /users/me`
- `GET/POST /cars`, `GET/PATCH/DELETE /cars/:id`
- Flutter: login + register screens, auth bootstrap from secure storage, automatic refresh on 401, cars list with empty/error states, add car form, car detail with tabbed shell.
- Photo uploads, fuel/maintenance/documents/reminders, OCR, geofencing, LLM features → upcoming phases.

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
