// Smoke test: app boots into the splash screen while auth bootstraps.
// Real feature tests land alongside features as they're built.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:garage/app.dart';

void main() {
  testWidgets('App boots without crashing', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: GarageApp()));
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
