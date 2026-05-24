# Garage — Handoff Notes

Snapshot of the work that landed on `main` during the 2026-05-23 → 2026-05-24 session. Aimed at the next person to open this repo.

## Where we left it

The app is a Flutter mobile client backed by a Node/TypeScript/Express server with Prisma + Postgres on Neon. It runs on Android (TECNO Camon 18P verified) and is set up for iOS via Xcode personal team. Five locked features all work end to end: multi-car profiles, predictive next-fill-up, smart service reminders, receipt OCR via Gemini multimodal, and geofenced auto-logging.

What the demo currently shows live on a real Android device:
- Auth (register / login / token refresh via single-flight interceptor)
- Multi-car switcher (bottom-sheet)
- Hero predict-next card on home dashboard
- Predict-explain modal (Gemini)
- OCR pipeline (Gemini multimodal extracts liters/price/total/station/date from a synthetic receipt in ~7s)
- Maintenance create with green "saved" toast
- Reminder create with AI-phrased message + StatusChip + projection
- Reminders list using the proper `/reminders` endpoint (no LLM thrash)
- Local notification scheduling pipeline (alarms reach AlarmManager — see "Known issues" for the OEM caveat)
- All forms with consistent success/error feedback toasts

## What changed in this session

### Android-side platform work
The app shipped iOS-only originally. We brought Android up to functional parity:

- **AndroidManifest.xml** — full permissions set: `INTERNET`, `ACCESS_NETWORK_STATE`, `CAMERA`, `READ_MEDIA_IMAGES`, `READ_EXTERNAL_STORAGE` (maxSdk 32), `ACCESS_FINE_LOCATION`, `ACCESS_COARSE_LOCATION`, `ACCESS_BACKGROUND_LOCATION`, `ACTIVITY_RECOGNITION` (+ GMS variant), `POST_NOTIFICATIONS`, `VIBRATE`, `WAKE_LOCK`, `RECEIVE_BOOT_COMPLETED`, `SCHEDULE_EXACT_ALARM`, `USE_EXACT_ALARM`. Added the uCrop activity declaration. Enabled `usesCleartextTraffic` so dev HTTP works (toggle off for prod).
- **build.gradle.kts** — enabled `isCoreLibraryDesugaringEnabled` and added `coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")` — required by `flutter_local_notifications` v17.
- **Package rename** — `com.omar.garage` → `com.garage.app`. Touched `build.gradle.kts` (namespace + applicationId), `MainActivity.kt` (package line + folder move from `com/omar/garage/` to `com/garage/app/`), `Runner.xcodeproj/project.pbxproj` (PRODUCT_BUNDLE_IDENTIFIER for both Runner and RunnerTests targets). Old app uninstalled cleanly.

### Backend additions

- **OpenAI LLM provider**. Implemented `OpenAiProvider implements LlmProvider` in `backend/src/services/llm.ts` alongside the existing `GeminiProvider`. Hoisted `withTimeout` to module scope. Wired the `case 'openai':` branch in the `llm()` factory. Env vars added: `OPENAI_API_KEY`, `OPENAI_MODEL` (default `gpt-4o-mini`). All three LLM touchpoints (OCR, reminder phrasing, predict-explain) now work transparently with either provider — pure swap via `LLM_PROVIDER=openai|gemini` in `.env`. Type-checked, no feature code touched.
- **`reminders.service.ts:listForCar` enriched**. Now returns reminders with deterministic `predictedDate` + `daysRemaining` (via the existing `projectNextDate` helper) and surfaces any cached `aiMessage`. No LLM call. Sort by predictedDate ascending; unprojectable items last. This is the correct fix for what was previously a bandaid (see "Bandaids corrected" below).
- **`gas-stations.service.ts:findNearby` honors `limit`**. Schema accepts `limit` (max 20, capped at the iOS CLCircularRegion ceiling), route passes it through. `.strict()` restored.
- **`middleware/error.ts` handles MulterError**. `LIMIT_FILE_SIZE` → clean `413 FILE_TOO_LARGE`, `LIMIT_UNEXPECTED_FILE`/`LIMIT_FILE_COUNT` → `400`. No more silent `500`s on oversized uploads. Cap stays at 5 MB.
- **`fuel.schemas.ts:updateFuelSchema` accepts null**. `station`, `notes`, `latitude`, `longitude`, `receiptPhotoUrl` use `.nullish()` instead of `.optional()` so the mobile edit form can clear a field by sending `null`.

### Mobile additions

