import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

typedef HolonRPCHandler = FutureOr<Map<String, dynamic>> Function(
    Map<String, dynamic> params);

class HolonRPCResponseException implements Exception {
  HolonRPCResponseException({
    required this.code,
    required this.message,
    this.data,
  });

  final int code;
  final String message;
  final Object? data;

  @override
  String toString() =>
      'HolonRPCResponseException(code: $code, message: $message)';
}

class HolonRPCClient {
  HolonRPCClient({
    this.heartbeatIntervalMs = 15000,
    this.heartbeatTimeoutMs = 5000,
    this.reconnectMinDelayMs = 500,
    this.reconnectMaxDelayMs = 30000,
    this.reconnectFactor = 2.0,
    this.reconnectJitter = 0.1,
    this.connectTimeoutMs = 10000,
    this.requestTimeoutMs = 10000,
    Random? random,
  }) : _random = random ?? Random();

  final int heartbeatIntervalMs;
  final int heartbeatTimeoutMs;
  final int reconnectMinDelayMs;
  final int reconnectMaxDelayMs;
  final double reconnectFactor;
  final double reconnectJitter;
  final int connectTimeoutMs;
  final int requestTimeoutMs;
  final Random _random;

  final Map<String, HolonRPCHandler> _handlers = <String, HolonRPCHandler>{};
  final Map<String, Completer<Map<String, dynamic>>> _pending =
      <String, Completer<Map<String, dynamic>>>{};

  WebSocket? _socket;
  StreamSubscription<dynamic>? _socketSubscription;
  Timer? _heartbeatTimer;
  Timer? _reconnectTimer;
  Completer<void>? _connectedWaiter;

  String? _url;
  int _nextID = 0;
  int _reconnectAttempt = 0;
  bool _connecting = false;
  bool _closed = false;

  Future<void> connect(String url) async {
    if (url.isEmpty) {
      throw ArgumentError('url is required');
    }

    if (_socket != null && _url == url) {
      return;
    }

    await close();
    _closed = false;
    _url = url;
    _connectedWaiter = Completer<void>();

    await _openSocket(initial: true);
    await _awaitConnected(Duration(milliseconds: connectTimeoutMs));
  }

  void register(String method, HolonRPCHandler handler) {
    if (method.isEmpty) {
      throw ArgumentError('method is required');
    }
    _handlers[method] = handler;
  }

  Future<Map<String, dynamic>> invoke(
    String method, {
    Map<String, dynamic> params = const <String, dynamic>{},
    int? timeoutMs,
  }) async {
    if (method.isEmpty) {
      throw ArgumentError('method is required');
    }

    await _awaitConnected(Duration(milliseconds: connectTimeoutMs));

    final id = 'c${++_nextID}';
    final completer = Completer<Map<String, dynamic>>();
    _pending[id] = completer;

    try {
      await _send(<String, dynamic>{
        'jsonrpc': '2.0',
        'id': id,
        'method': method,
        'params': params,
      });
    } catch (_) {
      _pending.remove(id);
      rethrow;
    }

    final timeout = Duration(milliseconds: timeoutMs ?? requestTimeoutMs);

    try {
      return await completer.future.timeout(timeout);
    } finally {
      _pending.remove(id);
    }
  }

  Future<void> close() async {
    _closed = true;
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;

    final socket = _socket;
    _socket = null;

    final subscription = _socketSubscription;
    _socketSubscription = null;
    await subscription?.cancel();

    if (socket != null) {
      await socket.close(WebSocketStatus.normalClosure, 'client close');
    }

    _failAllPending(StateError('holon-rpc client closed'));
  }

  Future<void> _openSocket({required bool initial}) async {
    if (_connecting || _closed) {
      return;
    }

    final url = _url;
    if (url == null) {
      throw StateError('url is not set');
    }

    _connecting = true;
    try {
      final socket =
          await WebSocket.connect(url, protocols: <String>['holon-rpc']);
      if (socket.protocol != 'holon-rpc') {
        await socket.close(
            WebSocketStatus.protocolError, 'missing holon-rpc subprotocol');
        throw StateError('server did not negotiate holon-rpc subprotocol');
      }

      _socket = socket;
      _reconnectAttempt = 0;
      _connectedWaiter ??= Completer<void>();
      if (!_connectedWaiter!.isCompleted) {
        _connectedWaiter!.complete();
      }

      _socketSubscription = socket.listen(
        _handleIncoming,
        onDone: _handleDisconnect,
        onError: (Object _, StackTrace __) => _handleDisconnect(),
        cancelOnError: true,
      );

      _startHeartbeat();
    } catch (_) {
      if (initial) {
        rethrow;
      }
      _scheduleReconnect();
    } finally {
      _connecting = false;
    }
  }

  void _handleIncoming(dynamic data) {
    final String text;
    if (data is String) {
      text = data;
    } else if (data is List<int>) {
      text = utf8.decode(data);
    } else {
      return;
    }

    late final Object decoded;
    try {
      decoded = jsonDecode(text);
    } catch (_) {
      return;
    }

    if (decoded is! Map<String, dynamic>) {
      return;
    }

    if (decoded['method'] != null) {
      unawaited(_handleRequest(decoded));
      return;
    }

    if (decoded['result'] != null || decoded['error'] != null) {
      _handleResponse(decoded);
    }
  }

