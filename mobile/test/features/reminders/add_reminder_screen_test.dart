// Widget tests for the km-vs-calendar conflict banner on the Add Reminder
// screen.
//
// The banner is a private `_ConflictBanner` driven by `_kmConflictMessage`.
// We assert behavior via the unique warning copy ("past the km threshold")
// rather than trying to find the private class directly.
//
// The screen reads `carsListProvider` to derive `currentKm` for the loaded
// car; we override it with a fixed list containing one fake car whose id
// matches the screen's `carId`.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:garage/core/theme/app_theme.dart';
import 'package:garage/features/cars/data/car_model.dart';
import 'package:garage/features/cars/data/cars_api.dart';
import 'package:garage/features/reminders/presentation/add_reminder_screen.dart';

void main() {
  group('AddReminderScreen — km-vs-calendar conflict banner', () {
    const fakeCarId = 'fake-car-1';
    const warningSubstring = 'past the km threshold';

    Car fakeCar({required int currentKm}) {
      return Car(
        id: fakeCarId,
        userId: 'usr_1',
        make: 'Range Rover',
        model: 'Sport',
        year: 2018,
        plate: 'TEST',
        color: null,
        currentKm: currentKm,
        fuelType: FuelType.gasoline,
        tankSize: 85,
        photoUrl: null,
        avgKmPerDay: 30,
        createdAt: DateTime(2025, 1, 1),
        updatedAt: DateTime(2025, 1, 1),
      );
    }

    Widget pump({required int currentKm}) {
      return ProviderScope(
        overrides: [
          carsListProvider.overrideWith(
            (_) => Future.value([fakeCar(currentKm: currentKm)]),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          home: const AddReminderScreen(carId: fakeCarId),
        ),
      );
    }

    /// Finds the [TextFormField] whose decoration's `labelText` matches.
    /// More resilient than positional `.at(i)` if field order shifts later.
    Finder fieldByLabel(String label) {
      return find.ancestor(
        of: find.text(label),
        matching: find.byType(TextFormField),
      );
    }

    testWidgets('shows nothing when only intervalKm is set', (tester) async {
      await tester.pumpWidget(pump(currentKm: 50000));
      await tester.pumpAndSettle();

      // Fill Service type (required for the screen not to error in any flow).
      await tester.enterText(fieldByLabel('Service type'), 'Oil change');
      // Set intervalKm but leave intervalMonths empty.
      await tester.enterText(fieldByLabel('Interval (km)'), '5000');
      await tester.pumpAndSettle();

      expect(find.textContaining(warningSubstring), findsNothing);
    });

    testWidgets(
        'shows nothing when both intervals are set but currentKm < threshold',
        (tester) async {
      // currentKm 50000, lastDoneKm 50000, intervalKm 10000 -> threshold 60000.
      // 50000 < 60000 -> no banner.
      await tester.pumpWidget(pump(currentKm: 50000));
      await tester.pumpAndSettle();

      await tester.enterText(fieldByLabel('Service type'), 'Oil change');
      await tester.enterText(fieldByLabel('Last done at (km)'), '50000');
      await tester.enterText(fieldByLabel('Interval (km)'), '10000');
      await tester.enterText(fieldByLabel('Interval (months)'), '6');
      await tester.pumpAndSettle();

      expect(find.textContaining(warningSubstring), findsNothing);
    });

    testWidgets(
        'shows banner when both intervals are set AND currentKm >= threshold',
        (tester) async {
      // currentKm 65000, lastDoneKm 50000, intervalKm 10000 -> threshold 60000.
      // 65000 >= 60000 -> banner appears.
      await tester.pumpWidget(pump(currentKm: 65000));
      await tester.pumpAndSettle();

      await tester.enterText(fieldByLabel('Service type'), 'Oil change');
      await tester.enterText(fieldByLabel('Last done at (km)'), '50000');
      await tester.enterText(fieldByLabel('Interval (km)'), '10000');
      await tester.enterText(fieldByLabel('Interval (months)'), '6');
      await tester.pumpAndSettle();

      expect(find.textContaining(warningSubstring), findsOneWidget);
    });
  });
}
