import 'dart:io';

/// Default transport URI when --listen is omitted.
const defaultUri = 'tcp://:9090';

class ParsedUri {
  const ParsedUri({
    required this.raw,
    required this.scheme,
    this.host,
    this.port,
    this.path,
    this.secure = false,
  });

  final String raw;
  final String scheme;
  final String? host;
  final int? port;
  final String? path;
  final bool secure;
}

sealed class TransportListener {
  const TransportListener();
}

class TcpTransportListener extends TransportListener {
  const TcpTransportListener(this.socket);
  final ServerSocket socket;
}

class UnixTransportListener extends TransportListener {
  const UnixTransportListener(this.socket, this.path);
  final ServerSocket socket;
  final String path;
}

class StdioTransportListener extends TransportListener {
  const StdioTransportListener({this.address = 'stdio://'});
  final String address;
}

class MemTransportListener extends TransportListener {
  const MemTransportListener({this.address = 'mem://'});
  final String address;
}

class WsTransportListener extends TransportListener {
  const WsTransportListener({
    required this.host,
    required this.port,
    required this.path,
    required this.secure,
  });

  final String host;
  final int port;
  final String path;
  final bool secure;
}

/// Extract the scheme from a transport URI.
String scheme(String uri) {
  final idx = uri.indexOf('://');
  return idx >= 0 ? uri.substring(0, idx) : uri;
}

/// Parse a transport URI into a normalized structure.
ParsedUri parseUri(String uri) {
  final s = scheme(uri);
  switch (s) {
    case 'tcp':
      if (!uri.startsWith('tcp://')) {
        throw ArgumentError('invalid tcp URI: $uri');
      }
      final (host, port) = _splitHostPort(uri.substring(6), 9090);
      return ParsedUri(raw: uri, scheme: 'tcp', host: host, port: port);
    case 'unix':
      if (!uri.startsWith('unix://')) {
        throw ArgumentError('invalid unix URI: $uri');
      }
      final path = uri.substring(7);
      if (path.isEmpty) {
        throw ArgumentError('invalid unix URI: $uri');
      }
      return ParsedUri(raw: uri, scheme: 'unix', path: path);
    case 'stdio':
      return const ParsedUri(raw: 'stdio://', scheme: 'stdio');
    case 'mem':
      return ParsedUri(raw: uri.startsWith('mem://') ? uri : 'mem://', scheme: 'mem');
    case 'ws':
    case 'wss':
      final secure = s == 'wss';
      final prefix = secure ? 'wss://' : 'ws://';
      if (!uri.startsWith(prefix)) {
        throw ArgumentError('invalid ws URI: $uri');
      }
      final trimmed = uri.substring(prefix.length);
      final slash = trimmed.indexOf('/');
      final addr = slash >= 0 ? trimmed.substring(0, slash) : trimmed;
      final path = slash >= 0 ? trimmed.substring(slash) : '/grpc';
      final (host, port) = _splitHostPort(addr, secure ? 443 : 80);
      return ParsedUri(
        raw: uri,
        scheme: s,
        host: host,
        port: port,
        path: path.isEmpty ? '/grpc' : path,
        secure: secure,
      );
    default:
      throw ArgumentError('unsupported transport URI: $uri');
  }
}

/// Parse a transport URI and create a listener variant.
Future<TransportListener> listen(String uri) async {
  final parsed = parseUri(uri);
  switch (parsed.scheme) {
    case 'tcp':
      return TcpTransportListener(await _listenTcp(parsed));
    case 'unix':
      final path = parsed.path ?? '';
      return UnixTransportListener(await _listenUnix(path), path);
    case 'stdio':
      return const StdioTransportListener();
    case 'mem':
      return const MemTransportListener();
    case 'ws':
    case 'wss':
      return WsTransportListener(
        host: parsed.host ?? '0.0.0.0',
        port: parsed.port ?? (parsed.secure ? 443 : 80),
        path: parsed.path ?? '/grpc',
        secure: parsed.secure,
      );
    default:
      throw ArgumentError('unsupported transport URI: $uri');
  }
}

Future<ServerSocket> _listenTcp(ParsedUri parsed) async {
  final host = parsed.host ?? '0.0.0.0';
  final port = parsed.port ?? 9090;
  return ServerSocket.bind(host, port);
}

Future<ServerSocket> _listenUnix(String path) async {
  // Clean stale socket
  try {
    File(path).deleteSync();
  } catch (_) {}
  return ServerSocket.bind(InternetAddress(path, type: InternetAddressType.unix), 0);
}

(String, int) _splitHostPort(String addr, int defaultPort) {
  if (addr.isEmpty) {
    return ('0.0.0.0', defaultPort);
  }
  final lastColon = addr.lastIndexOf(':');
  if (lastColon < 0) {
    return (addr, defaultPort);
  }
  final host = lastColon > 0 ? addr.substring(0, lastColon) : '0.0.0.0';
  final portText = addr.substring(lastColon + 1);
  final port = portText.isEmpty ? defaultPort : int.parse(portText);
  return (host, port);
}
