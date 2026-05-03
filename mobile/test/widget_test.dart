// Atomic widget tests. The full GarageApp boot is integration-level (touches
// secure-storage, notifications plugin, secure-storage-backed permissions
// flag, geolocator, etc.) so it lives in `integration_test/` not here.
//
// These unit tests exercise pure widget pieces that don't hit the platform.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:garage/core/theme/app_theme.dart';
import 'package:garage/features/home/splash_screen.dart';

void main() {
  testWidgets('AppTheme builds light + dark variants', (tester) async {
    final light = AppTheme.light;
    final dark = AppTheme.dark;

    expect(light.brightness, Brightness.light);
    expect(dark.brightness, Brightness.dark);
    expect(light.useMaterial3, isTrue);
    expect(dark.useMaterial3, isTrue);
  });

  testWidgets('SplashScreen renders the brand icon + spinner', (tester) async {
    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.light, home: const SplashScreen()),
    );
    expect(find.byType(SplashScreen), findsOneWidget);
    expect(find.byIcon(Icons.directions_car_filled), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });
}
