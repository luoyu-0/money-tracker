import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import 'ledger.dart';
import 'ledger_store.dart';
import 'ui.dart';

class StatisticsScreen extends StatefulWidget {
  const StatisticsScreen({
    super.key,
    required this.store,
    required this.revision,
    required this.openAnalysis,
  });
  final LedgerStore store;
  final int revision;
  final ValueChanged<DateTime> openAnalysis;

  @override
  State<StatisticsScreen> createState() => _StatisticsScreenState();
}

class _StatisticsScreenState extends State<StatisticsScreen> {
  PeriodKind kind = PeriodKind.month;
  EntryKind breakdown = EntryKind.expense;
  late Future<(PeriodKind, Period, List<Entry>, List<Entry>)> query = load();

  Future<(PeriodKind, Period, List<Entry>, List<Entry>)> load() async {
    final selected = kind;
    final (current, prior) = selected.ranges(DateTime.now());
    final results = await Future.wait([
      widget.store.entries(current),
      widget.store.entries(prior),
    ]);
    return (selected, current, results[0], results[1]);
  }

  void refresh() {
    query = load();
  }

  @override
  void didUpdateWidget(covariant StatisticsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.revision != widget.revision) refresh();
  }

  void select(PeriodKind next) {
    if (next == kind) return;
    setState(() {
      kind = next;
      refresh();
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
      children: [
        SlidingSegments<PeriodKind>(
          values: PeriodKind.values,
          label: (value) => value.label,
          selected: kind,
          onChanged: select,
        ),
        const SizedBox(height: 8),
        FutureBuilder<(PeriodKind, Period, List<Entry>, List<Entry>)>(
          future: query,
          builder: (context, snapshot) {
            final loading = snapshot.connectionState != ConnectionState.done;
            if (loading && !snapshot.hasData) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 26),
                child: LinearProgressIndicator(),
              );
            }
            if (snapshot.hasError || !snapshot.hasData) {
              return Column(
                children: [
                  const Text('无法读取统计'),
                  TextButton(
                    onPressed: () => setState(refresh),
                    child: const Text('重试'),
                  ),
                ],
              );
            }
            final (selected, current, entries, priorEntries) = snapshot.data!;
            final total = Totals(entries);
            final past = Totals(priorEntries);
            final duration = motion(context, 210);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(current.label, style: const TextStyle(color: mutedInk)),
                SizedBox(
                  height: 2,
                  child: loading ? const LinearProgressIndicator() : null,
                ),
                const SizedBox(height: 12),
                _PeriodComparison(kind: selected, total: total, past: past),
                const SectionTitle('收支趋势'),
                if (entries.isEmpty)
                  const PaperPanel(child: Text('这一时段还没有账目。'))
                else
                  PaperPanel(
                    child: _Trend(
                      key: ValueKey((current.start, current.end)),
                      entries: entries,
                      totals: total,
                      period: current,
                      duration: duration,
                    ),
                  ),
                const SectionTitle('分类构成'),
                Align(
                  alignment: Alignment.centerLeft,
                  child: SizedBox(
                    width: 176,
                    child: SlidingSegments<EntryKind>(
                      values: EntryKind.values,
                      label: (value) => value.label,
                      selected: breakdown,
                      onChanged: (value) => setState(() => breakdown = value),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                PaperPanel(
                  child: SlidingEntryContent(
                    kind: breakdown,
                    builder: (side) {
                      final values = side == EntryKind.income
                          ? total.incomeCategories
                          : total.expenseCategories;
                      return values.isEmpty
                          ? Padding(
                              padding: const EdgeInsets.symmetric(vertical: 24),
                              child: Text('这一时段还没有${side.label}'),
                            )
                          : _Breakdown(values: values, duration: duration);
                    },
                  ),
                ),
                const SizedBox(height: 24),
                FilledButton.tonalIcon(
                  onPressed: () => widget.openAnalysis(current.end),
                  icon: const Icon(Icons.insights_outlined),
                  label: const Text('查看 AI 月度分析'),
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class SummaryPanel extends StatelessWidget {
  const SummaryPanel({
    super.key,
    required this.income,
    required this.expense,
    this.label = '结余',
    this.priorNet,
    this.showMonthlyChange = false,
  });
  final int income;
  final int expense;
  final String label;
  final int? priorNet;
  final bool showMonthlyChange;

  @override
  Widget build(BuildContext context) => PaperPanel(
    color: blueTint,
    raised: true,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: mutedInk)),
        const SizedBox(height: 4),
        Row(
          children: [
            Expanded(
              child: MoneyText(
                income - expense,
                large: true,
                alignment: TextAlign.start,
              ),
            ),
            if (showMonthlyChange) ...[
              const SizedBox(width: 8),
              Expanded(
                child: _MonthlyChange(
                  current: income - expense,
                  previous: priorNet,
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 12),
        const Divider(height: 1),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final (kind, value) in [
              (EntryKind.income, income),
              (EntryKind.expense, expense),
            ])
              Expanded(
                child: Column(
                  crossAxisAlignment: kind == EntryKind.income
                      ? CrossAxisAlignment.start
                      : CrossAxisAlignment.end,
                  children: [
                    Text(kind.label, style: TextStyle(color: kind.color)),
                    MoneyText(
                      value,
                      kind: kind,
                      alignment: kind == EntryKind.income
                          ? TextAlign.start
                          : TextAlign.end,
                    ),
                  ],
                ),
              ),
          ],
        ),
      ],
    ),
  );
}

class _MonthlyChange extends StatelessWidget {
  const _MonthlyChange({required this.current, required this.previous});
  final int current;
  final int? previous;

  @override
  Widget build(BuildContext context) {
    final change = balanceChangePercent(current, previous);
    final color = change == null || change == 0
        ? mutedInk
        : change > 0
        ? incomeColor
        : expenseColor;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          '较上月',
          style: Theme.of(context).textTheme.bodySmall
              ?.copyWith(color: mutedInk),
        ),
        Wrap(
          alignment: WrapAlignment.end,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 4,
          children: [
            if (change != null)
              Icon(
                change > 0
                    ? Icons.arrow_upward
                    : change < 0
                    ? Icons.arrow_downward
                    : Icons.remove,
                size: 16,
                color: color,
              ),
            Text(
              change == null ? '—' : '${change.abs().toStringAsFixed(1)}%',
              semanticsLabel: change == null
                  ? '上月无可用的结余基数'
                  : '${change > 0
                        ? '增长'
                        : change < 0
                        ? '下降'
                        : '持平'} ${change.abs().toStringAsFixed(1)}%',
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w600,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _Trend extends StatelessWidget {
  const _Trend({
    super.key,
    required this.entries,
    required this.totals,
    required this.period,
    required this.duration,
  });
  final List<Entry> entries;
  final Totals totals;
  final Period period;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    final bucketSize = math.max(1, (period.length / 16).ceil());
    final bucketCount = (period.length / bucketSize).ceil();
    final amounts = [
      for (final _ in EntryKind.values) List.filled(bucketCount, 0),
    ];
    for (final entry in entries) {
      final offset = Period(period.start, entry.date).length - 1;
      amounts[entry.kind.index][offset ~/ bucketSize] += entry.cents;
    }
    final peak = amounts.expand((values) => values).reduce(math.max) / 100;
    final step = _axisStep(peak);
    final yMax = peak > 0 ? (peak / step).ceil() * step : step;
    final last = bucketCount - 1;
    final tickIndexes = {0, (last / 3).round(), (last * 2 / 3).round(), last};
    final labelStyle = Theme.of(context).textTheme.bodySmall?.copyWith(
      color: mutedInk,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: Wrap(
            spacing: 16,
            runSpacing: 4,
            children: [
              for (final kind in EntryKind.values)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(width: 14, height: 3, color: kind.color),
                    const SizedBox(width: 4),
                    Text(kind.label, style: labelStyle),
                  ],
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Semantics(
          label: '收入和支出趋势图。点击图中数据点查看金额。',
          child: SizedBox(
            height: 184,
            child: LineChart(
              LineChartData(
                minY: 0,
                minX: 0,
                maxX: math.max(1, bucketCount - 1).toDouble(),
                maxY: yMax,
                gridData: const FlGridData(show: false),
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(),
                  rightTitles: const AxisTitles(),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 52,
                      interval: step,
                      getTitlesWidget: (value, meta) => SideTitleWidget(
                        meta: meta,
                        space: 4,
                        child: Text(_axisAmount(value), style: labelStyle),
                      ),
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 28,
                      interval: 1,
                      getTitlesWidget: (value, meta) {
                        final index = value.round();
                        if (!tickIndexes.contains(index))
                          return const SizedBox.shrink();
                        final date = dayKey(
                          day(period.start, index * bucketSize),
                        ).substring(5);
                        return SideTitleWidget(
                          meta: meta,
                          space: 6,
                          fitInside: SideTitleFitInsideData.fromTitleMeta(
                            meta,
                            distanceFromEdge: 0,
                          ),
                          child: Text(date, style: labelStyle),
                        );
                      },
                    ),
                  ),
                ),
                borderData: FlBorderData(
                  border: const Border(
                    left: BorderSide(color: rule),
                    bottom: BorderSide(color: rule),
                  ),
                ),
                lineBarsData: [
                  for (final kind in EntryKind.values)
                    LineChartBarData(
                      color: kind.color,
                      barWidth: 2.5,
                      dotData: FlDotData(
                        getDotPainter: (_, _, _, _) => FlDotCirclePainter(
                          radius: 2.5,
                          color: surface,
                          strokeWidth: 1.5,
                          strokeColor: kind.color,
                        ),
                      ),
                      spots: [
                        for (var idx = 0; idx < bucketCount; idx++)
                          FlSpot(
                            idx.toDouble(),
                            amounts[kind.index][idx] / 100,
                          ),
                      ],
                    ),
                ],
                lineTouchData: LineTouchData(
                  touchTooltipData: LineTouchTooltipData(
                    fitInsideHorizontally: true,
                    fitInsideVertically: true,
                    getTooltipItems: (spots) => [
                      for (final spot in spots)
                        LineTooltipItem(
                          '${dayKey(day(period.start, spot.x.toInt() * bucketSize))}\n'
                          '${EntryKind.values[spot.barIndex].label} ${yuan((spot.y * 100).round())}',
                          const TextStyle(color: Colors.white),
                        ),
                    ],
                  ),
                ),
              ),
              duration: duration,
              curve: Curves.easeOutCubic,
            ),
          ),
        ),
        const SizedBox(height: 8),
        if (bucketSize > 1) Text('每 $bucketSize 天汇总', style: labelStyle),
        Text('收入 ${yuan(totals.income)}，支出 ${yuan(totals.expense)}'),
      ],
    );
  }
}

double _axisStep(double maximum) {
  if (maximum <= 0) return 1;
  final rough = maximum / 4;
  final scale = math.pow(10, (math.log(rough) / math.ln10).floor()).toDouble();
  final normalized = rough / scale;
  for (final factor in [1, 2, 2.5, 5, 10]) {
    if (normalized <= factor) return math.max(0.01, scale * factor);
  }
  return math.max(0.01, scale * 10);
}

String _axisAmount(double value) {
  if (value >= 100000000) return '${(value / 100000000).toStringAsFixed(1)}亿';
  if (value >= 10000) return '${(value / 10000).toStringAsFixed(1)}万';
  return '¥${value.toStringAsFixed(value == value.truncate()
      ? 0
      : (value * 10).round() / 10 == value
      ? 1
      : 2)}';
}

const chartColors = [
  Color(0xFF3274C9),
  Color(0xFF71A4E8),
  Color(0xFF9E7544),
  Color(0xFF438277),
  Color(0xFF79668D),
  Color(0xFF7288A7),
];

class _Breakdown extends StatelessWidget {
  const _Breakdown({required this.values, required this.duration});
  final Map<String, int> values;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    final sorted = values.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final total = sorted.fold<int>(0, (sum, value) => sum + value.value);
    final chart = sorted.length <= 6
        ? sorted
        : [
            ...sorted.take(5),
            MapEntry(
              '其余分类',
              sorted.skip(5).fold<int>(0, (sum, value) => sum + value.value),
            ),
          ];
    const holeRadius = 42.0;
    const ringWidth = 26.0;
    final smallest = chart.map((category) => category.value).reduce(math.min);
    final shortestArc =
        smallest / total * 2 * math.pi * (holeRadius + ringWidth / 2);
    return Column(
      children: [
        ExcludeSemantics(
          child: SizedBox(
            height: 160,
            child: PieChart(
              PieChartData(
                centerSpaceRadius: holeRadius,
                sectionsSpace: math.min(3.0, shortestArc * 0.35),
                sections: [
                  for (var index = 0; index < chart.length; index++)
                    PieChartSectionData(
                      color: chartColors[index],
                      value: chart[index].value.toDouble(),
                      radius: ringWidth,
                      cornerRadius: 5,
                      showTitle: false,
                    ),
                ],
              ),
              duration: duration,
              curve: Curves.easeOutCubic,
            ),
          ),
        ),
        for (var index = 0; index < sorted.length; index++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: chartColors[math.min(index, 5)],
                    shape: BoxShape.circle,
                  ),
                  child: const SizedBox(width: 8, height: 8),
                ),
                const SizedBox(width: 8),
                Expanded(flex: 4, child: Text(sorted[index].key)),
                const SizedBox(width: 8),
                Expanded(
                  flex: 3,
                  child: MoneyText(
                    sorted[index].value,
                    alignment: TextAlign.start,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: Text(
                    '${(100 * sorted[index].value / total).toStringAsFixed(1)}%',
                    style: const TextStyle(
                      color: mutedInk,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _PeriodComparison extends StatelessWidget {
  const _PeriodComparison({
    required this.kind,
    required this.total,
    required this.past,
  });

  final PeriodKind kind;
  final Totals total;
  final Totals past;

  @override
  Widget build(BuildContext context) {
    final previous = switch (kind) {
      PeriodKind.week => '上周同期',
      PeriodKind.month => '上月同期',
      PeriodKind.year => '去年同期',
    };
    final change = total.net - past.net;
    final changeColor = _changeColor(change);
    final balanceStyle = Theme.of(context).textTheme.headlineMedium?.copyWith(
      fontWeight: FontWeight.w700,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final priorBalance = _comparisonAmount(past.net, signed: true);
    final balance = _comparisonAmount(total.net, signed: true);
    final changeAmount = _comparisonAmount(change.abs(), currency: false);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PaperPanel(
          raised: true,
          child: Column(
            children: [
              Text(
                '结余变化（$previous → ${kind.label}）',
                textAlign: TextAlign.center,
                style: const TextStyle(color: mutedInk),
              ),
              const SizedBox(height: 8),
              Semantics(
                label: '$previous结余 $priorBalance，${kind.label}结余 $balance',
                excludeSemantics: true,
                child: Wrap(
                  alignment: WrapAlignment.center,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 8,
                  children: [
                    Text(
                      priorBalance,
                      textAlign: TextAlign.center,
                      style: balanceStyle?.copyWith(
                        color: _changeColor(past.net),
                      ),
                    ),
                    Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: '→ ',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          TextSpan(text: balance),
                        ],
                      ),
                      textAlign: TextAlign.center,
                      style: balanceStyle?.copyWith(
                        color: _changeColor(total.net),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Text(
                switch (change) {
                  > 0 => '结余改善 $changeAmount 元',
                  < 0 => '结余减少 $changeAmount 元',
                  _ => '结余持平',
                },
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: changeColor,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        PaperPanel(
          raised: true,
          child: Table(
            defaultVerticalAlignment: TableCellVerticalAlignment.middle,
            columnWidths: const {
              0: FlexColumnWidth(.75),
              2: FlexColumnWidth(1.15),
            },
            border: const TableBorder(
              horizontalInside: BorderSide(color: rule),
            ),
            children: [
              TableRow(
                children: [
                  for (final (index, label) in [
                    '项目',
                    kind.label,
                    previous,
                    '变动',
                  ].indexed)
                    _ComparisonCell(
                      label,
                      leading: index == 0,
                      color: mutedInk,
                      header: true,
                    ),
                ],
              ),
              for (final (label, value, prior, color, isExpense) in [
                ('收入', total.income, past.income, incomeColor, false),
                ('支出', total.expense, past.expense, expenseColor, true),
                (
                  '结余',
                  total.net,
                  past.net,
                  total.net < 0 ? expenseColor : accent,
                  false,
                ),
              ])
                TableRow(
                  children: [
                    _ComparisonCell(label, leading: true, header: true),
                    _ComparisonCell(
                      _comparisonAmount(
                        isExpense ? -value : value,
                        signed: true,
                      ),
                      color: color,
                    ),
                    _ComparisonCell(
                      _comparisonAmount(
                        isExpense ? -prior : prior,
                        signed: true,
                      ),
                      color: prior < 0 ? expenseColor : ink,
                    ),
                    _ComparisonCell(
                      _comparisonAmount(value - prior, signed: true),
                      color: _changeColor(
                        isExpense ? prior - value : value - prior,
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ComparisonCell extends StatelessWidget {
  const _ComparisonCell(
    this.text, {
    this.color = ink,
    this.leading = false,
    this.header = false,
  });

  final String text;
  final Color color;
  final bool leading;
  final bool header;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 10),
    child: Semantics(
      header: header,
      child: Text(
        text,
        textAlign: leading ? TextAlign.start : TextAlign.end,
        style: TextStyle(
          color: color,
          fontWeight: header ? FontWeight.w600 : FontWeight.normal,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    ),
  );
}

Color _changeColor(int amount) => switch (amount) {
  > 0 => incomeColor,
  < 0 => expenseColor,
  _ => mutedInk,
};

String _comparisonAmount(
  int cents, {
  bool signed = false,
  bool currency = true,
}) {
  final absolute = cents.abs();
  final amount = absolute % 100 == 0
      ? '${absolute ~/ 100}'
      : amountText(absolute);
  final sign = cents < 0
      ? '−'
      : signed && cents > 0
      ? '+'
      : '';
  return '$sign${currency ? '¥' : ''}$amount';
}
