import 'package:oh_release_kit/oh_release_kit.dart';
import 'package:test/test.dart';

const _lock = '''
packages:
  collection:
    dependency: transitive
    description:
      name: collection
      sha256: "abc"
      url: "https://pub.dev"
    source: hosted
    version: "1.19.1"
  oh_fleet_conformance:
    dependency: "direct dev"
    description:
      path: "../packages/oh_fleet_conformance"
      relative: true
    source: path
    version: "0.17.0"
  openhearth_design:
    dependency: "direct main"
    description:
      path: "../ohStyle/openhearth_design"
      relative: true
    source: path
    version: "0.9.2"
  openhearth_tokens:
    dependency: transitive
    description:
      path: "../ohStyle/openhearth_tokens"
      relative: true
    source: path
    version: "0.3.0"
sdks:
  dart: ">=3.8.0 <4.0.0"
''';

void main() {
  test('lists every path package, sorted, with version and path', () {
    final pkgs = parsePathPackages(_lock);
    expect(pkgs.map((p) => p.name), [
      'oh_fleet_conformance',
      'openhearth_design',
      'openhearth_tokens',
    ]);
    expect(pkgs.first.version, '0.17.0');
    expect(pkgs.first.path, '../packages/oh_fleet_conformance');
    expect(pkgs.first.dependency, 'direct dev');
  });

  test('hosted packages are left out', () {
    expect(
      parsePathPackages(_lock).map((p) => p.name),
      isNot(contains('collection')),
    );
  });

  test('a lock with no packages gives an empty list', () {
    expect(parsePathPackages('sdks:\n  dart: ">=3.0.0"\n'), isEmpty);
  });

  test('the ledger block names the app and each package on one line', () {
    final block = renderSharedVersions(
      app: 'demo 1.4.2+31',
      packages: parsePathPackages(_lock),
      commits: {'oh_fleet_conformance': '1a2b3c4'},
    );
    expect(block, contains('demo 1.4.2+31'));
    expect(
      block,
      contains(
        'oh_fleet_conformance  0.17.0  '
        '../packages/oh_fleet_conformance  commit 1a2b3c4',
      ),
    );
    expect(block, contains('openhearth_tokens  0.3.0  '));
  });
}
