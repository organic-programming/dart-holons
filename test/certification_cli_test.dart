import 'dart:convert';
import 'dart:io';

import 'package:holons/src/echo_cli.dart';
import 'package:test/test.dart';

void main() {
  group('certification commands', () {
    test('cert.json declares runnable echo commands and dial/listen flags', () {
      final certRaw = File('cert.json').readAsStringSync();
      final cert = jsonDecode(certRaw) as Map<String, dynamic>;
      final executables = cert['executables'] as Map<String, dynamic>;
      final capabilities = cert['capabilities'] as Map<String, dynamic>;

      expect(executables['echo_server'], equals('./bin/echo-server'));
      expect(executables['echo_client'], equals('./bin/echo-client'));
      expect(capabilities['grpc_listen_tcp'], isTrue);
      expect(capabilities['grpc_listen_stdio'], isTrue);
      expect(capabilities['grpc_dial_tcp'], isTrue);
      expect(capabilities['grpc_dial_stdio'], isTrue);
    });

    test('echo scripts exist', () {
      expect(File('bin/echo-client').existsSync(), isTrue);
      expect(File('bin/echo-server').existsSync(), isTrue);
    });

    test('echo scripts are executable on unix', () {
      if (Platform.isWindows) {
        return;
      }

      final clientMode = FileStat.statSync('bin/echo-client').mode;
      final serverMode = FileStat.statSync('bin/echo-server').mode;

      expect(clientMode & 0x49, greaterThan(0)); // 0o111
      expect(serverMode & 0x49, greaterThan(0)); // 0o111
    });

    test('parseEchoClientArgs defaults and uri normalization', () {
      final defaults = parseEchoClientArgs(
        const <String>[],
        environment: const <String, String>{'GO_BIN': 'go-custom'},
      );
      expect(defaults.uri, equals('stdio://'));
      expect(defaults.sdk, equals('dart-holons'));
      expect(defaults.serverSDK, equals('go-holons'));
      expect(defaults.message, equals('hello'));
      expect(defaults.timeoutMs, equals(5000));
      expect(defaults.goBinary, equals('go-custom'));

      final normalized = parseEchoClientArgs(
        const <String>['stdio'],
        environment: const <String, String>{'GO_BIN': 'go-custom'},
      );
      expect(normalized.uri, equals('stdio://'));
    });

    test('parseEchoClientArgs parses explicit flags', () {
      final options = parseEchoClientArgs(
        const <String>[
          'tcp://127.0.0.1:19090',
          '--sdk',
          'custom-sdk',
          '--server-sdk',
          'go-custom',
          '--message',
          'interop',
          '--timeout-ms',
          '1700',
          '--go',
          'go-1.25',
        ],
      );

      expect(options.uri, equals('tcp://127.0.0.1:19090'));
      expect(options.sdk, equals('custom-sdk'));
      expect(options.serverSDK, equals('go-custom'));
      expect(options.message, equals('interop'));
      expect(options.timeoutMs, equals(1700));
      expect(options.goBinary, equals('go-1.25'));
    });

    test('parseEchoClientArgs rejects invalid timeout', () {
      expect(
        () => parseEchoClientArgs(const <String>['--timeout-ms', '0']),
        throwsFormatException,
      );
    });

    test('buildEchoClientInvocation wires go helper and environment', () {
      const options = EchoClientOptions(
        uri: 'stdio://',
        sdk: 'dart-holons',
        serverSDK: 'go-holons',
        message: 'hello',
        timeoutMs: 5000,
        goBinary: 'go-bin',
      );

      final invocation = buildEchoClientInvocation(
        options,
        sdkRootPath: '/repo/sdk/dart-holons',
        baseEnvironment: const <String, String>{'PATH': '/bin'},
      );

      expect(invocation.command, equals('go-bin'));
      expect(invocation.args[0], equals('run'));
      expect(
        invocation.args[1],
        equals(
            '/repo/sdk/dart-holons/../js-web-holons/cmd/echo-client-go/main.go'),
      );
      expect(invocation.args.last, equals('stdio://'));
      expect(invocation.workingDirectory,
          equals('/repo/sdk/dart-holons/../go-holons'));
      expect(invocation.environment['PATH'], equals('/bin'));
      expect(invocation.environment['GOCACHE'], equals('/tmp/go-cache'));
    });

    test('parseEchoServerArgs strips --go and keeps passthrough flags', () {
      final options = parseEchoServerArgs(
        const <String>[
          '--listen',
          'tcp://127.0.0.1:0',
          '--go',
          'go-custom',
          '--sdk',
          'explicit',
        ],
      );

      expect(options.goBinary, equals('go-custom'));
      expect(
        options.passthroughArgs,
        equals(
          const <String>[
            '--listen',
            'tcp://127.0.0.1:0',
            '--sdk',
            'explicit',
          ],
        ),
      );
    });

    test('buildEchoServerInvocation appends sdk/version defaults when missing',
        () {
      final options = parseEchoServerArgs(
        const <String>[
          '--listen',
          'tcp://127.0.0.1:0',
        ],
        environment: const <String, String>{'GO_BIN': 'go-custom'},
      );

      final invocation = buildEchoServerInvocation(
        options,
        sdkRootPath: '/repo/sdk/dart-holons',
        baseEnvironment: const <String, String>{
          'PATH': '/bin',
          'GOCACHE': '/custom/cache',
        },
      );

      expect(invocation.command, equals('go-custom'));
      expect(invocation.args[0], equals('run'));
      expect(invocation.args[1], equals('./cmd/echo-server'));
      expect(invocation.args, contains('--sdk'));
      expect(invocation.args, contains('dart-holons'));
      expect(invocation.args, contains('--version'));
      expect(invocation.args, contains('0.1.0'));
      expect(invocation.environment['GOCACHE'], equals('/custom/cache'));
    });

    test('buildEchoServerInvocation respects explicit sdk/version', () {
      final options = parseEchoServerArgs(
        const <String>[
          '--listen',
          'tcp://127.0.0.1:0',
          '--sdk',
          'manual',
          '--version',
          '9.9.9',
          '--go',
          'go-custom',
        ],
      );

      final invocation = buildEchoServerInvocation(
        options,
        sdkRootPath: '/repo/sdk/dart-holons',
      );

      expect(invocation.command, equals('go-custom'));
      expect(
        invocation.args.where((arg) => arg == '--sdk').length,
        equals(1),
      );
      expect(
        invocation.args.where((arg) => arg == '--version').length,
        equals(1),
      );
      expect(invocation.args, contains('manual'));
      expect(invocation.args, contains('9.9.9'));
    });
  });
}
