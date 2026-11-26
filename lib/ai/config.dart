import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'deepseek.dart';
import 'glm.dart';
import 'provider.dart';
import 'qwen.dart';

const providers = <ModelProvider>[
  DeepSeekProvider(),
  QwenProvider(),
  GlmProvider(),
];

class AiConfig {
  const AiConfig(this.provider, this.key, this.model, this.host);
  final ModelProvider provider;
  final String key;
  final String model;
  final String host;
}

class AiSettings {
  const AiSettings({this.storage = const FlutterSecureStorage()});
  final FlutterSecureStorage storage;
  static const storageKey = 'money_tracker_ai';

  Future<AiConfig?> read() async {
    final value = await storage.read(key: storageKey);
    if (value == null) return null;
    final json = jsonDecode(value) as Map<String, dynamic>;
    final provider = providers
        .where((item) => item.id == json['provider'])
        .first;
    return AiConfig(
      provider,
      json['key'] as String,
      json['model'] as String,
      json['host'] as String,
    );
  }

  Future<void> save(AiConfig config) async {
    await storage.write(
      key: storageKey,
      value: jsonEncode({
        'provider': config.provider.id,
        'key': config.key,
        'model': config.model,
        'host': config.host,
      }),
    );
  }

  Future<void> clear() => storage.delete(key: storageKey);
}
