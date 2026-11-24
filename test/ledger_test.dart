import 'package:flutter_test/flutter_test.dart';
import 'package:money_tracker/ledger.dart';
import 'package:money_tracker/ledger_store.dart';
import 'package:money_tracker/ai/qwen.dart';
import 'package:money_tracker/ai/provider.dart';

void main() {
  final entry = Entry(
    id: newId(),
    kind: EntryKind.expense,
    cents: 1250,
    category: '餐饮',
    date: DateTime(2026, 11, 24),
    counterparty: '测试商家',
  );

  test('人民币金额按整数分读写', () {
    expect(parseAmount('12.5'), 1250);
    expect(parseAmount('0.01'), 1);
    expect(parseAmount('9999999999.99'), 999999999999);
    expect(parseAmount('12.345'), isNull);
    expect(parseAmount('0.00'), isNull);
    expect(parseAmount('1e3'), isNull);
    expect(amountText(-1250), '−12.50');
  });

  test('本周从周一开始，按当前进度对比', () {
    final (period, previous) = PeriodKind.week.ranges(DateTime(2026, 11, 24));
    expect(period.label, '2026-11-23 至 2026-11-24');
    expect(previous.label, '2026-11-16 至 2026-11-17');
  });

  test('上一周期较短时取到期末，跨年月份正确', () {
    final (_, shorter) = PeriodKind.month.ranges(DateTime(2024, 3, 31));
    expect(shorter.label, '2024-02-01 至 2024-02-29');
    final (_, lastYear) = PeriodKind.month.ranges(DateTime(2026, 1, 10));
    expect(lastYear.label, '2025-12-01 至 2025-12-10');
  });

  test('自定义时段按日期计算紧接的前一个等长区间', () {
    final period = Period(DateTime(2026, 1, 1), DateTime(2026, 1, 10));
    expect(period.preceding.label, '2025-12-22 至 2025-12-31');
    expect(period.length, period.preceding.length);
  });

  test('统计区分同名收支分类，模型汇总不含交易对方', () {
    final income = Entry(
      id: newId(),
      kind: EntryKind.income,
      cents: 5000,
      category: '餐饮',
      date: entry.date,
    );
    final totals = Totals([entry, income]);
    expect(totals.expenseCategories['餐饮'], 1250);
    expect(totals.incomeCategories['餐饮'], 5000);
    expect(totals.net, 3750);
    expect(totals.summary.toString(), isNot(contains('测试商家')));
  });

  test('备份往返保留稳定标识、候选值和 AI 报告', () {
    final file = LedgerFile(
      backup: true,
      entries: [entry],
      options: const [EntryOption(EntryKind.expense, '自定义')],
      reports: const [
        Report('2026-11', 'DeepSeek', '本月总结', '2026-11-24T11:10:00'),
      ],
    );
    final decoded = LedgerFile.decode(file.encode(), backup: true);
    expect(decoded.entries.single.id, entry.id);
    expect(decoded.entries.single.sameContents(entry), isTrue);
    expect(decoded.options.single.label, '自定义');
    expect(decoded.reports.single.content, '本月总结');
    expect(
      () => LedgerFile.decode(file.encode(), backup: false),
      throwsFormatException,
    );
  });

  test('读取文件时拒绝重复标识和被自动进位的非法日期', () {
    final duplicated = LedgerFile(
      backup: false,
      entries: [entry, entry],
    ).encode();
    final invalidDate = LedgerFile(
      backup: false,
      entries: [entry],
    ).encode().replaceAll('2026-11-24', '2026-11-31');
    expect(
      () => LedgerFile.decode(duplicated, backup: false),
      throwsFormatException,
    );
    expect(
      () => LedgerFile.decode(invalidDate, backup: false),
      throwsFormatException,
    );
  });

  test('千问使用官方接入域名', () {
    const provider = QwenProvider();
    expect(provider.endpoint('').host, 'dashscope.aliyuncs.com');
    expect(
      provider.endpoint('llm-workspace.cn-beijing.maas.aliyuncs.com').host,
      'llm-workspace.cn-beijing.maas.aliyuncs.com',
    );
    expect(
      () => provider.endpoint('dashscope.aliyuncs.com.example.com'),
      throwsA(isA<AiException>()),
    );
  });
}
