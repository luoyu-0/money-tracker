import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import 'ledger.dart';

class LedgerStore {
  LedgerStore(this.db);
  final Database db;

  static Future<LedgerStore> open() async {
    final db = await openDatabase(
      '${await getDatabasesPath()}/money_tracker.db',
      version: 1,
      onCreate: (db, version) async {
        await db.execute(
          'CREATE TABLE entries (id TEXT PRIMARY KEY NOT NULL, '
          'kind TEXT NOT NULL, cents INTEGER NOT NULL, category TEXT NOT NULL, '
          'date TEXT NOT NULL, counterparty TEXT)',
        );
        await db.execute('CREATE INDEX entries_date ON entries (date DESC)');
        await db.execute(
          'CREATE TABLE options (kind TEXT NOT NULL, label TEXT NOT NULL, '
          'PRIMARY KEY (kind, label))',
        );
        await db.execute(
          'CREATE TABLE reports (month TEXT PRIMARY KEY NOT NULL, '
          'provider TEXT NOT NULL, content TEXT NOT NULL, createdAt TEXT NOT NULL)',
        );
        await db.execute(
          'CREATE TABLE settings (name TEXT PRIMARY KEY NOT NULL, value TEXT NOT NULL)',
        );
      },
    );
    return LedgerStore(db);
  }

  Future<List<Entry>> entries([Period? period, int? limit]) async =>
      (await db.query(
        'entries',
        where: period == null ? null : 'date BETWEEN ? AND ?',
        whereArgs: period == null
            ? null
            : [dayKey(period.start), dayKey(period.end)],
        orderBy: 'date DESC, rowid DESC',
        limit: limit,
      )).map(Entry.fromMap).toList();

  Future<({int income, int expense, int priorNet})> overview(
    DateTime date,
  ) async {
    final currentStart = dayKey(DateTime(date.year, date.month));
    final priorStart = dayKey(DateTime(date.year, date.month - 1));
    final rows = await db.rawQuery(
      '''
      SELECT
        COALESCE(SUM(CASE WHEN date >= ? AND kind = 'income' THEN cents END), 0) AS income,
        COALESCE(SUM(CASE WHEN date >= ? AND kind = 'expense' THEN cents END), 0) AS expense,
        COALESCE(SUM(CASE WHEN date < ?
          THEN CASE kind WHEN 'income' THEN cents WHEN 'expense' THEN -cents END
        END), 0) AS priorNet
      FROM entries
      WHERE date BETWEEN ? AND ?
      ''',
      [currentStart, currentStart, currentStart, priorStart, dayKey(date)],
    );
    final row = rows.single;
    return (
      income: row['income'] as int,
      expense: row['expense'] as int,
      priorNet: row['priorNet'] as int,
    );
  }

