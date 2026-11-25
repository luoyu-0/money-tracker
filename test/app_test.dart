import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:money_tracker/ai/config.dart';
import 'package:money_tracker/ai/provider.dart';
import 'package:money_tracker/analysis_screen.dart';
import 'package:money_tracker/ui.dart';
import 'package:money_tracker/ledger.dart';
import 'package:money_tracker/ledger_store.dart';
import 'package:money_tracker/main.dart';
import 'package:money_tracker/statistics_screen.dart';
import 'package:sqflite/sqflite.dart';

class _UnusedDatabase extends Fake implements Database {}

class _TestStore extends LedgerStore {
  _TestStore() : super(_UnusedDatabase());
  final records = <String, Entry>{};
  final custom = <EntryOption>[];
  final entryQueries = <(Period?, int?)>[];
  int overviewRequests = 0;

  @override
  Future<({int income, int expense, int priorNet})> overview(
    DateTime date,
  ) async {
    overviewRequests++;
    final current = PeriodKind.month.ranges(date).$1;
    final prior = Period(
      DateTime(date.year, date.month - 1),
      DateTime(date.year, date.month, 0),
    );
    final totals = Totals(
      records.values.where((entry) => current.contains(entry.date)),
    );
    return (
      income: totals.income,
      expense: totals.expense,
      priorNet: Totals(
        records.values.where((entry) => prior.contains(entry.date)),
      ).net,
    );
  }

  @override
  Future<List<Entry>> entries([Period? period, int? limit]) async {
    entryQueries.add((period, limit));
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

void testStableSegments<T>(
  String name,
  List<T> values,
  String Function(T) labelText,
) {
  testWidgets('$name只移动滑块，文字和底色在转场中保持稳定', (tester) async {
    var selection = values.first;
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) => Center(
            child: SizedBox(
              width: 200,
              child: SlidingSegments<T>(
                values: values,
                selected: selection,
                label: labelText,
                onChanged: (kind) => setState(() => selection = kind),
              ),
            ),
          ),
        ),
      ),
    );
    final first = find.text(labelText(values.first));
    final second = find.text(labelText(values[1]));
    final indicator = find.descendant(
      of: find.byType(AnimatedAlign),
      matching: find.byType(DecoratedBox),
    );
    final labelsBefore = [
      for (final label in [first, second]) tester.widget<Text>(label).style,
    ];
    final fillBefore = tester.widget<DecoratedBox>(indicator).decoration;
    final sliderBefore = tester.getCenter(indicator).dx;
    await tester.tap(second);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    expect([
      for (final label in [first, second]) tester.widget<Text>(label).style,
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
      find.ancestor(of: second, matching: find.byType(InkWell)),
    );
    expect(button.splashFactory, NoSplash.splashFactory);
    expect(
      button.overlayColor!.resolve({WidgetState.pressed}),
      Colors.transparent,
    );
  });
}

