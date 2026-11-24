import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import 'ai/config.dart';
import 'ai/provider.dart';
import 'ledger.dart';
import 'ledger_store.dart';
import 'ui.dart';

class AnalysisScreen extends StatefulWidget {
  const AnalysisScreen({
    super.key,
    required this.store,
    required this.settings,
    required this.initialMonth,
    required this.openSettings,
  });
  final LedgerStore store;
  final AiSettings settings;
  final DateTime initialMonth;
  final VoidCallback openSettings;

  @override
  State<AnalysisScreen> createState() => _AnalysisScreenState();
}

class _AnalysisScreenState extends State<AnalysisScreen> {
  static DateTime monthOf(DateTime value) => DateTime(value.year, value.month);
  late DateTime month = widget.initialMonth.isAfter(DateTime.now())
      ? monthOf(DateTime.now())
      : monthOf(widget.initialMonth);
  String get key => dayKey(month).substring(0, 7);
  late Future<(AiConfig?, Report?)> snapshot = load();
  bool busy = false;
  String? error;

  Future<(AiConfig?, Report?)> load() async =>
      (await widget.settings.read(), await widget.store.report(key));

  Future<void> selectMonth() async {
    final now = DateTime.now();
    final selected = await showDialog<DateTime>(
      context: context,
      builder: (context) {
        var year = month.year;
        return StatefulBuilder(
          builder: (context, change) => AlertDialog(
            title: const Text('选择报告月份'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      IconButton(
                        tooltip: '上一年',
                        onPressed: year <= 1900
                            ? null
                            : () => change(() => year--),
                        icon: const Icon(Icons.chevron_left),
                      ),
                      Text('$year 年'),
                      IconButton(
                        tooltip: '下一年',
                        onPressed: year >= now.year
                            ? null
                            : () => change(() => year++),
                        icon: const Icon(Icons.chevron_right),
                      ),
                    ],
                  ),
                  Wrap(
                    spacing: 8,
                    children: [
                      for (var index = 1; index <= 12; index++)
                        ChoiceChip(
                          label: Text('$index 月'),
                          selected: year == month.year && index == month.month,
                          onSelected: year == now.year && index > now.month
                              ? null
                              : (_) => Navigator.pop(
                                  context,
                                  DateTime(year, index),
                                ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('取消'),
              ),
            ],
          ),
        );
      },
    );
    if (mounted && selected != null)
      setState(() {
        month = selected;
        error = null;
        snapshot = load();
      });
  }

  Future<void> generate(AiConfig config) async {
    if (busy) return;
    final target = key;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final today = day(DateTime.now());
      final thisMonth = monthOf(today);
      final current = Period(
        month,
        month == thisMonth ? today : DateTime(month.year, month.month + 1, 0),
      );
      final priorStart = DateTime(month.year, month.month - 1);
      final priorEnd = DateTime(month.year, month.month, 0);
      final matchedEnd = day(priorStart, current.length - 1);
      final previous = Period(
        priorStart,
        month == thisMonth && matchedEnd.isBefore(priorEnd)
            ? matchedEnd
            : priorEnd,
      );
      final currentEntries = await widget.store.entries(current);
      if (currentEntries.isEmpty)
        throw const AiException('选定月份还没有账目，添加记录后再生成报告。');
      final previousEntries = await widget.store.entries(previous);
      final summary = <String, Object>{
        '目标月份': target,
        '本月': {'区间': current.label, '汇总': Totals(currentEntries).summary},
        '上月': {
          '区间': previous.label,
          '有账目': previousEntries.isNotEmpty,
          '汇总': Totals(previousEntries).summary,
        },
      };
      if (!mounted ||
          !await confirm(
            context,
            '发送月度汇总',
            '以下内容将发送给 ${config.provider.label}。如自定义分类含有个人信息，请在发送前检查。\n\n'
                '${const JsonEncoder.withIndent('  ').convert(summary)}',
            '发送并生成',
          ))
        return;
      if (!mounted) return;
      final content = await config.provider.summarize(
        apiKey: config.key,
        model: config.model,
        host: config.host,
        summary: summary,
      );
      if (!mounted) return;
      await widget.store.saveReport(
        Report(
          target,
          config.provider.label,
          content,
          DateTime.now().toIso8601String(),
        ),
      );
      if (mounted) setState(() => snapshot = load());
    } on AiException catch (failure) {
      if (mounted) setState(() => error = failure.message);
    } on TimeoutException {
      if (mounted) setState(() => error = '请求超时，请检查网络后重新生成。');
    } catch (_) {
      if (mounted) setState(() => error = '无法生成或保存报告，请稍后重试。');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy,
    child: Scaffold(
      appBar: AppBar(title: const Text('AI 月度分析')),
      body: FutureBuilder<(AiConfig?, Report?)>(
        future: snapshot,
        builder: (context, result) {
          if (!result.hasData)
            return Center(
              child: result.hasError
                  ? TextButton(
                      onPressed: () => setState(() => snapshot = load()),
                      child: const Text('读取失败，点击重试'),
                    )
                  : const CircularProgressIndicator(),
            );
          final (config, report) = result.data!;
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            children: [
              OutlinedButton.icon(
                onPressed: busy ? null : selectMonth,
                icon: const Icon(Icons.calendar_month_outlined),
                label: Text('${month.year} 年 ${month.month} 月'),
              ),
              const SizedBox(height: 12),
              if (config == null)
                PaperPanel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('设置模型服务后可以生成月度总结和规划建议。'),
                      TextButton(
                        onPressed: widget.openSettings,
                        child: const Text('前往设置'),
                      ),
                    ],
                  ),
                )
              else ...[
                Text(
                  '服务商  ${config.provider.label}',
                  style: const TextStyle(color: mutedInk),
                ),
                const SizedBox(height: 8),
                FilledButton.icon(
                  onPressed: busy ? null : () => generate(config),
                  icon: const Icon(Icons.insights_outlined),
                  label: Text(
                    busy ? '正在准备或请求报告…' : (report == null ? '生成月度分析' : '重新生成'),
                  ),
                ),
              ],
              if (busy) const LinearProgressIndicator(),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    error!,
                    style: const TextStyle(color: expenseColor),
                  ),
                ),
              const SectionTitle('月度报告'),
              AnimatedSwitcher(
                duration: motion(context, 180),
                child: report == null
                    ? const SizedBox(
                        width: double.infinity,
                        child: PaperPanel(child: Text('这个月还没有生成报告。')),
                      )
                    : SizedBox(
                        key: ValueKey(report.createdAt),
                        width: double.infinity,
                        child: PaperPanel(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${report.provider} · ${dayKey(DateTime.parse(report.createdAt))}',
                                style: const TextStyle(color: mutedInk),
                              ),
                              const SizedBox(height: 10),
                              SelectableText(
                                report.content,
                                style: const TextStyle(height: 1.6),
                              ),
                            ],
                          ),
                        ),
                      ),
              ),
            ],
          );
        },
      ),
    ),
  );
}
