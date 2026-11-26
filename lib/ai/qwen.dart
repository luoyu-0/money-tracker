import 'provider.dart';

class QwenProvider extends ModelProvider {
  const QwenProvider();

  @override
  String get id => 'qwen';
  @override
  String get label => '通义千问';
  @override
  String get defaultModel => 'qwen-plus';

  @override
  Uri endpoint(String host) {
    final domain = host.trim().toLowerCase();
    if (domain.isNotEmpty &&
        domain != 'dashscope.aliyuncs.com' &&
        domain != 'dashscope-intl.aliyuncs.com' &&
        !RegExp(r'^[a-z0-9-]+\.[a-z0-9-]+\.maas\.aliyuncs\.com$')
            .hasMatch(domain)) {
      throw const AiException('请输入阿里云百炼控制台提供的 API Host，仅填写域名。');
    }
    return Uri.https(
      domain.isEmpty ? 'dashscope.aliyuncs.com' : domain,
      '/compatible-mode/v1/chat/completions',
    );
  }
}