- **Fuel edit, which was missing**. `AddFuelScreen` extended with optional `existing: FuelEntry?` constructor param. In edit mode, the form is seeded from the entry and `_save()` calls `PATCH /fuel/:id` via the existing `FuelApi.update()`. New go_router route `/cars/:id/fuel/:fuelId/edit`. Fuel list cards wrapped in `InkWell` that pushes the edit route with the entry as `extra`. AppBar title and save button label adapt.
- **`remindersListProvider` calls the right endpoint**. Now `listForCar()` → `GET /reminders` instead of `/due?withinDays=99999`. 3.5× faster on list open, zero LLM cost.
- **Shared success/error feedback**. `lib/core/ui/feedback.dart` exports `showFeedback(context, message, {isError})`. Used by every add/edit screen (cars, fuel, maintenance, documents, reminders). Green token for success, red token for errors, longer duration on errors. Replaces ad-hoc SnackBar calls.

### UI rebuild (token-based design system)

- **`lib/core/theme/tokens.dart`** — single source of truth for colors. Brand: deep navy primary, warm amber accent. Semantic: success / warning / danger. Surface, surface-elev, outline tokens for light and dark. Exposed via `GarageColors` `ThemeExtension` and a `context.tokens` extension method.
- **`lib/core/theme/app_theme.dart`** — full rewrite using tokens. Inter for body, Space Grotesk for display (numbers, headlines) via `google_fonts`. Refined card / button / input / chip / FAB / snackbar themes.
- **`lib/core/ui/status_chip.dart`** — `StatusChip.overdue` / `.dueSoon` / `.ok` / `.info`, all token-driven. Used across home banners, reminder cards, document cards.
- **Home dashboard** — `_OkCard` rebuilt as a navy-gradient hero with 56–64sp Space Grotesk number and amber tank gauge. `_AlertBanner` shared shell for expiring-docs + due-reminders banners. `_CarHeader` opens a bottom-sheet car switcher on tap. `_ActionTile` chips use amber-tinted icon squares.
- **Car detail tabs** — tab bar got icons. Reminder card now shows "Due {date}" as the headline with a `StatusChip` in the corner; AI message lives in an amber-tinted callout. Document card uses a square type-icon + chip. Fuel and maintenance cards aligned to the same square-icon pattern with cost/litres in the accent color.
- **Auth screens** — brand navy gradient backdrop, white logo card, white form card, white CTA text. Same pattern on login and register.

### Test infrastructure

- **`backend/scripts/make-test-receipt.ts`** — generates a synthetic Lebanese gas-pump receipt JPEG via `sharp`. Output at `backend/uploads/test/receipt.jpg`.
- **`backend/scripts/seed-alaa.ts`** — seeds 25 realistic fuel entries on the primary user's Mercedes (~6 months of data, mix of full/partial tanks, ~42 km/day pace). Idempotent — clears existing entries before insert. Rename + parameterize the `EMAIL` constant if you target a different user.
- **`backend/scripts/shift-due-date.ts`** — shifts a document expiry or a reminder lastDoneDate so the SchedulingSync `-30d` notification fires N seconds from now. Used to validate the local-notification pipeline end-to-end without waiting 30 days.
- **Phone-side test asset** pushed via adb to `/sdcard/Android/data/com.garage.app/files/garage-test/receipt.jpg`. Read by the debug OCR bypass below.
- **`OcrCameraScreen` debug button** (`kDebugMode` only) — "Pick test receipt" bypasses the system gallery picker entirely and reads from `garage-test/receipt.jpg`. Keeps the user's photo library completely out of adb-driven testing.
- **`SettingsScreen` debug buttons** (`kDebugMode` only) — "Fire test notification in 60s" (schedules a one-shot via `scheduleAt`) and "Force schedule resync" (re-runs `SchedulingSync.syncForAllCars`).

## Bandaids corrected (the right way)

Two patches I shipped during the test loop turned out to be smoothing over the real issue. Both have been replaced with proper fixes:

### Bandaid #1 — `/reminders/due?withinDays=99999`
The mobile reminders-list screen was calling `/due` with a junk-large horizon to get the projection data, costing a Gemini call per row on every list open. The real fix:
- Backend: `listForCar` now returns the projection deterministically (no LLM) + surfaces cached aiMessage if present.
- Mobile: `remindersListProvider` calls `listForCar` (→ `GET /reminders`).
- Backend: `dueQuerySchema.withinDays` capped back to `max(60)` — `/due` is for the home banner only.

### Bandaid #2 — `.strict()` removed from gas-stations
The mobile was sending `&limit=10` which the strict schema rejected with a 400. The bandaid removed strict and added `limit` as accepted-but-ignored. The real fix:
- Schema: `limit` is typed `int positive max(20) default(20)`. `.strict()` restored.
- Service: `findNearby(lat, lng, radiusKm, limit)` was already there; route now passes `limit` through.

