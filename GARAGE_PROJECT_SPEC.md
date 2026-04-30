# Garage — Smart Car Companion App

**Owner:** Omar Abi Akar (Senior Computer Engineering, Antonine University)
**Status:** Brainstorm complete · spec locked · ready for implementation
**Last updated:** 2026-04-30

---

## 1. One-line pitch

A Flutter + Node.js app for car owners that tracks fuel, maintenance, and documents per car, predicts the next fill-up from driving habits, converts service intervals into real calendar dates, auto-fills fuel entries from receipt photos via OCR, and pings the user when they roll into a known gas station.

---

## 2. Scope — five features, nothing else

**Shipping in v1:**

1. **Multi-car profiles** with maintenance logs, fuel tracking, and document storage (insurance, mécanique, registration) with expiry alerts.
2. **Predictive next fill-up** based on daily driving habits.
3. **Smart service reminders** adapted to real km/day instead of generic intervals.
4. **Receipt OCR** to auto-fill fuel entries from a photo.
5. **Geofenced auto-logging** — detects when the user is at a known gas station from their location and prompts a fill-up entry.

**Out of scope — will not be built:**

- AI maintenance advisor chatbot
- Weekly AI insights feed
- Mechanics directory + reviews
- Bilingual EN/AR + RTL layout
- OBD-II / ELM327 scaffolding (data model, stubs, "Coming Soon" tile)
- Forgot-password / email flow
- FCM / remote push (replaced by local notifications)
- LLM provider abstraction (no LLM features)
- LBP currency / parallel-rate handling (USD only)
- Charts / graphs in fuel stats (numeric stats only)

> "Smart" features (predictive fill-up, service reminders) are **pure math/algorithms**, not LLMs. OCR uses Google Cloud Vision (managed ML service). No LLM is part of v1.

---

## 3. Tech stack (locked)

### Backend
- **Runtime:** Node.js (LTS) + TypeScript
- **Framework:** Express
- **ORM:** Prisma
- **Database:** PostgreSQL
- **Validation:** Zod (small middleware that runs `schema.parse(req.body)` and returns 400 on failure)
- **Auth:** JWT access tokens (15min) + refresh tokens (7d) stored in DB so they can be revoked on logout
- **Password hashing:** bcrypt
- **File upload:** multer (multipart, 5MB cap, MIME validation: `image/jpeg | image/png | image/heic | application/pdf`)
- **Storage:** local filesystem in dev (`./uploads/`), MinIO via docker-compose for S3-parity dev option
- **Scheduled jobs:** `node-cron` (nightly recompute of `avgKmPerDay` per car)
- **Rate limiting:** `express-rate-limit` on `/fuel/ocr` (10/day/user) and `/auth/login` (10/min/IP)
- **Logging:** `pino` with `pino-http`
- **Containerization:** Docker + docker-compose (postgres + backend + minio)

