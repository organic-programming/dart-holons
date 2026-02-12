import 'dart:io';
import 'package:yaml/yaml.dart';

/// Parsed holon identity from HOLON.md.
class HolonIdentity {
  final String uuid;
  final String givenName;
  final String familyName;
  final String motto;
  final String composer;
  final String clade;
  final String status;
  final String born;
  final String lang;

  HolonIdentity({
    this.uuid = '',
    this.givenName = '',
    this.familyName = '',
    this.motto = '',
    this.composer = '',
    this.clade = '',
    this.status = '',
    this.born = '',
    this.lang = '',
  });
}

/// Parse a HOLON.md file.
HolonIdentity parseHolon(String path) {
  final text = File(path).readAsStringSync();

  if (!text.startsWith('---')) {
    throw FormatException('$path: missing YAML frontmatter');
  }

  final endIdx = text.indexOf('---', 3);
  if (endIdx < 0) {
    throw FormatException('$path: unterminated frontmatter');
  }

  final frontmatter = text.substring(3, endIdx).trim();
  final data = loadYaml(frontmatter) as YamlMap;

  return HolonIdentity(
    uuid: (data['uuid'] ?? '').toString(),
    givenName: (data['given_name'] ?? '').toString(),
    familyName: (data['family_name'] ?? '').toString(),
    motto: (data['motto'] ?? '').toString(),
    composer: (data['composer'] ?? '').toString(),
    clade: (data['clade'] ?? '').toString(),
    status: (data['status'] ?? '').toString(),
    born: (data['born'] ?? '').toString(),
    lang: (data['lang'] ?? '').toString(),
  );
}
