/// Facts about the package this page is showing off.
///
/// The version is injected at build time rather than typed here, because a
/// showcase that advertises a version which was never published is worse than
/// one that shows nothing at all.
library;

/// The version the install line offers.
///
/// The Pages workflow reads the real number out of the package's
/// `pubspec.yaml` and passes it in with `--dart-define`. The fallback is only
/// what a local `flutter run` shows.
const String kPackageVersion = String.fromEnvironment(
  'wovenVersion',
  defaultValue: '1.0.0',
);

/// The dependency line, exactly as it goes in a `pubspec.yaml`.
const String kInstallLine = 'woven_ring_chart: ^$kPackageVersion';

const String kPubDevUrl = 'https://pub.dev/packages/woven_ring_chart';
const String kRepoUrl = 'https://github.com/omar-hanafy/woven_ring_chart';
const String kApiDocsUrl =
    'https://pub.dev/documentation/woven_ring_chart/latest/';
