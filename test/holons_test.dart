import 'dart:io';
import 'package:test/test.dart';
import 'package:holons/holons.dart';

void main() {
  group('transport', () {
    test('scheme extracts transport scheme', () {
      expect(scheme('tcp://:9090'), equals('tcp'));
      expect(scheme('unix:///tmp/x.sock'), equals('unix'));
      expect(scheme('stdio://'), equals('stdio'));
      expect(scheme('mem://'), equals('mem'));
      expect(scheme('ws://127.0.0.1:8080/grpc'), equals('ws'));
      expect(scheme('wss://example.com:443/grpc'), equals('wss'));
    });

    test('defaultUri is tcp://:9090', () {
      expect(defaultUri, equals('tcp://:9090'));
    });

    test('listen tcp', () async {
      final listener = await listen('tcp://127.0.0.1:0');
      expect(listener, isA<TcpTransportListener>());
      final tcp = listener as TcpTransportListener;
      expect(tcp.socket.port, greaterThan(0));
      await tcp.socket.close();
    });

    test('parseUri wss defaults', () {
      final parsed = parseUri('wss://example.com:8443');
      expect(parsed.scheme, equals('wss'));
      expect(parsed.host, equals('example.com'));
      expect(parsed.port, equals(8443));
      expect(parsed.path, equals('/grpc'));
      expect(parsed.secure, isTrue);
    });

    test('stdio and mem variants', () async {
      final stdio = await listen('stdio://');
      final mem = await listen('mem://');
      expect(stdio, isA<StdioTransportListener>());
      expect(mem, isA<MemTransportListener>());
      expect((stdio as StdioTransportListener).address, equals('stdio://'));
      expect((mem as MemTransportListener).address, equals('mem://'));
    });

    test('ws variant', () async {
      final listener = await listen('ws://127.0.0.1:8080/holon');
      expect(listener, isA<WsTransportListener>());
      final ws = listener as WsTransportListener;
      expect(ws.host, equals('127.0.0.1'));
      expect(ws.port, equals(8080));
      expect(ws.path, equals('/holon'));
      expect(ws.secure, isFalse);
    });

    test('unsupported uri throws', () {
      expect(() => listen('ftp://host'), throwsArgumentError);
    });
  });

  group('serve', () {
    test('parseFlags --listen', () {
      expect(parseFlags(['--listen', 'tcp://:8080']), equals('tcp://:8080'));
    });

    test('parseFlags --port', () {
      expect(parseFlags(['--port', '3000']), equals('tcp://:3000'));
    });

    test('parseFlags default', () {
      expect(parseFlags([]), equals(defaultUri));
    });
  });

  group('identity', () {
    test('parseHolon parses HOLON.md', () {
      final tmp = File('${Directory.systemTemp.path}/test_holon_dart.md');
      tmp.writeAsStringSync(
        '---\nuuid: "abc-123"\ngiven_name: "test"\n'
        'family_name: "Test"\nlang: "dart"\n---\n# test\n',
      );

      final id = parseHolon(tmp.path);
      expect(id.uuid, equals('abc-123'));
      expect(id.givenName, equals('test'));
      expect(id.lang, equals('dart'));

      tmp.deleteSync();
    });

    test('parseHolon throws for missing frontmatter', () {
      final tmp = File('${Directory.systemTemp.path}/no_fm_dart.md');
      tmp.writeAsStringSync('# No frontmatter\n');
      expect(() => parseHolon(tmp.path), throwsFormatException);
      tmp.deleteSync();
    });
  });
}
