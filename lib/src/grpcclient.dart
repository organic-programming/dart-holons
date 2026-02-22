import 'dart:async';
import 'dart:io';

import 'package:grpc/grpc.dart';
import 'package:http2/transport.dart';

/// gRPC transport connector backed by a child process's stdin/stdout pipes.
///
/// Mirrors go-holons/pkg/grpcclient.DialStdio.
/// The child process must speak gRPC (HTTP/2) on its stdin/stdout - this is
/// the standard behavior of any holon started with
/// `serve --listen stdio://`.
class StdioTransportConnector implements ClientTransportConnector {
  StdioTransportConnector._(this._process) {
    _process.exitCode.then((_) {
      if (!_done.isCompleted) {
        _done.complete();
      }
    });
  }

  final Process _process;
  final Completer<void> _done = Completer<void>();

  /// Spawn [binaryPath] with the given [args] and return a connector.
  ///
  /// Default args: `['serve', '--listen', 'stdio://']`.
  static Future<StdioTransportConnector> spawn(
    String binaryPath, {
    List<String> args = const <String>['serve', '--listen', 'stdio://'],
  }) async {
    final process = await Process.start(binaryPath, args);
    return StdioTransportConnector._(process);
  }

  @override
  Future<ClientTransportConnection> connect() async {
    // process.stdout = server -> client (incoming)
    // process.stdin  = client -> server (outgoing)
    return ClientTransportConnection.viaStreams(
      _process.stdout,
      _process.stdin,
    );
  }

  @override
  Future<void> get done => _done.future;

  @override
  void shutdown() {
    _process.kill(ProcessSignal.sigterm);
  }

  @override
  String get authority => 'localhost';

  /// The underlying process, for lifecycle management by the caller.
  Process get process => _process;
}

/// Spawn a holon binary and return a gRPC channel backed by its stdio pipes.
///
/// Returns both the channel and the process so the caller can manage
/// the child process lifecycle (kill on shutdown, etc.).
Future<(ClientTransportConnectorChannel, Process)> dialStdio(
  String binaryPath, {
  List<String>? args,
  ChannelOptions options = const ChannelOptions(
    credentials: ChannelCredentials.insecure(),
  ),
}) async {
  final connector = await StdioTransportConnector.spawn(
    binaryPath,
    args: args ?? const <String>['serve', '--listen', 'stdio://'],
  );
  final channel = ClientTransportConnectorChannel(connector, options: options);
  return (channel, connector.process);
}
