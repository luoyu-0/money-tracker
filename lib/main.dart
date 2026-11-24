import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'ai/config.dart';
import 'analysis_screen.dart';
import 'entry_editor.dart';
import 'ledger.dart';
import 'ledger_store.dart';
import 'settings_screen.dart';
import 'statistics_screen.dart';
import 'ui.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MoneyTrackerApp());
}

class MoneyTrackerApp extends StatefulWidget {
  const MoneyTrackerApp({super.key, this.openStore = LedgerStore.open});

  final Future<LedgerStore> Function() openStore;

  @override
  State<MoneyTrackerApp> createState() => _MoneyTrackerAppState();
}

class _MoneyTrackerAppState extends State<MoneyTrackerApp> {
  late Future<LedgerStore> opening = widget.openStore();

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Money Tracker',
    debugShowCheckedModeBanner: false,
    theme: appTheme(),
    locale: const Locale('zh', 'CN'),
    supportedLocales: const [Locale('zh', 'CN')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    home: FutureBuilder<LedgerStore>(
      future: opening,
      builder: (context, snapshot) {
        if (snapshot.hasData) return _Home(store: snapshot.data!);
        if (snapshot.hasError)
          return Scaffold(
            body: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('无法打开本机账本'),
                  TextButton(
                    onPressed: () =>
                        setState(() => opening = widget.openStore()),
                    child: const Text('重试'),
                  ),
                ],
              ),
            ),
          );
        return const Scaffold(
          body: Center(
            child: CircularProgressIndicator(semanticsLabel: '正在打开账本'),
          ),
        );
      },
    ),
  );
}

class _Home extends StatefulWidget {
  const _Home({required this.store});
  final LedgerStore store;

  @override
  State<_Home> createState() => _HomeState();
}

class _HomeState extends State<_Home> {
  final aiSettings = const AiSettings();
  final pages = PageController();
  int selected = 0;
  int revision = 0;
  bool settingsBusy = false;
  String? highlighted;

  void changed() => setState(() => revision++);

  @override
  void dispose() {
    pages.dispose();
    super.dispose();
  }

  void selectPage(int page) {
    if (settingsBusy || !pages.hasClients) return;
    final duration = motion(context, 300);
    if (duration == Duration.zero) {
      pages.jumpToPage(page);
      return;
    }
    pages.animateToPage(page, duration: duration, curve: Curves.easeInCubic);
  }

  Future<void> record([Entry? entry]) async {
    final result = await editEntry(context, widget.store, entry);
    if (!mounted || result == null) return;
    setState(() {
      highlighted = entry == null ? result : null;
      revision++;
    });
    notice(context, result.isEmpty ? '账目已删除' : '账目已保存');
  }

  void openAnalysis(DateTime month) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (routeContext) => AnalysisScreen(
          store: widget.store,
          settings: aiSettings,
          initialMonth: month,
          openSettings: () {
            Navigator.pop(routeContext);
            selectPage(2);
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(
        const ['账本', '统计', '设置'][selected],
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
    ),
    body: SafeArea(
      top: false,
      bottom: false,
      child: PageView(
        controller: pages,
        physics: settingsBusy ? const NeverScrollableScrollPhysics() : null,
        onPageChanged: (value) => setState(() => selected = value),
        children: [
          _PreservedPage(
            child: _LedgerScreen(
              store: widget.store,
              revision: revision,
              highlighted: highlighted,
              edit: record,
            ),
          ),
          _PreservedPage(
            child: StatisticsScreen(
              store: widget.store,
              revision: revision,
              openAnalysis: openAnalysis,
            ),
          ),
          _PreservedPage(
            child: SettingsScreen(
              store: widget.store,
              aiSettings: aiSettings,
              onChanged: changed,
              onBusyChanged: (value) => setState(() => settingsBusy = value),
            ),
          ),
        ],
      ),
    ),
    floatingActionButton: selected != 0
        ? null
        : FloatingActionButton.extended(
            backgroundColor: accent,
            foregroundColor: Colors.white,
            elevation: 4,
            highlightElevation: 1,
            splashColor: const Color(0x30FFFFFF),
            onPressed: record,
            icon: const Icon(Icons.add),
            label: const Text('记一笔'),
          ),
    bottomNavigationBar: NavigationBar(
      selectedIndex: selected,
      animationDuration: motion(context, 180),
      onDestinationSelected: settingsBusy ? null : selectPage,
      destinations: const [
        NavigationDestination(
          icon: Icon(Icons.receipt_long_outlined),
          selectedIcon: Icon(Icons.receipt_long),
          label: '账本',
        ),
        NavigationDestination(
          icon: Icon(Icons.bar_chart_outlined),
          selectedIcon: Icon(Icons.bar_chart),
          label: '统计',
        ),
        NavigationDestination(
          icon: Icon(Icons.settings_outlined),
          selectedIcon: Icon(Icons.settings),
          label: '设置',
        ),
      ],
    ),
  );
}

class _PreservedPage extends StatefulWidget {
  const _PreservedPage({required this.child});
  final Widget child;

