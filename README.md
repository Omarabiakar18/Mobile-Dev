# Garage — Smart Car Companion App

University final project · Mobile Development · Antonine University.
Flutter (iOS) + Node.js / TypeScript backend.

> The single source of truth for the design is [`GARAGE_PROJECT_SPEC.md`](./GARAGE_PROJECT_SPEC.md).
> The 5-minute demo flow lives in [`DEMO.md`](./DEMO.md).

---

## What it does

Five locked features:

1. **Multi-car profiles** — cars, maintenance log, fuel log, documents (with expiry), reminders.
2. **Predictive next fill-up** — uses your fuel history + average consumption + km/day to estimate when you'll need to refuel.
3. **Smart service reminders** — projects intervals against *your* driving pace, not generic mileage. AI-phrased messages.
4. **Receipt OCR via Gemini multimodal** — snap a gas pump receipt, the form pre-fills.
5. **Geofenced auto-logging** — when you pull into a known gas station and stay >30s, a local notification offers to log a fill-up.

Plus three LLM touchpoints (spec §16): receipt extraction (§16-A), AI-phrased reminder messages (§16-B), and an "explain this prediction" modal (§16-C). All three fall back to deterministic templates if Gemini is unreachable.

---

## Tech stack

**Backend** — Node.js 20 + TypeScript + Express + Prisma + Postgres (Neon cloud) + Gemini multimodal SDK. JWT access + refresh tokens. Per-route rate limiting. Cron job at 03:00 daily for `avgKmPerDay` recompute.

**Mobile** — Flutter 3.x (iOS only) + Riverpod + dio (with single-flight 401-refresh interceptor) + go_router + flutter_secure_storage (Keychain) + sqflite (local cache) + flutter_local_notifications + geofence_service + image_picker / image_cropper / file_picker.

**No Docker required for dev.** Postgres runs on Neon (free tier). The only local prereqs are Node, Flutter, and Xcode.

---

## Quick start

### Prerequisites

