# RESUME_HERE — Garage project context

If you're returning to this Claude chat (or starting a new one), paste this file
into your first message. It captures all non-obvious state so the assistant can
pick up where you left off without re-deriving it.

> ⚠️ **PARTIALLY SUPERSEDED — read [`HANDOFF.md`](./HANDOFF.md) and
> [`README.md`](./README.md) first; they reflect the current state.** This file
> is kept for its hard-won iOS/Neon gotchas (§7, §14), but three headline facts
> below drifted after it was written:
> - **Owners:** co-owned by **Alaa Hassan & Omar Abi Akar** (not Omar alone).
> - **Bundle / package id:** `com.garage.app` on **both** platforms (the old
>   `com.omarabiakarmobiledev.garage` / `com.omar.garage` ids are retired).
> - **Platform:** runs on **Android *and* iOS** now — the "iOS-only" framing is
>   no longer true (Android verified on a real device; see HANDOFF.md).

---

## 1. What the project is

**Garage** — a Flutter (iOS + Android) + Node.js + TypeScript car-companion app
for a university final project. Co-owned by Alaa Hassan & Omar Abi Akar. Spec
lives in [`GARAGE_PROJECT_SPEC.md`](./GARAGE_PROJECT_SPEC.md) — that's the source
of truth for design decisions.

Five locked features:
1. Multi-car profiles (cars + maintenance + fuel + documents + expiry alerts)
2. Predictive next fill-up
3. Smart service reminders adapted to km/day
4. Receipt OCR via Gemini multimodal (no Vision API)
5. Geofenced auto-logging at gas stations (CLVisit + dwell timer + local notif)

Plus three LLM touchpoints (§16-A/B/C in spec): receipt OCR, AI-phrased reminder
messages, "explain this prediction" modal. All three gracefully fall back to
deterministic templates when Gemini isn't reachable or `DEMO_MODE=true`.

---

## 2. State as of last work

**Phases 1–6 all committed.** 14 commits on `main`. Verify with
`git log --oneline`. The most recent are:

```
36f2bd7 refactor: drop Google Cloud Vision — Gemini multimodal does OCR directly
b42bed6 feat: phase 6 demo seed + fix the 6 issues from the fresh code review
574c136 feat: phase 5 — local notifications, geofencing, gas-stations registry
979a605 feat: phase 4 — OCR pipeline + LLM enhancements (§16-A, §16-B, §16-C)
b44d736 fix: address Opus code review findings (8 must-fix items)
7384c25 feat: phase 3 — smart math
4d75e6c feat(mobile): home dashboard with expiring/due banners
4f3cddc feat: phase 2 — fuel, maintenance, documents, reminders verticals
e2236cd chore: switch dev database from local Docker to Neon
90c2e7a feat(mobile): phase 1 — auth + cars list + detail + add
43cbea7 feat(backend): phase 1 — auth, users, cars CRUD
12c355d feat: add LLM enhancements and switch local cache to SQLite
3fcf7f9 chore: scaffold initial project structure
```

**Quality gates last green:**
- `cd backend && npx tsc --noEmit` → clean
- All 4 verify scripts: 90/90 asserts pass (Phase 3 math 26 + Phase 4 OCR 30 +
  Phase 4 LLM 31 + Phase 5 geo 3)
- `cd mobile && flutter analyze` → 0 issues
- `cd mobile && flutter test` → 2/2 pass

---

## 3. Tech stack (locked — don't suggest swaps)

### Backend (`backend/`)
- Node.js + TypeScript + Express + Prisma + Postgres
- **Postgres = Neon (cloud)** — NO local Postgres, NO Docker required for dev.
  Pooled URL in `DATABASE_URL`, direct URL in `DIRECT_URL` (drop `-pooler` from
  the pooled host to derive direct).
