import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import 'ai/config.dart';
import 'ai/provider.dart';
import 'ledger_store.dart';
import 'ui.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    required this.store,
    required this.aiSettings,
    required this.onChanged,
    required this.onBusyChanged,
  });
  final LedgerStore store;
  final AiSettings aiSettings;
  final VoidCallback onChanged;
  final ValueChanged<bool> onBusyChanged;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool busy = false;

  Future<void> run(Future<void> Function() task) async {
    if (busy) return;
    setState(() => busy = true);
    widget.onBusyChanged(true);
    try {
      await task();
    } on FormatException catch (error) {
      message('无法读取文件：${error.message}');
    } catch (_) {
      message('操作失败，请检查文件或设备设置后重试。');
    } finally {
      if (mounted) {
        setState(() => busy = false);
        widget.onBusyChanged(false);
      }
    }
  }

  void message(String value) {
    if (mounted) notice(context, value);
  }

  Future<bool> saveFile(LedgerFile file, String prefix) async {
    final stamp = DateTime.now().toIso8601String().replaceAll(
      RegExp(r'[-:.]'),
      '',
    );
    final saved = await FilePicker.saveFile(
      fileName: '$prefix-$stamp.json',
      bytes: Uint8List.fromList(utf8.encode(file.encode())),
    );
    return saved != null;
  }

  Future<void> exportBackup() async {
    if (await saveFile(await widget.store.backup(), 'money-tracker-backup'))
      message('整本备份已保存');
  }

  Future<void> exportEntries() async {
    final period = await choosePeriod(context);
    if (period == null) return;
    final entries = await widget.store.entries(period);
    if (await saveFile(
      LedgerFile(backup: false, entries: entries),
      'money-tracker-entries',
    )) {
      message('已导出 ${entries.length} 笔账目');
    }
  }

  Future<LedgerFile?> readFile({required bool backup}) async {
    final selected = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: ['json'],
    );
    if (selected == null) return null;
    const limit = 64 * 1024 * 1024;
    final bytes = BytesBuilder(copy: false);
    await for (final part in selected.readAsByteStream()) {
      if (bytes.length + part.length > limit)
        throw const FormatException('文件大小超过 64 MB');
      bytes.add(part);
    }
    return LedgerFile.decode(utf8.decode(bytes.takeBytes()), backup: backup);
  }

  Future<void> importEntries() async {
    final file = await readFile(backup: false);
    if (file == null) return;
    final result = await widget.store.importEntries(file);
    if (!mounted ||
        !await confirm(context, '导入记录', '${result.label}。冲突时保留本机账目。', '确认导入'))
      return;
    final committed = await widget.store.importEntries(file, apply: true);
    widget.onChanged();
    message(committed.label);
  }

  Future<void> restoreBackup() async {
    final file = await readFile(backup: true);
    if (file == null || !mounted) return;
    final accepted = await confirm(
      context,
      '恢复整本备份',
      '文件包含 ${file.entries.length} 笔账目、${file.options.length} 个自定义候选值和 ${file.reports.length} 份 AI 报告。'
          '恢复会替换本机对应内容。请先选择保存恢复前副本的位置。',
      '保存副本并恢复',
      destructive: true,
    );
    if (!accepted ||
        !await saveFile(
          await widget.store.backup(),
          'money-tracker-before-restore',
        ))
      return;
    await widget.store.restore(file);
    widget.onChanged();
    message('已恢复账本，恢复前副本已保存');
  }

  Future<void> clearCache() async {
    await FilePicker.clearTemporaryFiles();
    message('缓存和临时文件已清除');
  }

  Future<void> clearData() async {
    final action = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清除本机数据？'),
        content: const Text(
          '将清除账目、自定义候选值、AI 报告、设置、API Key 和临时文件。已保存在应用外的备份和导出文件可以继续使用。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, 'backup'),
            child: const Text('先备份'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, 'clear'),
            style: FilledButton.styleFrom(backgroundColor: expenseColor),
            child: const Text('确认清除'),
          ),
        ],
      ),
    );
    if (action == 'backup') {
      await exportBackup();
      return;
    }
    if (action != 'clear') return;
    await FilePicker.clearTemporaryFiles();
    final config = await widget.aiSettings.read();
    await widget.aiSettings.clear();
    try {
      await widget.store.reset();
    } catch (_) {
      if (config != null) await widget.aiSettings.save(config);
      rethrow;
    }
    widget.onChanged();
    message('本机数据已清除');
  }

  Future<void> configureAi() async {
    final current = await widget.aiSettings.read();
    if (!mounted) return;
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) =>
            _AiConfigScreen(settings: widget.aiSettings, current: current),
      ),
    );
    if (result == true) message('AI 服务配置已保存');
  }

  Widget tile(
    IconData icon,
    String title,
    Future<void> Function() action, {
    String? subtitle,
    bool destructive = false,
  }) => ListTile(
    leading: Icon(icon),
    title: Text(title),
    subtitle: subtitle == null ? null : Text(subtitle),
    textColor: destructive ? expenseColor : ink,
    iconColor: destructive ? expenseColor : mutedInk,
    trailing: const Icon(Icons.chevron_right),
    enabled: !busy,
    onTap: () => run(action),
  );

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
    children: [
      if (busy) const LinearProgressIndicator(),
      const SectionTitle('AI 月度分析'),
      PaperPanel(
        child: tile(
          Icons.tune,
          '模型服务配置',
          configureAi,
          subtitle: '选择服务商并保存 API Key',
        ),
      ),
      const SectionTitle('备份与迁移'),
      PaperPanel(
        child: Column(
          children: [
            tile(Icons.backup_outlined, '创建整本备份', exportBackup),
            const Divider(height: 1),
            tile(Icons.restore, '恢复整本备份', restoreBackup),
            const Divider(height: 1),
            tile(Icons.upload_file_outlined, '导出记录', exportEntries),
            const Divider(height: 1),
            tile(Icons.file_download_outlined, '导入记录', importEntries),
          ],
        ),
      ),
      const SectionTitle('本机数据'),
      PaperPanel(
        child: Column(
          children: [
            tile(
              Icons.cleaning_services_outlined,
              '清除缓存',
              clearCache,
              subtitle: '清理临时文件',
            ),
            const Divider(height: 1),
            tile(Icons.delete_outline, '清除本机数据', clearData, destructive: true),
          ],
        ),
      ),
    ],
  );
}

