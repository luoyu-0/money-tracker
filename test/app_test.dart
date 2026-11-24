import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fl_chart/fl_chart.dart';
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

  testWidgets('主页面跟随横向手势，切换后保留统计筛选', (tester) async {
    await tester.binding.setSurfaceSize(const Size(412, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final store = _TestStore();
    await tester.pumpWidget(MoneyTrackerApp(openStore: () async => store));
    await tester.pumpAndSettle();

    final pager = find.byType(PageView);
    await tester.drag(pager, const Offset(-350, 0));
    await tester.pumpAndSettle();
    expect(
      tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
      1,
    );
    await tester.tap(find.text('本周'));
    await tester.pumpAndSettle();
    await tester.drag(pager, const Offset(350, 0));
    await tester.pumpAndSettle();
    expect(
      tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
      0,
    );
    await tester.tap(find.widgetWithText(NavigationDestination, '统计'));
    await tester.pumpAndSettle();
    expect(
      find.text(PeriodKind.week.ranges(DateTime.now()).$1.label),
      findsOneWidget,
    );
  });

  testWidgets('金额与交易对方的键盘 inset 在当帧生效', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(412, 920);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetViewInsets);
    final store = _TestStore();
    await tester.pumpWidget(MoneyTrackerApp(openStore: () async => store));
    await tester.pumpAndSettle();
    await tester.tap(find.text('记第一笔'));
    await tester.pumpAndSettle();
    final fields = find.byType(TextFormField);
    final scroll = find.ancestor(
      of: fields.first,
      matching: find.byType(SingleChildScrollView),
    );
    final bottom = tester.getBottomLeft(scroll).dy;
    await tester.tap(fields.first);
    tester.view.viewInsets = const FakeViewPadding(bottom: 160);
    await tester.pump();
    expect(tester.getBottomLeft(scroll).dy, bottom - 160);
    await tester.ensureVisible(fields.last);
    await tester.tap(fields.last);
    tester.view.viewInsets = const FakeViewPadding(bottom: 260);
    await tester.pump();
    expect(tester.getBottomLeft(scroll).dy, bottom - 260);
    expect(tester.testTextInput.isVisible, isTrue);
    expect(
      tester
          .widget<EditableText>(
            find.descendant(
              of: fields.last,
              matching: find.byType(EditableText),
            ),
          )
          .focusNode
          .hasFocus,
      isTrue,
    );
  });

  testWidgets('展示带坐标轴的无网格折线图与圆角分类环', (tester) async {
    await tester.binding.setSurfaceSize(const Size(412, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final store = _TestStore();
    final date = day(DateTime.now());
    await store.saveEntry(
      Entry(
        id: newId(),
        kind: EntryKind.expense,
        date: date,
        cents: 1200,
        category: '餐饮',
      ),
    );
    await store.saveEntry(
      Entry(
        id: newId(),
        kind: EntryKind.income,
        date: date,
        cents: 3500,
        category: '工资',
      ),
    );
    await tester.pumpWidget(MoneyTrackerApp(openStore: () async => store));
    await tester.pumpAndSettle();
    expect(find.text('餐饮'), findsOneWidget);
    expect(find.text('支出'), findsOneWidget); // 只出现于顶部摘要。
    await tester.tap(find.widgetWithText(NavigationDestination, '统计'));
    await tester.pumpAndSettle();
    final line = tester.widget<LineChart>(find.byType(LineChart)).data;
    expect(line.gridData.show, isFalse);
    expect(line.titlesData.bottomTitles.sideTitles.showTitles, isTrue);
    expect(line.titlesData.leftTitles.sideTitles.showTitles, isTrue);
    final pie = tester.widget<PieChart>(find.byType(PieChart)).data;
    expect(pie.sections.single.cornerRadius, greaterThan(0));
    expect(find.text('100.0%'), findsOneWidget);
    await tester.drag(find.byType(LineChart), const Offset(-350, 0));
    await tester.pumpAndSettle();
    expect(
      tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
      2,
    );
  });
}