- **`@google/generative-ai`** — Gemini for OCR multimodal + reminder phrasing +
  predict-explainer. **Vision API has been removed entirely** (the user
  explicitly didn't want two Google auth methods).
- Validation: Zod with `.strict()` on update schemas
- Auth: JWT access (15min) + refresh tokens stored hashed in DB, rotated on every refresh
- Rate limit: per-route via `express-rate-limit` in `auth.routes.ts` (login/register 10/min, refresh 30/min, OCR 10/day/user)
- File upload: `multer` per-module with explicit MIME→ext mapping
- Cron: `node-cron` at 03:00 daily for stale `avgKmPerDay` recompute
- Image preprocess: `sharp` (greyscale → contrast → upscale to ≥1200px JPEG)

### Mobile (`mobile/`)
- Flutter, **iOS + Android target** (free Apple personal cert for iOS; see banner)
- State: `flutter_riverpod`
- HTTP: `dio` with single-flight 401-refresh interceptor
- Storage: `flutter_secure_storage` (iOS Keychain / Android Keystore) + `sqflite` for local cache
- Navigation: `go_router` with auth-redirect via `_AuthRefresh` ChangeNotifier
- Photos: `image_picker` → `image_cropper` → `flutter_image_compress`
- Documents: `file_picker` (PDF support)
- Notifications: `flutter_local_notifications` + `timezone` (no FCM, no APNs)
- Geofencing: `geofence_service` (discontinued package; works on iOS for v1)
- Architecture: lean feature-first — `features/<feature>/data/` +
  `features/<feature>/presentation/`. No domain layer.

### What we explicitly DO NOT use (ever)
- ❌ Google Cloud Vision (replaced by Gemini multimodal)
- ❌ FCM / APNs (local notifications only)
- ❌ NestJS (plain Express)
- ❌ Docker for dev (only the Dockerfile for prod deploy)
- ❌ Bilingual / RTL (English-only)
- ❌ OBD-II scaffolding (cut)
- ❌ Mechanics directory (cut)
- ❌ AI chatbot screen / weekly insights feed (cut — only the 3 in-feature LLM touchpoints remain)
- ❌ Charts in fuel stats (numbers only)
- ❌ LBP currency (USD only)

---

## 4. How to run locally (every time)

```bash
# Terminal 1 — backend (stays running)
cd /Users/omarabiakar/Desktop/UA/MobileDev/Final_Project/backend
npm run dev
# → "Garage backend listening on http://localhost:3000"

# Terminal 2 — Flutter (rebuild as needed)
cd /Users/omarabiakar/Desktop/UA/MobileDev/Final_Project/mobile

# Find LAN IP — phone needs to reach the Mac over wifi:
ipconfig getifaddr en0
# → e.g. 192.168.33.110

flutter run --dart-define=API_BASE_URL=http://192.168.33.110:3000
# Hot reload: r        Hot restart: R       Quit: q
```

For simulator only (no LAN gymnastics):
```bash
open -a Simulator                                  # boot the iOS simulator
cd mobile && flutter run                           # uses default localhost:3000
```

---

## 5. Demo credentials

Pre-seeded by `prisma/seed.ts`:
```
email:    demo@garage.app
password: demo1234
```
This account has 3 cars (Range Rover Sport primary + Prius + GLE), 12 fuel
entries spanning ~6 months, 6 maintenance records, 4 reminders (one OVERDUE
oil change, one due-in-1-day brake check), 3 documents (mécanique expires in
~11 days → red banner), and 10 seeded gas stations near Beirut.

To re-seed (idempotent):
```bash
cd backend && npx tsx prisma/seed.ts
```

---

## 6. The Gemini key situation

`backend/.env` line 30 contains a real Gemini API key (gitignored, never
committed). `DEMO_MODE=false`. The OCR + reminder + explainer features all
make actual Gemini calls when this is set. If you swap the key out, it falls
back gracefully to canned responses without crashing.

To get a fresh key: https://aistudio.google.com/apikey (free tier, no billing).

---

## 7. Non-obvious gotchas (already debugged once — don't re-debug)

### macOS firewall blocks LAN incoming on port 3000
`localhost:3000` works but `192.168.x.x:3000` from the iPhone times out. Fix:
**System Settings → Network → Firewall → Options...** add
`/opt/homebrew/bin/node` (use `Cmd+Shift+G` in the file picker to navigate
there) and set to "Allow incoming connections". Or temporarily disable the
firewall: `sudo /usr/libexec/ApplicationFirewall/socketfilterfw --setglobalstate off`.

### Free Apple Dev cert can't use `UIBackgroundModes: fetch`
`fetch` mode requires a paid developer account; on free certs the OS rejects
the app at launch with no Dart-side trace (splash shows briefly, then dies).
Info.plist must contain only `<string>location</string>` under
`UIBackgroundModes` — `fetch` was removed in the latest commit. If anyone
adds it back, the app will crash on launch on a free cert.

### Free Apple Dev cert expires every 7 days
The signed app on the iPhone stops launching after 7 days. Fix: re-run
`flutter run` to re-sign. Set a calendar reminder.

### Bundle ID
Now `com.garage.app` on both Runner and RunnerTests targets (was
`com.omarabiakarmobiledev.garage` — retired in the 2026-05-24 rename; set in
Xcode → Runner target → Signing & Capabilities). Don't change it casually —
Apple's free tier limits you to 10 unique bundle IDs ever.

### `geofence_service` package is discontinued but kept
Replacement is `geofencing_api`. We pinned `^6.0.0+1` and it works on iOS.
Don't upgrade until Phase 5 is rewritten against `geofencing_api`.

### `file_picker` logs an `objc[]` FileUtils duplicate-class warning
Cosmetic only. Caused by `file_picker.framework` shipping a class that's also
in iOS's `OSAnalytics`. Doesn't crash anything. Ignore.

### Neon direct vs pooled URLs
Prisma schema declares both `url` (pooled) and `directUrl` (unpooled). The
unpooled host = pooled host with `-pooler` removed. Migrations need
`directUrl`; runtime uses `url`. If `prisma migrate dev` says "Can't reach
database server", you got the unpooled hostname wrong.

### iOS 26.4 + Flutter
The user is on iOS 26.4 (very new). `pub.dev` advisories format errors are
cosmetic (`FormatException: advisoriesUpdated must be a String`) — they do
not fail the build. `33 packages have newer versions incompatible` warnings
are also cosmetic — don't upgrade.

### macOS firewall pop-up on first `npm run dev`
First time you run the backend, macOS will pop a "Do you want to accept
incoming network connections?" dialog. Click **Allow**. If you missed it
and clicked Deny, see the firewall fix above.

---

## 8. Where things live (cheat sheet)

```
GARAGE_PROJECT_SPEC.md        — design source of truth
RESUME_HERE.md                — this file

backend/
├── .env                       — secrets (gitignored, has real Gemini key + Neon URLs)
├── .env.example               — template
├── prisma/schema.prisma       — DB schema
├── prisma/migrations/         — committed migrations (Neon-applied)
├── prisma/seed.ts             — demo seed (idempotent)
├── scripts/verify-phase3-math.ts    — 26 asserts (predict + reminder math)
├── scripts/verify-phase4-ocr.ts     — 30 asserts (regex parser)
├── scripts/verify-phase4-llm.ts     — 31 asserts (LLM prompt templates)
├── scripts/verify-phase5-geo.ts     — 3 asserts (Haversine)
├── src/index.ts               — Express bootstrap, route mounting
├── src/config/env.ts          — Zod-validated env
├── src/lib/                   — jwt, passwords, validate, errors, prisma client,
│                                avg-km-per-day (with cache-invalidation logic)
├── src/middleware/            — auth (requireAuth), error handler
├── src/services/
│   ├── llm.ts                 — Gemini wrapper: text(), json(), imageJson()
│   ├── ocr.ts                 — sharp preprocess (Vision removed)
│   └── ocr-parse.ts           — parseFieldsFromImageWithLlm + regex fallback
├── src/jobs/                  — node-cron: avg-km-per-day.cron.ts
└── src/modules/
    ├── auth/                  — register, login, refresh, logout, me
    ├── users/                 — PATCH /users/me
    ├── cars/                  — CRUD + assertOwnsCar helper
    ├── fuel/                  — CRUD + stats + predict-next + explain
    ├── maintenance/           — CRUD + photos
    ├── documents/             — CRUD + expiring (lower-bound 14d)
    ├── reminders/             — CRUD + due (with LLM-aiMessage cache)
    ├── ocr/                   — POST /cars/:id/fuel/ocr (Gemini multimodal)
    └── gas-stations/          — Phase 5 nearest-search

mobile/
├── pubspec.yaml               — deps (flutter_riverpod, dio, sqflite, etc.)
├── ios/Runner/Info.plist      — perms (camera/location/photo) +
│                                UIBackgroundModes: [location] (NO fetch)
├── lib/main.dart              — bootstraps providers + runApp + geofence
├── lib/app.dart               — go_router config + auth redirect
├── lib/core/
│   ├── theme/app_theme.dart
│   ├── api/dio_client.dart    — single-flight 401-refresh interceptor
│   ├── api/api_exception.dart
│   ├── api/base_url.dart      — reads --dart-define=API_BASE_URL
│   ├── storage/secure_storage.dart    — token storage (Keychain)
│   ├── db/local_db.dart       — sqflite cache schema
│   └── notifications/
│       ├── notifications_service.dart
│       ├── notification_ids_store.dart
│       ├── permissions_seen_store.dart
│       └── scheduling_sync.dart  — global 50-notification cap
└── lib/features/
    ├── auth/                  — login + register screens, AuthNotifier
    ├── cars/                  — list + detail (5 tabs) + add
    ├── fuel/                  — list + add + stats + predict card + OCR camera
    ├── maintenance/           — list + add (with photo)
    ├── documents/             — list + add (with file_picker)
    ├── reminders/             — list + add
    ├── geofence/              — gas station model, geofence service wrapper, settings screen
    ├── permissions/           — first-launch explainer
    └── home/                  — home dashboard + splash + selected_car_provider
```

---

## 9. The current iPhone setup

- iPhone: "Omar's iPhone", iOS 26.4
- Mac LAN IP at last check: **192.168.33.110**
- Bundle ID on the device: `com.garage.app`
- Apple ID: `abiakaromar18@icloud.com`
- Provisioning: Xcode-managed, free personal team
- Background modes in Info.plist: only `location` (NOT `fetch`)
- Dev cert was trusted via Settings → General → VPN & Device Management

If the LAN IP changes (rejoining wifi, different network), re-run with the new
IP via `--dart-define=API_BASE_URL=http://NEW.IP:3000`.

---

## 10. Open / next-up work

Nothing is "broken." A demo-ready build is on the iPhone. Possible next steps
the user might pick up:

- **Polish (purely optional):** shimmer loading skeletons, hero animations on
  car cards, dark-mode tweaks, animation transitions
- **Photo upload for cars** (deferred from Phase 2)
- **Receipt-photo persistence on fuel entries** (currently OCR doesn't save
  the photo URL onto the fuel entry)
- **Switch `geofence_service` → `geofencing_api`** (the maintained replacement)
- **Final report writeup for the prof** — architecture diagram, screenshots,
  one-page README polish

Don't suggest going back and re-architecting things. The user has been clear
about that.

---

## 11. How the user works

- Wants forward motion. Auto mode is on most sessions.
- Doesn't want excessive Q&A — make reasonable assumptions, proceed.
- "I just need to demo this to my prof." Pragmatic, not academic.
- Doesn't care about distinctions like Vision vs Gemini multimodal — wants the
  simplest path with one Google account.
- Speaks English + French + Arabic. Sometimes types in Arabic letters when
  the keyboard layout slips — ignore those messages, they're typos.
- The demo is the goal. Don't go off-piste.

---

## 12. The 5-minute demo flow (rehearse before showing the prof)

1. (0:00) Open app → home dashboard
   - 🚨 Mécanique expiring in 11 days (red banner)
   - 🟠 Oil change overdue, brake check in 1 day (amber banner)
   - ⛽ Predict-next-fill-up card: ~28 days remaining
2. (0:30) Tap car switcher → 3 cars listed → pick the Range Rover
3. (0:45) Tap reminder banner → reminders list with km/day projections
   - "Calculated from your driving data, not generic intervals"
4. (1:30) Home → "Scan Receipt" → camera → take photo of a real Lebanese
   gas pump receipt → Gemini parses → form pre-fills with real numbers
5. (2:30) Fuel tab → tap predict card → bottom sheet with LLM-narrated
   explanation interpolating real consumption + km/day
6. (3:15) Documents tab → tap mécanique → file opens → mention auto-scheduled
   local notifications at -30d / -7d
7. (4:00) Settings (gear icon, top-right) → Debug tools → "Simulate
   Geofence Entry" → notification fires → tap → fuel form opens pre-filled
   with the station name. *"Works whether the app is open or closed."*
8. (4:45) Brief code/architecture mention.

---

## 13. Useful one-liners

```bash
# Verify all 90 asserts still pass
cd backend && for s in scripts/verify-phase*.ts; do echo "--- $s ---"; npx tsx "$s" | tail -1; done

# Re-seed Neon (idempotent)
cd backend && npx tsx prisma/seed.ts

# Open Prisma Studio (DB GUI)
cd backend && npm run db:studio
# → http://localhost:5555

# Type-check + run
cd backend && npx tsc --noEmit && npm run dev

# Flutter clean rebuild (use after editing Info.plist or pubspec)
cd mobile && flutter clean && flutter run --dart-define=API_BASE_URL=http://YOUR_IP:3000

# Stream iPhone logs while app runs
cd mobile && flutter logs

# Stop the backend
lsof -ti:3000 | xargs -r kill
```

---

## 14. Lessons learned this session (don't re-discover)

1. macOS firewall silently blocks LAN incoming → must explicitly allow `node`
2. Free Apple Dev cert + `UIBackgroundModes: fetch` = silent crash on launch
3. iPhone simulator location must be set to Beirut (33.8938, 35.5018) for
   geofencing to register seeded stations
4. The user's Neon-direct hostname uses `c-5` (`ep-NAME.c-5.REGION.aws.neon.tech`)
   not `ep-NAME.REGION.aws.neon.tech`. Both DNS-resolve but only the c-5 form
   accepts the Prisma TLS handshake.
5. Gemini multimodal eliminates the need for Google Cloud Vision entirely —
   send the image as `inlineData` with a base64 `data` field.
6. Login screen and Register screen look similar; the user once typed login
   credentials thinking they were registering. Always verify which endpoint
   was hit before assuming a registration failed.
7. iOS 64-pending-notification cap requires a global cap-and-cancel sweep, not
   per-car loops. See `scheduling_sync.dart`.
8. When `Car.avgKmPerDay` shifts >5%, all cached `aiMessage` strings on that
   car's reminders must be invalidated (otherwise dashboard banner contradicts
   reminder list). See `recomputeAvgKmPerDay()` in `lib/avg-km-per-day.ts`.
