// Widget tests for the Android-only battery-whitelist card on the
// PermissionsScreen onboarding flow.
//
// The card is a private `_BatteryWhitelistCard` widget gated by
// `defaultTargetPlatform == TargetPlatform.android`. We assert behavior via
// the unique copy "Background reliability" rather than reaching for the
// private class.
//
// The screen reads notificationsServiceProvider and permissionsSeenStoreProvider
// only inside button callbacks — pumping the widget without tapping anything
// won't fire platform channels, so no provider overrides are required for
// these visibility-only assertions.

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:garage/core/theme/app_theme.dart';
import 'package:garage/features/permissions/presentation/permissions_screen.dart';

void main() {
  group('PermissionsScreen — Android-only battery whitelist card', () {
    Widget pump() {
      return ProviderScope(
        child: MaterialApp(
          theme: AppTheme.light,
          home: const PermissionsScreen(),
        ),
      );
    }

    /// Runs `body` with the foundation platform override set to `platform`,
    /// resetting the override inside the test body (before flutter_test's
    /// `_verifyInvariants` debug-vars check runs at end-of-test). A group
    /// `tearDown` or `addTearDown` would fire after that check and trip
    /// `debugAssertAllFoundationVarsUnset`.
    Future<void> withTargetPlatform(
      TargetPlatform platform,
      Future<void> Function() body,
    ) async {
      final original = debugDefaultTargetPlatformOverride;
      debugDefaultTargetPlatformOverride = platform;
      try {
        await body();
      } finally {
        debugDefaultTargetPlatformOverride = original;
      }
    }

    testWidgets('battery whitelist card is visible on Android',
        (tester) async {
      await withTargetPlatform(TargetPlatform.android, () async {
        await tester.pumpWidget(pump());
        await tester.pumpAndSettle();
        // Card title + the in-app settings CTA both confirm the card
        // mounted.
        expect(find.text('Background reliability'), findsOneWidget);
        expect(find.text('Open app settings'), findsOneWidget);
      });
    });

    testWidgets('battery whitelist card is hidden on iOS', (tester) async {
      await withTargetPlatform(TargetPlatform.iOS, () async {
        await tester.pumpWidget(pump());
        await tester.pumpAndSettle();
        // OEM card belongs to Android only — iOS / iPadOS don't have the
        // background-broadcast-killer problem.
        expect(find.text('Background reliability'), findsNothing);
        expect(find.text('Open app settings'), findsNothing);
      });
    });

    testWidgets(
        'battery whitelist card is hidden on other platforms (e.g. macOS)',
        (tester) async {
      await withTargetPlatform(TargetPlatform.macOS, () async {
        await tester.pumpWidget(pump());
        await tester.pumpAndSettle();
        expect(find.text('Background reliability'), findsNothing);
      });
    });
  });
}
