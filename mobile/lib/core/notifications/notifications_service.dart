import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'notification_ids_store.dart';

/// A single notification tap event — emitted whether the tap happened while
/// the app was foreground/background OR was the cause of a cold start.
@immutable
class NotificationTap {
  const NotificationTap({required this.payload, this.route});

  /// Decoded payload map, never null. Empty if the source notification had
  /// no payload.
  final Map<String, String> payload;

  /// Convenience accessor for `payload['route']`. Used by the deep-link
  /// handler in `app.dart` to call `router.go(route)`.
  final String? route;

  @override
  String toString() => 'NotificationTap(route: $route, payload: $payload)';
}

/// Channel keys used for Android notification channels. iOS ignores these
/// (it groups by `categoryIdentifier` instead) but they're required on
/// Android.
class NotificationChannel {
  const NotificationChannel._();

  /// Reminder + document expiry alerts. Default importance — these are
  /// scheduled days/weeks in advance, no need to override DND.
  static const reminders = 'garage.reminders';

  /// Geofence-entry "you arrived at [station]" prompts. High importance so
  /// the banner shows over the lock screen if the user has just parked.
  static const geofence = 'garage.geofence';
}

/// Wraps [FlutterLocalNotificationsPlugin] with:
///   - one-shot init (timezone db + iOS/Android settings + tap handlers)
///   - permission request via `permission_handler`
///   - absolute-time scheduling with persisted `key -> notificationId` map
///     so we can cancel + reschedule cleanly when projection dates shift
///   - foreground & cold-start tap stream that the router subscribes to
class NotificationsService {
  NotificationsService({
    FlutterLocalNotificationsPlugin? plugin,
    NotificationIdsStore? idsStore,
  })  : _plugin = plugin ?? FlutterLocalNotificationsPlugin(),
        _idsStore = idsStore ??
            NotificationIdsStore(
              const FlutterSecureStorage(
                iOptions: IOSOptions(
                  accessibility: KeychainAccessibility.first_unlock,
                ),
              ),
            );

  final FlutterLocalNotificationsPlugin _plugin;
  final NotificationIdsStore _idsStore;
  final Random _rng = Random.secure();
  final StreamController<NotificationTap> _taps =
      StreamController<NotificationTap>.broadcast();

  bool _initialized = false;

  /// Tap stream — fires for foreground taps, background taps that wake the
  /// app, and the cold-start tap (forwarded once during [init]).
  Stream<NotificationTap> get onTap => _taps.stream;

  // ---------------------------------------------------------------------------
  // Init / permissions
  // ---------------------------------------------------------------------------

  /// Idempotent. Safe to call multiple times — only the first call does work.
  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    // Required so `tz.TZDateTime` / `zonedSchedule` work. Plugin will throw a
    // misleading `InvalidArgumentException` without this.
    tzdata.initializeTimeZones();
    // We don't depend on `flutter_native_timezone`; `tz.local` falls back to
    // the host's IANA name when the platform exposes it, otherwise UTC. For
    // the demo (single-timezone iPhone) this is fine.

    final initSettings = InitializationSettings(
      android: const AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(
        // We DON'T request these here — the explicit `requestPermission()`
        // call from the permissions screen drives the prompt. Setting these
        // to false avoids the system asking on first init.
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
        // Foreground presentation — we want the banner+sound+badge even when
        // the app is open, so the user actually sees the prompt.
        defaultPresentAlert: true,
        defaultPresentBadge: true,
        defaultPresentSound: true,
        notificationCategories: <DarwinNotificationCategory>[
          DarwinNotificationCategory(
            'garage.geofence',
            actions: <DarwinNotificationAction>[
              DarwinNotificationAction.plain('LOG_FUEL', 'Log fuel'),
              DarwinNotificationAction.plain('DISMISS', 'Dismiss'),
            ],
            options: <DarwinNotificationCategoryOption>{
              DarwinNotificationCategoryOption.hiddenPreviewShowTitle,
            },
          ),
          DarwinNotificationCategory(
            'garage.reminders',
            options: <DarwinNotificationCategoryOption>{
              DarwinNotificationCategoryOption.hiddenPreviewShowTitle,
            },
          ),
        ],
      ),
    );

