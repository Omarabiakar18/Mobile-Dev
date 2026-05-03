// Widget + provider unit tests. They exercise rendering, state branching,
// and pure parsing — no platform plugins, no real network.
//
// The full GarageApp boot is integration-level (touches secure-storage,
// notifications plugin, secure-storage-backed permissions flag, geolocator
// etc.) so it doesn't live here. These tests run in seconds and catch the
// regressions that actually break the demo: empty/error rendering, model
// parsing, theme construction.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:garage/core/api/api_exception.dart';
import 'package:garage/core/theme/app_theme.dart';
import 'package:garage/features/cars/data/car_model.dart';
import 'package:garage/features/cars/data/cars_api.dart';
import 'package:garage/features/cars/presentation/cars_list_screen.dart';
import 'package:garage/features/home/splash_screen.dart';

void main() {
  // --- theme ---------------------------------------------------------------
  group('AppTheme', () {
    testWidgets('builds light + dark variants with Material 3', (tester) async {
      final light = AppTheme.light;
      final dark = AppTheme.dark;

      expect(light.brightness, Brightness.light);
      expect(dark.brightness, Brightness.dark);
      expect(light.useMaterial3, isTrue);
      expect(dark.useMaterial3, isTrue);
    });
  });

  // --- splash --------------------------------------------------------------
  group('SplashScreen', () {
    testWidgets('renders the brand icon + spinner', (tester) async {
      await tester.pumpWidget(
        MaterialApp(theme: AppTheme.light, home: const SplashScreen()),
      );
      expect(find.byType(SplashScreen), findsOneWidget);
      expect(find.byIcon(Icons.directions_car_filled), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });
  });

  // --- car model parsing ---------------------------------------------------
  group('Car.fromJson', () {
    test('parses a fully-populated record', () {
      final car = Car.fromJson({
        'id': 'car_1',
        'userId': 'usr_1',
        'make': 'Range Rover',
        'model': 'Sport',
        'year': 2018,
        'plate': '123 ABC',
        'color': 'Black',
        'currentKm': 120000,
        'fuelType': 'gasoline',
        'tankSize': '85.0',
        'photoUrl': null,
        'avgKmPerDay': '42.7',
        'createdAt': '2025-01-01T00:00:00.000Z',
        'updatedAt': '2025-01-02T00:00:00.000Z',
      });

      expect(car.displayName, '2018 Range Rover Sport');
      expect(car.fuelType, FuelType.gasoline);
      expect(car.tankSize, 85.0);
      expect(car.avgKmPerDay, 42.7);
    });

    test('handles null avgKmPerDay (new car, no fuel history yet)', () {
      final car = Car.fromJson({
        'id': 'car_2',
        'userId': 'usr_1',
        'make': 'Toyota',
        'model': 'Prius',
        'year': 2022,
        'plate': '456 DEF',
        'color': null,
        'currentKm': 0,
        'fuelType': 'gasoline',
        'tankSize': 43.0,
        'photoUrl': null,
        'avgKmPerDay': null,
        'createdAt': '2025-01-01T00:00:00.000Z',
        'updatedAt': '2025-01-01T00:00:00.000Z',
      });

      expect(car.avgKmPerDay, isNull);
      expect(car.color, isNull);
    });

    test('coerces unknown fuelType strings to gasoline (defensive)', () {
      final car = Car.fromJson({
        'id': 'car_3',
        'userId': 'usr_1',
        'make': 'X',
        'model': 'Y',
        'year': 2020,
        'plate': 'P',
        'currentKm': 0,
        'fuelType': 'rocket-fuel',
        'tankSize': 50,
        'createdAt': '2025-01-01T00:00:00.000Z',
        'updatedAt': '2025-01-01T00:00:00.000Z',
      });

      expect(car.fuelType, FuelType.gasoline);
    });
  });

  // --- cars list screen — state branches -----------------------------------
  group('CarsListScreen', () {
    Widget pump(Override carsOverride) {
      return ProviderScope(
        overrides: [carsOverride],
        child: MaterialApp(
          theme: AppTheme.light,
          home: const CarsListScreen(),
        ),
      );
    }

    testWidgets('loading state shows a spinner', (tester) async {
      await tester.pumpWidget(
        pump(carsListProvider.overrideWith((_) => _never<List<Car>>())),
      );
      // First frame is loading.
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      // Pump pending future so analyzers don't whine — we want the test to
      // exit cleanly with the future unresolved. Flutter test framework
      // tolerates this via runAsync.
    });

    testWidgets('empty state shows the empty-CTA + FAB', (tester) async {
      await tester.pumpWidget(
        pump(carsListProvider.overrideWith((_) => Future.value(<Car>[]))),
      );
      await tester.pumpAndSettle();

      // Empty-state copy + the "Add car" FAB.
      expect(find.text('No cars yet'), findsOneWidget);
      expect(find.byType(FloatingActionButton), findsOneWidget);
    });

    testWidgets('error state shows ApiException message + retry', (tester) async {
      await tester.pumpWidget(
        pump(carsListProvider.overrideWith(
          (_) => Future<List<Car>>.error(
            ApiException(500, 'INTERNAL', 'server fell over'),
          ),
        )),
      );
      await tester.pumpAndSettle();

      expect(find.text('server fell over'), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
    });

    testWidgets('data state lists every car by displayName', (tester) async {
      final cars = [
        _car(id: 'c1', make: 'Range Rover', model: 'Sport', year: 2018),
        _car(id: 'c2', make: 'Toyota', model: 'Prius', year: 2022),
      ];
      await tester.pumpWidget(
        pump(carsListProvider.overrideWith((_) => Future.value(cars))),
      );
      await tester.pumpAndSettle();

      expect(find.text('2018 Range Rover Sport'), findsOneWidget);
      expect(find.text('2022 Toyota Prius'), findsOneWidget);
    });
  });
}

// --- helpers ----------------------------------------------------------------

/// A future that never completes — used to pin a provider in the loading state
/// for testing.
Future<T> _never<T>() => Completer<T>().future;

Car _car({
  required String id,
  required String make,
  required String model,
  required int year,
}) {
  return Car(
    id: id,
    userId: 'usr_1',
    make: make,
    model: model,
    year: year,
    plate: 'TEST',
    color: null,
    currentKm: 100000,
    fuelType: FuelType.gasoline,
    tankSize: 60,
    photoUrl: null,
    avgKmPerDay: 30,
    createdAt: DateTime(2025, 1, 1),
    updatedAt: DateTime(2025, 1, 1),
  );
}
