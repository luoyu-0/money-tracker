import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:money_tracker/ai/config.dart';
import 'package:money_tracker/analysis_screen.dart';
import 'package:money_tracker/ui.dart';
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

  @override
  Future<Report?> report(String month) async => null;
}

void main() {
  testWidgets('收支切换只移动滑块，文字和底色在转场中保持稳定', (tester) async {
    var selection = EntryKind.income;
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) => Center(
            child: SizedBox(
              width: 200,
              child: SlidingSegments<EntryKind>(
                values: EntryKind.values,
                selected: selection,
                label: (kind) => kind.label,
                onChanged: (kind) => setState(() => selection = kind),
              ),
            ),
          ),
        ),
      ),
    );
    final income = find.text('收入');
    final expense = find.text('支出');
    final indicator = find.descendant(
      of: find.byType(AnimatedAlign),
      matching: find.byType(DecoratedBox),
    );
    final labelsBefore = [
      for (final label in [income, expense]) tester.widget<Text>(label).style,
    ];
    final fillBefore = tester.widget<DecoratedBox>(indicator).decoration;
    final sliderBefore = tester.getCenter(indicator).dx;
    await tester.tap(expense);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    expect([
      for (final label in [income, expense]) tester.widget<Text>(label).style,
    ], labelsBefore);
    expect(tester.widget<DecoratedBox>(indicator).decoration, fillBefore);
    final sliderDuring = tester.getCenter(indicator).dx;
    await tester.pumpAndSettle();
    expect(
      sliderDuring,
      allOf(
        greaterThan(sliderBefore),
        lessThan(tester.getCenter(indicator).dx),
      ),
    );
    final button = tester.widget<InkWell>(
      find.ancestor(of: expense, matching: find.byType(InkWell)),
    );
    expect(button.splashFactory, NoSplash.splashFactory);
    expect(
      button.overlayColor!.resolve({WidgetState.pressed}),
      Colors.transparent,
    );
  });

  testWidgets('分类滑动时两组内容相邻，容器高度连续变化', (tester) async {
    late StateSetter change;
    var kind = EntryKind.expense;
    const viewport = ValueKey('滑动区域');
    final income = find.byKey(const ValueKey(EntryKind.income));
    final expense = find.byKey(const ValueKey(EntryKind.expense));
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: StatefulBuilder(
            builder: (context, setState) {
              change = setState;
              return SizedBox(
                width: 300,
                child: SlidingEntryContent(
                  key: viewport,
                  kind: kind,
                  builder: (side) => SizedBox(
                    key: ValueKey(side),
                    height: side == EntryKind.income ? 48 : 144,
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
    change(() => kind = EntryKind.income);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    expect(
      tester.getTopLeft(expense).dx - tester.getTopLeft(income).dx,
      closeTo(300, 0.5),
    );
    expect(
      tester.getSize(find.byKey(viewport)).height,
      allOf(greaterThan(48), lessThan(144)),
    );
    final beforeReverse = tester.getTopLeft(income).dx;
    change(() => kind = EntryKind.expense);
    await tester.pump();
    expect(tester.getTopLeft(income).dx, closeTo(beforeReverse, 0.5));
    await tester.pumpAndSettle();
    expect(income, findsNothing);
    expect(tester.getSize(find.byKey(viewport)).height, 144);
  });

  testWidgets('月份仅显示数字且三行四列，保留上一年与未来月份限制', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 680));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    FlutterSecureStorage.setMockInitialValues({});
    final today = DateTime.now();
    await tester.pumpWidget(
      MaterialApp(
        home: AnalysisScreen(
          settings: const AiSettings(),
          store: _TestStore(),
          initialMonth: today,
          openSettings: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('${today.year} 年 ${today.month} 月'));
    await tester.pumpAndSettle();
    final points = [
      for (var i = 1; i <= 12; i++) tester.getCenter(find.text('$i')),
    ];
    for (var index = 0; index < points.length; index++) {
      expect(points[index].dx, closeTo(points[index % 4].dx, 0.5));
      expect(points[index].dy, closeTo(points[index ~/ 4 * 4].dy, 0.5));
    }
    final december = find.widgetWithText(TextButton, '12');
    expect(
      tester.widget<TextButton>(december).onPressed == null,
      today.month < 12,
    );
    await tester.tap(find.byTooltip('上一年'));
    await tester.pumpAndSettle();
    await tester.tap(december);
    await tester.pumpAndSettle();
    expect(find.text('${today.year - 1} 年 12 月'), findsOneWidget);
  });

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
      findsWidgets,
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
    expect(line.lineBarsData.map((bar) => bar.color), [
      incomeColor,
      expenseColor,
    ]);
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
