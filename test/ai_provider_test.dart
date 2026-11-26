import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:money_tracker/ai/provider.dart';

class _LocalProvider extends ModelProvider {
  const _LocalProvider(this.port);
  final int port;

  @override
  String get id => 'local';
  @override
  String get label => '测试服务';
  @override
  String get defaultModel => 'test-model';
  @override
  Uri endpoint(String host) => Uri.http('127.0.0.1:$port', '/chat/completions');
}

void main() {
  test('适配器通过授权头发送汇总并读取报告', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    const summary = {
      '本月': {'收入（分）': 500},
    };
    final handled = server.first.then((request) async {
      final body = jsonDecode(await utf8.decoder.bind(request).join()) as Map;
      request.response.write(
        jsonEncode({
          'choices': [
            {
              'message': {'content': '本月总结'},
            },
          ],
        }),
      );
      await request.response.close();
      return (
        request.method,
        request.headers.value(HttpHeaders.authorizationHeader),
        body,
      );
    });
    final report = await _LocalProvider(server.port).summarize(
      apiKey: 'test-credential',
      model: 'test-model',
      host: '',
      summary: summary,
    );
    final (method, authorization, body) = await handled;
    expect(report, '本月总结');
    expect(method, 'POST');
    expect(authorization, 'Bearer test-credential');
    expect(body['model'], 'test-model');
    expect(body.toString(), isNot(contains('test-credential')));
    expect(
      jsonDecode((body['messages'] as List).last['content'] as String),
      summary,
    );
  });

  test('鉴权失败不把服务商响应中的凭据写入错误信息', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    final handled = server.first.then((request) async {
      await request.drain<void>();
      request.response.statusCode = HttpStatus.unauthorized;
      request.response.write('test-credential');
      await request.response.close();
    });
    await expectLater(
      _LocalProvider(server.port).summarize(
        apiKey: 'test-credential',
        model: 'test-model',
        host: '',
        summary: {},
      ),
      throwsA(
        isA<AiException>().having(
          (error) => error.message,
          '提示',
          allOf(contains('API Key'), isNot(contains('test-credential'))),
        ),
      ),
    );
    await handled;
  });
}
