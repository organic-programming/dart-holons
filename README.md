# dart-holons

**Dart SDK for Organic Programming** — transport primitives,
serve-flag parsing, identity parsing, discovery, TCP-based `connect()`,
and Holon-RPC client/server utilities.

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
| `discover.dart` | `discover(root)`, `discoverLocal()`, `discoverAll()`, `findBySlug(slug)`, `findByUUID(prefix)` |
| `connect.dart` | `connect(target, [options])`, `disconnect(channel)`, `ConnectOptions` |
| `holonrpc.dart` | `HolonRPCClient` and `HolonRPCServer` |

## Current scope

- Runtime transports: `tcp://`, `unix://`, `stdio://`, `mem://`
- `ws://` and `wss://` are currently transport metadata, not runtime
  gRPC listeners
- Discovery scans local, `$OPBIN`, and cache roots
- `connect()` resolves slugs or direct targets and launches daemons on
  ephemeral localhost TCP

## Current gaps vs Go

- `connect()` is TCP-only today.
- There is no generic stdio/unix/websocket gRPC connect helper yet.
- `serve.dart` currently stops at standard flag parsing; it does not yet
  own a full gRPC server lifecycle runner.
