import 'dart:io';

import 'package:grpc/grpc.dart';
import 'package:holons/holons.dart';
import 'package:holons/gen/holonmeta/v1/holonmeta.pb.dart';
import 'package:holons/gen/holonmeta/v1/holonmeta.pbgrpc.dart';
import 'package:test/test.dart';

void main() {
  group('serve', () {
    test('startWithOptions advertises ephemeral tcp and auto-registers describe', () async {
      final root = _writeEchoHolon();
      final previous = Directory.current;
      Directory.current = root;

      try {
        final running = await startWithOptions(
          'tcp://127.0.0.1:0',
          const <Service>[],
        );
        final port = int.parse(running.publicUri.split(':').last);
        final channel = ClientChannel(
          '127.0.0.1',
          port: port,
          options: const ChannelOptions(
            credentials: ChannelCredentials.insecure(),
          ),
        );

        try {
          final client = HolonMetaClient(channel);
          final response = await client.describe(DescribeRequest());

          expect(response.slug, equals('echo-server'));
          expect(response.services, hasLength(1));
          expect(response.services.single.name, equals('echo.v1.Echo'));
        } finally {
          await channel.shutdown();
          await running.stop();
        }
      } finally {
        Directory.current = previous;
        root.deleteSync(recursive: true);
      }
    });
  });
}

Directory _writeEchoHolon() {
  final root = Directory.systemTemp.createTempSync('dart-holons-serve');
  Directory('${root.path}/protos/echo/v1').createSync(recursive: true);
  File('${root.path}/holon.yaml').writeAsStringSync(
    'given_name: Echo\nfamily_name: Server\nmotto: Reply precisely.\n',
  );
  File('${root.path}/protos/echo/v1/echo.proto').writeAsStringSync(
    '''
syntax = "proto3";
package echo.v1;

service Echo {
  rpc Ping(PingRequest) returns (PingResponse);
}

message PingRequest {
  string message = 1;
}

message PingResponse {
  string message = 1;
}
''',
  );
  return root;
}
