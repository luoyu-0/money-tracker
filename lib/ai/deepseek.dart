import 'provider.dart';

class DeepSeekProvider extends ModelProvider {
  const DeepSeekProvider();

  @override
  String get id => 'deepseek';
  @override
  String get label => 'DeepSeek';
  @override
  String get defaultModel => 'deepseek-flash';
  @override
  Uri endpoint(String host) =>
      Uri.https('api.deepseek.com', '/chat/completions');
}
