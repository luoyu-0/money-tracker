import 'provider.dart';

class GlmProvider extends ModelProvider {
  const GlmProvider();

  @override
  String get id => 'glm';
  @override
  String get label => '智谱 GLM';
  @override
  String get defaultModel => 'glm-4.7-flash';
  @override
  Uri endpoint(String host) =>
      Uri.https('open.bigmodel.cn', '/api/paas/v4/chat/completions');
}
