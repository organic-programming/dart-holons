import 'dart:io';

import 'package:grpc/grpc.dart';
import 'package:holons/holons.dart';
import 'package:holons/gen/holonmeta/v1/holonmeta.pb.dart';
import 'package:holons/gen/holonmeta/v1/holonmeta.pbgrpc.dart';
import 'package:test/test.dart';

void main() {
  group('describe', () {
    test('buildDescribeResponse parses echo proto', () {
      final root = _writeEchoHolon();
      try {
        final response = buildDescribeResponse(
          protoDir: '${root.path}/protos',
          holonYamlPath: '${root.path}/holon.yaml',
        );

        expect(response.slug, equals('echo-server'));
        expect(response.motto, equals('Reply precisely.'));
        expect(response.services, hasLength(1));

        final service = response.services.single;
        expect(service.name, equals('echo.v1.Echo'));
        expect(
          service.description,
          equals('Echo echoes request payloads for documentation tests.'),
        );

        final method = service.methods.single;
        expect(method.name, equals('Ping'));
        expect(method.inputType, equals('echo.v1.PingRequest'));
        expect(method.outputType, equals('echo.v1.PingResponse'));
        expect(
          method.exampleInput,
          equals('{"message":"hello","sdk":"go-holons"}'),
        );

        final field = method.inputFields.first;
        expect(field.name, equals('message'));
        expect(field.type, equals('string'));
        expect(field.number, equals(1));
        expect(field.description, equals('Message to echo back.'));
        expect(field.label, equals(FieldLabel.FIELD_LABEL_OPTIONAL));
        expect(field.required, isTrue);
        expect(field.example, equals('"hello"'));
      } finally {
        root.deleteSync(recursive: true);
      }
    });

    test('HolonMeta service returns Describe response', () async {
      final root = _writeEchoHolon();
      final server = Server.create(
        services: <Service>[
          describeService(
            protoDir: '${root.path}/protos',
            holonYamlPath: '${root.path}/holon.yaml',
          ),
        ],
      );

      try {
        await server.serve(address: InternetAddress.loopbackIPv4, port: 0);
        final channel = ClientChannel(
          '127.0.0.1',
          port: server.port!,
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
          expect(response.services.single.methods.single.name, equals('Ping'));
        } finally {
          await channel.shutdown();
        }
      } finally {
        await server.shutdown();
        root.deleteSync(recursive: true);
      }
    });

    test('buildDescribeResponse handles missing proto directory', () {
      final root = Directory.systemTemp.createTempSync('dart-holons-empty');
      try {
        File('${root.path}/holon.yaml').writeAsStringSync(
          'given_name: Silent\nfamily_name: Holon\nmotto: Quietly available.\n',
        );

        final response = buildDescribeResponse(
          protoDir: '${root.path}/protos',
          holonYamlPath: '${root.path}/holon.yaml',
        );

        expect(response.slug, equals('silent-holon'));
        expect(response.motto, equals('Quietly available.'));
        expect(response.services, isEmpty);
      } finally {
        root.deleteSync(recursive: true);
      }
    });
  });
}

Directory _writeEchoHolon() {
  final root = Directory.systemTemp.createTempSync('dart-holons-describe');
  Directory('${root.path}/protos/echo/v1').createSync(recursive: true);
  File('${root.path}/holon.yaml').writeAsStringSync(
    'given_name: Echo\nfamily_name: Server\nmotto: Reply precisely.\n',
  );
  File('${root.path}/protos/echo/v1/echo.proto').writeAsStringSync(
    '''
syntax = "proto3";
package echo.v1;

// Echo echoes request payloads for documentation tests.
service Echo {
  // Ping echoes the inbound message.
  // @example {"message":"hello","sdk":"go-holons"}
  rpc Ping(PingRequest) returns (PingResponse);
}

message PingRequest {
  // Message to echo back.
  // @required
  // @example "hello"
  string message = 1;

  // SDK marker included in the response.
  // @example "go-holons"
  string sdk = 2;
}

message PingResponse {
  // Echoed message.
  string message = 1;

  // SDK marker from the server.
  string sdk = 2;
}
''',
  );
  return root;
}
