/// The app's version, kept equal to pubspec.yaml's `version:` by
/// test/app_version_test.dart. A const rather than package_info_plus so
/// it is available synchronously without a platform channel round-trip.
library;

const appVersion = '1.6.20';

/// Standard desktop Firefox User-Agent sent on every native fetch so
/// requests blend into ordinary browser traffic instead of leaking app
/// identity or triggering scraper blocks on Dart's default
/// (`Dart/3.x (dart:io)`).
const trellisUserAgent =
    'Mozilla/5.0 (X11; Linux x86_64; rv:160.0) Gecko/20100101 Firefox/160.0';
