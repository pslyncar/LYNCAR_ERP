{{flutter_js}}
{{flutter_build_config}}

// The admin app is served with frequent updates and tenant-specific builds.
// Avoid Flutter's service worker here so Chrome cannot keep an old main.dart.js
// after local tests or production deploys.
_flutter.loader.load();