  Future<void> saveEntry(Entry entry) async {
    await db.insert(
      'entries',
      entry.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> deleteEntry(String id) async {
    await db.delete('entries', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<EntryOption>> options() async => (await db.query(
    'options',
    orderBy: 'rowid',
  )).map(EntryOption.fromMap).toList();

  Future<void> saveOption(EntryOption option) async {
    await db.insert(
      'options',
      option.toMap(),
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  Future<Report?> report(String month) async {
    final rows = await db.query(
      'reports',
      where: 'month = ?',
      whereArgs: [month],
    );
    return rows.isEmpty ? null : Report.fromMap(rows.first);
  }

  Future<void> saveReport(Report report) async {
    await db.insert(
      'reports',
      report.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<String?> setting(String name) async {
    final rows = await db.query(
      'settings',
      where: 'name = ?',
      whereArgs: [name],
    );
    return rows.isEmpty ? null : rows.first['value'] as String;
  }

  Future<void> saveSettings(Map<String, String> settings) async {
    await db.transaction((tx) async {
      for (final setting in settings.entries) {
        await tx.insert('settings', {
          'name': setting.key,
          'value': setting.value,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });
  }

  Future<LedgerFile> backup() => db.transaction(
    (tx) async => LedgerFile(
      backup: true,
      entries: (await tx.query('entries')).map(Entry.fromMap).toList(),
      options: (await tx.query('options')).map(EntryOption.fromMap).toList(),
      reports: (await tx.query('reports')).map(Report.fromMap).toList(),
    ),
  );

  Future<ImportResult> importEntries(
    LedgerFile file, {
    bool apply = false,
  }) async {
    return db.transaction((tx) async {
      var added = 0;
      var duplicated = 0;
      var conflicted = 0;
      final batch = tx.batch();
      final ids = file.entries.map((entry) => entry.id).toList();
      final existing = <String, Entry>{};
      for (var offset = 0; offset < ids.length; offset += 500) {
        final chunk = ids.skip(offset).take(500).toList();
        final placeholders = List.filled(chunk.length, '?').join(',');
        final matches = await tx.query(
          'entries',
          where: 'id IN ($placeholders)',
          whereArgs: chunk,
        );
        for (final row in matches) {
          final entry = Entry.fromMap(row);
          existing[entry.id] = entry;
        }
      }
      for (final entry in file.entries) {
        final current = existing[entry.id];
        if (current == null) {
          added++;
          if (apply) batch.insert('entries', entry.toMap());
        } else if (current.sameContents(entry)) {
          duplicated++;
        } else {
          conflicted++;
        }
      }
      if (apply && added > 0) await batch.commit(noResult: true);
      return ImportResult(added, duplicated, conflicted);
    });
  }

  Future<void> restore(LedgerFile file) async {
    await db.transaction((tx) async {
      final batch = tx.batch();
      for (final table in ['entries', 'options', 'reports']) {
        batch.delete(table);
      }
      for (final entry in file.entries) {
        batch.insert('entries', entry.toMap());
      }
      for (final option in file.options) {
        batch.insert('options', option.toMap());
      }
      for (final report in file.reports) {
        batch.insert('reports', report.toMap());
      }
      await batch.commit(noResult: true);
    });
  }

  Future<void> reset() async {
    await db.transaction((tx) async {
      for (final table in ['entries', 'options', 'reports', 'settings']) {
        await tx.delete(table);
      }
    });
  }
}

class ImportResult {
  const ImportResult(this.added, this.duplicated, this.conflicted);
  final int added;
  final int duplicated;
  final int conflicted;
  String get label => '新增 $added 笔，重复 $duplicated 笔，冲突 $conflicted 笔';
}

class LedgerFile {
  const LedgerFile({
    required this.backup,
    required this.entries,
    this.options = const [],
    this.reports = const [],
  });
  final bool backup;
  final List<Entry> entries;
  final List<EntryOption> options;
  final List<Report> reports;

  String encode() => jsonEncode({
    'format': backup ? 'money-tracker-backup' : 'money-tracker-entries',
    'version': 1,
    'entries': entries.map((e) => e.toMap()).toList(),
    if (backup) 'options': options.map((e) => e.toMap()).toList(),
    if (backup) 'reports': reports.map((e) => e.toMap()).toList(),
  });

  static LedgerFile decode(String input, {required bool backup}) {
    final root = jsonDecode(input);
    if (root is! Map<String, dynamic> ||
        root['version'] != 1 ||
        root['format'] !=
            (backup ? 'money-tracker-backup' : 'money-tracker-entries')) {
      throw const FormatException('文件类型或版本不受支持');
    }
    List<T> read<T>(
      String field,
      T Function(Map<String, Object?>) parse,
      Object Function(T) key,
    ) {
      final items = root[field];
      if (items is! List || items.length > 200000)
        throw const FormatException('文件内容不受支持');
      final seen = <Object>{};
      return items.map((item) {
        if (item is! Map<String, Object?>)
          throw const FormatException('文件字段无效');
        final value = parse(item);
        if (!seen.add(key(value))) throw const FormatException('文件中存在重复标识');
        return value;
      }).toList();
    }

    return LedgerFile(
      backup: backup,
      entries: read('entries', Entry.fromMap, (entry) => entry.id),
      options: backup
          ? read(
              'options',
              EntryOption.fromMap,
              (option) => (option.kind, option.label),
            )
          : const [],
      reports: backup
          ? read('reports', Report.fromMap, (report) => report.month)
          : const [],
    );
  }
}
