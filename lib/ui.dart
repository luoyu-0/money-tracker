import 'package:flutter/material.dart';

import 'ledger.dart';

const paper = Color(0xFFF4F8FD);
const surface = Color(0xFFFFFFFF);
const ink = Color(0xFF172B42);
const mutedInk = Color(0xFF51657D);
const accent = Color(0xFF215BA5);
const blueTint = Color(0xFFE0EEFF);
const controlTrack = Color(0xFFEAF2FC);
const incomeColor = Color(0xFF216B54);
const expenseColor = Color(0xFFAA4C41);
const rule = Color(0xFFDCE6F1);

ThemeData appTheme() {
  final colors = ColorScheme.fromSeed(seedColor: accent).copyWith(
    primary: accent,
    onPrimary: Colors.white,
    surface: surface,
    onSurface: ink,
    onSurfaceVariant: mutedInk,
    outlineVariant: rule,
    error: expenseColor,
    secondaryContainer: blueTint,
    onSecondaryContainer: accent,
  );
  return ThemeData(
    colorScheme: colors,
    scaffoldBackgroundColor: paper,
    dividerColor: rule,
    useMaterial3: true,
    appBarTheme: const AppBarTheme(
      backgroundColor: paper,
      foregroundColor: ink,
      scrolledUnderElevation: 0,
      centerTitle: false,
    ),
    navigationBarTheme: const NavigationBarThemeData(
      backgroundColor: surface,
      indicatorColor: blueTint,
      height: 64,
    ),
    bottomSheetTheme: const BottomSheetThemeData(backgroundColor: surface),
    chipTheme: const ChipThemeData(
      showCheckmark: false,
      side: BorderSide.none,
      backgroundColor: controlTrack,
      selectedColor: blueTint,
    ),
    inputDecorationTheme: InputDecorationTheme(
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: rule),
      ),
      filled: true,
      fillColor: paper,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(minimumSize: const Size(48, 48)),
    ),
  );
}

Duration motion(BuildContext context, int milliseconds) =>
    MediaQuery.disableAnimationsOf(context)
    ? Duration.zero
    : Duration(milliseconds: milliseconds);

void notice(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}

Future<bool> confirm(
  BuildContext context,
  String title,
  String description,
  String action, {
  bool destructive = false,
}) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: SingleChildScrollView(child: Text(description)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: destructive
                ? FilledButton.styleFrom(backgroundColor: expenseColor)
                : null,
            child: Text(action),
          ),
        ],
      ),
    ) ??
    false;

Future<Period?> choosePeriod(BuildContext context, [Period? initial]) async {
  final now = day(DateTime.now());
  final range = await showDateRangePicker(
    context: context,
    firstDate: DateTime(1900),
    lastDate: DateTime(9998, 12, 31),
    initialDateRange: DateTimeRange(
      start: initial?.start ?? DateTime(now.year, now.month),
      end: initial?.end ?? now,
    ),
  );
  return range == null ? null : Period(range.start, range.end);
}

class MoneyText extends StatelessWidget {
  const MoneyText(
    this.cents, {
    super.key,
    this.kind,
    this.large = false,
    this.signed = false,
    this.alignment = TextAlign.end,
  });
  final int cents;
  final EntryKind? kind;
  final bool large;
  final bool signed;
  final TextAlign alignment;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    final prefix = signed ? (kind == EntryKind.income ? '+' : '−') : '';
    return Text(
      '$prefix${yuan(cents)}',
      textAlign: alignment,
      semanticsLabel: signed && kind != null
          ? '${kind!.label} ${yuan(cents)}'
          : null,
      style: (large ? theme.headlineLarge : theme.titleMedium)?.copyWith(
        fontWeight: FontWeight.w600,
        fontFeatures: const [FontFeature.tabularFigures()],
        color: switch (kind) {
          EntryKind.income => incomeColor,
          EntryKind.expense => expenseColor,
          null => ink,
        },
      ),
    );
  }
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.label, {super.key});
  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 24, bottom: 8),
    child: Semantics(
      header: true,
      child: Text(
        label,
        style: Theme.of(context).textTheme.titleLarge
            ?.copyWith(fontWeight: FontWeight.w600),
      ),
    ),
  );
}

class PaperPanel extends StatelessWidget {
  const PaperPanel({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Material(
    color: surface,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    child: Padding(padding: const EdgeInsets.all(16), child: child),
  );
}

class SlidingSegments<T> extends StatelessWidget {
  const SlidingSegments({
    super.key,
    required this.values,
    required this.label,
    required this.selected,
    required this.onChanged,
  });

  final List<T> values;
  final String Function(T) label;
  final T selected;
  final ValueChanged<T>? onChanged;

  @override
  Widget build(BuildContext context) {
    final count = values.length;
    final selectedIndex = values.indexOf(selected);
    return Material(
      color: controlTrack,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Positioned.fill(
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: AnimatedAlign(
                duration: motion(context, 180),
                curve: Curves.easeOutCubic,
                alignment: Alignment(
                  count == 1 ? 0 : 2 * selectedIndex / (count - 1) - 1,
                  0,
                ),
                child: FractionallySizedBox(
                  widthFactor: 1 / count,
                  heightFactor: 1,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: surface,
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ),
            ),
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final value in values)
                Expanded(
                  child: Semantics(
                    selected: value == selected,
                    child: InkWell(
                      onTap: onChanged == null ? null : () => onChanged!(value),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(minHeight: 48),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 12,
                          ),
                          child: Center(
                            child: Text(
                              label(value),
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: value == selected ? accent : mutedInk,
                                fontWeight: value == selected
                                    ? FontWeight.w600
                                    : FontWeight.w400,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class SlidingEntryContent extends StatelessWidget {
  const SlidingEntryContent({
    super.key,
    required this.kind,
    required this.child,
  });
  final EntryKind kind;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final duration = motion(context, 180);
    if (duration == Duration.zero) return child;
    return ClipRect(
      child: AnimatedSwitcher(
        duration: duration,
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeOutCubic,
        layoutBuilder: (current, previous) => Stack(
          alignment: Alignment.topCenter,
          children: [
            for (final item in previous)
              Positioned.fill(
                child: IgnorePointer(
                  child: ExcludeSemantics(
                    child: OverflowBox(
                      alignment: Alignment.topCenter,
                      minHeight: 0,
                      maxHeight: double.infinity,
                      child: item,
                    ),
                  ),
                ),
              ),
            if (current != null) current,
          ],
        ),
        transitionBuilder: (child, animation) {
          final enteringKind = (child.key! as ValueKey<EntryKind>).value;
          final offset = enteringKind == EntryKind.income ? -0.24 : 0.24;
          return FadeTransition(
            opacity: animation,
            child: SlideTransition(
              position: animation.drive(
                Tween(begin: Offset(offset, 0), end: Offset.zero),
              ),
              child: child,
            ),
          );
        },
        child: SizedBox(
          key: ValueKey(kind),
          width: double.infinity,
          child: child,
        ),
      ),
    );
  }
}
