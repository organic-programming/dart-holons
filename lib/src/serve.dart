import 'dart:async';
import 'dart:io';

import 'package:grpc/grpc.dart';

import 'describe.dart';
import 'transport.dart';

/// Parse --listen or --port from command-line args.
String parseFlags(List<String> args) {
  for (var i = 0; i < args.length; i++) {
    if (args[i] == '--listen' && i + 1 < args.length) return args[i + 1];
    if (args[i] == '--port' && i + 1 < args.length) return 'tcp://:${args[i + 1]}';
  }
  return defaultUri;
}

class ServeOptions {
  const ServeOptions({
    this.describe = true,
    this.onListen,
    this.logger = _defaultLogger,
    this.protoDir,
    this.holonYamlPath,
  });

  final bool describe;
  final void Function(String publicUri)? onListen;
  final void Function(String message) logger;
  final String? protoDir;
  final String? holonYamlPath;
}

class RunningServer {
  RunningServer._({
    required this.server,
    required this.publicUri,
    required Future<void> completion,
    required Future<void> Function() stopCallback,
  })  : completion = completion,
        _stopCallback = stopCallback;

  final Server server;
  final String publicUri;
  final Future<void> completion;
  final Future<void> Function() _stopCallback;
  bool _stopped = false;

  Future<void> stop() async {
    if (_stopped) {
      await completion;
      return;
    }
    _stopped = true;
    await _stopCallback();
  }
}

Future<void> run(
  String listenUri,
  List<Service> services, {
  ServeOptions options = const ServeOptions(),
}) {
  return runWithOptions(listenUri, services, options: options);
}

Future<void> runWithOptions(
  String listenUri,
  List<Service> services, {
  ServeOptions options = const ServeOptions(),
}) async {
  final running = await startWithOptions(listenUri, services, options: options);

  late final StreamSubscription<ProcessSignal> sigintSub;
  sigintSub = ProcessSignal.sigint.watch().listen((_) async {
    options.logger('shutting down gRPC server');
    await running.stop();
  });

  StreamSubscription<ProcessSignal>? sigtermSub;
  try {
    sigtermSub = ProcessSignal.sigterm.watch().listen((_) async {
      options.logger('shutting down gRPC server');
      await running.stop();
    });
  } on UnsupportedError {
    sigtermSub = null;
  }

  try {
    await running.completion;
  } finally {
    await sigintSub.cancel();
    await sigtermSub?.cancel();
  }
}

Future<RunningServer> startWithOptions(
  String listenUri,
  List<Service> services, {
  ServeOptions options = const ServeOptions(),
}) async {
  final parsed = parseUri(listenUri.isEmpty ? defaultUri : listenUri);
  final resolvedServices = List<Service>.from(services);
  final describeEnabled = _maybeAddDescribe(resolvedServices, options);

  switch (parsed.scheme) {
    case 'tcp':
      final host = parsed.host ?? '0.0.0.0';
      final port = parsed.port ?? 9090;
      return _startTcpServer(
        host: host,
        port: port,
        publicUri: null,
        services: resolvedServices,
        describeEnabled: describeEnabled,
        options: options,
      );
    case 'stdio':
      final backing = await _startTcpServer(
        host: '127.0.0.1',
        port: 0,
        publicUri: null,
        services: resolvedServices,
        describeEnabled: describeEnabled,
        options: options,
        suppressAnnouncement: true,
      );
      final port = int.parse(backing.publicUri.split(':').last);
      late final RunningServer running;
      final bridge = await _StdioServerBridge.connect(
        host: '127.0.0.1',
        port: port,
        onDisconnect: () {
          unawaited(running.stop());
        },
      );
      running = RunningServer._(
        server: backing.server,
        publicUri: 'stdio://',
        completion: backing.completion,
        stopCallback: () async {
          await bridge.close();
          await backing.stop();
        },
      );
      bridge.start();
      final mode = describeEnabled ? 'Describe ON' : 'Describe OFF';
      options.onListen?.call('stdio://');
      options.logger('gRPC server listening on stdio:// ($mode)');
      return running;
    default:
      throw ArgumentError.value(
        listenUri,
        'listenUri',
        'Serve.run(...) currently supports tcp:// and stdio:// only',
      );
  }
}