    await _plugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _onResponse,
    );

    // Pre-create the Android channels. Idempotent on the platform side.
    final android =
        _plugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    if (android != null) {
      await android.createNotificationChannel(
        const AndroidNotificationChannel(
          NotificationChannel.reminders,
          'Reminders & document expiry',
          description: 'Service reminders and document expiry alerts.',
          importance: Importance.defaultImportance,
        ),
      );
      await android.createNotificationChannel(
        const AndroidNotificationChannel(
          NotificationChannel.geofence,
          'Gas station arrivals',
          description: 'Prompts to log a fill-up when you arrive at a station.',
          importance: Importance.high,
        ),
      );
    }

    // Cold-start handling. If the app was launched by tapping a notification,
    // surface that tap on `onTap` so the router redirect picks it up. We
    // delay by a microtask so listeners attached during the same frame
    // (router provider building) get the event.
    final launch = await _plugin.getNotificationAppLaunchDetails();
    if (launch?.didNotificationLaunchApp ?? false) {
      final response = launch!.notificationResponse;
      if (response != null) {
        scheduleMicrotask(() => _onResponse(response));
      }
    }
  }

  /// Explicit permission prompt — called from the permissions explainer
  /// screen (and re-callable from Settings later if the user changes mind).
  ///
  /// Returns true if alert permission is now granted. On Android 13+ this
  /// triggers the runtime POST_NOTIFICATIONS prompt; on older Android it's
  /// a no-op true. On iOS it triggers the standard permission alert with
  /// alert + badge + sound requested.
  Future<bool> requestPermission() async {
    // iOS path
    final ios = _plugin.resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>();
    if (ios != null) {
      final granted = await ios.requestPermissions(
            alert: true,
            badge: true,
            sound: true,
          ) ??
          false;
      return granted;
    }

    // Android path — use permission_handler so we get the same UX on
    // Android 13+. On older Android the call resolves to true immediately.
    final status = await Permission.notification.request();
    return status.isGranted;
  }

  // ---------------------------------------------------------------------------
  // Scheduling
  // ---------------------------------------------------------------------------

  /// Schedules an absolute-time notification. Returns the locally-generated
  /// notification id (caller can later pass it to [cancel]).
  ///
  /// Past `when` values are silently dropped (returns `-1`) — callers in
  /// [SchedulingSync] precheck this, but we belt-and-brace here too.
  ///
  /// `payload` is JSON-encoded into the platform `payload: String` slot.
  Future<int> scheduleAt(
    DateTime when, {
    required String title,
    required String body,
    required Map<String, String> payload,
    String? channelKey,
  }) async {
    if (!when.isAfter(DateTime.now())) return -1;

    final id = _rng.nextInt(0x7FFFFFFF);
    final tzWhen = tz.TZDateTime.from(when, tz.local);

    await _plugin.zonedSchedule(
      id,
      title,
      body,
      tzWhen,
      _details(channelKey),
      payload: jsonEncode(payload),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      // Required arg in v17. We always pass an absolute zoned time so wall
      // vs absolute interpretation doesn't matter; pick absoluteTime to keep
      // the alarm at exactly that instant even across DST transitions.
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
    );

    return id;
  }

  /// Fires immediately. Used by the "Simulate Geofence Entry" debug button
  /// (the geofencing agent calls this from their dwell handler too).
  Future<int> showNow({
    required String title,
    required String body,
    Map<String, String>? payload,
    String? channelKey,
  }) async {
    final id = _rng.nextInt(0x7FFFFFFF);
    await _plugin.show(
      id,
      title,
      body,
      _details(channelKey ?? NotificationChannel.geofence),
      payload: jsonEncode(payload ?? const <String, String>{}),
    );
    return id;
  }

  Future<void> cancel(int id) => _plugin.cancel(id);

  Future<void> cancelAll() async {
    await _plugin.cancelAll();
    await _idsStore.drainAll();
  }

  // ---------------------------------------------------------------------------
  // Keyed scheduling (used by SchedulingSync)
  // ---------------------------------------------------------------------------

  /// Schedules under a stable scheduling key (e.g. `reminder:abc:30d`).
  /// If a previous notification was scheduled under the same key, it's
  /// cancelled first. This makes "reschedule on date shift" trivial.
  ///
  /// Returns the new notification id, or `null` if `when` is in the past
  /// (in which case any existing scheduled notification under [key] is
  /// still cancelled — callers don't want stale notifications to fire).
  Future<int?> scheduleKeyed(
    String key,
    DateTime when, {
    required String title,
    required String body,
    required Map<String, String> payload,
    String? channelKey,
  }) async {
    await cancelKeyed(key);
    if (!when.isAfter(DateTime.now())) return null;

    final id = await scheduleAt(
      when,
      title: title,
      body: body,
      payload: payload,
      channelKey: channelKey,
    );
    if (id < 0) return null;
    await _idsStore.write(key, id);
    return id;
  }

  /// Cancels whatever (if anything) was scheduled under [key]. Safe to call
  /// when no scheduled notification exists.
  Future<void> cancelKeyed(String key) async {
    final existing = await _idsStore.read(key);
    if (existing != null) {
      await _plugin.cancel(existing);
      await _idsStore.remove(key);
    }
  }

  // ---------------------------------------------------------------------------
  // Internal
  // ---------------------------------------------------------------------------

  NotificationDetails _details(String? channelKey) {
    final ch = channelKey ?? NotificationChannel.reminders;
    return NotificationDetails(
      android: AndroidNotificationDetails(
        ch,
        ch == NotificationChannel.geofence
            ? 'Gas station arrivals'
            : 'Reminders & document expiry',
        channelDescription: ch == NotificationChannel.geofence
            ? 'Prompts to log a fill-up when you arrive at a station.'
            : 'Service reminders and document expiry alerts.',
        importance: ch == NotificationChannel.geofence
            ? Importance.high
            : Importance.defaultImportance,
        priority: ch == NotificationChannel.geofence
            ? Priority.high
            : Priority.defaultPriority,
      ),
      iOS: DarwinNotificationDetails(
        categoryIdentifier: ch,
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      ),
    );
  }

  void _onResponse(NotificationResponse response) {
    final raw = response.payload;
    Map<String, String> payload = const {};
    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          payload = decoded.map((k, v) => MapEntry(k.toString(), v.toString()));
        }
      } catch (_) {
        // unknown / malformed payload — emit empty.
      }
    }
    _taps.add(NotificationTap(payload: payload, route: payload['route']));
  }

  Future<void> dispose() async {
    await _taps.close();
  }
}

// -----------------------------------------------------------------------------
// Riverpod wiring
// -----------------------------------------------------------------------------

/// Singleton notifications service. Disposed automatically when the provider
/// container shuts down (test cleanup mostly).
final notificationsServiceProvider = Provider<NotificationsService>((ref) {
  final svc = NotificationsService();
  ref.onDispose(svc.dispose);
  return svc;
});

/// Boots the notifications layer once at app launch. The router watches this
/// (via `app.dart`) so the deep-link handler attaches before the cold-start
/// tap is replayed onto `onTap`.
final initNotificationsProvider = FutureProvider<void>((ref) async {
  await ref.read(notificationsServiceProvider).init();
});