### Frontend (Flutter)
- **Target:** iOS (sideloaded to Omar's iPhone via free Xcode personal team — re-sign within 7 days of demo)
- **Architecture:** Lean feature-first. `lib/features/<feature>/data/` (models + API client) + `lib/features/<feature>/presentation/` (screens + Riverpod notifiers). No domain layer.
- **State management:** `flutter_riverpod`
- **HTTP:** `dio` + interceptor for `Authorization: Bearer` + 401-refresh-retry
- **Token storage:** `flutter_secure_storage`, with first-launch stale-token clear
- **Photos:** `image_picker` → `flutter_image_compress` (max 1200px, ~80% JPEG) → multipart upload via `dio`
- **Caching:** `cached_network_image` for remote photos
- **Local persistence:** `hive` for caching the current car's profile (so the app opens to data even on slow networks)
- **Navigation:** `go_router` (declarative, type-safe params, deep-link support for cold-start notification taps)
- **Notifications:** `flutter_local_notifications` (scheduling, permission flow, deep-linked payloads)
- **Geofencing:** `geofence_service` (CLVisit + CLCircularRegion under the hood on iOS)
- **Forms / validation:** vanilla `Form` + `FormField`
- **Theme:** single `ThemeData` instance — one primary color (deep slate), one accent, system font, dark mode for free

### Third-party services
- **OCR:** Google Cloud Vision API (free tier covers v1 volume; ~1000 calls/month free)
- **Hosting (optional, demo evidence):** Neon free tier for Postgres, Render or Railway free tier for backend. Free.

---

## 4. Data model

All entities have `id` (UUID), `createdAt`, and `updatedAt` unless noted. Hard deletes (no soft-delete). Money stored as `Decimal(18, 4)`.

```
User
  id, email (unique), passwordHash, name, phone?, createdAt, updatedAt

RefreshToken
  id, userId (FK), tokenHash, expiresAt, revokedAt?, createdAt

Car
  id, userId (FK), make, model, year, plate, color?, currentKm,
  fuelType (enum: gasoline | diesel), tankSize, photoUrl?,
  avgKmPerDay (nullable, cached), createdAt, updatedAt

MaintenanceEntry
  id, carId (FK), date, km, type (enum: oil | brakes | tires | filter | battery | other),
  description?, cost (Decimal), notes?, createdAt, updatedAt

MaintenancePhoto
  id, maintenanceEntryId (FK), url, createdAt

FuelEntry
  id, carId (FK), date, odometer, liters (Decimal), pricePerLiter (Decimal),
  totalCost (Decimal), fuelType, station?, isFullTank (bool), receiptPhotoUrl?,
  latitude?, longitude?, notes?, createdAt, updatedAt

Document
  id, carId (FK), type (enum: insurance | mecanique | registration | other),
  issuedDate?, expiryDate, fileUrl, issuer?, notes?, createdAt, updatedAt

ServiceReminder
  id, carId (FK), serviceType, lastDoneKm, lastDoneDate, intervalKm?,
  intervalMonths?, isActive (bool), lastNotifiedAt?, createdAt, updatedAt

GasStation
  id, name, latitude, longitude, city, createdAt
  // seeded with ~10 real stations near Beirut/Jounieh

OcrCache
  id, imageHash (unique), fields (JSONB), confidence (JSONB),
  rawText, provider, createdAt
  // dedupes Vision API calls when the user retakes the same receipt
```

**Indexes that matter:**
- `User.email` (unique already)
- `Car (userId)`
- `FuelEntry (carId, date desc)`
- `MaintenanceEntry (carId, date desc)`
- `Document (carId, expiryDate)` — drives the "expiring soon" query
- `RefreshToken (userId, expiresAt)`

**User isolation:** Express middleware extracts `userId` from JWT. Every query in service code filters by `userId` (or by `carId` where the car belongs to the user). A small helper `assertOwnsCar(userId, carId)` is called at the top of every car-scoped handler.

---

## 5. API endpoints

All responses use the shape `{ data?: ..., error?: { code, message, details? } }`. Status codes are standard. Auth header: `Authorization: Bearer <accessToken>`. List endpoints support `?page=&limit=`.

```
POST   /auth/register                 → { user, accessToken, refreshToken }
POST   /auth/login                    → same
POST   /auth/refresh                  → new access + rotated refresh
POST   /auth/logout                   → revokes the refresh token
GET    /auth/me                       → current user
PATCH  /users/me                      → update name/phone

GET    /cars                          → user's cars
POST   /cars                          → multipart (json + optional photo file)
GET    /cars/:id
PATCH  /cars/:id                      → multipart (json + optional photo file)
DELETE /cars/:id

GET    /cars/:carId/fuel              → paginated, newest first
POST   /cars/:carId/fuel              → multipart (json + optional receipt file)
POST   /cars/:carId/fuel/ocr          → multipart image, returns parsed fields + confidence
GET    /fuel/:id
PATCH  /fuel/:id
DELETE /fuel/:id
GET    /cars/:carId/fuel/stats        → totals, avg L/100km, last 30/90 days
GET    /cars/:carId/fuel/predict-next → { tankRemainingLiters, daysRemaining, predictedDate, confidence }

GET    /cars/:carId/maintenance       → paginated
POST   /cars/:carId/maintenance
GET    /maintenance/:id
PATCH  /maintenance/:id
DELETE /maintenance/:id
POST   /maintenance/:id/photos        → multipart, attaches a photo
DELETE /maintenance/:id/photos/:photoId

GET    /cars/:carId/documents         → paginated
POST   /cars/:carId/documents         → multipart (json + file)
GET    /documents/:id
PATCH  /documents/:id
DELETE /documents/:id
GET    /cars/:carId/documents/expiring?withinDays=30   → dashboard banner

GET    /cars/:carId/reminders
POST   /cars/:carId/reminders
PATCH  /reminders/:id
DELETE /reminders/:id
GET    /cars/:carId/reminders/due?withinDays=30        → dashboard banner + scheduling source

GET    /gas-stations?lat=&lng=&radiusKm=               → for the Flutter geofence registrar
```

**File uploads:** all multipart-accepting endpoints handle their file inline. There is no standalone `/upload` endpoint.

**Errors:** uniform shape via Express error middleware. `ZodError` → 400. `AuthError` → 401. `ForbiddenError` → 403. `NotFoundError` → 404. Anything else → 500 (logged via `pino`, generic message in response).

---

## 6. Smart features — algorithms

### 6.1 Predictive next fill-up

**Inputs:** `Car.tankSize`, `Car.currentKm`, all `FuelEntry` rows for the car ordered by `odometer asc`.

**Bootstrap:** require ≥3 full-tank entries (`isFullTank = true`). Below that, return `confidence: "insufficient_data"` — Flutter UI shows "Add more fill-ups to enable predictions" placeholder.

**Algorithm:**
```
1. Pairs = consecutive (full-tank, full-tank) pairs in odometer order
2. consumptionPer100km = avg over pairs of: (liters_filled / (odo_end - odo_start)) * 100
3. lastFullTank = most recent FuelEntry where isFullTank
4. kmSinceLastFull = car.currentKm - lastFullTank.odometer
5. litersUsed = kmSinceLastFull * consumptionPer100km / 100
6. tankRemainingLiters = max(0, car.tankSize - litersUsed)
7. avgKmPerDay = (max(odometer) - min(odometer) over last 60d of fuel entries) / days_span
   (if <60d of data, fall back to 90d, then 180d; if still nothing, return null)
8. daysRemaining = (tankRemainingLiters / consumptionPer100km * 100) / avgKmPerDay
9. predictedDate = today + daysRemaining
```

**Edge case:** if `car.currentKm < lastFullTank.odometer`, return `confidence: "data_inconsistent"` — odometer entry is wrong somewhere. Flutter shows "Check your odometer entries" banner.

### 6.2 Smart service reminders

**`avgKmPerDay` is cached on the Car row.** Recomputed in the same DB transaction as every `FuelEntry` insert/update/delete. A nightly `node-cron` job (3am) recomputes for cars that haven't had a fuel insert in the last 60 days.

**Date projection per reminder:**
```
kmRemaining = (lastDoneKm + intervalKm) - car.currentKm
kmBasedDate = today + (kmRemaining / car.avgKmPerDay) days       (if avgKmPerDay > 0 and intervalKm set)
calendarDate = lastDoneDate + intervalMonths months              (if intervalMonths set)
predictedDate = min(kmBasedDate, calendarDate)
```

If both are null, return `null` and Flutter shows "Calendar interval not set."

**Notification scheduling (Flutter side):**
- On app launch and after every reminder mutation, fetch `/cars/:carId/reminders/due?withinDays=60`
- For each reminder with a `predictedDate`:
  - Schedule a local notification at `predictedDate - 30 days` ("Oil change approaching — book it")
  - Schedule a second at `predictedDate - 7 days` ("Oil change in 1 week")
  - Cancel + reschedule if the predicted date moves
- Backend tracks `lastNotifiedAt` to avoid double-firing

### 6.3 Document expiry alerts

Same pattern. On launch and after mutations, fetch `/cars/:carId/documents/expiring?withinDays=60`. For each:
- Schedule a local notification 30 days before `expiryDate`
- Schedule another 7 days before
- In-app red banner on the home dashboard for any document expiring within 14 days

---

## 7. Receipt OCR pipeline

**Flutter side:**
1. User taps "Scan Receipt" on the fuel-entry screen
2. `image_picker` opens camera (or library)
3. Optional crop step via `image_cropper`
4. `flutter_image_compress` to 1200px, ~80% JPEG
5. `POST /cars/:carId/fuel/ocr` (multipart) — show loading skeleton on the form (~2-5s)
6. Pre-fill the fuel entry form with returned fields
7. Low-confidence fields highlighted in orange; user must tap to confirm
8. User reviews → saves normally via `POST /cars/:carId/fuel`

**Backend side:**
1. Receive multipart upload, save to `./uploads/ocr/<hash>.jpg` (sha256 of bytes)
2. **Cache check:** if `<hash>` already in `OcrCache`, return cached result
3. Preprocess with `sharp`: greyscale → contrast (~+30%) → deskew → upscale if low DPI
4. Send to Google Cloud Vision (`textDetection`)
5. Field extraction via regex on the raw OCR text:
   - `total`: `\b(\d{1,3}(?:[.,]\d{2})?)\s*(?:USD|\$)\b` or last decimal in receipt
   - `liters`: `\b(\d{1,3}[.,]\d{1,3})\s*L\b`
   - `pricePerLiter`: `\b(\d{1,3}[.,]\d{1,3})\s*\$?/L\b`
   - `date`: `\b\d{1,2}[-/]\d{1,2}[-/]\d{2,4}\b`
   - `station`: first non-numeric line that looks like a name
6. Compute confidence per field (regex match strength + Vision API confidence)
7. Return `{ fields: { liters, pricePerLiter, totalCost, station, date }, confidence: { liters, pricePerLiter, ... }, rawText }`
8. Insert into `OcrCache`

**Demo-mode fallback:** if `DEMO_MODE=true`, the OCR endpoint skips Vision API entirely and returns hardcoded plausible fields. Flip on for the live demo.

---

## 8. Geofencing — iOS reality

1. App seeds ~10 real gas stations near Beirut/Jounieh into `GasStation` at backend startup (`db:seed`).
2. On Flutter app launch (and on significant location change), call `GET /gas-stations?lat=&lng=&radiusKm=10` and get the 10 nearest.
3. Register those as `CLCircularRegion` entries via `geofence_service` (well within iOS's 20-region cap).
4. When the user enters a region, start a 2-minute foreground timer. If they exit before it expires, cancel.
5. If the timer completes (user has dwelt at the station), fire a **local notification**: "At [Station Name] — log a fill-up?" with deep-link payload `{ route: "/fuel/new", stationId, stationName, lat, lng }`.
6. Tap → `go_router` opens the fuel entry form pre-filled with `station`, `latitude`, `longitude`, today's date.
7. Cold-start case: `flutter_local_notifications.getNotificationAppLaunchDetails()` is checked in `main()` and the deep link is honored before normal startup completes.

**Permissions flow:**
- First app launch → request `When In Use` location. If denied → degrade gracefully (rest of app works).
- After the user adds their first car → in-app explainer card → request `Always` location. If denied → keep working with When-In-Use; show "tap here to enable auto-logging" link to Settings.
- Notifications permission requested at first launch.

**Plist entries (iOS):**
- `NSLocationWhenInUseUsageDescription`
- `NSLocationAlwaysAndWhenInUseUsageDescription`
- `UIBackgroundModes`: `location`
- `NSCameraUsageDescription`
- `NSPhotoLibraryUsageDescription`

**Demo escape hatch:** A debug-build-only "Simulate Geofence Entry" button on a hidden Settings screen fires the local notification immediately without driving anywhere.

---

## 9. Screens (Flutter)

**~14 unique screens** (the original spec's 23 collapse — most were tabs).

```
1.  Splash (auto-routes to login or home)
2.  Login
3.  Register
4.  Home dashboard
    - Current car header with car switcher dropdown
    - "Documents expiring soon" red banner (if any)
    - "Reminders due soon" yellow banner (if any)
    - Predicted next fill-up card
    - Quick-action buttons: Add fuel, Add maintenance, Scan receipt
5.  Cars list
6.  Add/Edit car (with car photo upload)
7.  Car detail — TabBar: Overview | Fuel | Maintenance | Documents | Reminders
8.  Add/Edit fuel entry
9.  Receipt OCR camera flow (modal route)
10. Add/Edit maintenance entry
11. Add/Edit document (with file upload)
12. Add/Edit reminder
13. Profile / Settings (incl. logout, "Simulate Geofence" debug button in non-release builds)
14. Permissions explainer screen (shown the first time location is needed)
```

Every list/form must handle: **loading (shimmer skeleton), empty (illustration + CTA), error (retry button), success.** Non-optional.

---

## 10. Demo strategy

### Pre-seeded demo data (`db:seed`)
- 1 user: `omar@demo.test` / `demo1234`
- 2 cars
- 6 months of fuel entries on the primary car (~25 entries, mix of full and partial tanks)
- 8 maintenance records (oil changes, brakes, tires, filters)
- 3 active service reminders, with one **due in 4 days** (live dashboard banner)
- 3 documents: insurance (valid), registration (valid), mécanique (**expiring in 11 days**, red banner)
- 10 gas stations near Beirut/Jounieh
- A pre-cached `OcrCache` row matching one specific receipt photo so the demo OCR scan completes in <500ms

### 5-minute demo flow
1. (0:00) Open app → splash → home dashboard. Mécanique-expiring banner. Reminder banner. Predicted fill-up card.
2. (0:30) Tap car switcher — show 2 cars. Pick the primary.
3. (0:45) Tap reminder banner → reminders list. _"Calculated from your driving habits, not generic intervals."_
4. (1:30) Home → "Scan Receipt" → camera → photograph prepared receipt → fields auto-populate → save.
5. (2:30) Fuel tab → "Predict Next Fill-up" card → days-remaining + tank-remaining.
6. (3:15) Documents tab → tap mécanique → file opens. Mention auto-scheduled local notifications at 30d/7d.
7. (4:00) "Simulate Geofence Entry" button → notification fires → tap → fuel form pre-filled. _"Works whether the app is open or closed."_
8. (4:45) Brief code/architecture mention. Done.

### What can go wrong + mitigation

| Risk | Mitigation |
|---|---|
| OCR API down during demo | `DEMO_MODE=true` → hardcoded receipt parse |
| Geofence won't trigger live | Simulate Geofence debug button |
| iPhone cert expired | Re-sign via Xcode within 7 days of demo |
| Network slow / down | Read paths cache to `hive`; app opens with last-known data |
| Push permission denied | In-app banners still work for everything important |

---

## 11. Phasing — 14 weeks, ~155 hours total

| Phase | Weeks | Deliverable | Demo-ready? |
|---|---|---|---|
| **1. Foundation** | 1–2 | Backend: Express + Prisma + Postgres + Docker, auth (register/login/refresh/logout/me). Flutter: scaffold, Riverpod auth, login/register, home shell, cars list/detail. | No |
| **2. Core CRUD** | 3–4 | Cars CRUD with photo, fuel CRUD (no stats yet), maintenance CRUD, documents CRUD with file upload + expiry banner. | Partially |
| **3. Smart math** | 5–6 | `avgKmPerDay` recomputation, predictive fill-up endpoint + UI card, smart service reminders endpoint + UI, fuel stats numeric summary. **Walking skeleton end of week 6.** | Yes (first real demo) |
| **4. OCR** | 7–8 | OCR endpoint (Vision API + sharp preprocess + cache + DEMO_MODE), Flutter camera flow, confidence highlighting, fuel pre-fill. | Yes |
| **5. Notifications + Geofencing** | 9–10 | `flutter_local_notifications` setup, scheduled reminders + doc expiry, `geofence_service`, GasStation seed, deep-link handling, Simulate Geofence button. | Yes |
| **6. Polish + demo prep** | 11–14 | Loading/empty/error states, hero animations, dark mode, demo seed, pre-cached OCR sample, demo rehearsal. | Final demo build |

---

## 12. Cut-if-running-out-of-time order

1. **Documents** — drop document upload UI; keep entity for schema consistency.
2. **Multi-car switcher UI** — keep data model; ship one car with disabled "Add another" button.
3. **Geofencing** — fall back to "Log fill-up at current location" button (one-shot GPS).
4. **Predictive fill-up confidence states** — always show prediction even with sparse data.
5. **In-app banner on dashboard** — replace with list. Notifications still work.

The minimum that still passes the course: auth + 1 car + fuel CRUD + maintenance CRUD + service reminders w/ date projection + OCR.

---

## 13. Open risks

1. **Google Vision OCR accuracy on real Lebanese gas station receipts.** Test 5 actual receipts before committing the confirm/edit flow shape.
2. **iOS background location permission grant rate.** If "Always" denied, geofencing silently doesn't fire. Mitigation: Simulate button + in-app explainer.
3. **Free Apple Developer cert 7-day expiry.** Re-sign within 7 days of demo. Calendar reminder.
4. **Solo Flutter learning curve.** Phase 1 will take longer than estimated. Budget 1 week of slack.
5. **Demo network reliability.** Free-tier hosting cold starts. Run demo against `localhost` over USB tethering for reliability.

---

## 14. Definition of done

- All five features work end-to-end on a real iPhone (sideloaded build).
- Demo seed populates a realistic-looking dataset.
- `DEMO_MODE=true` works for OCR fallback.
- Loading/empty/error states implemented on every list and form screen.
- README documents env vars, seed script usage, and how to run docker-compose + flutter run.
- 5-minute demo flow rehearsed at least 3 times before showing the prof.

---

## 15. Repository layout

```
Final_Project/
├── GARAGE_PROJECT_SPEC.md              ← this doc (single source of truth)
├── README.md
├── docker-compose.yml
├── .gitignore
├── backend/
│   ├── package.json
│   ├── tsconfig.json
│   ├── .env.example
│   ├── Dockerfile
│   ├── prisma/
│   │   ├── schema.prisma
│   │   ├── migrations/
│   │   └── seed.ts
│   ├── src/
│   │   ├── index.ts                    ← Express app bootstrap
│   │   ├── config/                     ← env loading
│   │   ├── middleware/                 ← auth, validation, error handler
│   │   ├── modules/
│   │   │   ├── auth/
│   │   │   ├── users/
│   │   │   ├── cars/
│   │   │   ├── fuel/
│   │   │   ├── maintenance/
│   │   │   ├── documents/
│   │   │   ├── reminders/
│   │   │   ├── gas-stations/
│   │   │   └── ocr/
│   │   ├── services/
│   │   │   └── ocr.ts                  ← Vision API wrapper + sharp preprocess
│   │   ├── lib/                        ← shared helpers (jwt, money, dates)
│   │   └── jobs/                       ← node-cron schedules
│   └── uploads/                        ← gitignored
├── mobile/                             ← `flutter create`
│   ├── pubspec.yaml
│   ├── ios/                            ← Info.plist permissions
│   └── lib/
│       ├── main.dart
│       ├── app.dart                    ← go_router config
│       ├── core/                       ← theme, api client, secure storage, errors
│       └── features/
│           ├── auth/
│           ├── cars/
│           ├── fuel/
│           ├── ocr/
│           ├── maintenance/
│           ├── documents/
│           ├── reminders/
│           ├── geofence/
│           └── home/
```
