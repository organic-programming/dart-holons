import 'transport.dart';

/// Parse --listen or --port from command-line args.
String parseFlags(List<String> args) {
  for (var i = 0; i < args.length; i++) {
    if (args[i] == '--listen' && i + 1 < args.length) return args[i + 1];
    if (args[i] == '--port' && i + 1 < args.length) return 'tcp://:${args[i + 1]}';
  }
  return defaultUri;
}
