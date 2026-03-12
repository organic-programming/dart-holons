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
  });

  final bool describe;
  final void Function(String publicUri)? onListen;
  final void Function(String message) logger;
}

class RunningServer {
  RunningServer._({
    required this.server,
    required this.publicUri,
  });

  final Server server;
  final String publicUri;

  Future<void> stop() => server.shutdown();
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
  final shutdown = Completer<void>();

  late final StreamSubscription<ProcessSignal> sigintSub;
  sigintSub = ProcessSignal.sigint.watch().listen((_) async {
    if (!shutdown.isCompleted) {
      options.logger('shutting down gRPC server');
      await running.stop();
      shutdown.complete();
    }
    await sigintSub.cancel();
  });

  StreamSubscription<ProcessSignal>? sigtermSub;
  try {
    sigtermSub = ProcessSignal.sigterm.watch().listen((_) async {
      if (!shutdown.isCompleted) {
        options.logger('shutting down gRPC server');
        await running.stop();
        shutdown.complete();
      }
      await sigtermSub?.cancel();
    });
  } on UnsupportedError {
    sigtermSub = null;
  }

  try {
    await shutdown.future;
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
  final parsed = parseUri(listenUri);
  if (parsed.scheme != 'tcp') {
    throw ArgumentError.value(
      listenUri,
      'listenUri',
      'Serve.run(...) currently supports tcp:// only',
    );
  }

  final host = parsed.host ?? '0.0.0.0';
  final port = parsed.port ?? 9090;
  final resolvedServices = List<Service>.from(services);
  final describeEnabled = _maybeAddDescribe(resolvedServices, options.describe);

  final server = Server.create(services: resolvedServices);
  await server.serve(
    address: _bindAddress(host),
    port: port,
  );

  final publicUri = 'tcp://${_advertisedHost(host)}:${server.port!}';
  final mode = describeEnabled ? 'Describe ON' : 'Describe OFF';

  options.onListen?.call(publicUri);
  options.logger('gRPC server listening on $publicUri ($mode)');

  return RunningServer._(server: server, publicUri: publicUri);
}

bool _maybeAddDescribe(List<Service> services, bool enabled) {
  if (!enabled) {
    return false;
  }

  final holonYaml = File('holon.yaml');
  if (!holonYaml.existsSync()) {
    return false;
  }

  services.add(
    describeService(
      protoDir: 'protos',
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