- Node.js 20+
- A free [Neon](https://neon.tech) Postgres project
- Flutter 3.x with the iOS toolchain (Xcode 16+)
- A free Apple developer account (for sideloading to a real iPhone)
- A free [Google AI Studio](https://aistudio.google.com/apikey) API key for Gemini

### 1. Database — Neon

1. Create a free project at [neon.tech](https://neon.tech).
2. Copy the **Pooled** connection string from the Neon dashboard (host contains `-pooler`).
3. Derive the **Direct** URL by removing `-pooler` from the host (same credentials).

Both go into `backend/.env` — pooled as `DATABASE_URL` (runtime), direct as `DIRECT_URL` (migrations).

### 2. Backend

```bash
cd backend
cp .env.example .env                # paste Neon URLs + Gemini key
npm install
npx prisma migrate deploy           # apply committed migrations to Neon
npx tsx prisma/seed.ts              # demo data — idempotent
npm run dev                         # http://localhost:3000
```

Health check: `http://localhost:3000/health`.

### 3. Mobile app

The app builds and runs on both Android and iOS. Pick whichever you have set up.

**Android** (USB-tethered, fastest path):
```bash
cd mobile
flutter pub get
adb reverse tcp:3000 tcp:3000        # phone's localhost → Mac:3000
flutter run --dart-define=API_BASE_URL=http://localhost:3000
```

**iOS** (simulator or device):
```bash
cd mobile
flutter pub get
open ios/Runner.xcworkspace          # one-time: configure signing in Xcode
                                     # (set your Team under Runner ▸ Signing)
flutter run                          # runs on simulator
```

> **iOS one-time platform install.** When Xcode updates to a new major version
> (e.g. 26.5), the matching iOS platform support has to be downloaded
> separately — `flutter build ios` fails with *"iOS X.Y is not installed.
> Please download and install the platform from Xcode > Settings > Components"*.
> It's a ~7 GB one-time download. Until it's done, build for Android; the
> feature set is identical.

To run on a real iPhone over wifi:

```bash
ipconfig getifaddr en0              # get the Mac's LAN IP
flutter run --dart-define=API_BASE_URL=http://192.168.X.Y:3000
```

> **macOS firewall:** the first time you run the backend, macOS pops a "Allow incoming connections?" dialog. Click **Allow**, otherwise the iPhone times out reaching the LAN IP. If you missed it: System Settings ▸ Network ▸ Firewall ▸ Options... and add `/opt/homebrew/bin/node`.

---

## Demo credentials

Pre-seeded by `prisma/seed.ts`:

- **email:** `demo@garage.app`
- **password:** `demo1234`

The account ships with 3 cars, 12 fuel entries, 6 maintenance records, 4 reminders (one overdue), 3 documents (one expiring in ~11 days), and 10 gas stations seeded around Beirut/Jounieh.

Re-seed at any time — it's idempotent:

```bash
cd backend && npx tsx prisma/seed.ts
```

---

## Demo mode

Set `DEMO_MODE=true` in `backend/.env` to skip Gemini for OCR + reminder phrasing + predict-explainer. Endpoints return canned responses. Useful for offline demos or when the API key isn't set.

Default is `DEMO_MODE=false` so the real LLM path is exercised.

---

## Verification

All quality gates run via:

```bash
cd backend && ./scripts/verify-all.sh    # backend tsc + 4 phase verifies
cd mobile && flutter analyze             # 0 issues
cd mobile && flutter test                # widget tests
```

Or run pieces individually:

```bash
cd backend && npx tsc --noEmit                     # type-check backend
cd backend && npx tsx scripts/verify-phase3-math.ts # 26 asserts — predict + reminder math
cd backend && npx tsx scripts/verify-phase4-ocr.ts  # 30 asserts — OCR parser
cd backend && npx tsx scripts/verify-phase4-llm.ts  # 31 asserts — LLM prompt templates
cd backend && npx tsx scripts/verify-phase5-geo.ts  # 3 asserts — Haversine
```

---

## Project layout

```
.
├── GARAGE_PROJECT_SPEC.md   ← single source of truth for the design
├── DEMO.md                  ← 5-min demo script for the prof
├── README.md                ← this file
├── backend/                 ← Express + TypeScript + Prisma (Postgres on Neon)
│   ├── prisma/              ← schema + migrations + seed
│   ├── scripts/             ← verify-* and verify-all.sh
│   └── src/
│       ├── config/          ← env validation
│       ├── lib/             ← jwt, passwords, prisma, math helpers
│       ├── middleware/      ← auth, error handler
│       ├── modules/         ← feature verticals (auth/cars/fuel/maintenance/documents/reminders/ocr/gas-stations)
│       ├── services/        ← llm (Gemini), ocr (sharp preprocess), ocr-parse
│       └── jobs/            ← node-cron jobs
└── mobile/
    ├── ios/                 ← Info.plist (perms + UIBackgroundModes: location)
    ├── lib/
    │   ├── core/            ← api client, secure storage, sqflite, theme, notifications
    │   └── features/        ← auth / cars / fuel / maintenance / documents / reminders / geofence / home
    └── test/                ← widget tests
```

---

## Phase status

All six phases from [`GARAGE_PROJECT_SPEC.md` §11](./GARAGE_PROJECT_SPEC.md#11-phasing--14-weeks-155-hours-total) shipped:

- [x] **Phase 1** — Foundation (auth, scaffolds, cars CRUD)
- [x] **Phase 2** — Core CRUD (fuel, maintenance, documents, reminders)
- [x] **Phase 3** — Smart math (predictive fill-up, service reminder dates, fuel stats)
- [x] **Phase 4** — Receipt OCR via Gemini multimodal + LLM enhancements §16-A/B/C
- [x] **Phase 5** — Local notifications + geofencing + gas-stations registry
- [x] **Phase 6** — Polish + demo seed + code-review fixes

---

## Key design notes

- **Gemini multimodal handles OCR end-to-end.** The image is sent as `inlineData` (base64) and Gemini returns structured JSON. There is no separate Vision API. `sharp` preprocesses the image (greyscale → contrast → upscale ≥1200px) before the call.
- **Free Apple cert ≠ `UIBackgroundModes: fetch`.** That mode requires a paid developer account. Info.plist declares only `location`. Geofencing runs on `CLVisit` + a 30-second dwell timer.
- **JWT refresh is single-flight.** Concurrent 401s share one refresh future so a network burst can't sign the user out by force.
- **`avgKmPerDay` is cached + invalidated.** When recomputed and it shifts >5%, all cached AI-phrased reminder messages on that car are invalidated so the dashboard can't disagree with the reminder list.
- **iOS 64-pending-notification cap is global.** Scheduling sweeps the whole pool and caps at 50, prioritizing soonest first.

---

## License

Coursework — not licensed for redistribution.
