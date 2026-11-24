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
  Period? comparison;
  EntryKind breakdown = EntryKind.expense;
  late (Period, Period) ranges = computeRanges();
  late Future<(Period, Period, List<Entry>, List<Entry>)> query = load();

  (Period, Period) computeRanges() {
    final (current, prior) = kind.ranges(DateTime.now());
    return (current, comparison ?? prior);
  }

  Future<(Period, Period, List<Entry>, List<Entry>)> load() async {
    final (current, prior) = ranges;
    final results = await Future.wait([
      widget.store.entries(current),
      widget.store.entries(prior),
    ]);
    return (current, prior, results[0], results[1]);
  }

  void refresh() {
    ranges = computeRanges();
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
      comparison = null;
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
        FutureBuilder<(Period, Period, List<Entry>, List<Entry>)>(
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
            final (current, prior, entries, priorEntries) = snapshot.data!;
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
                SummaryPanel(income: total.income, expense: total.expense),
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
                const SectionTitle('时段对比'),
                Align(
                  alignment: Alignment.centerLeft,
                  child: FilledButton.tonalIcon(
                    onPressed: () async {
                      final picked = await choosePeriod(
                        context,
                        prior.start.year >= 1900 ? prior : null,
                      );
                      if (mounted && picked != null)
                        setState(() {
                          comparison = picked;
                          refresh();
                        });
                    },
                    icon: const Icon(Icons.calendar_today_outlined),
                    label: const Text('选择对比时段'),
                  ),
                ),
                if (comparison != null)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      onPressed: () => setState(() {
                        comparison = null;
                        refresh();
                      }),
                      child: const Text('恢复默认对比'),
                    ),
                  ),
                const SizedBox(height: 8),
                _PeriodComparison(
                  current: current,
                  prior: prior,
                  total: total,
                  past: past,
                ),
                const SectionTitle('本时段收支'),
                _CurrentComparison(period: current, totals: total),
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
    required this.current,
    required this.prior,
    required this.total,
    required this.past,
  });

  final Period current;
  final Period prior;
  final Totals total;
  final Totals past;

  @override
  Widget build(BuildContext context) {
    final maximum = [
      total.income,
      total.expense,
      past.income,
      past.expense,
    ].reduce(math.max);
    return PaperPanel(
      raised: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _PeriodLabel('当前时段', current),
          const SizedBox(height: 8),
          _PeriodLabel('对比时段', prior),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Divider(height: 1),
          ),
          for (final (kind, currentValue, priorValue) in [
            (EntryKind.income, total.income, past.income),
            (EntryKind.expense, total.expense, past.expense),
          ]) ...[
            if (kind == EntryKind.expense)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Divider(height: 1),
              ),
            Text(
              kind.label,
              style: TextStyle(fontWeight: FontWeight.w600, color: kind.color),
            ),
            const SizedBox(height: 4),
            _AmountBar(
              label: '当前',
              kind: kind,
              value: currentValue,
              maximum: maximum,
            ),
            const SizedBox(height: 8),
            _AmountBar(
              label: '对比',
              kind: kind,
              value: priorValue,
              maximum: maximum,
              comparison: true,
            ),
          ],
        ],
      ),
    );
  }
}

class _CurrentComparison extends StatelessWidget {
  const _CurrentComparison({required this.period, required this.totals});

  final Period period;
  final Totals totals;

  @override
  Widget build(BuildContext context) {
    final maximum = math.max(totals.income, totals.expense);
    return PaperPanel(
      raised: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(period.label, style: const TextStyle(color: mutedInk)),
          const SizedBox(height: 12),
          _AmountBar(
            label: '收入',
            kind: EntryKind.income,
            value: totals.income,
            maximum: maximum,
          ),
          const SizedBox(height: 12),
          _AmountBar(
            label: '支出',
            kind: EntryKind.expense,
            value: totals.expense,
            maximum: maximum,
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Divider(height: 1),
          ),
          Row(
            children: [
              const Expanded(child: Text('结余')),
              Expanded(child: MoneyText(totals.net)),
            ],
          ),
        ],
      ),
    );
  }
}

class _PeriodLabel extends StatelessWidget {
  const _PeriodLabel(this.label, this.period);

  final String label;
  final Period period;

  @override
  Widget build(BuildContext context) => Text.rich(
    TextSpan(
      text: '$label  ',
      style: const TextStyle(fontWeight: FontWeight.w600),
      children: [
        TextSpan(
          text: period.label,
          style: const TextStyle(color: mutedInk, fontWeight: FontWeight.w400),
        ),
      ],
    ),
  );
}

class _AmountBar extends StatelessWidget {
  const _AmountBar({
    required this.label,
    required this.kind,
    required this.value,
    required this.maximum,
    this.comparison = false,
  });

  final String label;
  final EntryKind kind;
  final int value;
  final int maximum;
  final bool comparison;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(color: comparison ? mutedInk : kind.color),
            ),
          ),
          Expanded(child: MoneyText(value, kind: kind)),
        ],
      ),
      const SizedBox(height: 4),
      ExcludeSemantics(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: ColoredBox(
            color: controlTrack,
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: TweenAnimationBuilder<double>(
                tween: Tween(end: maximum == 0 ? 0 : value / maximum),
                duration: motion(context, 180),
                curve: Curves.easeOutCubic,
                builder: (context, fraction, mark) =>
                    FractionallySizedBox(widthFactor: fraction, child: mark),
                child: ColoredBox(
                  color: comparison
                      ? kind.color.withValues(alpha: .42)
                      : kind.color,
                  child: SizedBox(height: comparison ? 5 : 8),
                ),
              ),
            ),
          ),
        ),
      ),
    ],
  );
}
