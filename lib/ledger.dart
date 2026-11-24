import 'dart:convert';
import 'dart:math';

enum EntryKind {
  income('收入', '来源'),
  expense('支出', '用途');

  const EntryKind(this.label, this.categoryLabel);
  final String label;
  final String categoryLabel;
}

final _random = Random.secure();
String newId() =>
    base64Url.encode(List.generate(18, (_) => _random.nextInt(256)));

String dayKey(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

DateTime day(DateTime date, [int offset = 0]) =>
    DateTime(date.year, date.month, date.day + offset);

int? parseAmount(String input) {
  final value = input.trim();
  if (!RegExp(r'^\d{1,10}(?:\.\d{1,2})?$').hasMatch(value)) return null;
  final parts = value.split('.');
  final cents =
      int.parse(parts.first) * 100 +
      (parts.length == 2 ? int.parse(parts.last.padRight(2, '0')) : 0);
  return cents > 0 ? cents : null;
}

String amountText(int cents) {
  final absolute = cents.abs();
  return '${cents < 0 ? '−' : ''}${absolute ~/ 100}.${(absolute % 100).toString().padLeft(2, '0')}';
}

String yuan(int cents) => '¥${amountText(cents)}';

double? balanceChangePercent(int current, int? previous) =>
    previous == null || previous == 0
    ? null
    : (current - previous) / previous.abs() * 100;

class Entry {
  const Entry({
    required this.id,
    required this.kind,
    required this.cents,
    required this.category,
    required this.date,
    this.counterparty,
  });

  final String id;
  final EntryKind kind;
  final int cents;
  final String category;
  final DateTime date;
  final String? counterparty;

  Map<String, Object?> toMap() => {
    'id': id,
    'kind': kind.name,
    'cents': cents,
    'category': category,
    'date': dayKey(date),
    'counterparty': counterparty,
  };

  factory Entry.fromMap(Map<String, Object?> value) {
    final id = value['id'];
    final kind = value['kind'];
    final cents = value['cents'];
    final category = value['category'];
    final date = value['date'];
    final counterparty = value['counterparty'];
    final parsed = date is String ? DateTime.tryParse(date) : null;
    if (id is! String ||
        !RegExp(r'^[A-Za-z0-9_-]{24}$').hasMatch(id) ||
        cents is! int ||
        cents <= 0 ||
        cents > 999999999999 ||
        category is! String ||
        category.isEmpty ||
        category.length > 40 ||
        category.trim() != category ||
        parsed == null ||
        date != dayKey(parsed) ||
        parsed.year < 1900 ||
        parsed.year > 9998 ||
        (counterparty != null &&
            (counterparty is! String || counterparty.length > 80)) ||
        (kind != 'income' && kind != 'expense')) {
      throw const FormatException('账目字段无效');
    }
    return Entry(
      id: id,
      kind: EntryKind.values.byName(kind as String),
      cents: cents,
      category: category,
      date: parsed,
      counterparty: counterparty as String?,
    );
  }

  bool sameContents(Entry other) =>
      kind == other.kind &&
      cents == other.cents &&
      category == other.category &&
      dayKey(date) == dayKey(other.date) &&
      counterparty == other.counterparty;
}

class Period {
  const Period(this.start, this.end);
  final DateTime start;
  final DateTime end;

  int get length =>
      DateTime.utc(
        end.year,
        end.month,
        end.day,
      ).difference(DateTime.utc(start.year, start.month, start.day)).inDays +
      1;

  String get label => '${dayKey(start)} 至 ${dayKey(end)}';
  bool contains(DateTime date) => !date.isBefore(start) && !date.isAfter(end);
  Period get preceding => Period(day(start, -length), day(start, -1));
}

enum PeriodKind {
  week('本周'),
  month('本月'),
  year('本年'),
  custom('自定义');

  const PeriodKind(this.label);
  final String label;

  (Period, Period) ranges(DateTime date) {
    final today = day(date);
    final (start, previous, previousEnd) = switch (this) {
      week => (
        day(today, 1 - today.weekday),
        day(today, -6 - today.weekday),
        day(today, -today.weekday),
      ),
      month => (
        DateTime(today.year, today.month),
        DateTime(today.year, today.month - 1),
        DateTime(today.year, today.month, 0),
      ),
      year => (
        DateTime(today.year),
        DateTime(today.year - 1),
        DateTime(today.year, 1, 0),
      ),
      custom => throw StateError('自定义范围需要指定日期'),
    };
    final current = Period(start, today);
    final matchingEnd = day(previous, current.length - 1);
    return (
      current,
      Period(
        previous,
        matchingEnd.isAfter(previousEnd) ? previousEnd : matchingEnd,
      ),
    );
  }
}

class Totals {
  Totals(Iterable<Entry> entries) {
    for (final entry in entries) {
      final bucket = entry.kind == EntryKind.income
          ? incomeCategories
          : expenseCategories;
      bucket.update(
        entry.category,
        (amount) => amount + entry.cents,
        ifAbsent: () => entry.cents,
      );
      if (entry.kind == EntryKind.income) {
        income += entry.cents;
      } else {
        expense += entry.cents;
      }
    }
  }

  int income = 0;
  int expense = 0;
  int get net => income - expense;
  final incomeCategories = <String, int>{};
  final expenseCategories = <String, int>{};

  Map<String, Object> get summary => {
    '收入（分）': income,
    '支出（分）': expense,
    '结余（分）': net,
    '收入来源（分）': incomeCategories,
    '支出用途（分）': expenseCategories,
  };
}

class EntryOption {
  const EntryOption(this.kind, this.label);
  final EntryKind kind;
  final String label;

  Map<String, Object?> toMap() => {'kind': kind.name, 'label': label};
  factory EntryOption.fromMap(Map<String, Object?> map) {
    final label = map['label'];
    final kind = map['kind'];
    if (label is! String ||
        label.isEmpty ||
        label.length > 40 ||
        label.trim() != label ||
        (kind != 'income' && kind != 'expense')) {
      throw const FormatException('候选值无效');
    }
    return EntryOption(EntryKind.values.byName(kind as String), label);
  }

  static const defaults = [
    EntryOption(EntryKind.expense, '餐饮'),
    EntryOption(EntryKind.expense, '交通'),
    EntryOption(EntryKind.expense, '购物'),
    EntryOption(EntryKind.expense, '居住'),
    EntryOption(EntryKind.expense, '娱乐'),
    EntryOption(EntryKind.expense, '其他'),
    EntryOption(EntryKind.income, '工资'),
    EntryOption(EntryKind.income, '奖金'),
    EntryOption(EntryKind.income, '兼职'),
    EntryOption(EntryKind.income, '红包'),
    EntryOption(EntryKind.income, '其他'),
  ];
}

class Report {
  const Report(this.month, this.provider, this.content, this.createdAt);
  final String month;
  final String provider;
  final String content;
  final String createdAt;

  Map<String, Object?> toMap() => {
    'month': month,
    'provider': provider,
    'content': content,
    'createdAt': createdAt,
  };

  factory Report.fromMap(Map<String, Object?> map) {
    final month = map['month'];
    final provider = map['provider'];
    final content = map['content'];
    final createdAt = map['createdAt'];
    if (month is! String ||
        !RegExp(r'^\d{4}-(0[1-9]|1[0-2])$').hasMatch(month) ||
        provider is! String ||
        provider.isEmpty ||
        provider.length > 30 ||
        content is! String ||
        content.trim().isEmpty ||
        content.length > 100000 ||
        createdAt is! String ||
        DateTime.tryParse(createdAt) == null) {
      throw const FormatException('月度报告无效');
    }
    return Report(month, provider, content, createdAt);
  }
}
