import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/theme/app_theme.dart';
import 'features/auth/presentation/auth_notifier.dart';
import 'features/auth/presentation/login_screen.dart';
import 'features/auth/presentation/register_screen.dart';
import 'features/cars/presentation/add_car_screen.dart';
import 'features/cars/presentation/car_detail_screen.dart';
import 'features/cars/presentation/cars_list_screen.dart';
import 'features/documents/presentation/add_document_screen.dart';
import 'features/documents/presentation/documents_list_screen.dart';
import 'features/fuel/data/ocr_prefill_model.dart';
import 'features/fuel/presentation/add_fuel_screen.dart';
import 'features/fuel/presentation/fuel_stats_screen.dart';
import 'features/fuel/presentation/ocr_camera_screen.dart';
import 'features/home/home_screen.dart';
import 'features/home/splash_screen.dart';
import 'features/maintenance/presentation/add_maintenance_screen.dart';
import 'features/maintenance/presentation/maintenance_list_screen.dart';
import 'features/reminders/presentation/add_reminder_screen.dart';
import 'features/reminders/presentation/reminders_list_screen.dart';

class GarageApp extends ConsumerWidget {
  const GarageApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    return MaterialApp.router(
      title: 'Garage',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.system,
      routerConfig: router,
    );
  }
}

/// Router rebuilds when auth state changes (loading → signed-in/out → ...).
/// `redirect` is the choke-point that decides where the user lands.
final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/',
    refreshListenable: _AuthRefresh(ref),
    redirect: (context, state) {
      final auth = ref.read(authProvider);
      final loc = state.matchedLocation;

      // Bootstrap loading — let the splash render
      if (auth.isLoading) return loc == '/splash' ? null : '/splash';

      final signedIn = auth.maybeWhen(data: (u) => u != null, orElse: () => false);
      final onAuth = loc == '/login' || loc == '/register';
      final onSplash = loc == '/splash';

      if (!signedIn && !onAuth) return '/login';
      if (signedIn && (onAuth || onSplash)) return '/';
      return null;
    },
    routes: [
      GoRoute(path: '/splash', builder: (_, _) => const SplashScreen()),
      GoRoute(path: '/login', builder: (_, _) => const LoginScreen()),
      GoRoute(path: '/register', builder: (_, _) => const RegisterScreen()),
      GoRoute(path: '/', builder: (_, _) => const HomeScreen()),
      GoRoute(path: '/cars', builder: (_, _) => const CarsListScreen()),
      GoRoute(path: '/cars/new', builder: (_, _) => const AddCarScreen()),
      GoRoute(
        path: '/cars/:id',
        builder: (_, state) => CarDetailScreen(carId: state.pathParameters['id']!),
      ),

      // Phase 2 — fuel. `extra` (Phase 4) optionally carries an `OcrPrefill`
      // so the OCR camera flow can populate the form before the user verifies.
      GoRoute(
        path: '/cars/:id/fuel/new',
        builder: (_, state) => AddFuelScreen(
          carId: state.pathParameters['id']!,
          ocrPrefill: state.extra is OcrPrefill
              ? state.extra as OcrPrefill
              : null,
        ),
      ),

      // Phase 3 — fuel stats screen
      GoRoute(
        path: '/cars/:id/fuel/stats',
        builder: (_, state) =>
            FuelStatsScreen(carId: state.pathParameters['id']!),
      ),

      // Phase 4 — receipt OCR camera flow. Lands on the OCR screen, which
      // pushes the user forward to `/fuel/new` with an `OcrPrefill` extra.
      GoRoute(
        path: '/cars/:id/fuel/scan',
        builder: (_, state) =>
            OcrCameraScreen(carId: state.pathParameters['id']!),
      ),

      // Phase 2 — maintenance
      GoRoute(
        path: '/cars/:id/maintenance',
        builder: (_, state) =>
            MaintenanceListScreen(carId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/cars/:id/maintenance/new',
        builder: (_, state) =>
            AddMaintenanceScreen(carId: state.pathParameters['id']!),
      ),

      // Phase 2 — documents
      GoRoute(
        path: '/cars/:id/documents',
        builder: (_, state) =>
            DocumentsListScreen(carId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/cars/:id/documents/new',
        builder: (_, state) =>
            AddDocumentScreen(carId: state.pathParameters['id']!),
      ),

      // Phase 2 — reminders
      GoRoute(
        path: '/cars/:id/reminders',
        builder: (_, state) =>
            RemindersListScreen(carId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/cars/:id/reminders/new',
        builder: (_, state) =>
            AddReminderScreen(carId: state.pathParameters['id']!),
      ),
    ],
  );
});

/// Bridges Riverpod's `authProvider` changes to GoRouter's `refreshListenable`
/// so the redirect re-evaluates on every auth state change. `fireImmediately`
/// is true so a synchronously-completed bootstrap (e.g. cold launch with no
/// stored token) immediately moves the redirect off /splash on the first
/// frame instead of sticking until the next state change.
class _AuthRefresh extends ChangeNotifier {
  _AuthRefresh(this._ref) {
    _sub = _ref.listen<AsyncValue<dynamic>>(
      authProvider,
      (_, _) => notifyListeners(),
      fireImmediately: true,
    );
  }
  final Ref _ref;
  late final ProviderSubscription<AsyncValue<dynamic>> _sub;

  @override
  void dispose() {
    _sub.close();
    super.dispose();
  }
}
