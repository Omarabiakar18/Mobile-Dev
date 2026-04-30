/// Where the Flutter app talks to the backend.
///
/// Override per environment:
///   - iOS Simulator → http://localhost:3000
///   - Android emulator → http://10.0.2.2:3000
///   - Real iPhone over Wi-Fi → http://YOUR_MAC_LAN_IP:3000
///       (find with `ipconfig getifaddr en0`)
///
/// You can override at build time:
///   flutter run --dart-define=API_BASE_URL=http://192.168.1.42:3000
const String apiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'http://localhost:3000',
);
