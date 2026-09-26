// lib/config/app_config.dart
//
// Single source of truth for the backend's address. Every screen that
// talks to the API used to hardcode the tunnel URL itself (the same
// literal string copy-pasted into ~40 files) - that meant switching
// tunnels (ngrok -> Tailscale -> whatever comes after) required
// hunting down and editing every one of them by hand, easy to miss one.
//
// Now every file derives its own baseUrl/apiBase/etc. from these two
// constants instead. Switching backends is a one-line change HERE,
// nothing else needs to be touched.
class AppConfig {
  // The backend's root address - no trailing slash, no '/api' suffix.
  // Change ONLY this line when switching tunnels/hosting.
  // Self-hosted since Sep 2026 (was the ngrok tunnel before).
  static const String apiHost = 'https://idaagrico.duckdns.org';

  // What almost every screen actually wants for its HTTP calls.
  static const String apiBaseUrl = '$apiHost/api';
}
