---
# Cartouche v1
title: "dart-holons — Dart SDK for Organic Programming"
author:
  name: "B. ALTER"
created: 2026-02-12
revised: 2026-02-13
access:
  humans: true
  agents: false
status: draft
---
# dart-holons

**Dart SDK for Organic Programming** — transport, serve, and identity
utilities for building holons in Dart.

## Test

```bash
dart test
```

## API surface

| Library | Description |
|---------|-------------|
| `transport.dart` | `parseUri(uri)`, `listen(uri)`, `listenRuntime(uri)`, `scheme(uri)` |
| `serve.dart` | `parseFlags(args)` |
| `identity.dart` | `parseHolon(path)` |

## Transport support

| Scheme | Support |
|--------|---------|
| `tcp://<host>:<port>` | Bound socket (`TcpTransportListener`) |
| `unix://<path>` | Bound UNIX socket (`UnixTransportListener`) |
| `stdio://` | Native runtime listener (`StdioRuntimeListener`) + metadata marker |
| `mem://` | Native runtime listener (`MemRuntimeListener`) + metadata marker |
| `ws://<host>:<port>` | Listener metadata (`WsTransportListener`) |
| `wss://<host>:<port>` | Listener metadata (`WsTransportListener`) |

## Parity Notes vs Go Reference

Implemented parity:

- URI parsing and listener dispatch semantics
- Native runtime listeners for `tcp`, `unix`, `stdio`, and `mem`
- In-process memory transport with explicit `dial()`/`accept()` pairing
- Standard serve flag parsing
- HOLON identity parsing including list/meta fields (`parents`, `aliases`, `generated_by`, `proto_status`)

Not yet achievable with the current Dart stack (justified gaps):

- `ws://` / `wss://` runtime listener parity:
  - Go uses a `net.Listener` abstraction over upgraded WebSocket streams.
  - `grpc-dart` does not provide an official WebSocket server transport for HTTP/2 gRPC framing.
  - `listenRuntime(uri)` therefore throws `UnsupportedError` for `ws/wss`.
- Transport-agnostic gRPC client helpers (`Dial`, `DialStdio`, `DialMem`, `DialWebSocket`):
  - A faithful Dart equivalent needs a dedicated gRPC channel helper layer that is not yet part of this SDK.
