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
      expect(listen('ftp://host'), throwsArgumentError);
    });
  });

  group('runtime transport', () {
    test('runtime tcp roundtrip', () async {
      final runtime = await listenRuntime('tcp://127.0.0.1:0');
      expect(runtime, isA<TcpRuntimeListener>());
      final tcp = runtime as TcpRuntimeListener;

      final acceptedFuture = tcp.accept();
      final client = await Socket.connect('127.0.0.1', tcp.socket.port);
      final server = await acceptedFuture;

      client.add('ping'.codeUnits);
      await client.flush();

      final received = await server.read(maxBytes: 4);
      expect(String.fromCharCodes(received), equals('ping'));

      await server.close();
      await client.close();
      await tcp.close();
    });

    test('runtime unix roundtrip', () async {
      if (Platform.isWindows) {
        return;
      }

      final socketPath = '${Directory.systemTemp.path}/holons_dart_${DateTime.now().microsecondsSinceEpoch}.sock';
      final runtime = await listenRuntime('unix://$socketPath');
      expect(runtime, isA<UnixRuntimeListener>());
      final unix = runtime as UnixRuntimeListener;

      final acceptedFuture = unix.accept();
      final client = await Socket.connect(InternetAddress(socketPath, type: InternetAddressType.unix), 0);
      final server = await acceptedFuture;

      client.add('unix'.codeUnits);
      await client.flush();

      final received = await server.read(maxBytes: 4);
      expect(String.fromCharCodes(received), equals('unix'));

      await server.close();
      await client.close();
      await unix.close();
    });

    test('runtime stdio only accepts once', () async {
      final runtime = await listenRuntime('stdio://');
      expect(runtime, isA<StdioRuntimeListener>());
      final stdio = runtime as StdioRuntimeListener;

      final conn = await stdio.accept();
      await conn.close();

      expect(stdio.accept(), throwsStateError);
      await stdio.close();
    });

    test('runtime mem roundtrip', () async {
      final runtime = await listenRuntime('mem://dart-test');
      expect(runtime, isA<MemRuntimeListener>());
      final mem = runtime as MemRuntimeListener;

      final acceptedFuture = mem.accept();
      final client = await mem.dial();
      final server = await acceptedFuture;

      await client.write('mem'.codeUnits);
      final received = await server.read(maxBytes: 3);
      expect(String.fromCharCodes(received), equals('mem'));

      await server.close();
      await client.close();
      await mem.close();
    });

    test('runtime ws unsupported', () {
      expect(listenRuntime('ws://127.0.0.1:8080/grpc'), throwsA(isA<UnsupportedError>()));
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
        'family_name: "Test"\nlang: "dart"\n'
        'parents: ["a", "b"]\n'
        'generated_by: "sophia-who"\n'
        'proto_status: draft\n'
        'aliases: ["d1"]\n'
        '---\n# test\n',
      );

      final id = parseHolon(tmp.path);
      expect(id.uuid, equals('abc-123'));
      expect(id.givenName, equals('test'));
      expect(id.lang, equals('dart'));
      expect(id.parents, equals(<String>['a', 'b']));
      expect(id.generatedBy, equals('sophia-who'));
      expect(id.protoStatus, equals('draft'));
      expect(id.aliases, equals(<String>['d1']));

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
