import 'dart:io';

import 'package:holons/holons.dart';
import 'package:test/test.dart';

void main() {
  group('discover', () {
    test('recurses skips and dedups by uuid', () async {
      final root = Directory.systemTemp.createTempSync('holons_discover_dart_');
      addTearDown(() => root.delete(recursive: true));

      _writeHolon(root.path, 'holons/alpha',
          const _HolonSeed('uuid-alpha', 'Alpha', 'Go', 'alpha-go'));
      _writeHolon(root.path, 'nested/beta',
          const _HolonSeed('uuid-beta', 'Beta', 'Rust', 'beta-rust'));
      _writeHolon(root.path, 'nested/dup/alpha',
          const _HolonSeed('uuid-alpha', 'Alpha', 'Go', 'alpha-go'));

      for (final skipped in <String>[
        '.git/hidden',
        '.op/hidden',
        'node_modules/hidden',
        'vendor/hidden',
        'build/hidden',
        '.cache/hidden',
      ]) {
        _writeHolon(
            root.path,
            skipped,
            const _HolonSeed(
                'ignored-uuid', 'Ignored', 'Holon', 'ignored-holon'));
      }

      final entries = await discover(root.path);
      expect(entries, hasLength(2));

      final alpha = entries.firstWhere((entry) => entry.uuid == 'uuid-alpha');
      expect(alpha.slug, equals('alpha-go'));
      expect(alpha.relativePath, equals('holons/alpha'));
      expect(alpha.manifest?.build.runner, equals('go-module'));

      final beta = entries.firstWhere((entry) => entry.uuid == 'uuid-beta');
      expect(beta.relativePath, equals('nested/beta'));
    });

    test('discoverLocal and find helpers use the current directory', () async {
      final root = Directory.systemTemp.createTempSync('holons_find_dart_');
      addTearDown(() => root.delete(recursive: true));

      _writeHolon(
        root.path,
        'rob-go',
        const _HolonSeed(
          'c7f3a1b2-1111-1111-1111-111111111111',
          'Rob',
          'Go',
          'rob-go',
        ),
      );

      final original = Directory.current;
      Directory.current = root.path;
      addTearDown(() {
        Directory.current = original;
      });

      final local = await discoverLocal();
      expect(local, hasLength(1));
      expect(local.single.slug, equals('rob-go'));

      final bySlug = await findBySlug('rob-go');
      expect(bySlug?.uuid, equals('c7f3a1b2-1111-1111-1111-111111111111'));

      final byUuid = await findByUUID('c7f3a1b2');
      expect(byUuid?.slug, equals('rob-go'));

      expect(await findBySlug('missing'), isNull);
    });
  });
}

class _HolonSeed {
  final String uuid;
  final String givenName;
  final String familyName;
  final String binary;

  const _HolonSeed(this.uuid, this.givenName, this.familyName, this.binary);
}

void _writeHolon(String root, String relativeDir, _HolonSeed seed) {
  final dir = Directory('$root/$relativeDir')..createSync(recursive: true);
  final file = File('${dir.path}/holon.yaml');
  file.writeAsStringSync('''
schema: holon/v0
uuid: "${seed.uuid}"
given_name: "${seed.givenName}"
family_name: "${seed.familyName}"
motto: "Test"
composer: "test"
clade: deterministic/pure
status: draft
born: "2026-03-07"
generated_by: test
kind: native
build:
  runner: go-module
artifacts:
  binary: ${seed.binary}
''');
}