  @override
  State<_PreservedPage> createState() => _PreservedPageState();
}

class _PreservedPageState extends State<_PreservedPage>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}

class _LedgerScreen extends StatefulWidget {
  const _LedgerScreen({
    required this.store,
    required this.revision,
    required this.highlighted,
    required this.edit,
  });
  final LedgerStore store;
  final int revision;
  final String? highlighted;
  final void Function([Entry?]) edit;

  @override
  State<_LedgerScreen> createState() => _LedgerScreenState();
}

class _LedgerScreenState extends State<_LedgerScreen> {
  int limit = 60;
  late Future<(Totals, int?, List<Entry>)> query = load();

  Future<(Totals, int?, List<Entry>)> load() async {
    final now = DateTime.now();
    final results = await Future.wait([
      widget.store.entries(PeriodKind.month.ranges(now).$1),
      widget.store.entries(
        Period(
          DateTime(now.year, now.month - 1),
          DateTime(now.year, now.month, 0),
        ),
      ),
      widget.store.entries(null, limit + 1),
    ]);
    final priorEntries = results[1];
    return (
      Totals(results[0]),
      priorEntries.isEmpty ? null : Totals(priorEntries).net,
      results[2],
    );
  }

  @override
  void didUpdateWidget(covariant _LedgerScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.revision != oldWidget.revision) query = load();
  }

  @override
  Widget build(
    BuildContext context,
  ) => FutureBuilder<(Totals, int?, List<Entry>)>(
    future: query,
    builder: (context, snapshot) {
      if (!snapshot.hasData)
        return Center(
          child: snapshot.hasError
              ? TextButton(
                  onPressed: () => setState(() => query = load()),
                  child: const Text('读取账本失败，点击重试'),
                )
              : const CircularProgressIndicator(semanticsLabel: '正在读取账本'),
        );
      final (totals, priorNet, records) = snapshot.data!;
      final count = records.length > limit ? limit : records.length;
      final now = DateTime.now();
      return ListView.builder(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 92),
        itemCount: count + 2,
        itemBuilder: (context, index) {
          if (index == 0)
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SummaryPanel(
                  totals,
                  label: '${now.month} 月结余',
                  priorNet: priorNet,
                  showMonthlyChange: true,
                ),
                const SectionTitle('最近账目'),
              ],
            );
          if (index == count + 1) {
            if (records.isEmpty)
              return PaperPanel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '账本还没有记录',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 5),
                    const Text('从一次收入或支出开始。'),
                    TextButton(
                      onPressed: () => widget.edit(),
                      child: const Text('记第一笔'),
                    ),
                  ],
                ),
              );
            return records.length > limit
                ? TextButton(
                    onPressed: () => setState(() {
                      limit += 60;
                      query = load();
                    }),
                    child: const Text('加载更多账目'),
                  )
                : const SizedBox.shrink();
          }
          final entry = records[index - 1];
          final startsDate =
              index == 1 ||
              dayKey(records[index - 2].date) != dayKey(entry.date);
          return Column(
            key: ValueKey(entry.id),
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (startsDate)
                Padding(
                  padding: const EdgeInsets.only(top: 12, bottom: 8),
                  child: Semantics(
                    header: true,
                    child: Text(
                      dayKey(entry.date),
                      style: const TextStyle(
                        color: mutedInk,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              TweenAnimationBuilder<Color?>(
                key: ValueKey('${entry.id}:${widget.highlighted == entry.id}'),
                tween: ColorTween(
                  begin: widget.highlighted == entry.id ? blueTint : paper,
                  end: paper,
                ),
                duration: motion(context, 240),
                builder: (context, color, child) =>
                    Material(color: color, child: child),
                child: ListTile(
                  onTap: () => widget.edit(entry),
                  contentPadding: EdgeInsets.zero,
                  title: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          entry.category,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: MoneyText(
                          entry.cents,
                          kind: entry.kind,
                          signed: true,
                        ),
                      ),
                    ],
                  ),
                  subtitle: entry.counterparty == null
                      ? null
                      : Text(
                          entry.counterparty!,
                          style: const TextStyle(color: mutedInk),
                        ),
                ),
              ),
              const Divider(height: 1),
            ],
          );
        },
      );
    },
  );
}
