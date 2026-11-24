import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_tracker/ledger.dart';
import 'package:money_tracker/ledger_store.dart';
import 'package:money_tracker/main.dart';
import 'package:sqflite/sqflite.dart';

class _UnusedDatabase extends Fake implements Database {}

class _TestStore extends LedgerStore {
  _TestStore() : super(_UnusedDatabase());
  final records = <String, Entry>{};
  final custom = <EntryOption>[];

  @override
  Future<List<Entry>> entries([Period? period, int? limit]) async {
    final values = records.values.where(
      (item) => period?.contains(item.date) ?? true,
    );
    return (limit == null ? values : values.take(limit)).toList();
  }

  @override
  Future<List<EntryOption>> options() async => custom;

  @override
  Future<void> saveOption(EntryOption option) async => custom.add(option);

  @override
  Future<void> saveEntry(Entry entry) async => records[entry.id] = entry;

  @override
  Future<void> deleteEntry(String id) async => records.remove(id);
}

void main() {
  testWidgets('从空账本新建候选值，保存并删除账目', (tester) async {
    final store = _TestStore();
    await tester.pumpWidget(MoneyTrackerApp(openStore: () async => store));
    await tester.pumpAndSettle();
    await tester.tap(find.text('记第一笔'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).first, '25.50');
    await tester.tap(find.widgetWithText(ActionChip, '添加'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextFormField),
      ),
      '日用',
    );
    await tester.tap(find.widgetWithText(FilledButton, '添加'));
    await tester.pumpAndSettle();
    final save = find.widgetWithText(FilledButton, '保存账目');
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(store.records.values.single.cents, 2550);
    expect(store.records.values.single.category, '日用');
    expect(store.custom.single.label, '日用');
    await tester.tap(find.text('日用'));
    await tester.pumpAndSettle();
    final remove = find.text('删除账目');
    await tester.ensureVisible(remove);
    await tester.tap(remove);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '删除'));
    await tester.pumpAndSettle();
    expect(store.records, isEmpty);
    expect(find.text('记第一笔'), findsOneWidget);
  });

  testWidgets('统计与设置可从底部导航打开', (tester) async {
    await tester.binding.setSurfaceSize(const Size(412, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MoneyTrackerApp(openStore: () async => _TestStore()),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(NavigationDestination, '统计'));
    await tester.pumpAndSettle();
    expect(find.text('收支趋势'), findsOneWidget);
    expect(find.text('本月'), findsOneWidget);
    await tester.tap(find.widgetWithText(NavigationDestination, '设置'));
    await tester.pumpAndSettle();
    expect(find.text('创建整本备份'), findsOneWidget);
    expect(find.text('清除缓存'), findsOneWidget);
  });
}