class _AiConfigScreen extends StatefulWidget {
  const _AiConfigScreen({required this.settings, this.current});
  final AiSettings settings;
  final AiConfig? current;

  @override
  State<_AiConfigScreen> createState() => _AiConfigScreenState();
}

class _AiConfigScreenState extends State<_AiConfigScreen> {
  final form = GlobalKey<FormState>();
  late ModelProvider provider = widget.current?.provider ?? providers.first;
  late final key = TextEditingController();
  late final model = TextEditingController(
    text: widget.current?.model ?? provider.defaultModel,
  );
  late final host = TextEditingController(text: widget.current?.host);
  bool saving = false;
  bool get hasSavedKey => widget.current?.provider.id == provider.id;

  @override
  void dispose() {
    key.dispose();
    model.dispose();
    host.dispose();
    super.dispose();
  }

  Future<void> save() async {
    if (!form.currentState!.validate()) return;
    setState(() => saving = true);
    try {
      final enteredKey = key.text.trim();
      await widget.settings.save(
        AiConfig(
          provider,
          enteredKey.isEmpty ? widget.current!.key : enteredKey,
          model.text.trim(),
          host.text.trim(),
        ),
      );
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (mounted) notice(context, '无法保存配置，请检查系统安全存储后重试。');
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('模型服务配置')),
    body: Form(
      key: form,
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          DropdownButtonFormField<ModelProvider>(
            initialValue: provider,
            decoration: const InputDecoration(labelText: '服务商'),
            items: [
              for (final item in providers)
                DropdownMenuItem(value: item, child: Text(item.label)),
            ],
            onChanged: saving
                ? null
                : (value) => setState(() {
                    provider = value!;
                    key.clear();
                    model.text = hasSavedKey
                        ? widget.current!.model
                        : provider.defaultModel;
                    host.text = hasSavedKey ? widget.current!.host : '';
                  }),
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: key,
            enabled: !saving,
            obscureText: true,
            autocorrect: false,
            enableSuggestions: false,
            decoration: InputDecoration(
              labelText: 'API Key',
              helperText: hasSavedKey ? '已保存，留空继续使用当前密钥' : '仅保存在设备的安全存储中',
            ),
            validator: (value) {
              final secret = value?.trim() ?? '';
              if (secret.isEmpty && !hasSavedKey) return '请输入 API Key';
              if (RegExp(r'\s').hasMatch(secret)) return 'API Key 不能包含空白字符';
              return null;
            },
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: model,
            enabled: !saving,
            autocorrect: false,
            decoration: const InputDecoration(labelText: '模型 ID'),
            validator: (value) =>
                (value?.trim().isEmpty ?? true) ? '请输入模型 ID' : null,
          ),
          if (provider.id == 'qwen') ...[
            const SizedBox(height: 14),
            TextFormField(
              controller: host,
              enabled: !saving,
              autocorrect: false,
              decoration: const InputDecoration(
                labelText: '百炼 API Host（可选）',
                helperText: '默认使用北京地域。填写控制台显示的域名。',
              ),
              validator: (value) {
                try {
                  provider.endpoint(value ?? '');
                  return null;
                } on AiException catch (error) {
                  return error.message;
                }
              },
            ),
          ],
          const SizedBox(height: 20),
          FilledButton(
            onPressed: saving ? null : save,
            child: const Text('保存配置'),
          ),
        ],
      ),
    ),
  );
}