void main() {
  testWidgets('冷启动只读取一次总览和首批账目，合计包含后续账目', (tester) async {
    final store = _TestStore();
    final date = day(DateTime.now());
    for (var index = 0; index < 80; index++) {
      await store.saveEntry(
        Entry(
          id: newId(),
          kind: EntryKind.income,
          cents: 100,
          category: '工资',
          date: date,
        ),
      );
    }
    await tester.pumpWidget(MoneyTrackerApp(openStore: () async => store));
    await tester.pumpAndSettle();
    expect(store.overviewRequests, 1);
    expect(store.entryQueries, [(null, 61)]);
    final summary = tester.widget<SummaryPanel>(find.byType(SummaryPanel));
    expect(summary.income, 8000);
  });

  testStableSegments('收支切换', EntryKind.values, (kind) => kind.label);
  testStableSegments('周期切换', PeriodKind.values, (kind) => kind.label);

  testWidgets('服务商菜单锚定字段，选中后更新模型 ID 和地区配置', (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    FlutterSecureStorage.setMockInitialValues({});
    final store = _TestStore();
    await tester.pumpWidget(MoneyTrackerApp(openStore: () async => store));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(NavigationDestination, '设置'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('模型服务配置'));
    await tester.pumpAndSettle();
    final field = find.byType(DropdownMenu<ModelProvider>);
    await tester.tap(field);
    await tester.pumpAndSettle();
    final selected = find.widgetWithText(MenuItemButton, 'DeepSeek');
    final qwen = find.widgetWithText(MenuItemButton, '通义千问');
    final anchor = tester.getRect(field);
    final option = tester.getRect(selected);
    expect(option.top, greaterThanOrEqualTo(anchor.bottom));
    expect(option.left, greaterThanOrEqualTo(anchor.left));
    expect(
      tester
          .widget<MenuItemButton>(selected)
          .style
          ?.backgroundColor
          ?.resolve({}),
      blueTint,
    );
    await tester.tap(qwen);
    await tester.pumpAndSettle();
    expect(find.text('qwen-plus'), findsOneWidget);
    expect(find.text('百炼 API Host（可选）'), findsOneWidget);
    expect(qwen, findsNothing);
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
    final current = find.widgetWithText(TextButton, '${today.month}');
    final unselected = find.widgetWithText(
      TextButton,
      '${today.month == 1 ? 2 : 1}',
    );
    expect(
      tester.widget<TextButton>(current).style?.backgroundColor?.resolve({}),
      selectedTint,
    );
    expect(
      tester.widget<TextButton>(unselected).style?.backgroundColor?.resolve({}),
      controlTrack,
    );
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
    expect(
      find.widgetWithText(SlidingSegments<PeriodKind>, '本月'),
      findsOneWidget,
    );
    expect(find.text('自定义'), findsNothing);
    await tester.tap(find.widgetWithText(NavigationDestination, '设置'));
    await tester.pumpAndSettle();
    expect(find.text('创建整本备份'), findsOneWidget);
    expect(find.text('清除缓存'), findsOneWidget);
  });

  testWidgets('统计用结余摘要和表格自动对比上一周期同期', (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final store = _TestStore();
    final now = DateTime.now();
    final (current, prior) = PeriodKind.month.ranges(now);
    for (final (date, kind, cents, category) in [
      (current.start, EntryKind.income, 11025, '工资'),
      (current.start, EntryKind.expense, 2400, '餐饮'),
      (prior.start, EntryKind.expense, 15600, '餐饮'),
      (DateTime(now.year - 1), EntryKind.income, 50000, '工资'),
    ]) {
      await store.saveEntry(
        Entry(
          id: newId(),
          kind: kind,
          date: date,
          cents: cents,
          category: category,
        ),
      );
    }
    await tester.pumpWidget(MoneyTrackerApp(openStore: () async => store));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(NavigationDestination, '统计'));
    await tester.pumpAndSettle();

    final table = find.byType(Table);
    Finder tableText(String value) =>
        find.descendant(of: table, matching: find.text(value));
    expect(find.text('结余变化（上月同期 → 本月）'), findsOneWidget);
    expect(find.text('结余改善 242.25 元'), findsOneWidget);
    for (final value in [
      '¥110.25',
      '¥24',
      '−¥156',
      '+110.25',
      '−132',
      '+242.25',
    ]) {
      expect(tableText(value), findsOneWidget);
    }
    expect(tester.widget<Text>(tableText('−132')).style?.color, incomeColor);
    expect(find.text('选择对比时段'), findsNothing);
    expect(find.text('本时段收支'), findsNothing);
    expect(find.text('本月明细'), findsNothing);

    tester.platformDispatcher.textScaleFactorTestValue = 1.7;
    await tester.tap(
      find.descendant(
        of: find.byType(SlidingSegments<PeriodKind>),
        matching: find.text('本年'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('结余变化（去年同期 → 本年）'), findsOneWidget);
    expect(find.textContaining('结余减少'), findsOneWidget);
    expect(tester.takeException(), isNull);
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
