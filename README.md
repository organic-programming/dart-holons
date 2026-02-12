---
# Cartouche v1
title: "dart-holons — Dart SDK for Organic Programming"
author:
  name: "B. ALTER"
created: 2026-02-12
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
| `transport.dart` | `parseUri(uri)`, `listen(uri)`, `scheme(uri)` |
| `serve.dart` | `parseFlags(args)` |
| `identity.dart` | `parseHolon(path)` |

## Transport support

| Scheme | Support |
|--------|---------|
| `tcp://<host>:<port>` | Bound socket (`TcpTransportListener`) |
| `unix://<path>` | Bound UNIX socket (`UnixTransportListener`) |
| `stdio://` | Listener marker (`StdioTransportListener`) |
| `mem://` | Listener marker (`MemTransportListener`) |
| `ws://<host>:<port>` | Listener metadata (`WsTransportListener`) |
| `wss://<host>:<port>` | Listener metadata (`WsTransportListener`) |