## How to run

Prereqs: Node 20+, Flutter 3.x, Neon Postgres project, Google AI Studio API key (or OpenAI key). For Android testing: Android SDK + adb on PATH (or use the SDK's `platform-tools` directly).

```bash
# 1) Backend
cd backend
cp .env.example .env
# fill DATABASE_URL, DIRECT_URL (Neon pooled + direct), JWT_*_SECRET, LLM provider
npm install
npx prisma migrate deploy
npx tsx prisma/seed.ts     # demo user demo@garage.app / demo1234
npm run dev                # http://localhost:3000

# 2) Mobile (Android, USB-tethered)
cd ../mobile
flutter pub get
adb reverse tcp:3000 tcp:3000     # phone's localhost → PC backend
flutter build apk --debug --dart-define=API_BASE_URL=http://localhost:3000
adb install -r build/app/outputs/flutter-apk/app-debug.apk

# 3) Optional — seed a realistic dataset on a registered user
cd ../backend
npx tsx scripts/seed-alaa.ts      # edit EMAIL constant to target your user

# 4) Optional — test OCR with a synthetic receipt
npx tsx scripts/make-test-receipt.ts
adb push uploads/test/receipt.jpg /sdcard/Android/data/com.garage.app/files/garage-test/receipt.jpg
# In the app: Scan Receipt → "debug · pick test receipt"
```

For iOS: open `mobile/ios/Runner.xcworkspace` in Xcode, set Team under Signing, `flutter run --dart-define=API_BASE_URL=http://<mac-LAN-ip>:3000`. Free Apple certs expire every 7 days.

## Known issues

### TECNO HiOS suppresses scheduled local notifications
On this device (and most TECNO / Infinix / Itel handsets), `scheduleAt` correctly queues alarms in `AlarmManager` (verified via `dumpsys alarm`) but HiOS Power Marshall kills the receiver broadcast when the app is backgrounded. The notification never posts. `showNow()` (used by the geofence-arrival flow) does fire because it runs in-process.

This is **not a code bug** — it's an OEM policy. Two practical responses:
1. Document the whitelist procedure for end users: Settings → Apps → Garage → Battery → "No restrictions"; Settings → Security → Permissions → Autostart → enable Garage; recent-apps "Lock in memory" gesture.
2. Don't add a foreground service to bully the OS — it breaks the battery/privacy contract the spec explicitly chose to honor.

Other OEMs with the same behavior: Xiaomi/MIUI, Oppo/ColorOS, Vivo/FuntouchOS. Stock Android (Pixel) and Samsung One UI honor scheduled alarms correctly.

### Document upload error path was 500 (now fixed)
Prior to this session, uploading a PDF >5 MB returned `500 Internal Server Error` with no useful client message. Now returns `413 FILE_TOO_LARGE` with a clean toast. Limit kept at 5 MB.

### Mobile-side file-size validation is absent
The client doesn't pre-check file size before upload; it submits and shows the server's error. Adding a `file_picker` size check before the multipart send is a 10-minute addition — left for next person if needed.

### Reminder km vs calendar projection
When a reminder has both `intervalKm` and `intervalMonths`, the projection takes `min(kmLeg, calendarLeg)`. If the car's km is already past the threshold (`kmRemaining ≤ 0`), the km leg projects to "today" and wins, which silently masks the calendar leg. Not a blocker but worth a comment / UX hint when both intervals are entered together.

### iOS test path not driven this session
All adb-driven verification ran on Android. iOS paths (CLCircularRegion-backed geofences, Keychain storage, free-cert background-modes workaround) were not exercised live in this session. Code changes were Android- and backend-focused; iOS-specific code paths weren't touched.

## Architectural decisions worth knowing

- **LLM provider is env-selected, not per-call.** Switch between Gemini and OpenAI with `LLM_PROVIDER` in `.env`. Per-feature routing (e.g. OCR via OpenAI, explainer via Gemini) is a ~50-line extension if needed later — single `getLlm(feature)` resolver + per-feature env vars.
- **Tokens-first theming.** Never hardcode `Color(0xFF...)` outside `lib/core/theme/tokens.dart`. Use `context.tokens.warning` etc. The grep `Color(0xFF` was zero across `lib/` post-cleanup; any new literal will stand out in review.
- **Feedback is global.** `showFeedback(context, message, {isError})` is the only path for success/error toasts. Resist the urge to recreate per-screen SnackBars — keep the visual contract consistent.
- **`/reminders` vs `/reminders/due` have distinct contracts.** Full list = no LLM, deterministic projection only. Due-soon = LLM-enriched, capped 60-day horizon. Don't conflate again.
- **Gas-stations `limit` is bounded by the iOS region cap (20).** Not negotiable — increasing it doesn't help because iOS will silently drop registrations.
- **Edit flows reuse the Add screen.** AddFuelScreen takes an optional `existing` to mean "edit mode." If you add a new editable feature, repurpose the existing form rather than duplicating it.

## Suggested next work, prioritized

1. **Foreground-service docs in-app**. One-time card on first launch: "If you want background notifications to fire reliably on your device, whitelist Garage in Battery → No restrictions." Same UX every messaging app uses.
2. **Reminder km-vs-calendar UX**. When the user sets both intervals and they conflict (km already past), show an inline warning in the form so they know the calendar leg won't be used.
3. **Maintenance ↔ reminder cross-update**. Logging a maintenance entry should optionally update the matching reminder's `lastDoneKm` / `lastDoneDate`. Currently they're independent — the user has to update both.
4. **Document picker file-size precheck**. Client-side `file_picker` check before upload.
5. **Phase E illustrations**. SVG empty-state art for the four list screens (fuel, maintenance, documents, reminders). Current empty states are functional with icons + token colors, but illustrations would lift them further.
6. **iOS verification pass**. None of this session's work was exercised on iOS. Worth a half-day to confirm the new package id, the Inter / Space Grotesk fonts, and the theme tokens all render correctly.

## File map of new / heavily changed files

```
backend/
  src/middleware/error.ts                    ← MulterError → 413
  src/services/llm.ts                        ← OpenAiProvider
  src/config/env.ts                          ← OPENAI_* vars
  src/modules/reminders/reminders.service.ts ← listForCar enriched
  src/modules/reminders/reminders.schemas.ts ← withinDays max(60)
  src/modules/gas-stations/gas-stations.schemas.ts ← limit, .strict()
  src/modules/gas-stations/gas-stations.routes.ts  ← pass limit through
  src/modules/fuel/fuel.schemas.ts           ← .nullish() for clearable fields
  scripts/make-test-receipt.ts               ← new
  scripts/seed-alaa.ts                       ← new (parameterize EMAIL)
  scripts/shift-due-date.ts                  ← new

mobile/
  android/app/build.gradle.kts               ← namespace + applicationId + desugaring
  android/app/src/main/AndroidManifest.xml   ← full permissions + uCrop activity
  android/app/src/main/kotlin/com/garage/app/MainActivity.kt  ← moved + repackaged
  ios/Runner.xcodeproj/project.pbxproj       ← bundle id renames
  pubspec.yaml                               ← google_fonts dep
  lib/core/theme/tokens.dart                 ← new
  lib/core/theme/app_theme.dart              ← full rewrite
  lib/core/ui/feedback.dart                  ← new
  lib/core/ui/status_chip.dart               ← new
  lib/app.dart                               ← /fuel/:fuelId/edit route
  lib/features/home/home_screen.dart         ← hero card, alert banner, switcher sheet
  lib/features/cars/presentation/car_detail_screen.dart ← tab icons
  lib/features/fuel/presentation/add_fuel_screen.dart   ← edit mode
  lib/features/fuel/presentation/fuel_list_screen.dart  ← tap-to-edit, new card design
  lib/features/fuel/presentation/ocr_camera_screen.dart ← debug bypass
  lib/features/reminders/data/reminders_api.dart        ← listForCar provider
  lib/features/reminders/presentation/reminders_list_screen.dart ← StatusChip card
  lib/features/documents/presentation/documents_list_screen.dart ← chip card
  lib/features/maintenance/presentation/maintenance_list_screen.dart ← polished card
  lib/features/auth/presentation/login_screen.dart      ← gradient backdrop
  lib/features/auth/presentation/register_screen.dart   ← gradient backdrop
  lib/features/geofence/presentation/settings_screen.dart ← 2 debug buttons
  lib/features/cars/presentation/add_car_screen.dart      ← showFeedback
  lib/features/maintenance/presentation/add_maintenance_screen.dart ← showFeedback
  lib/features/documents/presentation/add_document_screen.dart ← showFeedback
  lib/features/reminders/presentation/add_reminder_screen.dart ← showFeedback
```

## Out of scope decisions left untouched

- Spec §2 exclusions still apply: no AI chatbot, no weekly insights, no mechanics directory, no bilingual EN/AR, no OBD-II, no FCM/APNs, no LBP currency, no charts.
- Spec §16 LLM touchpoints (OCR, reminder phrasing, predict-explainer) work; no new LLM features added.
- iOS-only constraint from the original spec is now relaxed — the app runs on Android too with full feature parity (modulo the OEM notification caveat above).