Future<RunningServer> _startTcpServer({
  required String host,
  required int port,
  required String? publicUri,
  required List<Service> services,
  required bool describeEnabled,
  required ServeOptions options,
  bool suppressAnnouncement = false,
}) async {
  final server = Server.create(services: services);
  final completion = Completer<void>();

  await server.serve(
    address: _bindAddress(host),
    port: port,
  );

  final advertised = publicUri ?? 'tcp://${_advertisedHost(host)}:${server.port!}';
  final mode = describeEnabled ? 'Describe ON' : 'Describe OFF';
  if (!suppressAnnouncement) {
    options.onListen?.call(advertised);
    options.logger('gRPC server listening on $advertised ($mode)');
  }

  return RunningServer._(
    server: server,
    publicUri: advertised,
    completion: completion.future,
    stopCallback: () async {
      if (!completion.isCompleted) {
        await server.shutdown();
        completion.complete();
      }
    },
  );
}

bool _maybeAddDescribe(List<Service> services, ServeOptions options) {
  if (!options.describe) {
    return false;
  }

  final holonYaml = File(options.holonYamlPath ?? 'holon.yaml');
  if (!holonYaml.existsSync()) {
    return false;
  }

  services.add(
    describeService(
      protoDir: options.protoDir ?? 'protos',
      holonYamlPath: holonYaml.path,
    ),
  );
  return true;
}

InternetAddress _bindAddress(String host) {
  switch (host) {
    case '':
    case '0.0.0.0':
      return InternetAddress.anyIPv4;
    case '::':
      return InternetAddress.anyIPv6;
    default:
      return InternetAddress(host);
  }
}

String _advertisedHost(String host) {
  switch (host) {
    case '':
    case '0.0.0.0':
      return '127.0.0.1';
    case '::':
      return '::1';
    default:
      return host;
  }
}

void _defaultLogger(String message) {
  stderr.writeln(message);
}

class _StdioServerBridge {
  _StdioServerBridge._({
    required Socket socket,
    required void Function() onDisconnect,
  })  : _socket = socket,
        _onDisconnect = onDisconnect;

  final Socket _socket;
  final void Function() _onDisconnect;
  bool _closed = false;
  int _pendingPumps = 2;
  StreamSubscription<List<int>>? _stdinSub;
  StreamSubscription<List<int>>? _socketSub;

  static Future<_StdioServerBridge> connect({
    required String host,
    required int port,
    required void Function() onDisconnect,
  }) async {
    final socket = await Socket.connect(host, port);
    return _StdioServerBridge._(socket: socket, onDisconnect: onDisconnect);
  }

  void start() {
    _stdinSub = stdin.listen(
      (data) {
        if (_closed) {
          return;
        }
        _socket.add(data);
      },
      onError: (_) => _markPumpDone(),
      onDone: () async {
        try {
          await _socket.close();
        } catch (_) {}
        _markPumpDone();
      },
      cancelOnError: true,
    );

    _socketSub = _socket.listen(
      (data) async {
        if (_closed) {
          return;
        }
        stdout.add(data);
        await stdout.flush();
      },
      onError: (_) => _markPumpDone(),
      onDone: _markPumpDone,
      cancelOnError: true,
    );
  }

  Future<void> close() async {
    if (_closed) {
      return;
    }
    _closed = true;
    await _stdinSub?.cancel();
    await _socketSub?.cancel();
    _socket.destroy();
  }

  void _markPumpDone() {
    if (_pendingPumps <= 0) {
      return;
    }
    _pendingPumps -= 1;
    if (_pendingPumps == 0) {
      _onDisconnect();
    }
  }
}
