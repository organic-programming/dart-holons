import 'dart:io';

/// Default transport URI when --listen is omitted.
const defaultUri = 'tcp://:9090';

/// Extract the scheme from a transport URI.
String scheme(String uri) {
  final idx = uri.indexOf('://');
  return idx >= 0 ? uri.substring(0, idx) : uri;
}

/// Parse a transport URI and bind a server socket.
Future<ServerSocket> listen(String uri) async {
  if (uri.startsWith('tcp://')) {
    return _listenTcp(uri.substring(6));
  } else if (uri.startsWith('unix://')) {
    return _listenUnix(uri.substring(7));
  } else {
    throw ArgumentError('unsupported transport URI: $uri');
  }
}

Future<ServerSocket> _listenTcp(String addr) async {
  final lastColon = addr.lastIndexOf(':');
  final host = lastColon > 0 ? addr.substring(0, lastColon) : '0.0.0.0';
  final port = int.parse(addr.substring(lastColon + 1));
  return ServerSocket.bind(host, port);
}

Future<ServerSocket> _listenUnix(String path) async {
  // Clean stale socket
  try {
    File(path).deleteSync();
  } catch (_) {}
  return ServerSocket.bind(InternetAddress(path, type: InternetAddressType.unix), 0);
}
