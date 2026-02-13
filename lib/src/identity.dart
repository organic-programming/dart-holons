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
  final List<String> parents;
  final String reproduction;
  final String generatedBy;
  final String protoStatus;
  final List<String> aliases;

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
    this.parents = const <String>[],
    this.reproduction = '',
    this.generatedBy = '',
    this.protoStatus = '',
    this.aliases = const <String>[],
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
  final raw = loadYaml(frontmatter);
  final data = raw is YamlMap ? raw : YamlMap();

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
    parents: _toStringList(data['parents']),
    reproduction: (data['reproduction'] ?? '').toString(),
    generatedBy: (data['generated_by'] ?? '').toString(),
    protoStatus: (data['proto_status'] ?? '').toString(),
    aliases: _toStringList(data['aliases']),
  );
}

List<String> _toStringList(Object? value) {
  if (value is YamlList) {
    return value.map((item) => item.toString()).toList(growable: false);
  }
  if (value is List) {
    return value.map((item) => item.toString()).toList(growable: false);
  }
  return const <String>[];
}
