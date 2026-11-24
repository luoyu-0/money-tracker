import 'package:flutter/material.dart';

import 'ledger.dart';

const paper = Color(0xFFF7F4EC);
const surface = Color(0xFFFFFCF6);
const ink = Color(0xFF202923);
const mutedInk = Color(0xFF56645B);
const green = Color(0xFF235944);
const incomeColor = Color(0xFF226248);
const expenseColor = Color(0xFF9E4432);
const rule = Color(0xFFDCDDD0);

ThemeData appTheme() {
  final colors = ColorScheme.fromSeed(seedColor: green).copyWith(
    primary: green,
    onPrimary: Colors.white,
    surface: surface,
    onSurface: ink,
    onSurfaceVariant: mutedInk,
    outlineVariant: rule,
    error: expenseColor,
    secondaryContainer: const Color(0xFFDDEBDD),
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
      indicatorColor: Color(0xFFDDEBDD),
      height: 68,
    ),
    inputDecorationTheme: const InputDecorationTheme(
      border: OutlineInputBorder(),
      filled: true,
      fillColor: surface,
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
  });
  final int cents;
  final EntryKind? kind;
  final bool large;
  final bool signed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    final prefix = signed ? (kind == EntryKind.income ? '+' : '−') : '';
    return Text(
      '$prefix${yuan(cents)}',
      textAlign: TextAlign.end,
      style: (large ? theme.headlineLarge : theme.titleMedium)?.copyWith(
        fontWeight: FontWeight.w700,
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
    padding: const EdgeInsets.only(top: 23, bottom: 10),
    child: Semantics(
      header: true,
      child: Text(
        label,
        style: Theme.of(context).textTheme.titleLarge
            ?.copyWith(fontWeight: FontWeight.w700),
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
    shape: RoundedRectangleBorder(
      side: const BorderSide(color: rule),
      borderRadius: BorderRadius.circular(16),
    ),
    child: Padding(padding: const EdgeInsets.all(16), child: child),
  );
}