  Future<void> _handleRequest(Map<String, dynamic> msg) async {
    final dynamic id = msg['id'];
    final method = msg['method'];
    final jsonrpc = msg['jsonrpc'];

    if (jsonrpc != '2.0' || method is! String || method.isEmpty) {
      if (id != null) {
        await _sendError(id, -32600, 'invalid request');
      }
      return;
    }

    if (method == 'rpc.heartbeat') {
      if (id != null) {
        await _sendResult(id, <String, dynamic>{});
      }
      return;
    }

    if (id != null) {
      if (id is! String || !id.startsWith('s')) {
        await _sendError(id, -32600, "server request id must start with 's'");
        return;
      }
    }

    final handler = _handlers[method];
    if (handler == null) {
      if (id != null) {
        await _sendError(id, -32601, 'method "$method" not found');
      }
      return;
    }

    final dynamic rawParams = msg['params'];
    final params = rawParams is Map<String, dynamic>
        ? rawParams
        : rawParams is Map
            ? rawParams.cast<String, dynamic>()
            : <String, dynamic>{};

    try {
      final result = await handler(params);
      if (id != null) {
        await _sendResult(id, result);
      }
    } on HolonRPCResponseException catch (rpcError) {
      if (id != null) {
        await _sendError(id, rpcError.code, rpcError.message, rpcError.data);
      }
    } catch (error) {
      if (id != null) {
        await _sendError(id, 13, error.toString());
      }
    }
  }

  void _handleResponse(Map<String, dynamic> msg) {
    final rawID = msg['id'];
    final id = rawID is String ? rawID : rawID?.toString();
    if (id == null) {
      return;
    }

    final completer = _pending.remove(id);
    if (completer == null || completer.isCompleted) {
      return;
    }

    final dynamic rawError = msg['error'];
    if (rawError is Map<String, dynamic>) {
      final rawCode = rawError['code'];
      final code = rawCode is int
          ? rawCode
          : (rawCode is num ? rawCode.toInt() : -32603);
      final message = rawError['message']?.toString() ?? 'internal error';
      completer.completeError(
        HolonRPCResponseException(
          code: code,
          message: message,
          data: rawError['data'],
        ),
      );
      return;
    }

    final dynamic rawResult = msg['result'];
    if (rawResult is Map<String, dynamic>) {
      completer.complete(rawResult);
      return;
    }
    if (rawResult is Map) {
      completer.complete(rawResult.cast<String, dynamic>());
      return;
    }

    completer.complete(<String, dynamic>{});
  }

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(
      Duration(milliseconds: heartbeatIntervalMs),
      (_) async {
        if (_closed || _socket == null) {
          return;
        }

        try {
          await invoke(
            'rpc.heartbeat',
            params: const <String, dynamic>{},
            timeoutMs: heartbeatTimeoutMs,
          );
        } catch (_) {
          await _socket?.close(WebSocketStatus.goingAway, 'heartbeat timeout');
        }
      },
    );
  }

  void _handleDisconnect() {
    _socket = null;
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;

    _connectedWaiter = Completer<void>();
    _failAllPending(StateError('holon-rpc connection closed'));

    if (_closed) {
      return;
    }

    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    if (_closed || _reconnectTimer != null) {
      return;
    }

    final baseDelay = min(
      reconnectMinDelayMs * pow(reconnectFactor, _reconnectAttempt),
      reconnectMaxDelayMs.toDouble(),
    );
    final jitter = baseDelay * reconnectJitter * _random.nextDouble();
    final delayMs = (baseDelay + jitter).round();
    _reconnectAttempt += 1;

    _reconnectTimer = Timer(Duration(milliseconds: delayMs), () async {
      _reconnectTimer = null;
      await _openSocket(initial: false);
    });
  }

  Future<void> _awaitConnected(Duration timeout) async {
    if (_socket != null) {
      return;
    }
    if (_closed) {
      throw StateError('holon-rpc client closed');
    }

    _connectedWaiter ??= Completer<void>();
    await _connectedWaiter!.future.timeout(timeout);
  }

  Future<void> _send(Map<String, dynamic> payload) async {
    final socket = _socket;
    if (socket == null) {
      throw StateError('websocket is not connected');
    }
    socket.add(jsonEncode(payload));
  }

  Future<void> _sendResult(dynamic id, Map<String, dynamic> result) async {
    await _send(<String, dynamic>{
      'jsonrpc': '2.0',
      'id': id,
      'result': result,
    });
  }

  Future<void> _sendError(
    dynamic id,
    int code,
    String message, [
    Object? data,
  ]) async {
    await _send(<String, dynamic>{
      'jsonrpc': '2.0',
      'id': id,
      'error': <String, dynamic>{
        'code': code,
        'message': message,
        if (data != null) 'data': data,
      },
    });
  }

  void _failAllPending(Object error) {
    if (_pending.isEmpty) {
      return;
    }
    final values = _pending.values.toList(growable: false);
    _pending.clear();
    for (final completer in values) {
      if (!completer.isCompleted) {
        completer.completeError(error);
      }
    }
  }
}
